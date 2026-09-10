;;;; src/conditions.lisp
;;;;
;;;; Condition hierarchy for cl-spec (specification §21, §47).  Every condition
;;;; the framework signals inherits from CL-SPEC-ERROR so that callers can trap
;;;; the framework as a whole.

(defpackage #:cl-spec/src/conditions
  (:use #:cl)
  (:export #:cl-spec-error
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
           #:generator-unavailable
           #:generator-unavailable-spec
           #:generator-unavailable-reason
           #:unsupported-seed))

(in-package #:cl-spec/src/conditions)

(define-condition cl-spec-error (error)
  ()
  (:documentation "Root of every condition signalled by cl-spec."))

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

(define-condition no-generator-backend (cl-spec-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "No generator backend is installed. ~
                             Load the CL-SPEC/CHECK-IT system to install one.")))
  (:documentation
   "Signalled when generation is requested while *GENERATOR-BACKEND* is NIL."))

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
             (format stream "~S is not a valid spec form~@[: ~A~]."
                     (invalid-spec-form-form condition)
                     (invalid-spec-form-reason condition))))
  (:documentation
   "Signalled when NORMALIZE-SPEC-FORM cannot make sense of a form."))

(define-condition invalid-property-form (cl-spec-error)
  ((form :initarg :form
         :initform nil
         :reader invalid-property-form-form
         :documentation "The DEFPROPERTY option clause that could not be parsed.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-property-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (format stream "~S is not a valid DEFPROPERTY clause~@[: ~A~]."
                     (invalid-property-form-form condition)
                     (invalid-property-form-reason condition))))
  (:documentation
   "Signalled when DEFPROPERTY cannot make sense of one of its option clauses."))

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
             (format stream "~S is not a valid function spec clause~@[: ~A~]."
                     (invalid-function-spec-form-form condition)
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
