;;;; tests/explain-test.lisp

(defpackage #:cl-spec/tests/explain-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:not-implemented-operator)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain))

(in-package #:cl-spec/tests/explain-test)

(defun signalled-operator (thunk)
  "Call THUNK and return the operator named by the NOT-IMPLEMENTED condition it
signals, or NIL if it signals no such condition."
  (handler-case (progn (funcall thunk) nil)
    (not-implemented (condition) (not-implemented-operator condition))))

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

(deftest explain-entry-points-name-themselves
  (testing "the signalled condition's operator names the entry point that signalled it"
    (ok (eq 'compile-explainer
            (signalled-operator
             (lambda ()
               (compile-explainer
                (make-instance 'type-spec :type-specifier 'integer))))))
    (ok (eq 'explain-data
            (signalled-operator (lambda () (explain-data 'positive-integer -1)))))
    (ok (eq 'explain
            (signalled-operator (lambda () (explain 'positive-integer -1)))))))
