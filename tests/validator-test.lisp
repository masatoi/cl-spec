;;;; tests/validator-test.lisp

(defpackage #:cl-spec/tests/validator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation
                #:spec-violation-value
                #:spec-violation-errors)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate))

(in-package #:cl-spec/tests/validator-test)

(deftest validp-agrees-with-explain-data
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "VALIDP is true exactly when EXPLAIN-DATA reports no errors"
      (dolist (value (list 10 -1 0 1 "foo" nil))
        (ok (eq (and (validp 'positive-integer value :registry registry) t)
                (and (getf (explain-data 'positive-integer value :registry registry) :valid) t)))))))

(deftest validate-returns-or-signals
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "a valid value is returned unchanged"
      (ok (eql 10 (validate 'positive-integer 10 :registry registry))))
    (testing "an invalid value signals SPEC-VIOLATION carrying the structured errors"
      (let ((condition (handler-case (progn (validate 'positive-integer -1 :registry registry) nil)
                         (spec-violation (c) c))))
        (ok condition)
        (ok (eql -1 (spec-violation-value condition)))
        (ok (spec-violation-errors condition))))))

(deftest compile-validator-produces-a-predicate
  (testing "the compiled function takes one argument and returns a boolean"
    (let ((validator (compile-validator (normalize-spec-form '(and integer (range 1 *))))))
      (ok (funcall validator 5))
      (ok (not (funcall validator -5))))))
