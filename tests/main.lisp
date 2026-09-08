(defpackage cl-spec/tests/main
  (:use :cl
        :cl-spec
        :rove))
(in-package :cl-spec/tests/main)

;; NOTE: To run this test file, execute `(asdf:test-system :cl-spec)' in your Lisp.

(deftest test-target-1
  (testing "should (= 1 1) to be true"
    (ok (= 1 1))))
