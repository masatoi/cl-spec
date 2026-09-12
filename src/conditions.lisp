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
           #:unsupported-seed))

(in-package #:cl-spec/src/conditions)

(define-condition cl-spec-error (error)
  ()
  (:documentation "Root of every condition signalled by cl-spec."))

(define-condition invalid-backend-result (cl-spec-error)
  ((reason :initarg :reason :reader invalid-backend-result-reason))
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
