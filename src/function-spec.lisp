;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-function-spec)
  (:export #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-return-spec
           #:function-spec-preconditions
           #:function-spec-postconditions
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:register-function-spec
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
                   :documentation "List of (PARAMETER SPEC-DESIGNATOR) pairs
in lambda list order, from :ARGS.")
   (return-spec :initarg :return-spec
                :initform nil
                :reader function-spec-return-spec
                :documentation "Spec designator the return value must satisfy,
from :RETURNS.")
   (preconditions :initarg :preconditions
                  :initform nil
                  :reader function-spec-preconditions
                  :documentation "Forms that must hold before the call
(specification §19).")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-spec-postconditions
                   :documentation "Forms that must hold after the call.")
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
  (:documentation "A contract attached to an existing function by name."))

(defun register-function-spec (function-spec &optional (registry *registry*))
  "Register FUNCTION-SPEC in REGISTRY under its own name and return it."
  (registry-register-function-spec registry
                                   (function-spec-name function-spec)
                                   function-spec))

(defun check-function (function-designator &key trials seed options)
  "Generatively check FUNCTION-DESIGNATOR against its registered function spec.

Arguments are generated from the argument specs, preconditions filter the
generated inputs, and the return value is checked against the return spec.
Returns a PROPERTY-RESULT.

Not implemented yet."
  (declare (ignore function-designator trials seed options))
  (error 'not-implemented :operator 'check-function))
