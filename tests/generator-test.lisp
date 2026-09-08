;;;; tests/generator-test.lisp

(defpackage #:cl-spec/tests/generator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:no-generator-backend)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:generator-for
                #:sample))

(in-package #:cl-spec/tests/generator-test)

(deftest backend-protocol-is-generic
  (testing "the three backend operations are generic functions"
    (ok (typep #'compile-generator 'generic-function))
    (ok (typep #'generate-value 'generic-function))
    (ok (typep #'run-generated-test 'generic-function))))

(deftest missing-backend-is-reported
  (testing "CURRENT-GENERATOR-BACKEND signals when no backend is installed"
    (let ((*generator-backend* nil))
      (ok (signals (current-generator-backend) 'no-generator-backend)))))

(deftest installed-backend-is-returned
  (testing "CURRENT-GENERATOR-BACKEND returns whatever is bound"
    (let ((*generator-backend* :fake-backend))
      (ok (eq :fake-backend (current-generator-backend))))))

(deftest generator-front-end-is-a-stub
  (testing "GENERATOR-FOR and SAMPLE signal NOT-IMPLEMENTED"
    (let ((*generator-backend* :fake-backend))
      (ok (signals (generator-for 'positive-integer) 'not-implemented))
      (ok (signals (sample 'positive-integer) 'not-implemented)))))
