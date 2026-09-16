;;;; src/execution.lisp

(defpackage #:cl-spec/src/execution
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result #:case-selection-error)
  (:import-from #:cl-spec/src/call-outcome
                #:call-outcome #:call-outcome-kind #:call-outcome-values #:call-outcome-condition)
  (:import-from #:cl-spec/src/property #:property #:property-function)
  (:export #:*trial-observations* #:trial-observation #:make-trial-observation
           #:trial-observation-arguments #:trial-observation-arguments-mutated-p
           #:trial-observation-outcome #:trial-observation-status
           #:trial-observation-reason #:trial-observation-signature
           #:trial-observation-explanation #:trial-observation-condition
           #:trial-observation-condition-report #:trial-observation-value
           #:trial-observation-case #:note-trial-outcome #:observation-failure-phase
           #:observation-from-current-run-p #:evaluate-trial #:observe-trial #:observation-failure-p
           #:failure-identities-match-p #:snapshot-value #:same-value-p))

(in-package #:cl-spec/src/execution)

(defstruct (trial-observation
            (:constructor make-trial-observation
                (&key run property arguments arguments-mutated-p
                      (status :passed) reason signature explanation condition
                      condition-report (outcome :not-collected) value case))
            (:copier nil))
  "Evidence from one invocation, with snapshots of its conses and arrays. Arbitrary objects and external state are not
checkpointed. CONDITION retains the actual condition; CONDITION-REPORT is its
text at observation time."
  (run nil :read-only t)
  (property nil :read-only t)
  (arguments nil :read-only t)
  (arguments-mutated-p nil :read-only t)
  (status :passed :read-only t)
  (reason nil :read-only t)
  (signature nil :read-only t)
  (explanation nil :read-only t)
  (condition nil :read-only t)
  (condition-report nil :read-only t)
  (outcome :not-collected :read-only t)
  (value nil :read-only t)
  (case nil :read-only t))

;; DEFSTRUCT cannot attach a docstring to a slot, and these accessors are part
;; of the public API, so their documentation is installed explicitly.  The
;; generated reference reads it back with CL:DOCUMENTATION like any other
;; function (see API-DOCS.LISP).

(setf (documentation 'make-trial-observation 'function)
      "Create the evidence record for one invocation.

RUN is the observation log the trial belongs to and PROPERTY is the property
that was run.  The accessors below expose the invocation's arguments, outcome
and failure evidence; see OBSERVE-TRIAL for how they are filled in.")

(setf (documentation 'trial-observation-arguments 'function)
      "Snapshot of the argument list the invocation received, or NIL.")

(setf (documentation 'trial-observation-arguments-mutated-p 'function)
      "True when the invocation changed the structure of its arguments.

Conses and arrays are compared with SAME-VALUE-P before and after the call.
Arbitrary objects and external state are not checkpointed or compared.")

(setf (documentation 'trial-observation-status 'function)
      "One of :PASSED, :REJECTED, :FAILED or :ERROR.")

(setf (documentation 'trial-observation-reason 'function)
      "Machine-readable failure reason keyword, or NIL when the invocation
passed or was rejected.")

(setf (documentation 'trial-observation-signature 'function)
      "Failure identity a shrink candidate must preserve, or NIL.

Status and reason alone do not pin a failure down: the signature says which
return spec or postcondition form broke, so shrinking cannot cross from one
failure into another.")

(setf (documentation 'trial-observation-explanation 'function)
      "Structured EXPLAIN-DATA for the failed check, or NIL.")

(setf (documentation 'trial-observation-condition 'function)
      "The condition object the invocation signalled, or NIL.")

(setf (documentation 'trial-observation-condition-report 'function)
      "Text of CONDITION rendered at observation time, or NIL.

The condition object is retained for inspection, but a report is captured
first because not every condition can be printed again later.")

(setf (documentation 'trial-observation-outcome 'function)
      "Observed outcome plist, or :NOT-COLLECTED when the evaluator did not
report one.

Distinguishes a call that returned zero values from one that returned a single
NIL, which the primary VALUE alone cannot.")

(setf (documentation 'trial-observation-value 'function)
      "Snapshot of the primary value the invocation returned, or NIL.")

(setf (documentation 'trial-observation-case 'function)
      "Name of the selected function-spec case, or NIL.

A case-less contract, a precondition refusal and a case-selection error all have
no selected case, so this is NIL for them.  A failure of a selected case carries
the name in its signature as well, which is what keeps shrinking and rechecking
inside one case.")

(defun snapshot-value (value)
  "Copy conses and arrays iteratively, preserving cycles and sharing within VALUE.
Other objects retain identity; arbitrary application state is not checkpointed."
  (let ((copies (make-hash-table :test #'eq))
        (pending nil))
    (labels ((allocate (item)
               (cond
                 ((gethash item copies))
                 ((or (consp item) (arrayp item))
                  (let ((copy
                          (if (consp item)
                              (cons nil nil)
                              (make-array
                               (array-dimensions item)
                               :element-type (array-element-type item)
                               :adjustable (adjustable-array-p item)
                               :fill-pointer (when (array-has-fill-pointer-p item)
                                               (fill-pointer item))))))
                    (setf (gethash item copies) copy)
                    (push (cons item copy) pending)
                    copy))
                 (t item))))
      (let ((result (allocate value)))
        (loop while pending
              for pair = (pop pending)
              for source = (car pair)
              for copy = (cdr pair)
              do (if (consp source)
                     (setf (car copy) (allocate (car source))
                           (cdr copy) (allocate (cdr source)))
                     (dotimes (i (array-total-size source))
                       (setf (row-major-aref copy i)
                             (allocate (row-major-aref source i))))))
        result))))

(defun same-value-p (left right)
  "Compare graphs iteratively, preserving sharing and numeric and array types."
  (let ((seen (make-hash-table :test #'eq))
        (reverse-seen (make-hash-table :test #'eq))
        (pending (list (cons left right))))
    (loop while pending
          for pair = (pop pending)
          for a = (car pair)
          for b = (cdr pair)
          do (cond
               ((gethash a seen)
                (unless (eq b (gethash a seen)) (return-from same-value-p nil)))
               ((gethash b reverse-seen) (return-from same-value-p nil))
               ((and (consp a) (consp b))
                (setf (gethash a seen) b (gethash b reverse-seen) a)
                (push (cons (cdr a) (cdr b)) pending)
                (push (cons (car a) (car b)) pending))
               ((and (arrayp a) (arrayp b)
                     (equal (array-dimensions a) (array-dimensions b))
                     (equal (array-element-type a) (array-element-type b))
                     (eql (array-has-fill-pointer-p a) (array-has-fill-pointer-p b))
                     (or (not (array-has-fill-pointer-p a))
                         (= (fill-pointer a) (fill-pointer b))))
                (setf (gethash a seen) b (gethash b reverse-seen) a)
                (dotimes (i (array-total-size a))
                  (push (cons (row-major-aref a i) (row-major-aref b i)) pending)))
               ((not (eql a b)) (return-from same-value-p nil))))
    t))

(defun case-headed-signature-p (signature)
  "Return true when SIGNATURE claims to be a case-wrapped failure identity.

Detecting the claim even when it is malformed matters: a naked CASE-CARRIED
identity must never fall through to the unwrapped comparison and match a
case-less failure."
  (and (consp signature) (eq :case (first signature))))

(defun case-wrapped-signature-p (signature)
  "Return true when SIGNATURE is a well-formed (:CASE NAME . INNER) identity."
  (and (consp signature)
       (eq :case (first signature))
       (keywordp (second signature))
       (consp (cddr signature))))

(defun failure-identities-match-p (original candidate)
  "Compare observed failure signatures against the ORIGINAL trial.
False property results and conditions have distinct classes, and conditions
compare by type. Legacy primary-value return-spec/postcondition crossings retain
 their shared :RETURN-VALUE class; within each clause, shapes or indices must agree.
Fixed :RETURN-VALUES failures require the same clause and shape or post-form index;
this prevents a return-position violation from shrinking into a different post failure.
An unknown post-form identity never establishes a match, including clause crossings.
A function-spec case wraps that identity as (:CASE NAME . INNER): the case names
must be EQ and the inner comparison is exactly the one above, so the same
violation in a different case is a different failure while the rules inside a
case are unchanged.  A wrapped identity never matches an unwrapped one, so
evidence that names no case cannot be adopted for a case-carrying failure."
  (and original candidate
       (if (or (case-headed-signature-p original) (case-headed-signature-p candidate))
           (and (case-wrapped-signature-p original)
                (case-wrapped-signature-p candidate)
                (eq (second original) (second candidate))
                (failure-identities-match-p (cddr original) (cddr candidate)))
           (and (eq (first original) (first candidate))
                (not (and (member (first original) '(:return-value :return-values))
                          (eq (second original) :postcondition)
                          (null (third original))))
                (not (and (member (first candidate) '(:return-value :return-values))
                          (eq (second candidate) :postcondition)
                          (null (third candidate))))
                (if (eq (first original) :return-value)
                    (or (not (eq (second original) (second candidate)))
                        (same-value-p (cddr original) (cddr candidate)))
                    (same-value-p (rest original) (rest candidate)))))))

(defun observation-failure-p (observation)
  "Return true when OBSERVATION records a failed or signalled trial."
  (and (typep observation 'trial-observation)
       (member (trial-observation-status observation) '(:failed :error))
       t))

(defgeneric evaluate-trial (property arguments &key context)
  (:documentation "Evaluate PROPERTY once, returning status, reason, signature,
explanation, condition and value. Status is :passed, :rejected, :failed or :error.
The optional seventh value is the captured target call outcome; the optional
eighth names the selected function-spec case, or NIL when none was selected.
The first six keep their established meaning, so an existing specialization that
returns only those stays valid.
Backends call OBSERVE-TRIAL to capture these values with the input snapshot.
Specializations must classify during this invocation, never by rerunning it."))

(defmethod evaluate-trial ((property property) arguments &key context)
  "Evaluate an ordinary property once and classify false results and conditions."
  (declare (ignore context))
  (handler-case
      (let ((value (apply (property-function property) arguments)))
        (if value
            (values :passed nil nil nil nil value)
            (values :failed :predicate-false '(:property-false) nil nil nil)))
    (error (condition)
      (values :error :condition (list :property-condition (type-of condition))
              nil condition nil))))

(defun render-condition-report (condition)
  "Capture diagnostic text without losing evidence to a broken condition printer."
  (when condition
    (handler-case
        (let ((*print-circle* t))
          (princ-to-string condition))
      (error () (format nil "~S (condition report unavailable)" (type-of condition))))))

(defvar *trial-observations* nil
  "Fresh identity token for the active backend invocation; retains no observations.")

(defun observation-from-current-run-p (observation property)
  "Check that OBSERVATION was captured for PROPERTY during this backend invocation."
  (and *trial-observations*
       (eq *trial-observations* (trial-observation-run observation))
       (eq property (trial-observation-property observation))))

(defun observed-outcome-data (outcome)
  "Freeze target observations separately from contract classification."
  (cond
    ((null outcome) :not-collected)
    ((not (typep outcome 'call-outcome))
     (error 'invalid-backend-result :reason "evaluate-trial returned an invalid target outcome"))
    ((eq :returned (call-outcome-kind outcome))
     (list :kind :returned :values (snapshot-value (call-outcome-values outcome))))
    ((eq :signaled (call-outcome-kind outcome))
     (let ((condition (call-outcome-condition outcome)))
       (list :kind :signaled :condition-type (type-of condition)
             :condition-report (render-condition-report condition))))
    (t (error 'invalid-backend-result :reason "unknown target outcome kind"))))

(defun observation-failure-phase (observation)
  "Return the phase OBSERVATION stopped in, or NIL for a target observation.

An observation whose condition is a CASE-SELECTION-ERROR never reached the
target: the contract could not decide which required behaviour applied.  Naming
:CASE-SELECTION here lets the runner and the result report that without knowing
which classifier produced it, and keeps such a trial out of the target-failure
paths (shrinking, counterexample artifacts)."
  (when (and (typep observation 'trial-observation)
             (typep (trial-observation-condition observation) 'case-selection-error))
    :case-selection))

(defgeneric note-trial-outcome (property observation)
  (:documentation "Record one ordinary trial OBSERVATION of PROPERTY, if the run keeps evidence.

The backend calls this once per generated trial and never for a shrink candidate,
so a specialization can keep per-run counters without counting shrinking.  The
default keeps nothing: an ordinary PROPERTY has no per-case state to aggregate.")
  (:method ((property property) observation)
    (declare (ignore property observation))
    nil))

(defun observe-trial (property arguments &key context)
  "Evaluate generated objects once, snapshot evidence and record invocation provenance.
Mutations of conses and arrays, including changed sharing, stop backend shrinking.
The optional eighth EVALUATE-TRIAL value names the selected function-spec case, or
NIL when none was selected, and is recorded on the observation."
  (let ((snapshot (snapshot-value arguments)))
    (multiple-value-bind (status reason signature explanation condition value outcome
                          selected-case)
        (evaluate-trial property arguments :context context)
      (unless (and (member status '(:passed :rejected :failed :error))
                   (if (member status '(:failed :error))
                       (and reason (consp signature)
                            (if (eq status :error)
                                (typep condition 'error)
                                (null condition)))
                       (not (or reason signature explanation condition)))
                   (or (null selected-case) (keywordp selected-case)))
        (error 'invalid-backend-result
               :reason "evaluate-trial returned an invalid status or inconsistent evidence"))
      (make-trial-observation
       :run *trial-observations* :property property
       :arguments snapshot
       :arguments-mutated-p (not (same-value-p snapshot arguments))
       :status status :reason reason
       :signature (snapshot-value signature)
       :explanation (snapshot-value explanation)
       :condition condition
       :condition-report (render-condition-report condition)
       :outcome (observed-outcome-data outcome)
        :value (snapshot-value value)
        :case selected-case))))
