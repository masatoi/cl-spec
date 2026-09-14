;;;; src/field-spec.lisp

(defpackage #:cl-spec/src/field-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:export #:field-definition #:make-field-definition
           #:field-key #:field-value-spec #:field-required-p
           #:field-spec #:field-spec-fields #:field-spec-closed-p
           #:keyed-field-spec #:field-key-test
           #:key-test-designator #:key-test-designator-p #:key-test-name
           #:key-test-function
           #:alist-spec #:alist-structure-error
           #:hash-table-spec #:hash-table-structure-error
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

(defparameter +key-tests+
  '((:eq . eq) (:eql . eql) (:equal . equal) (:equalp . equalp))
  "The key comparison tests a keyed field spec accepts, as (KEYWORD . FUNCTION-NAME).")

(defun key-test-designator (object)
  "Return the canonical key-test keyword named by OBJECT, or NIL.

Both a keyword and a plain symbol are accepted, matched by name: a DSL form is
read in the user's package, so the EQL of (:test eql) is not EQ to the EQL
interned here."
  (when (symbolp object)
    (car (find (symbol-name object) +key-tests+
               :key (lambda (entry) (symbol-name (car entry)))
               :test #'string=))))

(defun key-test-designator-p (object)
  "Return true when OBJECT names an accepted key comparison test."
  (not (null (key-test-designator object))))

(defun key-test-name (test)
  "Return the COMMON-LISP function name for the canonical key-test keyword TEST."
  (or (cdr (assoc test +key-tests+))
      (error 'invalid-spec-form :form test :reason "unknown key test")))

(defun key-test-function (test)
  "Return the comparison function for the canonical key-test keyword TEST."
  (symbol-function (key-test-name test)))

(defclass keyed-field-spec (field-spec)
  ((key-test :initarg :key-test
             :initform :eql
             :reader keyed-field-spec-key-test
             :documentation "Canonical keyword naming the comparison used for keys."))
  (:documentation "Base IR for field records whose keys are compared by a declared test."))

(defgeneric field-key-test (spec)
  (:documentation "Return SPEC's canonical key comparison keyword, or NIL when it declares none.")
  (:method ((spec field-spec)) nil)
  (:method ((spec keyed-field-spec)) (keyed-field-spec-key-test spec)))

(defclass alist-spec (keyed-field-spec)
  ()
  (:documentation "An association list of (KEY . VALUE) pairs with unique keys."))

(defmethod spec-kind ((spec alist-spec))
  :alist)

(defclass hash-table-spec (keyed-field-spec)
  ()
  (:documentation "A hash table whose key comparison and named fields are declared."))

(defmethod spec-kind ((spec hash-table-spec))
  :hash-table)

(defgeneric validate-field-layout (spec fields closed-p key-test)
  (:documentation "Check common field layout and representation-specific invariants.

KEY-TEST is the key comparison designator the caller is about to store, canonical
keyword or NIL for a representation that declares none.  It is threaded through
rather than read from SPEC because reinitialization validates before the slot
changes."))

(defmethod validate-field-layout ((spec field-spec) fields closed-p key-test)
  (declare (ignore key-test))
  (unless (and (typep closed-p 'boolean)
               (finite-list-p fields)
               (every (lambda (field) (typep field 'field-definition)) fields))
    (error 'invalid-spec-form :form (list :fields fields :closed-p closed-p)
           :reason "Fields must be a finite list of field definitions; closed-p must be boolean.")))

(defmethod validate-field-layout ((spec plist-spec) fields closed-p key-test)
  (declare (ignore key-test))
  (call-next-method)
  (let ((seen (make-hash-table :test #'eq)))
    (dolist (field fields)
      (unless (and (keywordp (field-key field)) (not (gethash (field-key field) seen)))
        (error 'invalid-spec-form :form (list :fields fields :closed-p closed-p)
               :reason "Plist field keys must be unique keywords."))
      (setf (gethash (field-key field) seen) t))))

(defmethod validate-field-layout ((spec keyed-field-spec) fields closed-p key-test)
  (call-next-method)
  (let ((canonical (key-test-designator key-test)))
    (unless canonical
      (error 'invalid-spec-form
             :form (list :fields fields :closed-p closed-p :key-test key-test)
             :reason "The key test must name EQ, EQL, EQUAL or EQUALP."))
    (let ((test (key-test-function canonical))
          (seen nil))
      (dolist (field fields)
        (when (member (field-key field) seen :test test)
          (error 'invalid-spec-form
                 :form (list :fields fields :closed-p closed-p :key-test key-test)
                 :reason "Field keys must be unique under the declared key test."))
        (push (field-key field) seen)))))

(defmethod shared-initialize :around
    ((spec field-spec) slot-names &rest initargs
     &key (fields nil fields-p) (closed-p nil closed-p-p)
          (key-test nil key-test-p))
  "Validate common and concrete field semantics before changing SPEC.

The candidate KEY-TEST is threaded to VALIDATE-FIELD-LAYOUT because
reinitialization must refuse a bad test before the slot changes; reading the slot
here would see the previous value."
  (declare (ignore slot-names initargs))
  (validate-field-layout
   spec
   (if fields-p fields
       (when (slot-boundp spec 'fields) (field-spec-fields spec)))
   (if closed-p-p closed-p
       (when (slot-boundp spec 'closed-p) (field-spec-closed-p spec)))
   (cond (key-test-p key-test)
         ((and (typep spec 'keyed-field-spec) (slot-boundp spec 'key-test))
          (slot-value spec 'key-test))
         (t :eql)))
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

(defun alist-structure-error (value key-test)
  "Return (values KIND KEY) after checking that VALUE is a well-formed alist.

KIND and KEY describe malformed structure and are NIL on success.  An entry is a
cons whose CAR is the key and whose CDR is the value, so the value of (:id . NIL)
is present but NIL, exactly as ASSOC reads it.  Keys are unique under KEY-TEST."
  (unless (finite-list-p value)
    (return-from alist-structure-error (values :not-an-alist nil)))
  (let ((test (key-test-function (key-test-designator key-test)))
        (seen nil))
    (dolist (entry value)
      (unless (consp entry)
        (return-from alist-structure-error (values :bad-association entry)))
      (let ((key (car entry)))
        (when (member key seen :test test)
          (return-from alist-structure-error (values :duplicate-key key)))
        (push key seen)))
    (values nil nil)))

(defun hash-table-structure-error (value key-test)
  "Return (values KIND ACTUAL) after checking that VALUE is a hash table.

KIND is NIL on success.  A table whose test does not match the declared KEY-TEST
is :WRONG-KEY-TEST with the table's test as ACTUAL, so the key comparison the
spec declares is the comparison the value actually uses."
  (unless (hash-table-p value)
    (return-from hash-table-structure-error (values :not-a-hash-table nil)))
  (let ((declared (key-test-designator key-test))
        (actual (key-test-designator (hash-table-test value))))
    (if (and actual (eq actual declared))
        (values nil nil)
        (values :wrong-key-test (hash-table-test value)))))

(defun field-descriptions (spec)
  "Describe field-to-child associations without duplicating the child IR."
  (loop for field in (field-spec-fields spec)
        for index from 0
        collect (list :key (field-key field) :required (field-required-p field)
                      :child-index index)))
