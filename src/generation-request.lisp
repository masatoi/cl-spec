;;;; src/generation-request.lisp
;;;;
;;;; Request-scoped bounded-filter budget and generation report (specification
;;;; §12, §14).  A generation request owns one finite candidate budget shared by
;;;; every structural bounded AND filter it reaches, together with the counters
;;;; and termination state the generation report exposes.

(defpackage #:cl-spec/src/generation-request
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions
                #:generation-budget-exhausted
                #:generation-budget-exhausted-request
                #:generation-budget-exhausted-phase)
  (:export #:*generation-budget-coefficient*
           #:generation-request
           #:make-generation-request
           #:*generation-request*
           #:current-generation-request
           #:generation-request-budget
           #:generation-request-planned
           #:generation-request-budget-source
           #:generation-request-coefficient
           #:generation-request-policy
           #:generation-request-report
           #:generation-report-p
           #:reserve-generation-candidate
           #:record-generation-rejection
           #:record-generated-value
           #:with-generation-phase
           #:owned-generation-exhaustion-p))

(in-package #:cl-spec/src/generation-request)

(defparameter *generation-budget-coefficient* 1000
  "Initial candidate budget per planned root value.

The effective default is COEFFICIENT × N, where N is the planned number of
normal root values or argument tuples.  It is an initial engineering default,
not an empirically validated optimum and not a completion guarantee: an
impossible filter still consumes more work as the budget grows.")

(defstruct (generation-request
             (:constructor %make-generation-request
                 (&key (planned 0) (budget 0) (budget-source :default)
                       (coefficient 1000)))
             (:conc-name generation-request-))
  "One generation request's shared bounded-filter budget and counters.

Budget and counters live here rather than on a compiled generator object, so a
reusable generator carries no request state and sequential requests get fresh
counters.  The struct is mutable by design; the report is an immutable snapshot."
  (planned 0 :read-only t)
  (budget 0 :read-only t)
  (budget-source :default :read-only t)
  (coefficient 1000 :read-only t)
  (policy :and-single-source-v1 :read-only t)
  (phase :generation)
  (attempts 0)
  (rejections 0)
  (generation-attempts 0)
  (generation-rejections 0)
  (shrinking-attempts 0)
  (shrinking-rejections 0)
  (generated-values 0)
  (termination :completed)
  (exhaustion-phase nil)
  (exhausted-at nil))

(defvar *generation-request* nil
  "The active generation request, or NIL outside a generation boundary.

Bound by the public generation entry points.  A nested public request rebinds
it, so an inner request's exhaustion is distinguishable from the outer request's
own depletion.  Internal retries and recursive descent never create a fresh
budget while one is active.")

(defun current-generation-request ()
  "Return the active generation request, or NIL."
  *generation-request*)

(defun make-generation-request (&key (planned 0) (budget nil budget-p))
  "Return a request whose budget defaults to COEFFICIENT × PLANNED.

An explicit BUDGET is validated as a nonnegative integer; explicit zero is not an
omission and forbids every new bounded-filter source call without forbidding a
draw that uses no such filter."
  (unless (and (integerp planned) (not (minusp planned)))
    (error 'type-error :datum planned :expected-type '(integer 0 *)))
  (let ((effective (if budget-p budget
                       (* *generation-budget-coefficient* planned))))
    (unless (and (integerp effective) (not (minusp effective)))
      (error 'type-error :datum effective :expected-type '(integer 0 *)))
    (%make-generation-request
     :planned planned
     :budget effective
     :budget-source (if budget-p :explicit :default)
     :coefficient *generation-budget-coefficient*)))

(defun generation-request-report (request)
  "Return REQUEST's immutable generation report as ordinary Lisp data."
  (when request
    (list :scope :request
          :unit :bounded-filter-source-call
          :policy (generation-request-policy request)
          :budget (generation-request-budget request)
          :budget-source (generation-request-budget-source request)
          :default-coefficient (generation-request-coefficient request)
          :requested-values (generation-request-planned request)
          :generated-values (generation-request-generated-values request)
          :attempts (generation-request-attempts request)
          :rejections (generation-request-rejections request)
          :phases (list :generation
                        (list :attempts (generation-request-generation-attempts request)
                              :rejections (generation-request-generation-rejections request))
                        :shrinking
                        (list :attempts (generation-request-shrinking-attempts request)
                              :rejections (generation-request-shrinking-rejections request)))
          :termination (generation-request-termination request)
          :exhaustion-phase (generation-request-exhaustion-phase request)
          :exhausted-at (generation-request-exhausted-at request))))

(defun phase-counts-p (plist)
  "Recognize a :GENERATION or :SHRINKING phase plist with nonnegative counts.

The shape is checked before any GETF so a malformed backend report is refused as
INVALID-BACKEND-RESULT rather than escaping as an incidental sequence error."
  (and (finite-list-p plist)
       (evenp (length plist))
       (let ((keys (loop for key in plist by #'cddr collect key)))
         (and (every #'keywordp keys)
              (= (length keys) (length (remove-duplicates keys)))))
       (typep (getf plist :attempts) '(integer 0 *))
       (typep (getf plist :rejections) '(integer 0 *))))

(defun generation-report-p (report)
  "Recognize a coherent generation report.

Validates the counting scope, nonnegative counts, root and rejection bounds,
phase sums, the total attempt bound, and the exhaustion fields.  Owned exhaustion
requires ATTEMPTS = BUDGET, because it is recorded when a further reservation is
denied; a completed report may also have ATTEMPTS = BUDGET when the final
permitted candidate sufficed."
  (and (finite-list-p report)
       (evenp (length report))
       (let ((keys (loop for key in report by #'cddr collect key)))
         (and (every #'keywordp keys)
              (= (length keys) (length (remove-duplicates keys)))))
       (eq :request (getf report :scope))
       (eq :bounded-filter-source-call (getf report :unit))
       (eq :and-single-source-v1 (getf report :policy))
       (typep (getf report :budget) '(integer 0 *))
       (member (getf report :budget-source) '(:default :explicit))
       (typep (getf report :default-coefficient) '(integer 0 *))
       (typep (getf report :requested-values) '(integer 0 *))
       (typep (getf report :generated-values) '(integer 0 *))
       (<= (getf report :generated-values) (getf report :requested-values))
       (typep (getf report :attempts) '(integer 0 *))
       (typep (getf report :rejections) '(integer 0 *))
       (<= (getf report :rejections) (getf report :attempts))
       (<= (getf report :attempts) (getf report :budget))
       (let ((phases (getf report :phases)))
         (and (finite-list-p phases)
              (= 4 (length phases))
              (eq :generation (first phases))
              (eq :shrinking (third phases))
              (phase-counts-p (second phases))
              (phase-counts-p (fourth phases))
              (let ((generation (second phases))
                    (shrinking (fourth phases)))
                (and (<= (getf generation :rejections) (getf generation :attempts))
                     (<= (getf shrinking :rejections) (getf shrinking :attempts))
                     (= (+ (getf generation :attempts) (getf shrinking :attempts))
                        (getf report :attempts))
                     (= (+ (getf generation :rejections) (getf shrinking :rejections))
                        (getf report :rejections))))))
       (member (getf report :termination) '(:completed :budget-exhausted :interrupted))
       (if (eq :budget-exhausted (getf report :termination))
           (and (= (getf report :attempts) (getf report :budget))
                (member (getf report :exhaustion-phase) '(:generation :shrinking)))
           (null (getf report :exhaustion-phase)))))

(defun reserve-generation-candidate (path spec)
  "Reserve one candidate unit from the active request.

Signals GENERATION-BUDGET-EXHAUSTED, owned by the active request, when no unit
remains; the denied reservation records the phase and PATH.  Returns the reserved
attempt count.  Reservation happens immediately before a bounded filter calls its
source, so a propagated source error is not a rejection and consumes no unit."
  (let ((request *generation-request*))
    (unless request
      (error "~S requires an active generation request" 'reserve-generation-candidate))
    (when (>= (generation-request-attempts request)
              (generation-request-budget request))
      (setf (generation-request-termination request) :budget-exhausted
            (generation-request-exhaustion-phase request) (generation-request-phase request)
            (generation-request-exhausted-at request) path)
      (error 'generation-budget-exhausted
             :spec spec
             :reason "the request-owned candidate budget was exhausted"
             :report (generation-request-report request)
             :request request))
    (incf (generation-request-attempts request))
    (ecase (generation-request-phase request)
      (:generation (incf (generation-request-generation-attempts request)))
      (:shrinking (incf (generation-request-shrinking-attempts request))))
    (generation-request-attempts request)))

(defun record-generation-rejection ()
  "Record one false whole-AND validation for a reserved fresh candidate.

Only normal-generation filter rejections and shrink-time regeneration rejections
reach here; a pure shrink-candidate validation failure never does."
  (let ((request *generation-request*))
    (when request
      (incf (generation-request-rejections request))
      (ecase (generation-request-phase request)
        (:generation (incf (generation-request-generation-rejections request)))
        (:shrinking (incf (generation-request-shrinking-rejections request)))))))

(defun record-generated-value ()
  "Record one root value returned normally by a top-level generator."
  (when *generation-request*
    (incf (generation-request-generated-values *generation-request*))))

(defmacro with-generation-phase ((phase) &body body)
  "Run BODY with the active request's phase set to PHASE, restoring it after."
  (let ((request (gensym "REQUEST"))
        (previous (gensym "PREVIOUS")))
    `(let* ((,request *generation-request*)
            (,previous (and ,request (generation-request-phase ,request))))
       (when ,request (setf (generation-request-phase ,request) ,phase))
       (unwind-protect (progn ,@body)
         (when ,request (setf (generation-request-phase ,request) ,previous))))))

(defun owned-generation-exhaustion-p (condition &optional (phase :generation))
  "Return true when CONDITION is this request's own exhaustion in PHASE.

An inner public request's condition, or a target that signals the same class,
does not match: only the request bound here owns this run's depletion."
  (and (typep condition 'generation-budget-exhausted)
       (let ((request *generation-request*))
         (and request
              (eq (generation-budget-exhausted-request condition) request)
              (eq phase (generation-budget-exhausted-phase condition))))))
