;;;; tests/dsl-test.lisp

(defpackage #:cl-spec/tests/dsl-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir
                #:spec-kind
                #:spec-name
                #:spec-source-form)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-spec)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator
                #:register-spec
                #:normalize-spec-form
                #:register-function-spec
                #:expand-function-spec-definition
                #:register-property
                #:expand-property-definition
                #:expand-generator-definition))

(in-package #:cl-spec/tests/dsl-test)

(deftest dsl-macros-are-macros
  (testing "the four DSL entry points are macros, not functions"
    (ok (macro-function 'defspec))
    (ok (macro-function 'defspec-function))
    (ok (macro-function 'defproperty))
    (ok (macro-function 'defgenerator))))

(deftest dsl-macros-expand-without-error
  (testing "macroexpansion produces the expected call shape"
    (let ((expansion (macroexpand-1
                       '(defspec positive-integer (and integer (range 1 *))))))
      (ok (eq 'register-spec (first expansion)))
      (ok (eq 'positive-integer (second (second expansion))))
      (ok (eq 'normalize-spec-form (first (third expansion)))))
    (let ((expansion (macroexpand-1
                       '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction)))))
      (ok (eq 'register-function-spec (first expansion)))
      (ok (eq 'expand-function-spec-definition (first (second expansion))))
      (ok (eq 'transfer (second (second (second expansion))))))
    (let ((expansion (macroexpand-1
                       '(defproperty addition-preserves-order
                         ((x positive-integer) (y positive-integer))
                         (:about +)
                         (> (+ x y) x)))))
      (ok (eq 'register-property (first expansion)))
      (ok (eq 'expand-property-definition (first (second expansion))))
      (ok (eq 'addition-preserves-order (second (second (second expansion))))))
    (let ((expansion (macroexpand-1
                       '(defgenerator small-integer () (random 100)))))
      (ok (eq 'expand-generator-definition (first expansion)))
      (ok (eq 'small-integer (second (second expansion)))))))

(deftest dsl-macros-signal-at-runtime
  (testing "evaluating an expansion of DEFSPEC-FUNCTION, DEFPROPERTY or DEFGENERATOR reaches a stub and signals NOT-IMPLEMENTED"
    (ok (signals (eval '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction)))
                 'not-implemented))
    (ok (signals (eval '(defproperty addition-preserves-order
                         ((x positive-integer) (y positive-integer))
                         (:about +)
                         (> (+ x y) x)))
                 'not-implemented))
    (ok (signals (eval '(defgenerator small-integer () (random 100)))
                 'not-implemented))))

(deftest defspec-registers-a-normalized-spec
  (let ((*registry* (make-hash-table-registry)))
    (testing "DEFSPEC normalizes its form and registers the result"
      (eval '(defspec positive (satisfies plusp)))
      (let ((spec (find-spec 'positive)))
        (ok spec)
        (ok (eq :predicate (spec-kind spec)))
        (ok (eq 'positive (spec-name spec)))
        (ok (equal '(satisfies plusp) (spec-source-form spec)))))))

(deftest defspec-rejects-a-composite-head-for-now
  (let ((*registry* (make-hash-table-registry)))
    (testing "composite heads are not normalized yet"
      (ok (signals (eval '(defspec positive-integer (and integer (range 1 *))))
                   'invalid-spec-form)))))
