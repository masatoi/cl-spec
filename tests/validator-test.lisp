;;;; tests/validator-test.lisp

(defpackage #:cl-spec/tests/validator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:not-implemented-operator)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate))

(in-package #:cl-spec/tests/validator-test)

(defun signalled-operator (thunk)
  "Call THUNK and return the operator named by the NOT-IMPLEMENTED condition it
signals, or NIL if it signals no such condition."
  (handler-case (progn (funcall thunk) nil)
    (not-implemented (condition) (not-implemented-operator condition))))

(deftest validator-entry-points-exist
  (testing "the public validation entry points are defined"
    (ok (fboundp 'compile-validator))
    (ok (fboundp 'validp))
    (ok (fboundp 'validate))))

(deftest validator-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (compile-validator
                  (make-instance 'type-spec :type-specifier 'integer))
                 'not-implemented))
    (ok (signals (validp 'positive-integer 10) 'not-implemented))
    (ok (signals (validate 'positive-integer 10) 'not-implemented))))

(deftest validator-entry-points-name-themselves
  (testing "the signalled condition's operator names the entry point that signalled it"
    (ok (eq 'compile-validator
            (signalled-operator
             (lambda ()
               (compile-validator
                (make-instance 'type-spec :type-specifier 'integer))))))
    (ok (eq 'validp
            (signalled-operator (lambda () (validp 'positive-integer 10)))))
    (ok (eq 'validate
            (signalled-operator (lambda () (validate 'positive-integer 10)))))))
