;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unknown-function-spec)
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
           #:resolve-function-spec
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
order, from :ARGS.  SPEC is a Semantic IR object once DEFSPEC-FUNCTION has
normalized it; the class itself stores whatever it is given, exactly as
PROPERTY does with its arguments.")
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

TRIALS counts what the backend generated; TRIALS minus this is what the
function was actually called with.  Reporting only the first would let a run
that rejected every input read as a run that checked every input (§19, §73.3).")
   (failure-reason :initarg :failure-reason
                   :initform nil
                   :reader function-check-result-failure-reason
                   :documentation "Which half of the contract broke:
:RETURN-SPEC, :POSTCONDITION, :PRECONDITION, :CONDITION, or NIL.

NIL on a passing run, and also on a failing run whose counterexample could not
be reproduced -- a function that is not deterministic.  The two are told apart
by the status, not by this slot.")
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
  "Return (values REASON EXPLANATION) for ARGUMENTS breaking CONTRACT.

Re-runs the checks once on the reported counterexample rather than recording a
reason during the trial loop, because the loop's last failure is not always the
one that was reported: shrinking runs the same predicate many more times after
it.  A function that gives a different answer the second time reports NIL,
which says \"not reproducible\" rather than naming a half of the contract that
may not be the one that broke."
  (let ((return-spec (function-spec-return-spec contract))
        (precondition (function-spec-precondition-function contract))
        (postcondition (function-spec-postcondition-function contract)))
    (handler-case
        (cond
          ((and precondition (not (apply precondition arguments)))
           (values :precondition nil))
          (t
           (let ((result (apply target arguments)))
             (cond
               ((and return-spec (not (validp return-spec result :registry registry)))
                (values :return-spec (explain-data return-spec result :registry registry)))
               ((and postcondition (not (apply postcondition result arguments)))
                (values :postcondition nil))
               (t (values nil nil))))))
      (error () (values :condition nil)))))

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

A run in which :PRE refused every generated input reports :SKIPPED, never
:PASSED: nothing called the function, so nothing about it was checked."
  (let* ((contract (resolve-function-spec function-designator registry))
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
                            (if (and precondition (not (apply precondition arguments)))
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
                                    (t t)))))))
         (result (run-property property :seed seed :options options :registry registry))
         (executed (- (or (property-result-trials result) 0) rejected))
         (status (if (and (eq :passed (property-result-status result)) (zerop executed))
                     :skipped
                     (property-result-status result))))
    (multiple-value-bind (reason explanation)
        (case status
          (:failed (classify-function-failure
                    contract target
                    (counterexample-values
                     (or (property-result-shrunk-counterexample result)
                         (property-result-counterexample result)))
                    registry))
          (:error (values :condition nil))
          (t (values nil nil)))
      (make-instance 'function-check-result
                     :status status
                     :property name
                     :trials (property-result-trials result)
                     :seed (property-result-seed result)
                     :profile (property-result-profile result)
                     :counterexample (property-result-counterexample result)
                     :shrunk-counterexample (property-result-shrunk-counterexample result)
                     :condition (property-result-condition result)
                     :elapsed (property-result-elapsed result)
                     :rejected rejected
                     :failure-reason reason
                     :explanation explanation))))
