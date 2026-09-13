;;;; src/field-spec.lisp

(defpackage #:cl-spec/src/field-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:export #:field-definition #:make-field-definition
           #:field-key #:field-value-spec #:field-required-p
           #:field-spec #:field-spec-fields #:field-spec-closed-p
           #:plist-spec #:plist-structure-error #:field-descriptions))

(in-package #:cl-spec/src/field-spec)

(defstruct (field-definition
             (:constructor make-field-definition (&key key value-spec (required-p t)))
             (:conc-name field-))
  "Representation-independent key, child IR and presence requirement."
  (key nil :read-only t)
  (value-spec (error "A field requires a value spec.") :type spec :read-only t)
  (required-p t :type boolean :read-only t))

(defclass field-spec (spec)
  ((fields :initarg :fields :initform nil :reader field-spec-fields
           :documentation "Ordered field definitions, independent of storage representation.")
   (closed-p :initarg :closed-p :initform nil :reader field-spec-closed-p
             :documentation "True when keys outside the declared fields are refused."))
  (:documentation "Base IR for records with named fields and presence requirements."))

(defmethod spec-children ((spec field-spec))
  (mapcar #'field-value-spec (field-spec-fields spec)))

(defclass plist-spec (field-spec)
  ()
  (:documentation "A finite keyword plist with unique keys and declared field specs."))

(defmethod spec-kind ((spec plist-spec))
  :plist)

(defgeneric validate-field-layout (spec fields closed-p)
  (:documentation "Check common field layout and representation-specific invariants."))

(defmethod validate-field-layout ((spec field-spec) fields closed-p)
  (unless (and (typep closed-p 'boolean)
               (finite-list-p fields)
               (every (lambda (field) (typep field 'field-definition)) fields))
    (error 'invalid-spec-form :form (list :fields fields :closed-p closed-p)
           :reason "Fields must be a finite list of field definitions; closed-p must be boolean.")))

(defmethod validate-field-layout ((spec plist-spec) fields closed-p)
  (call-next-method)
  (let ((seen (make-hash-table :test #'eq)))
    (dolist (field fields)
      (unless (and (keywordp (field-key field)) (not (gethash (field-key field) seen)))
        (error 'invalid-spec-form :form (list :fields fields :closed-p closed-p)
               :reason "Plist field keys must be unique keywords."))
      (setf (gethash (field-key field) seen) t))))

(defmethod shared-initialize :around
    ((spec field-spec) slot-names &rest initargs
     &key (fields nil fields-p) (closed-p nil closed-p-p))
  "Validate common and concrete field semantics before changing SPEC."
  (declare (ignore slot-names initargs))
  (validate-field-layout
   spec
   (if fields-p fields
       (when (slot-boundp spec 'fields) (field-spec-fields spec)))
   (if closed-p-p closed-p
       (when (slot-boundp spec 'closed-p) (field-spec-closed-p spec))))
  (call-next-method))

(defun plist-structure-error (value)
  "Return (values KIND KEY INDEX KEYS) after checking a keyword plist.
KIND and KEY describe malformed structure. On success INDEX maps keys to values
and KEYS retains their input order. Callers can reuse the checked index."
  (unless (finite-list-p value)
    (return-from plist-structure-error :not-a-plist))
  (let ((index (make-hash-table :test #'eq))
        (keys nil))
    (loop for tail on value by #'cddr
          for key = (car tail)
          do (unless (and (cdr tail) (keywordp key))
               (return-from plist-structure-error :not-a-plist))
             (when (nth-value 1 (gethash key index))
               (return-from plist-structure-error (values :duplicate-key key)))
             (setf (gethash key index) (second tail))
             (push key keys))
    (values nil nil index (nreverse keys))))

(defun field-descriptions (spec)
  "Describe field-to-child associations without duplicating the child IR."
  (loop for field in (field-spec-fields spec)
        for index from 0
        collect (list :key (field-key field) :required (field-required-p field)
                      :child-index index)))
