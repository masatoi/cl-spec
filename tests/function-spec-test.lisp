;;;; tests/function-spec-test.lisp

(defpackage #:cl-spec/tests/function-spec-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-function-spec
                #:list-function-specs)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name
                #:function-spec-argument-specs
                #:function-spec-return-spec
                #:function-spec-preconditions
                #:function-spec-postconditions
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata
                #:register-function-spec
                #:check-function))

(in-package #:cl-spec/tests/function-spec-test)

(deftest function-spec-slots-round-trip
  (testing "every documented slot is readable"
    (let ((instance (make-instance 'function-spec
                                   :name 'transfer
                                   :argument-specs '((from account)
                                                     (to account)
                                                     (amount positive-money))
                                   :return-spec 'transaction
                                   :preconditions '((distinct-accounts-p from to))
                                   :postconditions '((balance-preserved-p))
                                   :source-form '(defspec-function transfer)
                                   :source-location '(:file "/tmp/bank.lisp")
                                   :metadata '(:owner "bank-team"))))
      (ok (eq 'transfer (function-spec-name instance)))
      (ok (equal '((from account) (to account) (amount positive-money))
                 (function-spec-argument-specs instance)))
      (ok (eq 'transaction (function-spec-return-spec instance)))
      (ok (equal '((distinct-accounts-p from to))
                 (function-spec-preconditions instance)))
      (ok (equal '((balance-preserved-p)) (function-spec-postconditions instance)))
      (ok (equal '(defspec-function transfer) (function-spec-source-form instance)))
      (ok (equal '(:file "/tmp/bank.lisp") (function-spec-source-location instance)))
      (ok (equal '(:owner "bank-team") (function-spec-metadata instance))))))

(deftest function-spec-registration
  (testing "REGISTER-FUNCTION-SPEC uses the function spec's own name"
    (let ((*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (ok (eq instance (register-function-spec instance)))
      (ok (eq instance (find-function-spec 'transfer)))
      (ok (equal '(transfer) (list-function-specs)))))
  (testing "an explicit registry argument is honoured"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (register-function-spec instance other)
      (ok (null (find-function-spec 'transfer)))
      (ok (eq instance (find-function-spec 'transfer other))))))

(deftest check-function-is-a-stub
  (testing "CHECK-FUNCTION signals NOT-IMPLEMENTED"
    (ok (signals (check-function 'transfer) 'not-implemented))))
