;;;; tests/backends/check-it-test.lisp

(defpackage #:cl-spec/tests/backends/check-it-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend
                #:install-check-it-backend
                #:default-trials))

(in-package #:cl-spec/tests/backends/check-it-test)

(deftest loading-installs-the-backend
  (testing "loading this system leaves a CHECK-IT-BACKEND in *GENERATOR-BACKEND*"
    (ok (typep *generator-backend* 'check-it-backend))
    (ok (typep (current-generator-backend) 'check-it-backend))))

(deftest install-is-idempotent-and-returns-the-backend
  (testing "INSTALL-CHECK-IT-BACKEND can be called again safely"
    (let ((backend (install-check-it-backend)))
      (ok (typep backend 'check-it-backend))
      (ok (eq backend *generator-backend*)))))

(deftest default-trials-comes-from-check-it
  (testing "the default trial count is taken from CHECK-IT:*NUM-TRIALS*"
    (ok (integerp (default-trials)))
    (ok (plusp (default-trials)))))

(deftest backend-methods-are-stubs
  (testing "the three protocol methods are specialised but not yet written"
    (let ((backend (install-check-it-backend)))
      (ok (signals (compile-generator backend :any-spec) 'not-implemented))
      (ok (signals (generate-value backend :any-generator) 'not-implemented))
      (ok (signals (run-generated-test backend :any-property)
                   'not-implemented)))))
