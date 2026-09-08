;;;; tests/normalize-test.lisp

(defpackage #:cl-spec/tests/normalize-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form
                #:*spec-primitives*))

(in-package #:cl-spec/tests/normalize-test)

(deftest mvp-primitives-are-declared
  (testing "*SPEC-PRIMITIVES* lists exactly the MVP spec head names"
    (ok (equal '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
                 "LIST-OF" "VECTOR-OF" "CONS-OF" "TUPLE" "NULLABLE"
                 "INSTANCE-OF")
               *spec-primitives*)))
  (testing "heads are names, so they survive being written in another package"
    (ok (every #'stringp *spec-primitives*))
    (ok (member (symbol-name 'range) *spec-primitives* :test #'string=))))

(deftest normalize-is-a-stub
  (testing "NORMALIZE-SPEC-FORM signals NOT-IMPLEMENTED until it is written"
    (ok (signals (normalize-spec-form '(and integer (satisfies plusp)))
                 'not-implemented))))
