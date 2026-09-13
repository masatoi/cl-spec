;;;; src/generator-definition.lisp
;;;;
;;;; User-defined generators (specification §11).  A domain object's admissible
;;;; values usually cannot be read off its class -- an ACCOUNT's balance floor,
;;;; the currencies it may hold and the KYC rule behind its state all live in
;;;; code -- so a spec may name a generator that produces its values instead of
;;;; describing them.

(defpackage #:cl-spec/src/generator-definition
  (:use #:cl)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-generator)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots
                #:call-with-definition-rollback
                #:finite-definition-form-p #:definition-keyword-plist-p)
  (:export #:custom-generator
           #:custom-generator-name
           #:custom-generator-function
           #:custom-generator-documentation
           #:custom-generator-source-form
           #:custom-generator-source-location
           #:invalid-generator-form #:invalid-generator-form-reason
           #:invalid-generator-form-form
           #:register-generator))

(in-package #:cl-spec/src/generator-definition)

(define-condition invalid-generator-form (error)
  ((reason :initarg :reason :reader invalid-generator-form-reason
           :documentation "The violated generator invariant.")
   (form :initarg :form :reader invalid-generator-form-form
         :documentation "The offending generator field or update."))
  (:documentation "A malformed custom generator definition or inconsistent update.")
  (:report (lambda (condition stream)
             (format stream "Invalid generator definition: ~A"
                     (invalid-generator-form-reason condition)))))

(defclass custom-generator ()
  ((name :initarg :name
         :initform nil
         :reader custom-generator-name
         :documentation "Symbol this generator is registered under.  A spec
names it in a (:GENERATOR NAME) clause, and the backend resolves that name in
the same registry the spec was resolved in.")
   (function :initarg :function
             :initform nil
             :reader custom-generator-function
             :documentation "Function of no arguments returning one generated
value.  The backend calls it once per draw.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader custom-generator-documentation
                         :documentation "The definition's docstring, or NIL.")
   (source-form :initarg :source-form
                :initform nil
                :reader custom-generator-source-form
                :documentation "The whole DEFGENERATOR form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader custom-generator-source-location
                    :documentation "Source location plist, or NIL."))
  (:documentation "A value generator that a spec names instead of describing.

An entity of its own rather than a slot on the spec, so that one generator can
be shared by several specs and found by name the way a spec or a contract can."))

(defmethod definition-validation-slots append ((generator custom-generator))
  '(name function documentation-string source-form source-location))

(defmethod shared-initialize :around ((generator custom-generator) slot-names
                                     &rest initargs &key &allow-other-keys)
  (declare (ignore slot-names))
  (call-with-definition-rollback
   generator
   (lambda ()
     (when (and (slot-boundp generator 'source-form)
                (custom-generator-source-form generator)
                (not (eq (loop for key in initargs by #'cddr thereis (eq key :function))
                         (loop for key in initargs by #'cddr thereis (eq key :source-form)))))
       (error 'invalid-generator-form :reason :source-function-update-required :form initargs))
     (call-next-method))))

(defmethod shared-initialize :after ((generator custom-generator) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition generator))

(defmethod validate-definition ((generator custom-generator))
  "Validate generator identity, executable function and finite source metadata."
  (flet ((require-field (valid reason value)
           (unless valid (error 'invalid-generator-form :reason reason :form value))))
    (let ((name (custom-generator-name generator))
          (function (custom-generator-function generator))
          (documentation (custom-generator-documentation generator))
          (source (custom-generator-source-form generator))
          (location (custom-generator-source-location generator)))
      (require-field (and name (symbolp name) (not (keywordp name)) (not (constantp name)))
                     :invalid-name name)
      (require-field (functionp function) :invalid-function function)
      (require-field (typep documentation '(or null string)) :invalid-documentation documentation)
      (require-field (and (finite-list-p source) (finite-definition-form-p source))
                     :invalid-source-form source)
      (require-field (and (definition-keyword-plist-p location)
                          (finite-definition-form-p location))
                     :invalid-source-location location)))
  generator)

(defun register-generator (generator &optional (registry *registry*))
  "Register GENERATOR in REGISTRY under its own name and return it."
  (registry-register-generator registry
                               (custom-generator-name generator)
                               generator))
