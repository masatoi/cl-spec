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
                       '(defgenerator small-integer () (random 100)))))
      (ok (eq 'expand-generator-definition (first expansion)))
      (ok (eq 'small-integer (second (second expansion)))))))

(deftest dsl-macros-signal-at-runtime
  (testing "evaluating an expansion of DEFSPEC-FUNCTION or DEFGENERATOR reaches a
stub and signals NOT-IMPLEMENTED"
    (ok (signals (eval '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction)))
                 'not-implemented))
    (ok (signals (eval '(defgenerator small-integer () (random 100)))
                 'not-implemented))))

(deftest defspec-registers-a-normalized-spec
  (let ((*registry* (make-hash-table-registry)))
    (testing "DEFSPEC normalizes and registers"
      (eval '(defspec positive-integer (and integer (range 1 *))))
      (let ((spec (find-spec 'positive-integer)))
        (ok spec)
        (ok (eq :and (spec-kind spec)))
        (ok (eq 'positive-integer (spec-name spec)))
        (ok (equal '(and integer (range 1 *)) (spec-source-form spec)))))))

(deftest defproperty-registers-a-normalized-property
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defspec positive-integer (and integer (range 1 *))))
    (eval '(cl-spec/src/dsl:defproperty addition-preserves-order
               ((x positive-integer) (y positive-integer))
             "Adding a positive integer only ever grows a positive integer."
             (:about +)
             (:kind :monotonicity)
             (:tags :arithmetic)
             (> (+ x y) x)))
    (let ((property (cl-spec/src/registry:find-property 'addition-preserves-order)))
      (testing "the property is registered under its own name"
        (ok property)
        (ok (eq 'addition-preserves-order (cl-spec/src/property:property-name property))))
      (testing "the option clauses are parsed"
        (ok (equal '(+) (cl-spec/src/property:property-targets property)))
        (ok (eq :monotonicity (cl-spec/src/property:property-kind property)))
        (ok (equal '(:arithmetic) (cl-spec/src/property:property-tags property)))
        (ok (stringp (cl-spec/src/property:property-documentation property))))
      (testing "the arguments carry normalized IR, not designators"
        (let ((arguments (cl-spec/src/property:property-arguments property)))
          (ok (equal '(x y) (mapcar #'first arguments)))
          (ok (every (lambda (argument) (typep (second argument) 'cl-spec/src/ir:spec))
                     arguments))))
      (testing "the body is both callable and readable"
        (ok (funcall (cl-spec/src/property:property-function property) 1 2))
        (ok (equal '((> (+ x y) x)) (cl-spec/src/property:property-body property))))
      (testing "the whole form is kept for introspection"
        (ok (eq 'cl-spec/src/dsl:defproperty
                (first (cl-spec/src/property:property-source-form property)))))
      (testing "shrinking defaults to on"
        (ok (getf (cl-spec/src/property:property-metadata property) :shrink)))
      (testing "the reverse index finds it from its target"
        (ok (equal (list (cl-spec/src/property:property-name property))
                   (cl-spec/src/registry:properties-for '+)))))))

(deftest defproperty-stops-consuming-options-at-the-first-non-option
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty stops-at-the-body ((x integer))
             (:kind :invariant)
             (integerp x)
             (:not-an-option-keyword x)))
    (testing "forms after the first non option stay in the body"
      (ok (= 2 (length (cl-spec/src/property:property-body
                        (cl-spec/src/registry:find-property 'stops-at-the-body))))))))

(deftest defproperty-validates-its-trials-clause
  (testing "(:trials 25), a plausible mis-write for a flat trial count, is rejected"
    ;; Left unvalidated, 25 reaches RESOLVE-TRIALS's GETF and signals an
    ;; unrelated SIMPLE-TYPE-ERROR instead of naming the actual problem.
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-trials ((x integer))
                          (:trials 25)
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form)))
  (testing "a well formed :TRIALS plist is accepted"
    (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
      (eval '(cl-spec/src/dsl:defproperty good-trials ((x integer))
              (:trials (:smoke 5 :normal 200))
              (integerp x)))
      (ok (equal '(:smoke 5 :normal 200)
                 (cl-spec/src/property:property-trials
                  (cl-spec/src/registry:find-property 'good-trials)))))))

(deftest defproperty-rejects-extra-values-on-single-value-clauses
  (testing "(:trials (:smoke 5) (:normal 200)), a plausible mis-write for a two
profile plist, is a clause with three elements; unvalidated, (second clause)
is the well formed (:smoke 5) alone and (:normal 200) is silently dropped"
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-trials-profiles ((x integer))
                          (:trials (:smoke 5) (:normal 200))
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form)))
  (testing ":KIND takes exactly one value; an extra element is rejected the same way"
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-kind ((x integer))
                          (:kind :invariant :extra)
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form))))
