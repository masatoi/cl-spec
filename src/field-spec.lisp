;;;; src/field-spec.lisp

(defpackage #:cl-spec/src/field-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:export #:field-definition #:make-field-definition
           #:field-key #:field-value-spec #:field-required-p
           #:field-spec #:field-spec-fields #:field-spec-closed-p
           #:plist-spec #:plist-structure-error #:plist-field-value
           #:finite-proper-list-p #:field-descriptions))

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

(defun finite-proper-list-p (value)
  "Recognize proper lists, including NIL, without looping on circular lists."
  (handler-case (not (null (list-length value)))
    (type-error () nil)))

(defun validate-plist-fields (fields closed-p)
  "Refuse malformed programmatic plist declarations before changing an instance."
  (flet ((refuse (reason)
           (error 'invalid-spec-form :form (list :fields fields :closed-p closed-p)
                  :reason reason)))
    (unless (typep closed-p 'boolean)
      (refuse "A plist closed flag must be T or NIL."))
    (unless (finite-proper-list-p fields)
      (refuse "Plist fields must be a finite proper list."))
    (let ((seen (make-hash-table :test #'eq)))
      (dolist (field fields)
        (unless (typep field 'field-definition)
          (refuse "Every plist field must be a field definition."))
        (unless (and (keywordp (field-key field))
                     (typep (field-value-spec field) 'spec)
                     (typep (field-required-p field) 'boolean))
          (refuse "A plist field requires a keyword key, child IR and boolean required flag."))
        (when (gethash (field-key field) seen)
          (refuse "Plist field keys must be unique."))
        (setf (gethash (field-key field) seen) t)))))

(defmethod shared-initialize :around
    ((spec plist-spec) slot-names &rest initargs
     &key (fields nil fields-p) (closed-p nil closed-p-p) &allow-other-keys)
  "Validate proposed field semantics before initialization or reinitialization mutates SPEC."
  (declare (ignore slot-names initargs))
  (validate-plist-fields
   (if fields-p fields
       (when (slot-boundp spec 'fields) (field-spec-fields spec)))
   (if closed-p-p closed-p
       (when (slot-boundp spec 'closed-p) (field-spec-closed-p spec))))
  (call-next-method))

(defun plist-structure-error (value)
  "Return (values KIND KEY) for malformed plist structure, or NIL.
KEY is relevant only for :DUPLICATE-KEY; values are never mistaken for keys."
  (unless (and (finite-proper-list-p value) (evenp (length value)))
    (return-from plist-structure-error :not-a-plist))
  (let ((seen (make-hash-table :test #'eq)))
    (loop for (key) on value by #'cddr
          do (unless (keywordp key)
               (return-from plist-structure-error :not-a-plist))
             (when (gethash key seen)
               (return-from plist-structure-error (values :duplicate-key key)))
             (setf (gethash key seen) t))))

(defun plist-field-value (value key)
  "Return (values VALUE PRESENT-P) for KEY in an already checked keyword plist."
  (loop for (entry-key entry-value) on value by #'cddr
        when (eq key entry-key) do (return (values entry-value t))
        finally (return (values nil nil))))

(defun field-descriptions (spec)
  "Describe field-to-child associations without duplicating the child IR."
  (loop for field in (field-spec-fields spec)
        for index from 0
        collect (list :key (field-key field) :required (field-required-p field)
                      :child-index index)))
