;;;; tests/validator-test.lisp

(defpackage #:cl-spec/tests/validator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation
                #:spec-violation-value
                #:spec-violation-path
                #:spec-violation-errors)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate))

(in-package #:cl-spec/tests/validator-test)

(deftest validp-agrees-with-explain-data
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "VALIDP is true exactly when EXPLAIN-DATA reports no errors"
      (dolist (value (list 10 -1 0 1 "foo" nil))
        (ok (eq (and (validp 'positive-integer value :registry registry) t)
                (and (getf (explain-data 'positive-integer value :registry registry)
                           :valid)
                     t)))))))

(deftest validate-returns-or-signals
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "a valid value is returned unchanged"
      (ok (eql 10 (validate 'positive-integer 10 :registry registry))))
    (testing "an invalid value signals SPEC-VIOLATION carrying the structured errors"
      (let ((condition (handler-case (progn (validate 'positive-integer -1 :registry registry) nil)
                         (spec-violation (c) c))))
        (ok condition)
        (ok (eql -1 (spec-violation-value condition)))
        (ok (spec-violation-errors condition))))))

(deftest validate-signals-with-the-failing-path
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'ints
                            (normalize-spec-form '(list-of integer) :name 'ints))
    (testing "PATH is populated from the first structured error, not left NIL"
      ;; A top level scalar failure has an empty path, so this needs a spec
      ;; that actually nests -- otherwise the assertion would pass whether or
      ;; not PATH were ever populated.
      (let ((condition (handler-case
                            (progn (validate 'ints '(1 2 "x" 4) :registry registry) nil)
                          (spec-violation (c) c))))
        (ok condition)
        (ok (equal '(2) (spec-violation-path condition)))
        (ok (search "at path (2)" (princ-to-string condition)))))))

(deftest validate-names-an-anonymous-spec-by-its-source-form
  (testing "an anonymous spec object reports its source form, not NIL"
    ;; (RANGE 1 10) has no registered name, so :SPEC used to fall back to NIL
    ;; and the report read literally "99 does not satisfy NIL."
    (let ((condition (handler-case
                          (progn (validate (normalize-spec-form '(range 1 10)) 99) nil)
                        (spec-violation (c) c))))
      (ok condition)
      (ok (search "does not satisfy (RANGE 1 10)" (princ-to-string condition))))))

(deftest predicate-errors-distinguish-value-bugs-from-spec-bugs
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive
                            (normalize-spec-form '(satisfies plusp) :name 'positive))
    (registry-register-spec registry 'broken
                            ;; PLUSSPP does not exist: a typo the author made, not a fact
                            ;; about any value handed to VALIDP.
                            (normalize-spec-form '(satisfies plusspp) :name 'broken))
    (testing "a predicate applied to the wrong kind of value still answers NIL"
      (ok (not (validp 'positive "foo" :registry registry))))
    (testing "an undefined predicate signals rather than reporting the value as invalid"
      (ok (handler-case (progn (validp 'broken 1 :registry registry) nil)
            (undefined-function () t))))))

(deftest compile-validator-produces-a-predicate
  (testing "the compiled function takes one argument and returns a boolean"
    (let ((validator (compile-validator (normalize-spec-form '(and integer (range 1 *))))))
      (ok (funcall validator 5))
      (ok (not (funcall validator -5))))))
