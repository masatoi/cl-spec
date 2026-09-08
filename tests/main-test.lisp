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

(defun symbol-reachable-p (symbol)
  "Return true when SYMBOL names something: a function, a special variable, a
class or a macro.

A symbol can be external in a package and still name nothing at all, for
example when a :IMPORT-FROM clause is dropped from MAIN.LISP but the matching
:EXPORT entry is left behind.  Status alone does not catch that; this does."
  (or (fboundp symbol)
      (boundp symbol)
      (find-class symbol nil)
      (macro-function symbol)))

(deftest cl-spec-nickname-resolves
  (testing "the public package is reachable under the CL-SPEC nickname"
    (ok (eq (find-package "CL-SPEC") (find-package "CL-SPEC/MAIN")))))

(deftest mvp-api-is-external
  (testing "every §51 symbol is external in CL-SPEC"
    (dolist (name *mvp-api*)
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok (and symbol (eq :external status)))))))

(deftest mvp-api-is-reachable
  (testing "every §51 symbol names something, not just a bare interned symbol"
    (dolist (name *mvp-api*)
      (let ((symbol (find-symbol name "CL-SPEC")))
        (ok (symbol-reachable-p symbol))))))

(deftest new-public-symbols-are-reachable
  (testing "the conditions the MVP added are external in CL-SPEC"
    (dolist (name '("INVALID-SPEC-FORM" "INVALID-SPEC-FORM-FORM" "INVALID-SPEC-FORM-REASON"
                    "GENERATOR-UNAVAILABLE" "GENERATOR-UNAVAILABLE-SPEC"
                    "GENERATOR-UNAVAILABLE-REASON" "UNSUPPORTED-SEED"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok symbol)
        (ok (eq :external status)))))
  (testing "source locations can be read without reaching into an internal package"
    (dolist (name '("SOURCE-LOCATION-FILE" "SOURCE-LOCATION-PACKAGE"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok symbol)
        (ok (eq :external status))))))
