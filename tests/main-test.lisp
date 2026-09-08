;;;; tests/main-test.lisp

(defpackage #:cl-spec/tests/main-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main))

(in-package #:cl-spec/tests/main-test)

(defparameter *mvp-api*
  '("DEFSPEC" "FIND-SPEC" "LIST-SPECS" "VALIDP" "VALIDATE" "EXPLAIN"
    "EXPLAIN-DATA"
    "DEFGENERATOR" "GENERATOR-FOR" "SAMPLE"
    "DEFSPEC-FUNCTION" "FIND-FUNCTION-SPEC" "CHECK-FUNCTION"
    "DEFPROPERTY" "FIND-PROPERTY" "LIST-PROPERTIES" "PROPERTIES-FOR"
    "RUN-PROPERTY" "RUN-PROPERTIES" "REPLAY-PROPERTY"
    "DESCRIBE-SPEC" "DESCRIBE-PROPERTY" "SPEC-DATA" "PROPERTY-DATA")
  "The MVP API of specification §51.  Every name must be external in CL-SPEC.")

(deftest cl-spec-nickname-resolves
  (testing "the public package is reachable under the CL-SPEC nickname"
    (ok (eq (find-package "CL-SPEC") (find-package "CL-SPEC/MAIN")))))

(deftest mvp-api-is-external
  (testing "every §51 symbol is external in CL-SPEC"
    (dolist (name *mvp-api*)
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok (and symbol (eq :external status)))))))
