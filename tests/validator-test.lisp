;;;; tests/validator-test.lisp

(defpackage #:cl-spec/tests/validator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate))

(in-package #:cl-spec/tests/validator-test)

(deftest validator-entry-points-exist
  (testing "the public validation entry points are defined"
    (ok (fboundp 'compile-validator))
    (ok (fboundp 'validp))
    (ok (fboundp 'validate))))

(deftest validator-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (compile-validator
                  (make-instance 'type-spec :type-specifier 'integer))
                 'not-implemented))
    (ok (signals (validp 'positive-integer 10) 'not-implemented))
    (ok (signals (validate 'positive-integer 10) 'not-implemented))))
