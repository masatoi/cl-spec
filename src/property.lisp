;;;; src/property.lisp
;;;;
;;;; Property IR (specification §4, §39).  A property is not just a test: it is
;;;; a registered, introspectable statement about a set of target symbols, and
;;;; the registry indexes it so that an agent editing TRANSFER can ask which
;;;; properties must be re-run.

(defpackage #:cl-spec/src/property
  (:use #:cl)
  (:import-from #:cl-spec/src/ir #:tuple-spec)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-property)
  (:export #:property
           #:property-name
           #:property-arguments #:property-argument-schema
           #:property-targets
           #:property-kind
           #:property-tags
           #:property-documentation
           #:property-body
           #:property-function
           #:property-source-form
           #:property-source-location
           #:property-trials
           #:property-metadata
           #:register-property))

(in-package #:cl-spec/src/property)

(defclass property ()
  ((name :initarg :name
         :initform nil
         :reader property-name
         :documentation "Package-qualified symbol naming this property.")
   (arguments :initarg :arguments
              :initform nil
              :reader property-arguments
              :documentation "List of (VARIABLE SPEC) bindings the generator
fills in.  SPEC is a normalized Semantic IR object; a spec written as a bare
symbol becomes a REFERENCE-SPEC, so a property may name a spec defined later.")
   (targets :initarg :targets
            :initform nil
            :reader property-targets
            :documentation "Symbols this property is about, from :ABOUT.
Indexed for reverse lookup.")
   (kind :initarg :kind
         :initform nil
         :reader property-kind
         :documentation "Classification keyword such as :INVARIANT or
:ROUND-TRIP (specification §6).")
   (tags :initarg :tags
         :initform nil
         :reader property-tags
         :documentation "Tag designators, indexed for reverse lookup.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader property-documentation
                         :documentation "Human readable description, or NIL.")
   (property-function :initarg :function
                      :initform nil
                      :reader property-function
                      :documentation "The predicate compiled from BODY.
Kept alongside BODY rather than instead of it: a compiled function cannot be
read, and reading the property is half of what it is for (specification §39).")
   (body :initarg :body
         :initform nil
         :reader property-body
         :documentation "Forms of the property predicate, kept verbatim so that
introspection can show the author's source.")
   (source-form :initarg :source-form
                :initform nil
                :reader property-source-form
                :documentation "The whole DEFPROPERTY form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader property-source-location
                    :documentation "Source location plist, or NIL.")
   (trials :initarg :trials
           :initform nil
           :reader property-trials
           :documentation "Per-profile trial counts, for example
(:SMOKE 10 :NORMAL 100) (specification §33).")
   (metadata :initarg :metadata
             :initform nil
             :reader property-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "A registered, executable statement about program behaviour."))

(defgeneric property-argument-schema (property)
  (:documentation "Return the whole positional argument tuple spec compiled by a backend."))

(defmethod property-argument-schema ((property property))
  "Derive an independent tuple generator from the ordinary property bindings."
  (make-instance 'tuple-spec :element-specs (mapcar #'second (property-arguments property))))

(defun register-property (property &optional (registry *registry*))
  "Register PROPERTY in REGISTRY under its own name and return PROPERTY.

The target and tag index keys are taken from the property object, which is why
this function lives here rather than in the registry: the registry deliberately
knows nothing about property objects."
  (registry-register-property registry
                              (property-name property)
                              property
                              :targets (property-targets property)
                              :tags (property-tags property)))
