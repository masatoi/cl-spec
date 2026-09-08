;;;; tests/introspection-test.lisp

(defpackage #:cl-spec/tests/introspection-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:not-implemented-operator)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data))

(in-package #:cl-spec/tests/introspection-test)

(defun signalled-operator (thunk)
  "Call THUNK and return the operator named by the NOT-IMPLEMENTED condition it
signals, or NIL if it signals no such condition."
  (handler-case (progn (funcall thunk) nil)
    (not-implemented (condition) (not-implemented-operator condition))))

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

(deftest introspection-entry-points-name-themselves
  (testing "the signalled condition's operator names the entry point that signalled it"
    (ok (eq 'spec-data
            (signalled-operator (lambda () (spec-data 'positive-integer)))))
    (ok (eq 'property-data
            (signalled-operator
             (lambda () (property-data 'addition-preserves-order)))))
    (ok (eq 'describe-spec
            (signalled-operator (lambda () (describe-spec 'positive-integer)))))
    (ok (eq 'describe-property
            (signalled-operator
             (lambda () (describe-property 'addition-preserves-order)))))))
