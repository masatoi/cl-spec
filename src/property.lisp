;;;; src/property.lisp
;;;;
;;;; Property IR (specification §4, §39).  A property is not just a test: it is
;;;; a registered, introspectable statement about a set of target symbols, and
;;;; the registry indexes it so that an agent editing TRANSFER can ask which
;;;; properties must be re-run.

(defpackage #:cl-spec/src/property
  (:use #:cl)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots
                #:call-with-definition-rollback #:finite-definition-form-p
                #:definition-keyword-plist-p)
  (:import-from #:cl-spec/src/conditions #:invalid-property-form)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/ir #:tuple-spec)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-property)
  (:export #:validate-property-executable
           #:property
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

(defmethod definition-validation-slots append ((object property))
  '(name arguments targets kind tags documentation-string property-function body
    source-form source-location trials metadata))

(defgeneric validate-property-executable (property)
  (:documentation "Validate executable behavior; evaluator subclasses may specialize this hook."))

(defmethod validate-property-executable ((object property))
  (unless (functionp (property-function object))
    (error 'invalid-property-form :form (property-function object)
                                  :reason "a property requires a compiled function"))
  object)

(defmethod validate-definition ((object property))
  "Validate public construction invariants and normalize argument spec designators."
  (flet ((refuse (form reason)
           (error 'invalid-property-form :form form :reason reason))
         (forms-p (value)
           (and (finite-list-p value) (finite-definition-form-p value))))
    (unless (and (symbolp (property-name object)) (property-name object)
                 (not (constantp (property-name object))) (not (keywordp (property-name object))))
      (refuse (property-name object) "name must be a nonconstant, nonkeyword symbol"))
    (dolist (symbols (list (property-targets object) (property-tags object)))
      (unless (and (finite-list-p symbols) (every #'symbolp symbols))
        (refuse symbols "targets and tags must be finite lists of symbols")))
    (unless (or (null (property-kind object)) (keywordp (property-kind object)))
      (refuse (property-kind object) "kind must be NIL or a keyword"))
    (unless (or (null (property-documentation object))
                (stringp (property-documentation object)))
      (refuse (property-documentation object) "documentation must be NIL or a string"))
    (unless (and (definition-keyword-plist-p (property-trials object))
                 (loop for (key count) on (property-trials object) by #'cddr
                       always (typep count '(integer 0 *))))
      (refuse (property-trials object) "trials require unique keyword profiles and nonnegative counts"))
    (unless (definition-keyword-plist-p (property-metadata object))
      (refuse (property-metadata object) "metadata must be a finite plist with unique keyword keys"))
    (unless (member (getf (property-metadata object) :shrink) '(nil t))
      (refuse (property-metadata object) ":shrink must be boolean"))
    (unless (and (forms-p (property-body object)) (forms-p (property-source-form object)))
      (refuse (list (property-body object) (property-source-form object))
              "body and source form must be finite proper lists with acyclic subforms"))
    (unless (and (definition-keyword-plist-p (property-source-location object))
                 (finite-definition-form-p (property-source-location object)))
      (refuse (property-source-location object) "source location must be a finite keyword plist"))
    (validate-property-executable object)
    (let ((bindings (property-arguments object)) (seen (make-hash-table :test #'eq)))
      (unless (and (finite-list-p bindings) (finite-definition-form-p bindings))
        (refuse bindings "arguments must be a finite list with acyclic spec forms"))
      (let ((normalized
              (loop for entry in bindings
                    do (unless (and (finite-list-p entry) (= 2 (length entry)))
                         (refuse entry "expected exactly (variable spec)"))
                       (let ((variable (first entry)))
                         (unless (and variable (symbolp variable) (not (constantp variable))
                                      (not (member variable lambda-list-keywords)))
                           (refuse entry "argument variable must be bindable"))
                         (when (gethash variable seen)
                           (refuse entry "argument variable appears more than once"))
                         (setf (gethash variable seen) t))
                    collect (list (first entry) (normalize-spec-form (second entry))))))
        (setf (slot-value object 'arguments) normalized))))
  object)

(defmethod shared-initialize :around ((object property) slot-names &rest initargs)
  "Keep declaration text and behavior paired and restore participating slots on refusal."
  (flet ((supplied-p (key)
           (loop for (candidate) on initargs by #'cddr thereis (eq candidate key))))
    (when (and (or (and (slot-boundp object 'body) (property-body object))
                   (getf initargs :body))
               (not (eq (not (null (supplied-p :body)))
                        (not (null (supplied-p :function))))))
      (error 'invalid-property-form :form (getf initargs :body)
                                    :reason ":body and :function must change together")))
  (call-with-definition-rollback
    object (lambda () (apply #'call-next-method object slot-names initargs))))

(defmethod shared-initialize :after ((object property) slot-names &key)
  "Validate creation, reinitialization, and class changes through one protocol."
  (declare (ignore slot-names))
  (validate-definition object))

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
