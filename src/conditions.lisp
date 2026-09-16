;;;; src/conditions.lisp
;;;;
;;;; Condition hierarchy for cl-spec (specification §21, §47).  Every condition
;;;; the framework signals inherits from CL-SPEC-ERROR so that callers can trap
;;;; the framework as a whole.

(defpackage #:cl-spec/src/conditions
  (:use #:cl)
  (:export #:invalid-backend-result
           #:invalid-backend-result-reason
           #:cl-spec-error
           #:not-implemented
           #:not-implemented-operator
           #:spec-violation
           #:spec-violation-spec
           #:spec-violation-value
           #:spec-violation-path
           #:spec-violation-errors
           #:unknown-spec
           #:unknown-spec-name
           #:unknown-property
           #:unknown-property-name
           #:unknown-function-spec
           #:unknown-function-spec-name
           #:unbound-target
           #:no-generator-backend
           #:invalid-spec-form
           #:invalid-spec-form-form
           #:invalid-spec-form-reason
           #:invalid-property-form
           #:invalid-property-form-form
           #:invalid-property-form-reason
           #:invalid-function-spec-form
           #:invalid-function-spec-form-form
           #:invalid-function-spec-form-reason
           #:invalid-generator-form
           #:invalid-generator-form-form
           #:invalid-generator-form-reason
           #:invalid-generated-arguments #:invalid-generated-arguments-generator
           #:invalid-generated-arguments-value #:invalid-generated-arguments-reason
           #:generator-unavailable
           #:generator-unavailable-spec
           #:generator-unavailable-reason
           #:generation-budget-exhausted
           #:generation-budget-exhausted-report
           #:generation-budget-exhausted-request
           #:generation-budget-exhausted-attempts
           #:generation-budget-exhausted-rejections
           #:generation-budget-exhausted-budget
           #:generation-budget-exhausted-phase
           #:generation-budget-exhausted-path
           #:case-selection-error
           #:case-selection-error-function
           #:case-selection-error-kind
           #:case-selection-error-cases
           #:case-selection-error-case
           #:case-selection-error-original-condition
           #:case-selection-error-data
           #:capture-error
           #:capture-error-function
           #:capture-error-binding
           #:capture-error-index
           #:capture-error-captured
           #:capture-error-original-condition
           #:capture-error-data
           #:state-post-error
           #:state-post-error-function
           #:state-post-error-case
           #:state-post-error-index
           #:state-post-error-form
           #:state-post-error-original-condition
           #:state-post-error-data
           #:unsupported-stateful-operation
           #:unsupported-stateful-operation-operation
           #:unsupported-stateful-operation-function
           #:unsupported-stateful-operation-reason
           #:unsupported-seed))

(in-package #:cl-spec/src/conditions)

(define-condition cl-spec-error (error)
  ()
  (:documentation "Root of every condition signalled by cl-spec."))

(define-condition invalid-backend-result (cl-spec-error)
  ((reason :initarg :reason
           :reader invalid-backend-result-reason
           :documentation "Why the backend's returned value is invalid."))
  (:report (lambda (condition stream)
             (format stream "Invalid backend result: ~A"
                     (invalid-backend-result-reason condition))))
  (:documentation "A backend violated the required trial count or evidence protocol."))

(define-condition not-implemented (cl-spec-error)
  ((operator :initarg :operator
             :reader not-implemented-operator
             :documentation "Symbol naming the operator that is still a stub."))
  (:report (lambda (condition stream)
             (format stream "~S is not implemented yet."
                     (not-implemented-operator condition))))
  (:documentation
   "Signalled by skeleton stubs that carry a settled signature but no body."))

(define-condition spec-violation (cl-spec-error)
  ((spec :initarg :spec
         :reader spec-violation-spec
         :documentation "Spec designator the value was checked against.")
   (value :initarg :value
          :reader spec-violation-value
          :documentation "Value that failed the check.")
   (path :initarg :path
         :initform nil
         :reader spec-violation-path
         :documentation "Path from the root value down to the failing part.")
   (errors :initarg :errors
           :initform nil
           :reader spec-violation-errors
           :documentation "Structured error list as produced by EXPLAIN-DATA."))
  (:report (lambda (condition stream)
             (format stream "~S does not satisfy ~S~@[ at path ~S~]."
                     (spec-violation-value condition)
                     (spec-violation-spec condition)
                     (spec-violation-path condition))))
  (:documentation "Signalled when a value fails to satisfy a spec."))

(define-condition unknown-spec (cl-spec-error)
  ((name :initarg :name
         :reader unknown-spec-name
         :documentation "Symbol that is not registered as a spec."))
  (:report (lambda (condition stream)
             (format stream "No spec named ~S is registered."
                     (unknown-spec-name condition))))
  (:documentation "Signalled when a spec designator resolves to nothing."))

(define-condition unknown-property (cl-spec-error)
  ((name :initarg :name
         :reader unknown-property-name
         :documentation "Symbol that is not registered as a property."))
  (:report (lambda (condition stream)
             (format stream "No property named ~S is registered."
                     (unknown-property-name condition))))
  (:documentation "Signalled when a property designator resolves to nothing."))

(define-condition unknown-function-spec (cl-spec-error)
  ((name :initarg :name
         :reader unknown-function-spec-name
         :documentation "Symbol that has no registered function spec."))
  (:report (lambda (condition stream)
             (format stream "No function spec is registered for ~S."
                     (unknown-function-spec-name condition))))
  (:documentation "Signalled when CHECK-FUNCTION is given a name with no contract.

Distinct from a contract that holds: an agent that reads \"nothing is
registered\" as \"nothing is wrong\" would treat an unspecified function as a
verified one."))

(define-condition unbound-target (cl-spec-error undefined-function)
  ()
  (:documentation "Signalled when a contract's function is not defined.

Inherits from both roots on purpose.  §21 promises a caller can trap the
framework as a whole, and CL-SPEC-ERROR calls itself the root of every
condition cl-spec signals -- a plain UNDEFINED-FUNCTION escaped that handler,
so one unadopted function lost a whole batch of checks.  It is still an
UNDEFINED-FUNCTION, because that is what it is, and a caller who wrote the
standard handler keeps it."))

(define-condition no-generator-backend (cl-spec-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "No generator backend is installed. ~
                             Load the CL-SPEC/CHECK-IT system to install one.")))
  (:documentation
   "Signalled when generation is requested while *GENERATOR-BACKEND* is NIL."))

(defun report-invalid-form (stream form description reason)
  "Print a malformed declaration without recursively expanding circular list structure."
  (let ((*print-circle* t)
        (*print-length* 20)
        (*print-level* 8))
    (format stream "~S is not a valid ~A~@[: ~A~]." form description reason)))

(define-condition invalid-spec-form (cl-spec-error)
  ((form :initarg :form
         :initform nil
         :reader invalid-spec-form-form
         :documentation "The spec DSL form that could not be normalized.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-spec-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (report-invalid-form stream (invalid-spec-form-form condition)
                                  "spec form"
                                  (invalid-spec-form-reason condition))))
  (:documentation
   "Signalled when NORMALIZE-SPEC-FORM cannot make sense of a form."))

(define-condition invalid-property-form (cl-spec-error)
  ((form :initarg :form
         :initform nil
         :reader invalid-property-form-form
         :documentation "The rejected DEFPROPERTY name, bindings, body, or option clause.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-property-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (report-invalid-form stream (invalid-property-form-form condition)
                                  "DEFPROPERTY declaration fragment"
                                  (invalid-property-form-reason condition))))
  (:documentation
   "Signalled when DEFPROPERTY cannot parse a declaration fragment."))

(define-condition invalid-function-spec-form (cl-spec-error)
  ((form :initarg :form
         :initform nil
         :reader invalid-function-spec-form-form
         :documentation "The clause, or the slot value, that could not be accepted.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-function-spec-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (report-invalid-form stream (invalid-function-spec-form-form condition)
                                  "function spec clause"
                                  (invalid-function-spec-form-reason condition))))
  (:documentation
   "Signalled when a function spec claims something the checker cannot honour.

Specification §17 requires that a contract the checker cannot honour is refused
rather than partially accepted: one whose unsupported half is silently dropped
would report a verified result for a claim nothing checked.

Raised from two places, which is why the report does not name a macro: from
DEFSPEC-FUNCTION at macroexpansion time for syntax the MVP does not support,
and from the FUNCTION-SPEC class for a contract built directly through the
public CLOS API in a state its own consumers could not read."))

(define-condition invalid-generator-form (cl-spec-error)
  ((form :initarg :form
         :initform nil
         :reader invalid-generator-form-form
         :documentation "The DEFGENERATOR form that could not be accepted.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-generator-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (report-invalid-form stream (invalid-generator-form-form condition)
                                  "custom generator"
                                  (invalid-generator-form-reason condition))))
  (:documentation
   "Signalled when DEFGENERATOR cannot honour the definition it was given.

The rule §17 follows for contracts: a definition this version cannot use is
refused rather than registered with part of its meaning dropped.  A generator
whose parameters were silently ignored would look like a working generator and
produce values from a body called without the bindings its author wrote."))

(define-condition invalid-generated-arguments (cl-spec-error)
  ((generator :initarg :generator :reader invalid-generated-arguments-generator
              :documentation "Name of the argument-set generator that produced invalid output.")
   (value :initarg :value :reader invalid-generated-arguments-value
          :documentation "Snapshot of the invalid generated argument set.")
   (reason :initarg :reason :reader invalid-generated-arguments-reason
           :documentation "Why the generated value cannot be used as arguments."))
  (:report (lambda (condition stream)
             (format stream "Argument generator ~S produced invalid arguments: ~A."
                     (invalid-generated-arguments-generator condition)
                     (invalid-generated-arguments-reason condition))))
  (:documentation "Signalled before invoking a target when an argument-set draw is invalid."))

(define-condition generator-unavailable (cl-spec-error)
  ((spec :initarg :spec
         :initform nil
         :reader generator-unavailable-spec
         :documentation "Spec no generator could be derived from.")
   (reason :initarg :reason
           :initform nil
           :reader generator-unavailable-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (format stream "No generator can be derived from ~S~@[: ~A~]."
                     (generator-unavailable-spec condition)
                     (generator-unavailable-reason condition))))
  (:documentation
   "Signalled when an IR node has no generation strategy on this backend."))

(define-condition generation-budget-exhausted (generator-unavailable)
  ((report :initarg :report
           :initform nil
           :reader generation-budget-exhausted-report
           :documentation "Immutable snapshot of the request's generation report
at the moment the budget was exhausted.")
   (request :initarg :request
            :initform nil
            :reader generation-budget-exhausted-request
            :documentation "Identity of the generation request whose budget ran out.

Compared by the runner against the request it owns, so an inner public request's
or a target's condition of the same class is not misread as this request's own
depletion.  The live object is internal state, never wire metadata."))
  (:report (lambda (condition stream)
             (format stream "The selected generation strategy exhausted its ~
                             candidate budget (~D of ~D attempts, ~D rejected)~
                             ~@[ at ~S~].  No claim is made that the ~
                             specification is unsatisfiable."
                     (generation-budget-exhausted-attempts condition)
                     (generation-budget-exhausted-budget condition)
                     (generation-budget-exhausted-rejections condition)
                     (generation-budget-exhausted-path condition))))
  (:documentation "Signalled when a request-owned candidate budget is exhausted.

A subclass of GENERATOR-UNAVAILABLE, so a caller that already treats \"this
generation could not complete\" as one family keeps working, while a caller that
must tell a static no-strategy refusal from dynamic budget depletion handles this
type first.  The report and the message state explicitly that exhausting a
finite budget is not a proof that the spec admits no values."))

(defun generation-budget-exhausted-attempts (condition)
  "Return the candidate reservations the request made before exhaustion."
  (getf (generation-budget-exhausted-report condition) :attempts))

(defun generation-budget-exhausted-rejections (condition)
  "Return the filter rejections the request recorded before exhaustion."
  (getf (generation-budget-exhausted-report condition) :rejections))

(defun generation-budget-exhausted-budget (condition)
  "Return the effective candidate budget of the exhausted request."
  (getf (generation-budget-exhausted-report condition) :budget))

(defun generation-budget-exhausted-phase (condition)
  "Return :GENERATION or :SHRINKING, the phase that owned the exhausted budget."
  (getf (generation-budget-exhausted-report condition) :exhaustion-phase))

(defun generation-budget-exhausted-path (condition)
  "Return the declaration path of the filter whose reservation was denied, or NIL."
  (getf (generation-budget-exhausted-report condition) :exhausted-at))

(define-condition case-selection-error (cl-spec-error)
  ((function :initarg :function
             :initform nil
             :reader case-selection-error-function
             :documentation "Name of the function whose contract was being checked.")
   (kind :initarg :kind
         :initform nil
         :reader case-selection-error-kind
         :documentation ":NO-MATCHING-CASE, :AMBIGUOUS-CASE or :CASE-GUARD-ERROR.")
   (cases :initarg :cases
          :initform nil
          :reader case-selection-error-cases
          :documentation "Case names that matched more than once, for :AMBIGUOUS-CASE.
NIL for the other kinds.")
   (case :initarg :case
         :initform nil
         :reader case-selection-error-case
         :documentation "Case whose :WHEN signalled, for :CASE-GUARD-ERROR.  NIL otherwise.")
   (original-condition :initarg :original-condition
                       :initform nil
                       :reader case-selection-error-original-condition
                       :documentation "Condition the case guard signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again."))
  (:report (lambda (condition stream)
             (ecase (case-selection-error-kind condition)
               (:no-matching-case
                (format stream "No case of ~S matches the argument bindings."
                        (case-selection-error-function condition)))
               (:ambiguous-case
                (format stream "More than one case of ~S matches the argument ~
                                bindings: ~{~S~^, ~}."
                        (case-selection-error-function condition)
                        (case-selection-error-cases condition)))
               (:case-guard-error
                (format stream "The :WHEN of case ~S of ~S signalled ~A."
                        (case-selection-error-case condition)
                        (case-selection-error-function condition)
                        (type-of (case-selection-error-original-condition condition)))))))
  (:documentation "Signalled (as captured evidence) when case selection is not unique.

Selection is exclusive: exactly one case must match the admitted input.  Zero
matches, several matches and a guard that signalled are contract-side errors,
not target failures.  The target is not invoked for any of them, so none of them
is a target counterexample or a precondition rejection.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION."))

(defun condition-report-text (condition)
  "Render CONDITION as text without losing evidence to a broken condition printer.

LOCAL to the condition vocabulary: SRC/EXECUTION keeps the same rule for trial
observation, but it depends on this file, so the projection here cannot reach
that helper without closing the dependency graph into a cycle."
  (when condition
    (handler-case
        (let ((*print-circle* t))
          (princ-to-string condition))
      (error () (format nil "~S (condition report unavailable)" (type-of condition))))))

(defun case-selection-error-data (condition)
  "Project CONDITION as the explanation plist a function-check result carries.

The shape is fixed: :KIND is always :CASE-SELECTION-ERROR, :CASE-ERROR is the
selection error kind, :FUNCTION names the contract, :CASES lists the ambiguous
matches, and :CASE, :CONDITION-TYPE and :CONDITION-REPORT describe the guard that
signalled.  Unused keys are NIL rather than absent, so a consumer reads one
shape for every kind."
  (let ((original (case-selection-error-original-condition condition)))
    (list :kind :case-selection-error
          :case-error (case-selection-error-kind condition)
          :function (case-selection-error-function condition)
          :cases (case-selection-error-cases condition)
          :case (case-selection-error-case condition)
          :condition-type (and original (type-of original))
          :condition-report (and original (condition-report-text original)))))

(define-condition unsupported-seed (cl-spec-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "Deriving a random state from an integer seed is ~
                             not supported on ~A; reproducible property runs ~
                             currently require SBCL."
                     (lisp-implementation-type))))
  (:documentation
   "Signalled when an integer seed cannot be honoured on this implementation."))

(define-condition capture-error (cl-spec-error)
  ((function :initarg :function
             :initform nil
             :reader capture-error-function
             :documentation "Name of the function whose contract was being checked.")
   (binding :initarg :binding
            :initform nil
            :reader capture-error-binding
            :documentation "Name of the :capture binding whose form signalled.")
   (index :initarg :index
          :initform nil
          :reader capture-error-index
          :documentation "Zero-based declaration position of the failing binding.")
   (captured :initarg :captured
             :initform nil
             :reader capture-error-captured
             :documentation "Ordered (NAME . VALUE) pairs completed before the failure.
Only the bindings that finished are present; a later binding is never shown as
obtained, and a captured NIL is a pair with a NIL value rather than an absence.")
   (original-condition :initarg :original-condition
                       :initform nil
                       :reader capture-error-original-condition
                       :documentation "Condition the capture form signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again."))
  (:report (lambda (condition stream)
             (format stream "The :capture binding ~S at position ~D of ~S signalled ~A."
                     (capture-error-binding condition)
                     (capture-error-index condition)
                     (capture-error-function condition)
                     (type-of (capture-error-original-condition condition)))))
  (:documentation "Signalled (as captured evidence) when a :capture form signals.

Capture runs before the target, so the target was not called for such a trial:
this is a contract-side error, not a target failure, and it is neither a
counterexample nor a precondition rejection.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION."))

(defun capture-error-data (condition)
  "Project CONDITION as the explanation plist a function-check result carries.

The shape is fixed: :KIND is always :CAPTURE-ERROR, :BINDING and :INDEX name the
form that signalled, and :CONDITION-TYPE and :CONDITION-REPORT describe the
original condition.  The values completed before the failure are the
observation's state evidence, not part of this explanation."
  (let ((original (capture-error-original-condition condition)))
    (list :kind :capture-error
          :function (capture-error-function condition)
          :binding (capture-error-binding condition)
          :index (capture-error-index condition)
          :condition-type (and original (type-of original))
          :condition-report (and original (condition-report-text original)))))

(define-condition state-post-error (cl-spec-error)
  ((function :initarg :function
             :initform nil
             :reader state-post-error-function
             :documentation "Name of the function whose contract was being checked.")
   (case :initarg :case
         :initform nil
         :reader state-post-error-case
         :documentation "Selected case name, or NIL for a case-less contract.")
   (index :initarg :index
          :initform nil
          :reader state-post-error-index
          :documentation "Zero-based position of the :state-post form that signalled.")
   (form :initarg :form
         :initform nil
         :reader state-post-error-form
         :documentation "The :state-post form that signalled.")
   (original-condition :initarg :original-condition
                       :initform nil
                       :reader state-post-error-original-condition
                       :documentation "Condition the state-post form signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again."))
  (:report (lambda (condition stream)
             (format stream "The :state-post form at position ~D~@[ of case ~S~] ~
                             of ~S signalled ~A."
                     (state-post-error-index condition)
                     (state-post-error-case condition)
                     (state-post-error-function condition)
                     (type-of (state-post-error-original-condition condition)))))
  (:documentation "Signalled (as captured evidence) when a :state-post form signals.

The target was called for this trial, so this is a contract-side evaluation
error that still owns the selected case and retains the captured target
outcome.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION."))

(defun state-post-error-data (condition)
  "Project CONDITION as the explanation plist a function-check result carries.

The shape is fixed: :KIND is always :STATE-POST-ERROR, :CASE, :INDEX and :FORM
name the offending clause position, and :CONDITION-TYPE and :CONDITION-REPORT
describe the original condition.  Expected values are not extracted."
  (let ((original (state-post-error-original-condition condition)))
    (list :kind :state-post-error
          :function (state-post-error-function condition)
          :case (state-post-error-case condition)
          :index (state-post-error-index condition)
          :form (state-post-error-form condition)
          :condition-type (and original (type-of original))
          :condition-report (and original (condition-report-text original)))))

(define-condition unsupported-stateful-operation (cl-spec-error)
  ((operation :initarg :operation
              :reader unsupported-stateful-operation-operation
              :documentation "The refused operation, such as :REPLAY.")
   (function :initarg :function
             :initform nil
             :reader unsupported-stateful-operation-function
             :documentation "Name of the state-observing function spec.")
   (reason :initarg :reason
           :initform :state-restoration-unavailable
           :reader unsupported-stateful-operation-reason
           :documentation "Machine-readable reason the operation is unsupported."))
  (:report (lambda (condition stream)
             (format stream "Cannot ~S ~S: ~A.  The contract observes state but ~
                             no contract for rebuilding the same initial state ~
                             exists, so a past run cannot be replayed."
                     (unsupported-stateful-operation-operation condition)
                     (unsupported-stateful-operation-function condition)
                     (unsupported-stateful-operation-reason condition))))
  (:documentation "Signalled when a state-observing contract is asked to replay a past run.

A :capture / :state-post contract observes state and never restores it, so
reapplying a saved run against an unrestored state is refused explicitly rather
than performed silently.  A new run with an integer seed is not this operation
and is allowed."))
