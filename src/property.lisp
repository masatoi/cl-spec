;;;; src/property.lisp
;;;;
;;;; Property IR (specification §4, §39).  A property is not just a test: it is
;;;; a registered, introspectable statement about a set of target symbols, and
;;;; the registry indexes it so that an agent editing TRANSFER can ask which
;;;; properties must be re-run.

(defpackage #:cl-spec/src/property
  (:use #:cl)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-property)
  (:export #:property
           #:property-name
           #:property-arguments
           #:property-targets
           #:property-kind
           #:property-tags
           #:property-documentation
           #:property-body
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
              :documentation "List of (VARIABLE SPEC-DESIGNATOR) bindings the
generator fills in.")
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
