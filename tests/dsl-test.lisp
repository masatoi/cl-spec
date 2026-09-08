;;;; tests/dsl-test.lisp

(defpackage #:cl-spec/tests/dsl-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator))

(in-package #:cl-spec/tests/dsl-test)

(deftest dsl-macros-are-macros
  (testing "the four DSL entry points are macros, not functions"
    (ok (macro-function 'defspec))
    (ok (macro-function 'defspec-function))
    (ok (macro-function 'defproperty))
    (ok (macro-function 'defgenerator))))

(deftest dsl-macros-expand-without-error
  (testing "macroexpansion succeeds so that source files still compile"
    (ok (macroexpand-1 '(defspec positive-integer (and integer (range 1 *)))))
    (ok (macroexpand-1 '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction))))
    (ok (macroexpand-1 '(defproperty addition-preserves-order
                         ((x positive-integer) (y positive-integer))
                         (:about +)
                         (> (+ x y) x))))
    (ok (macroexpand-1 '(defgenerator small-integer () (random 100))))))

(deftest dsl-macros-signal-at-runtime
  (testing "evaluating an expansion reaches a stub and signals NOT-IMPLEMENTED"
    (ok (signals (eval '(defspec positive-integer (and integer (range 1 *))))
                 'not-implemented))
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
