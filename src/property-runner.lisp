;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
                #:property-trials)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-property)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:run-generated-test
                #:backend-default-trials)
  (:import-from #:cl-spec/src/utils/random
                #:make-seed
                #:seed->random-state)
  (:export #:property-result
           #:property-result-status
           #:property-result-property
           #:property-result-trials
           #:property-result-seed
           #:property-result-profile
           #:property-result-counterexample
           #:property-result-shrunk-counterexample
           #:property-result-condition
           #:property-result-elapsed
           #:run-property
           #:run-properties
           #:replay-property))

(in-package #:cl-spec/src/property-runner)

(defclass property-result ()
  ((status :initarg :status
           :initform :pending
           :reader property-result-status
           :documentation "One of :PASSED, :FAILED, :ERROR, :SKIPPED or
:PENDING.")
   (property :initarg :property
             :initform nil
             :reader property-result-property
             :documentation "Name of the property that was run.")
   (trials :initarg :trials
           :initform nil
           :reader property-result-trials
           :documentation "Number of trials actually executed.")
   (seed :initarg :seed
         :initform nil
         :reader property-result-seed
         :documentation "Random seed the run started from, for replay.")
   (profile :initarg :profile
            :initform nil
            :reader property-result-profile
            :documentation "Effective profile the run resolved its trial count from.
TRIALS records only the trial the run stopped at, not the budget it was
allowed, and that budget cannot be recovered from it -- REPLAY-PROPERTY needs
this slot to reproduce a run faithfully when it is handed the result instead
of the bare seed.")
   (counterexample :initarg :counterexample
                   :initform nil
                   :reader property-result-counterexample
                   :documentation "Arguments of the first failing trial.")
   (shrunk-counterexample :initarg :shrunk-counterexample
                          :initform nil
                          :reader property-result-shrunk-counterexample
                          :documentation "Minimal failing arguments after
shrinking.  This is the value an agent should be shown first.")
   (signalled-condition :initarg :condition
                        :initform nil
                        :reader property-result-condition
                        :documentation "Condition signalled by the property
body, or NIL.")
   (elapsed :initarg :elapsed
            :initform nil
            :reader property-result-elapsed
            :documentation "Wall clock seconds the run took, or NIL."))
  (:documentation "Structured outcome of running one property.

A property run is never reported as a bare boolean: the seed, the trial count
and the shrunk counterexample are what make a failure actionable."))

(declaim (ftype (function ((or symbol property)
                           &key (:profile t) (:seed t) (:options t) (:registry t))
                          (values property-result &optional))
                run-property))

(defun resolve-trials (property profile backend)
  "Return the trial count for PROPERTY under PROFILE (specification §33).

PROPERTY-TRIALS is a plist keyed by profile; a property that names no count for
the profile in effect falls back to the backend's own default."
  (let ((table (property-trials property)))
    (or (and table (getf table (or profile :normal)))
        (backend-default-trials backend))))

(defun name-arguments (property values)
  "Return VALUES as a plist keyed by PROPERTY's argument variables.

The backend reports counterexamples positionally; this is where they become the
{name: value} shape section 14 shows."
  (when values
    (loop for (variable nil) in (property-arguments property)
          for value in values
          append (list variable value))))

(defun run-property (property-designator &key profile seed options (registry *registry*))
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend."
  ;; Guarded here rather than left to SEED->RANDOM-STATE, which answered an
  ;; unusable seed with a condition naming an internal symbol.  A result stands
  ;; in for its seed, as REPLAY-PROPERTY and CHECK-FUNCTION both allow.
  (unless (or (null seed)
              (typep seed 'property-result)
              (and (integerp seed) (not (minusp seed))))
    (error 'type-error :datum seed
                       :expected-type '(or null property-result (integer 0 *))))
  (let* ((seed (if (typep seed 'property-result) (property-result-seed seed) seed))
         (property (resolve-property property-designator registry))
         (backend (current-generator-backend))
         (effective-seed (or seed (make-seed)))
         ;; Recorded on the result as-is (not the raw PROFILE argument) so a result
         ;; is self-describing -- :PROFILE :NORMAL tells an agent what ran, where NIL
         ;; would not -- and so replaying from the result reproduces this run by
         ;; construction rather than by both paths happening to default the same way.
         (effective-profile (or profile :normal))
         (trials (resolve-trials property effective-profile backend))
         (start (get-internal-real-time))
         ;; One binding covers generation and shrinking alike, because the whole
         ;; trial loop lives inside this single call.
         (outcome (let ((*random-state* (seed->random-state effective-seed)))
                    (run-generated-test backend property
                                        :options (list* :trials trials
                                                        :registry registry
                                                        options))))
         (elapsed (/ (float (- (get-internal-real-time) start))
                     internal-time-units-per-second)))
    (make-instance 'property-result
                   ;; A budget of zero runs the loop no times, and the backend
                   ;; reports :PASSED for it.  Nothing was executed, so there
                   ;; is nothing to have passed -- §73.3's zero-count success,
                   ;; which CHECK-FUNCTION already refuses to call a pass.
                   :status (if (and (eq :passed (getf outcome :status))
                                    (not (plusp (or (getf outcome :trials) 0))))
                               :skipped
                               (getf outcome :status))
                   :property (property-name property)
                   :trials (getf outcome :trials)
                   :seed effective-seed
                   :profile effective-profile
                   :counterexample (name-arguments property (getf outcome :counterexample))
                   :shrunk-counterexample (name-arguments
                                           property (getf outcome :shrunk-counterexample))
                   :condition (getf outcome :condition)
                   :elapsed elapsed)))

(defun run-properties (property-designators &key profile options (registry *registry*))
  "Run each property in PROPERTY-DESIGNATORS and return the results in order.

Each run draws its own seed, so one failure can be replayed without re-running
the others."
  (mapcar (lambda (designator)
            (run-property designator :profile profile :options options :registry registry))
          property-designators))

(defun replay-property (property-designator seed &key profile options (registry *registry*))
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

SEED is either the integer seed of an earlier run or the PROPERTY-RESULT that
run produced, since section 15 shows both spellings and an agent holding a
result should not have to dig the seed out of it.

PROFILE selects a trial count from the property's :TRIALS table (§33), exactly
as run-property does. The PROFILE must match the original run's PROFILE for the
replay to reproduce it faithfully — the seed alone is not sufficient, because a
different profile changes the trial count. When SEED is a PROPERTY-RESULT, that
result carries its own PROPERTY-RESULT-PROFILE, and this function uses it when
PROFILE is not supplied -- so the recommended spelling, passing the result with
no :PROFILE, is faithful. An explicitly supplied PROFILE always wins over the
result's, so a caller can deliberately replay under a different budget. An
integer SEED carries no profile, so that spelling still requires the caller to
supply a matching PROFILE.

SEED must be a property-result or a non-negative integer, or an error is
signalled."
  (unless (or (typep seed 'property-result)
              (and (integerp seed) (>= seed 0)))
    (error 'type-error
           :datum seed
           :expected-type '(or property-result (integer 0 *))))
  (run-property property-designator
                :seed (if (typep seed 'property-result)
                          (property-result-seed seed)
                          seed)
                :profile (or profile
                             (and (typep seed 'property-result)
                                  (property-result-profile seed)))
                :options options
                :registry registry))
