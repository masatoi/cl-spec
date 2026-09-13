;;;; tests/property-test.lisp

(defpackage #:cl-spec/tests/property-test
  (:use #:cl)
  (:import-from #:cl-spec/src/ir #:reference-spec-target)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-property
                #:list-properties
                #:properties-for
                #:properties-with-tag)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
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

(in-package #:cl-spec/tests/property-test)

(defun make-test-property ()
  "Return a fully populated PROPERTY for use in the tests below."
  (make-instance 'property
                 :name 'transfer-preserves-total-balance
                 :arguments '((state state-spec) (amount positive-money))
                 :targets '(transfer)
                 :kind :invariant
                 :tags '(:money :invariant)
                 :documentation "Transfer keeps the total balance unchanged."
                 :body '((= (total-balance state) (total-balance result)))
                 :function (lambda (state amount) (declare (ignore state amount)) t)
                 :source-form '(defproperty transfer-preserves-total-balance)
                 :source-location '(:file "/tmp/bank.lisp")
                 :trials '(:smoke 10 :normal 100)
                 :metadata '(:owner "bank-team")))

(deftest property-slots-round-trip
  (testing "every documented slot is readable"
    (let ((instance (make-test-property)))
      (ok (eq 'transfer-preserves-total-balance (property-name instance)))
      (ok (equal '((state state-spec) (amount positive-money))
                 (mapcar (lambda (binding)
                           (list (first binding) (reference-spec-target (second binding))))
                         (property-arguments instance))))
      (ok (equal '(transfer) (property-targets instance)))
      (ok (eq :invariant (property-kind instance)))
      (ok (equal '(:money :invariant) (property-tags instance)))
      (ok (equal "Transfer keeps the total balance unchanged."
                 (property-documentation instance)))
      (ok (equal '((= (total-balance state) (total-balance result)))
                 (property-body instance)))
      (ok (equal '(defproperty transfer-preserves-total-balance)
                 (property-source-form instance)))
      (ok (equal '(:file "/tmp/bank.lisp") (property-source-location instance)))
      (ok (equal '(:smoke 10 :normal 100) (property-trials instance)))
      (ok (equal '(:owner "bank-team") (property-metadata instance))))))

(deftest property-slots-default-to-nil
  (testing "a bare property has NIL everywhere except a required name"
    (let ((instance (make-instance 'property :name 'bare :function (constantly t))))
      (ok (eq 'bare (property-name instance)))
      (ok (null (property-arguments instance)))
      (ok (null (property-targets instance)))
      (ok (null (property-kind instance)))
      (ok (null (property-tags instance)))
      (ok (null (property-documentation instance)))
      (ok (null (property-body instance)))
      (ok (null (property-trials instance))))))

(deftest registering-indexes-targets-and-tags
  (testing "REGISTER-PROPERTY derives the index keys from the property itself"
    (let ((*registry* (make-hash-table-registry))
          (instance (make-test-property)))
      (ok (eq instance (register-property instance)))
      (ok (eq instance (find-property 'transfer-preserves-total-balance)))
      (ok (equal '(transfer-preserves-total-balance) (list-properties)))
      (ok (equal '(transfer-preserves-total-balance) (properties-for 'transfer)))
      (ok (equal '(transfer-preserves-total-balance) (properties-with-tag :money))))))

(deftest registering-accepts-an-explicit-registry
  (testing "REGISTER-PROPERTY writes to the registry it is handed"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry))
          (instance (make-test-property)))
      (register-property instance other)
      (ok (null (find-property 'transfer-preserves-total-balance)))
      (ok (eq instance (find-property 'transfer-preserves-total-balance other))))))

(deftest a-property-carries-a-callable-body
  (testing "PROPERTY-FUNCTION returns the compiled predicate"
    (let ((property (make-instance 'property
                                   :name 'p
                                   :function (lambda (x) (plusp x))
                                   :body '((plusp x)))))
      (ok (funcall (property-function property) 1))
      (ok (not (funcall (property-function property) -1))))
    (testing "the source body is kept alongside the compiled function"
      (ok (equal '((plusp x))
                 (property-body (make-instance 'property :name 'p :body '((plusp x))
                                                :function #'plusp)))))))
