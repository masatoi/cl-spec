;;;; tests/explain-test.lisp

(defpackage #:cl-spec/tests/explain-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain))

(in-package #:cl-spec/tests/explain-test)

(deftest explain-entry-points-exist
  (testing "the public explanation entry points are defined"
    (ok (fboundp 'compile-explainer))
    (ok (fboundp 'explain-data))
    (ok (fboundp 'explain))))

(deftest explain-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (compile-explainer
                  (make-instance 'type-spec :type-specifier 'integer))
                 'not-implemented))
    (ok (signals (explain-data 'positive-integer -1) 'not-implemented))
    (ok (signals (explain 'positive-integer -1) 'not-implemented))))
