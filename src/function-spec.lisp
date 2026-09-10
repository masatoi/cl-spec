;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unknown-function-spec
                #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-find-function-spec
                #:registry-register-function-spec)
  (:import-from #:cl-spec/src/property
                #:property)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-status
                #:property-result-property
                #:property-result-trials
                #:property-result-seed
                #:property-result-profile
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:property-result-elapsed
                #:run-property)
  (:import-from #:cl-spec/src/validator
                #:validp)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-return-spec
           #:function-spec-preconditions
           #:function-spec-postconditions
           #:function-spec-precondition-function
           #:function-spec-postcondition-function
           #:function-spec-documentation
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:register-function-spec
           #:function-check-result
           #:function-check-result-function
           #:function-check-result-rejected
           #:function-check-result-failure-reason
           #:function-check-result-explanation
           #:check-function))

(in-package #:cl-spec/src/function-spec)

(defclass function-spec ()
  ((name :initarg :name
         :initform nil
         :reader function-spec-name
         :documentation "Package-qualified symbol naming the specified function.")
   (argument-specs :initarg :argument-specs
                   :initform nil
                   :reader function-spec-argument-specs
                   :documentation "List of (PARAMETER SPEC) pairs in lambda list
order, from :ARGS.  SPEC is always a Semantic IR object: a designator handed to
the constructor is normalized in place, so every reader sees one shape.  Each
PARAMETER is named once.")
   (return-spec :initarg :return-spec
                :initform nil
                :reader function-spec-return-spec
                :documentation "Semantic IR object the return value must
satisfy, from :RETURNS, or NIL when the contract names none.")
   (preconditions :initarg :preconditions
                  :initform nil
                  :reader function-spec-preconditions
                  :documentation "The :PRE forms as written, kept for reading
(specification §19).  PRECONDITION-FUNCTION is what actually runs.")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-spec-postconditions
                   :documentation "The :POST forms as written, kept for reading.
POSTCONDITION-FUNCTION is what actually runs.")
   (precondition-function :initarg :precondition-function
                          :initform nil
                          :reader function-spec-precondition-function
                          :documentation "Compiled predicate over the parameters,
true when every :PRE form holds, or NIL when the contract has no :PRE.

Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.")
   (postcondition-function :initarg :postcondition-function
                           :initform nil
                           :reader function-spec-postcondition-function
                           :documentation "Compiled predicate over the return
value followed by the parameters, true when every :POST form holds, or NIL when
the contract has no :POST.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader function-spec-documentation
                         :documentation "Docstring of the contract, or NIL.

This is the contract's own prose, not the function's: it says what the contract
claims, which is what an agent asking \"what may I pass here\" needs.")
   (source-form :initarg :source-form
                :initform nil
                :reader function-spec-source-form
                :documentation "The whole DEFSPEC-FUNCTION form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader function-spec-source-location
                    :documentation "Source location plist, or NIL.")
   (metadata :initarg :metadata
             :initform nil
             :reader function-spec-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "A contract attached to an existing function by name.

The function is never redefined, so an existing codebase adopts cl-spec one
function at a time (specification §3.2)."))

(defparameter *function-spec-slot-names*
  '(name argument-specs return-spec preconditions postconditions
    precondition-function postcondition-function documentation-string
    source-form source-location metadata)
  "Every slot of FUNCTION-SPEC, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod shared-initialize :around ((contract function-spec) slot-names &rest initargs)
  "Leave CONTRACT as it was when initialization is refused.

The :AFTER method below validates, but by the time it runs the standard method
has already written the initargs into the slots.  So catching its refusal left
the object holding exactly the state the check exists to refuse -- and
discarding it is not open to the caller, because REGISTER-FUNCTION-SPEC stores
the object by identity: the registry, FIND-FUNCTION-SPEC, FUNCTION-SPEC-DATA
and CHECK-FUNCTION are all aliased to that one instance.  A refused
REINITIALIZE-INSTANCE could leave a registered contract whose :PRECONDITIONS
the checker then ignored while reporting :PASSED, or whose argument specs no
longer normalized, and a refused :RETURN-SPEC typo destroyed a return spec that
had been fine.

Restoring an unbound slot writes NIL rather than making it unbound again, which
matters only during MAKE-INSTANCE -- where the object is discarded anyway."
  (let ((snapshot (loop for slot in *function-spec-slot-names*
                        collect (cons slot (when (slot-boundp contract slot)
                                             (slot-value contract slot)))))
        (committed nil))
    (unwind-protect
         (multiple-value-prog1 (apply #'call-next-method contract slot-names initargs)
           (setf committed t))
      (unless committed
        (loop for (slot . value) in snapshot
              do (setf (slot-value contract slot) value))))))

(defmethod shared-initialize :after ((contract function-spec) slot-names &key)
  "Refuse a contract that could not be honoured, and normalize what can be.

Enforced here rather than in CHECK-FUNCTION because the class and
REGISTER-FUNCTION-SPEC are both public: a contract can be built without the
DSL, and every consumer -- the checker, FUNCTION-SPEC-DATA, a future printer --
would otherwise have to re-derive the same invariants or be handed an object
the others rejected.

On SHARED-INITIALIZE rather than INITIALIZE-INSTANCE, because MAKE-INSTANCE is
not the only standard way to fill these slots: REINITIALIZE-INSTANCE and
CHANGE-CLASS reach them too, and a check that covers only the first lets the
second put back exactly the states it exists to refuse.

Three invariants:

A clause's forms and its compiled predicate are present together or not at all.
Forms alone cannot be run -- §60 forbids runtime EVAL, so the predicate cannot
be recovered from them -- and the checker would report :PASSED for a claim it
ignored.  A predicate alone is the same failure seen from the other side: it
runs, so inputs are refused and results judged, while FUNCTION-SPEC-DATA
reports the contract as having no such clause.

A parameter is named once.  §14's counterexample is a {name value} plist, and
one built over a name bound twice is not one: GETF answers with the first
value and the second cannot be recovered, so the counterexample reported for a
failure cannot reproduce it.

Spec designators are normalized rather than refused, because unlike a
predicate they can be recovered: NORMALIZE-SPEC-FORM is pure, and returns an
already-normalized spec unchanged, so the DSL's output passes through
untouched.  Without this a contract built through the class reached the
generator as a bare symbol and signalled NO-APPLICABLE-METHOD."
  (declare (ignore slot-names))
  (flet ((refuse (form reason)
           (error 'invalid-function-spec-form :form form :reason reason))
         (half (forms-initarg function-initarg forms predicate)
           (cond ((and forms (null predicate))
                  (format nil "~A was given without ~A, and a compiled ~
predicate cannot be recovered from the forms"
                          forms-initarg function-initarg))
                 ((and predicate (null forms))
                  (format nil "~A was given without ~A, so the predicate ~
would run while introspection reported no such clause"
                          function-initarg forms-initarg)))))
    (let ((pre (half ":preconditions" ":precondition-function"
                     (function-spec-preconditions contract)
                     (function-spec-precondition-function contract)))
          (post (half ":postconditions" ":postcondition-function"
                      (function-spec-postconditions contract)
                      (function-spec-postcondition-function contract))))
      (when pre
        (refuse (or (function-spec-preconditions contract)
                    (function-spec-precondition-function contract))
                pre))
      (when post
        (refuse (or (function-spec-postconditions contract)
                    (function-spec-postcondition-function contract))
                post)))
    (let ((seen '()))
      (setf (slot-value contract 'argument-specs)
            (loop for entry in (function-spec-argument-specs contract)
                  do (unless (and (consp entry)
                                  (= 2 (length entry))
                                  (first entry)
                                  (symbolp (first entry))
                                  (not (keywordp (first entry))))
                       ;; Not merely malformed: (amount integer extra) would
                       ;; otherwise pass through with EXTRA silently dropped.
                       (refuse entry "expected (parameter spec)"))
                     (when (member (first entry) seen)
                       (refuse entry "the same parameter is named twice"))
                     (push (first entry) seen)
                  collect (list (first entry) (normalize-spec-form (second entry))))))
    (let ((returns (function-spec-return-spec contract)))
      (when returns
        (setf (slot-value contract 'return-spec) (normalize-spec-form returns))))))

(defun register-function-spec (function-spec &optional (registry *registry*))
  "Register FUNCTION-SPEC in REGISTRY under its own name and return it."
  (registry-register-function-spec registry
                                   (function-spec-name function-spec)
                                   function-spec))

(defun resolve-function-spec (designator registry)
  "Return the function spec DESIGNATOR names, signalling UNKNOWN-FUNCTION-SPEC.

This lives here rather than beside RESOLVE-SPEC and RESOLVE-PROPERTY because
CHECK-FUNCTION needs the property runner, which needs SRC/RESOLVE: putting the
function spec case there would close the dependency graph into a cycle."
  (if (typep designator 'function-spec)
      designator
      (multiple-value-bind (entry found-p)
          (registry-find-function-spec registry designator)
        (if found-p
            entry
            (error 'unknown-function-spec :name designator)))))

(defclass function-check-result (property-result)
  ((rejected :initarg :rejected
             :initform 0
             :reader function-check-result-rejected
             :documentation "Generated argument lists the preconditions refused.

TRIALS counts what the backend generated; TRIALS minus this is the number of
trials that reached the function.  Reporting only the first would let a run
that rejected every input read as a run that checked every input (§19, §73.3).

Not the number of calls: shrinking runs the function many more times after the
failing trial, and so does the re-run that names the broken half.  This counts
trials, which is what the trial budget is about.")
   (failure-reason :initarg :failure-reason
                   :initform nil
                   :reader function-check-result-failure-reason
                   :documentation "Which half of the contract broke:
:RETURN-SPEC, :POSTCONDITION, :CONDITION, or NIL.

It describes the counterexample this result puts forward -- the shrunk one
when there is one, the original otherwise -- and the status agrees with it.

There is no :PRECONDITION: the trial predicate answers true for every input
:PRE refuses, so one can never be the reason a run failed.

NIL on a passing run, and also on a failing run neither counterexample
reproduced -- a function that does not answer the same way twice.  The two are
told apart by the status, not by this slot.")
   (explanation :initarg :explanation
                :initform nil
                :reader function-check-result-explanation
                :documentation "EXPLAIN-DATA for a :RETURN-SPEC failure, else NIL.

\"The return value is wrong\" is not actionable on its own; this says which
part of the return spec the value missed."))
  (:documentation "Outcome of checking a function against its registered contract.

A PROPERTY-RESULT, so one set of readers covers a DEFPROPERTY run and a
CHECK-FUNCTION run alike.  The inherited PROPERTY slot holds the specified
function's name: the run's identity is the contract, and the contract is
registered under that name."))

(defun function-check-result-function (result)
  "Return the name of the function RESULT checked.

The same symbol PROPERTY-RESULT-PROPERTY returns, under the name that says what
it is here."
  (property-result-property result))

(defun function-spec-target (contract)
  "Return the function CONTRACT specifies, signalling UNDEFINED-FUNCTION otherwise.

A contract may be registered before the function it describes exists -- §3.2
adopts cl-spec one function at a time -- so the absence is reported at check
time rather than at definition time."
  (let ((name (function-spec-name contract)))
    (unless (fboundp name)
      (error 'undefined-function :name name))
    (symbol-function name)))

(defun counterexample-values (plist)
  "Return the values of a {name value} counterexample PLIST, in argument order."
  (loop for (nil value) on plist by #'cddr
        collect value))

(defun classify-function-failure (contract target arguments registry)
  "Return (values REASON EXPLANATION CONDITION) for ARGUMENTS breaking CONTRACT.

REASON is NIL when ARGUMENTS do not break it -- including when :PRE refuses
them, which makes them not a counterexample at all rather than a counterexample
of a fourth kind.  The trial predicate answers true for every input :PRE
refuses, so one can never be the reason a run failed; reporting :PRECONDITION
read as \"your caller broke the contract, the function is fine\" for runs where
the function was the broken thing.

Only the call to TARGET is caught.  A condition from the contract's own parts
-- its :PRE or :POST predicate, or the :RETURNS spec -- is an authoring bug in
the contract, not a finding about the function, and is left to propagate.
Catching those said \"the function signalled\" for a contract naming a predicate
that does not exist, and put forward a minimal counterexample in a run where
every input produced the identical error.  SRC/EXPLAIN.LISP re-signals the same
class of condition for the same reason: the reader is pointed at the broken
spec rather than told the value is bad.

CONDITION is the one ARGUMENTS actually signal, captured here rather than taken
from the trial loop, whose condition belongs to whichever input failed first
and need not be this one."
  (let ((return-spec (function-spec-return-spec contract))
        (precondition (function-spec-precondition-function contract))
        (postcondition (function-spec-postcondition-function contract)))
    (if (and precondition (not (apply precondition arguments)))
        (values nil nil nil)
        (multiple-value-bind (result signalled)
            (handler-case (values (apply target arguments) nil)
              (error (condition) (values nil condition)))
          (cond
            (signalled (values :condition nil signalled))
            ((and return-spec (not (validp return-spec result :registry registry)))
             (values :return-spec
                     (explain-data return-spec result :registry registry)
                     nil))
            ((and postcondition (not (apply postcondition result arguments)))
             (values :postcondition nil nil))
            (t (values nil nil nil)))))))

(defun reproduce-function-failure (contract target result registry)
  "Return (values REASON EXPLANATION CONDITION SHRUNK-USABLE-P) for RESULT.

The shrunk counterexample is tried first, and used only if it really breaks
the contract.  It need not: the backend counts a signalled condition as \"still
fails\" while shrinking, which is right for a property -- §13 says a signalled
condition is a failure -- but lets a shrink candidate the target cannot even be
applied to pass for a smaller counterexample.  Against a STRING argument that
is not hypothetical: CHECK-IT hands the test the cached character list, the
target signals on it, and shrinking walks out of the failing region entirely.
The value then reported as \"the value an agent should be shown first\" is one
the contract holds for.

So the first candidate that reproduces wins, and the original counterexample is
the fallback.  When neither reproduces, REASON is NIL, which is the slot's
documented meaning -- a function that does not answer the same way twice -- and
now says only that."
  (let ((candidates (remove-duplicates
                     (list (counterexample-values
                            (property-result-shrunk-counterexample result))
                           (counterexample-values
                            (property-result-counterexample result)))
                     :test #'equal
                     :from-end t)))
    (loop for candidate in candidates
          for shrunk-usable = (equal candidate (first candidates))
          do (multiple-value-bind (reason explanation condition)
                 (classify-function-failure contract target candidate registry)
               (when reason
                 (return (values reason explanation condition
                                 (and shrunk-usable
                                      (property-result-shrunk-counterexample result)
                                      t)))))
          finally (return (values nil nil nil nil)))))

(defun check-function (function-designator &key trials seed options (registry *registry*))
  "Generatively check FUNCTION-DESIGNATOR against its registered contract.

Arguments are generated from the :ARGS specs, :PRE filters the generated
inputs, the function is called, and the value it returns is checked against
:RETURNS and then :POST (specification §18).  TRIALS overrides the backend's
default trial count; SEED reproduces an earlier run; OPTIONS is passed through
to the backend.

Returns a FUNCTION-CHECK-RESULT, which is a PROPERTY-RESULT carrying the seed,
the trial count, the counterexample and its shrunk form, plus the count of
inputs :PRE refused and which half of the contract broke.

A run that never called the function reports :SKIPPED, never :PASSED --
whether because :PRE refused every generated input or because TRIALS was zero.
Nothing called the function, so nothing about it was checked."
  ;; Checked before anything is resolved.  A negative count makes the backend's
  ;; trial loop run zero times and report :PASSED with that count, and the
  ;; vacuous-run guard below reads a negative EXECUTED as "some trials ran" --
  ;; a verified contract whose function was never called.
  (unless (or (null trials) (and (integerp trials) (not (minusp trials))))
    (error 'type-error :datum trials :expected-type '(or null (integer 0 *))))
  ;; The seed is guarded here for the same reason, and a result is accepted in
  ;; its place the way REPLAY-PROPERTY accepts one: FUNCTION-CHECK-RESULT is a
  ;; PROPERTY-RESULT so that one reader set covers both, and digging the
  ;; integer back out of it was the only spelling that worked.  Unguarded, an
  ;; unusable seed reached SEED->RANDOM-STATE and leaked a condition naming an
  ;; internal symbol.
  (unless (or (null seed)
              (typep seed 'property-result)
              (and (integerp seed) (not (minusp seed))))
    (error 'type-error :datum seed
                       :expected-type '(or null property-result (integer 0 *))))
  (let* ((seed (if (typep seed 'property-result) (property-result-seed seed) seed))
         (contract (resolve-function-spec function-designator registry))
         (name (function-spec-name contract))
         (target (function-spec-target contract))
         (return-spec (function-spec-return-spec contract))
         (precondition (function-spec-precondition-function contract))
         (postcondition (function-spec-postcondition-function contract))
         (rejected 0)
         ;; Shrinking re-runs this predicate long after the failing trial, and
         ;; those runs are not trials.  Counting stops at the first real
         ;; failure so REJECTED stays a statement about generation.
         (countingp t)
         (property
           (make-instance 'property
                          :name name
                          :arguments (function-spec-argument-specs contract)
                          :targets (list name)
                          :kind :function-spec
                          :documentation (function-spec-documentation contract)
                          :trials (when trials (list :normal trials))
                          :source-form (function-spec-source-form contract)
                          :source-location (function-spec-source-location contract)
                          :metadata (list :shrink t)
                          :function
                          (lambda (&rest arguments)
                            ;; A signalled condition ends the trial loop
                            ;; exactly as a false result does, so counting has
                            ;; to stop there too: everything the backend runs
                            ;; afterwards is shrinking, and a shrink candidate
                            ;; :PRE refuses is not a rejected trial.  Left
                            ;; counting, REJECTED overtakes TRIALS and the
                            ;; call count they imply goes negative.
                            ;;
                            ;; HANDLER-BIND rather than HANDLER-CASE: the
                            ;; handler declines, so the condition still
                            ;; reaches the backend unchanged and the run is
                            ;; still reported as :ERROR.
                            (handler-bind ((error (lambda (condition)
                                                    (declare (ignore condition))
                                                    (setf countingp nil))))
                              (if (and precondition
                                       (not (apply precondition arguments)))
                                  (progn
                                    (when countingp (incf rejected))
                                    t)
                                  (let ((result (apply target arguments)))
                                    (cond
                                      ((and return-spec
                                            (not (validp return-spec result
                                                         :registry registry)))
                                       (setf countingp nil)
                                       nil)
                                      ((and postcondition
                                            (not (apply postcondition result arguments)))
                                       (setf countingp nil)
                                       nil)
                                      (t t))))))))
         (result (run-property property :seed seed :options options :registry registry))
         (executed (- (or (property-result-trials result) 0) rejected))
         (backend-status (property-result-status result))
         ;; NOT PLUSP rather than ZEROP: the question is whether any trial
         ;; reached the function, and a count that is not positive answers no
         ;; however it got that way.
         (vacuous (and (eq :passed backend-status) (not (plusp executed)))))
    (multiple-value-bind (reason explanation condition shrunk-usable)
        (if (member backend-status '(:failed :error))
            ;; Under the run's own seed.  RUN-PROPERTY binds *RANDOM-STATE*
            ;; around the trial and shrink loop so a run can be replayed; this
            ;; re-run happens after it returns, and it decides the reported
            ;; status.  Left on the ambient state, a target that reads mutable
            ;; state gave two different verdicts for one seed -- the same
            ;; counterexample and the same shrunk value, reported once as
            ;; :ERROR and once as :FAILED.
            (let ((*random-state* (seed->random-state (property-result-seed result))))
              (reproduce-function-failure contract target result registry))
            (values nil nil nil nil))
      (make-instance 'function-check-result
                     ;; The status describes the counterexample the result puts
                     ;; forward.  The backend's own comes from the first
                     ;; failing trial, and shrinking can cross from one half of
                     ;; the contract to the other: that gave :ERROR beside a
                     ;; minimal input signalling nothing, and :FAILED beside
                     ;; :CONDITION with no condition to look at.
                     :status (cond (vacuous :skipped)
                                   ((eq :condition reason) :error)
                                   ((member reason '(:return-spec :postcondition)) :failed)
                                   (t backend-status))
                     :property name
                     :trials (property-result-trials result)
                     :seed (property-result-seed result)
                     :profile (property-result-profile result)
                     :counterexample (property-result-counterexample result)
                     :shrunk-counterexample (when shrunk-usable
                                              (property-result-shrunk-counterexample result))
                     :condition (if reason condition (property-result-condition result))
                     :elapsed (property-result-elapsed result)
                     :rejected rejected
                     :failure-reason reason
                     :explanation explanation))))
