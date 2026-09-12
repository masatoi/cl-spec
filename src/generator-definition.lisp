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
  (:export #:custom-generator
           #:custom-generator-name
           #:custom-generator-function
           #:custom-generator-documentation
           #:custom-generator-source-form
           #:custom-generator-source-location
           #:register-generator))

(in-package #:cl-spec/src/generator-definition)

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

(defun register-generator (generator &optional (registry *registry*))
  "Register GENERATOR in REGISTRY under its own name and return it."
  (registry-register-generator registry
                               (custom-generator-name generator)
                               generator))
