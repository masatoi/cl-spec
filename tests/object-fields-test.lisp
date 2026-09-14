;;;; tests/object-fields-test.lisp

(defpackage #:cl-spec/tests/object-fields-test
  (:use #:cl)
  (:import-from #:cl-spec/src/field-spec
                #:object-spec #:object-spec-class-name
                #:field-spec-fields #:make-field-definition)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:cl-spec/src/explain #:expected-descriptor)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:validp #:explain-data #:spec-data
                #:definition-digest #:spec-kind))

(in-package #:cl-spec/tests/object-fields-test)

(defclass object-user ()
  ((id :initarg :id :reader object-user-id)
   (name :initarg :name :reader object-user-name)
   (nickname :initarg :nickname :reader object-user-nickname))
  (:documentation "CLOS fixture whose nickname slot may stay unbound."))

(defclass object-account ()
  ((owner :initarg :owner :reader object-account-owner)
   (balance :initarg :balance :reader object-account-balance))
  (:documentation "CLOS fixture holding another observed object."))

(defstruct object-point
  (x 0)
  (y 0))

(defun object-noisy-reader (object)
  "A reader that signals, to check structured reader-failure reporting."
  (declare (ignore object))
  (error "noisy reader"))

(defun accepts-p (form value)
  "Check a DSL form, treating an unsupported declaration as a failed expectation."
  (handler-case (validp (normalize-spec-form form) value)
    (invalid-spec-form () nil)))

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(deftest object-of-validates-class-and-fields
  (let ((form '(object-of object-user
                (:required (object-user-id integer) (object-user-name string))
                (:optional (object-user-nickname (nullable string))))))
    (ok (accepts-p form (make-instance 'object-user :id 1 :name "a" :nickname nil)))
    (ok (accepts-p form (make-instance 'object-user :id 1 :name "a")))
    (ok (not (accepts-p form (make-instance 'object-user :id 1))))
    (ok (not (accepts-p form (make-instance 'object-user :id "x" :name "a"))))
    (ok (not (accepts-p form (make-instance 'object-account :owner 1 :balance 2))))
    (ok (not (accepts-p form 42))))
  (testing "a spec with no clauses is a plain class check"
    (ok (accepts-p '(object-of object-user) (make-instance 'object-user :id 1 :name "a")))
    (ok (not (accepts-p '(object-of object-user) 42)))))

(deftest object-of-distinguishes-unbound-from-nil
  (testing "a required reader that returns NIL is present"
    (let ((spec (normalize-spec-form
                 '(object-of object-user (:required (object-user-nickname (nullable string)))))))
      (ok (validp spec (make-instance 'object-user :nickname nil)))
      (ok (not (validp spec (make-instance 'object-user :nickname :not-a-string))))
      (let ((datum (first (getf (explain-data spec (make-instance 'object-user)) :errors))))
        (ok (eq :unbound-slot (getf datum :kind)))
        (ok (equal '(object-user-nickname) (getf datum :path))))))
  (testing "an optional reader that signals UNBOUND-SLOT is absent"
    (let ((spec (normalize-spec-form
                 '(object-of object-user (:optional (object-user-nickname (nullable string)))))))
      (ok (validp spec (make-instance 'object-user)))
      (ok (validp spec (make-instance 'object-user :nickname nil))))))

(deftest object-of-supports-structs
  (let ((spec (normalize-spec-form
               '(object-of object-point
                 (:required (object-point-x integer) (object-point-y integer))))))
    (ok (validp spec (make-object-point :x 1 :y 2)))
    (ok (not (validp spec (make-object-point :x "a" :y 2))))
    (ok (not (validp spec (make-instance 'object-user :id 1 :name "a"))))))

(deftest object-of-refuses-unobservable-closedness
  (ok (refuses-form-p '(object-of object-user (:closed t) (:required (object-user-id integer)))))
  (ok (refuses-form-p '(object-of object-user (:test eql) (:required (object-user-id integer)))))
  (let ((field (make-field-definition :key 'object-user-id
                                      :value-spec (normalize-spec-form 'integer))))
    (ok (handler-case
            (progn (make-instance 'object-spec :class-name 'object-user
                                  :fields (list field) :closed-p t)
                   nil)
          (invalid-spec-form () t)))))

(deftest object-of-refuses-malformed-declarations
  (dolist (form '((object-of)
                  (object-of 42 (:required (object-user-id integer)))
                  (object-of nil (:required (object-user-id integer)))
                  (object-of object-user (:unknown t))
                  (object-of object-user (:required (object-user-id)))
                  (object-of object-user (:required (object-user-id integer extra)))
                  (object-of object-user (:required ("id" integer)))
                  (object-of object-user (:required (nil integer)))
                  (object-of object-user
                             (:required (object-user-id integer) (object-user-id string)))
                  (object-of . object-user)))
    (ok (refuses-form-p form) (format nil "~S must be refused" form)))
  (testing "empty clauses are allowed"
    (ok (not (refuses-form-p '(object-of object-user (:required)))))
    (ok (accepts-p '(object-of object-user (:required))
                   (make-instance 'object-user :id 1)))))

(deftest object-of-explains-field-paths
  (let ((spec (normalize-spec-form
               '(object-of object-account
                 (:required (object-account-owner
                             (object-of object-user
                               (:required (object-user-id integer)))))))))
    (let ((errors (getf (explain-data spec
                                      (make-instance 'object-account
                                                     :owner (make-instance 'object-user :id "bad")))
                        :errors)))
      (ok (equal '(object-account-owner object-user-id) (getf (first errors) :path)))
      (ok (eq :type-failed (getf (first errors) :kind))))
    (let ((missing (first (getf (explain-data spec
                                              (make-instance 'object-account
                                                             :owner (make-instance 'object-user)))
                                :errors))))
      (ok (eq :unbound-slot (getf missing :kind)))
      (ok (equal '(object-account-owner object-user-id) (getf missing :path))))
    (let ((wrong (first (getf (explain-data spec (make-instance 'object-account :owner 42))
                              :errors))))
      (ok (eq :not-an-instance (getf wrong :kind)))
      (ok (equal '(object-account-owner) (getf wrong :path))))))

(deftest object-of-reader-failures-are-structured
  (let ((spec (normalize-spec-form
               '(object-of object-user (:required (object-noisy-reader integer))))))
    (let ((datum (first (getf (explain-data spec (make-instance 'object-user :id 1)) :errors))))
      (ok (eq :reader-errored (getf datum :kind)))
      (ok (eq 'simple-error (getf datum :condition-type)))
      (ok (equal '(object-noisy-reader) (getf datum :path)))))
  (testing "an undefined reader is an authoring error and still propagates"
    (let ((spec (normalize-spec-form
                 '(object-of object-user (:required (object-undefined-reader integer))))))
      (ok (handler-case (progn (validp spec (make-instance 'object-user :id 1)) nil)
            (undefined-function () t))))))

(deftest object-of-introspection-and-digest
  (let* ((form '(object-of object-user
                 (:required (object-user-id integer))
                 (:optional (object-user-name string))))
         (data (spec-data (normalize-spec-form form))))
    (ok (eq :object (getf data :kind)))
    (ok (eq 'object-user (getf data :class-name)))
    (ok (equal '((:key object-user-id :required t :child-index 0)
                 (:key object-user-name :required nil :child-index 1))
               (getf data :fields)))
    (ok (equal form (getf data :source-form)))
    (ok (getf data :definition-digest-complete))
    (ok (integerp (length (getf data :definition-digest))))
    (let ((digest (getf data :definition-digest)))
      (dolist (other '((object-of object-account
                        (:required (object-user-id integer))
                        (:optional (object-user-name string)))
                       (object-of object-user
                        (:required (object-user-name string))
                        (:optional (object-user-id integer)))))
        (ok (not (equal digest (definition-digest (normalize-spec-form other)))))))))

(deftest object-of-descriptors-expose-field-contracts
  (let ((descriptor (expected-descriptor
                     (normalize-spec-form
                      '(object-of object-user
                        (:required (object-user-id integer))
                        (:optional (object-user-name string)))))))
    (ok (equal '(:kind :object :class object-user
                 :fields ((:key object-user-id :required t :expected (:type integer))
                          (:key object-user-name :required nil :expected (:type string))))
               descriptor))))

(deftest object-of-failure-identity-distinguishes-fields
  (let ((spec (normalize-spec-form
               '(object-of object-user
                 (:required (object-user-id integer) (object-user-name integer))))))
    (ok (not (equal
              (failure-signature :return-spec
                                 (explain-data spec
                                               (make-instance 'object-user :id "bad" :name 1))
                                 nil)
              (failure-signature :return-spec
                                 (explain-data spec
                                               (make-instance 'object-user :id 1 :name "bad"))
                                 nil))))))

(deftest programmatic-object-invariants
  (let* ((child (normalize-spec-form 'integer))
         (field (make-field-definition :key 'object-user-id :value-spec child))
         (foreign (make-field-definition :key "id" :value-spec child))
         (spec (make-instance 'object-spec :class-name 'object-user :fields (list field))))
    (ok (eq :object (spec-kind spec)))
    (dolist (initargs (list (list :class-name 'object-user :fields (list field field))
                            (list :class-name 'object-user :fields (list foreign))
                            (list :class-name 42 :fields (list field))
                            (list :class-name nil :fields (list field))
                            (list :class-name 'object-user :fields (list field) :closed-p t)))
      (ok (handler-case (progn (apply #'make-instance 'object-spec initargs) nil)
            (invalid-spec-form () t))
          (format nil "~S must be refused" initargs)))
    (ok (equal (list field) (field-spec-fields spec)))
    (reinitialize-instance spec :class-name 'object-account)
    (ok (eq 'object-account (object-spec-class-name spec)))
    (ok (handler-case (progn (reinitialize-instance spec :class-name 42) nil)
          (invalid-spec-form () t)))
    (ok (eq 'object-account (object-spec-class-name spec)))
    (ok (handler-case (progn (reinitialize-instance spec :fields (list field field)) nil)
          (invalid-spec-form () t)))
    (ok (equal (list field) (field-spec-fields spec)))))
