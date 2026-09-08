;;;; tests/introspection-test.lisp

(defpackage #:cl-spec/tests/introspection-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data))

(in-package #:cl-spec/tests/introspection-test)

(deftest introspection-entry-points-exist
  (testing "the four introspection entry points are defined"
    (ok (fboundp 'describe-spec))
    (ok (fboundp 'describe-property))
    (ok (fboundp 'spec-data))
    (ok (fboundp 'property-data))))

(deftest introspection-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (spec-data 'positive-integer) 'not-implemented))
    (ok (signals (property-data 'addition-preserves-order) 'not-implemented))
    (ok (signals (describe-spec 'positive-integer) 'not-implemented))
    (ok (signals (describe-property 'addition-preserves-order)
                 'not-implemented))))
