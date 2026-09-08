;;;; tests/self-properties-test.lisp
;;;;
;;;; The framework tested with its own property runner (specification §68).
;;;; These specs and properties register into the global *REGISTRY* under
;;;; SELF- prefixed names, because a property has to be registered to be run.

(defpackage #:cl-spec/tests/self-properties-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defproperty)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/generator
                #:sample)
  (:import-from #:cl-spec/src/property-runner
                #:run-property
                #:replay-property
                #:property-result-status
                #:property-result-seed
                #:property-result-counterexample)
  (:import-from #:cl-spec/src/registry
                #:find-spec
                #:list-specs)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/self-properties-test)

(defspec self-positive-integer (and integer (range 1 *)))

(defproperty self-generated-values-satisfy-their-spec ((x self-positive-integer))
  "Whatever the generator produces, the spec it came from admits."
  (:about sample)
  (:kind :invariant)
  (validp 'self-positive-integer x))

(defproperty self-validp-agrees-with-explain-data ((x integer))
  "VALIDP and EXPLAIN-DATA never disagree about the same value."
  (:about validp)
  (:kind :invariant)
  (eq (and (validp 'self-positive-integer x) t)
      (and (getf (explain-data 'self-positive-integer x) :valid) t)))

(defproperty self-and-matches-its-conjuncts ((x integer))
  "A conjunction admits exactly what all of its conjuncts admit."
  (:about validp)
  (:kind :invariant)
  (eq (and (validp 'self-positive-integer x) t)
      (and (integerp x) (>= x 1) t)))

(defproperty self-registry-lookup-is-stable ((x self-positive-integer))
  "Looking a spec up twice returns the same object."
  (:about find-spec)
  (:kind :invariant)
  (and x (eq (find-spec 'self-positive-integer) (find-spec 'self-positive-integer))))

(deftest the-framework-satisfies-its-own-properties
  (dolist (name '(self-generated-values-satisfy-their-spec
                  self-validp-agrees-with-explain-data
                  self-and-matches-its-conjuncts
                  self-registry-lookup-is-stable))
    (testing (format nil "~S passes" name)
      (let ((result (run-property name)))
        (ok (eq :passed (property-result-status result))
            (format nil "~S: ~S" name (property-result-counterexample result)))))))

(deftest sampled-values-satisfy-the-spec-they-came-from
  (testing "every sampled value is admitted by its own spec"
    (ok (every (lambda (value) (validp 'self-positive-integer value))
               (sample 'self-positive-integer :count 100)))))

(defspec self-small-integer (range integer 1 100))

(defproperty self-fails-above-ten ((x self-small-integer))
  "Deliberately false above ten, so that replay has something to reproduce."
  (:kind :invariant)
  (:trials (:normal 200))
  (< x 10))

(deftest a-seed-reproduces-the-same-counterexample
  (let ((first-run (run-property 'self-fails-above-ten)))
    (testing "the property fails, as it is meant to"
      (ok (eq :failed (property-result-status first-run))))
    (testing "replaying from the recorded seed finds the same counterexample"
      (ok (equal (property-result-counterexample first-run)
                 (property-result-counterexample
                  (replay-property 'self-fails-above-ten
                                   (property-result-seed first-run))))))))
