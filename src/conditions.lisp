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
           #:no-generator-backend
           #:invalid-spec-form
           #:invalid-spec-form-form
           #:invalid-spec-form-reason
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

(define-condition generator-unavailable (cl-spec-error)
  ((spec :initarg :spec
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
