;;;; tests/property-runner-test.lisp

(defpackage #:cl-spec/tests/property-runner-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-status
                #:property-result-property
                #:property-result-trials
                #:property-result-seed
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:property-result-elapsed
                #:run-property
                #:run-properties
                #:replay-property))

(in-package #:cl-spec/tests/property-runner-test)

(deftest property-result-slots-round-trip
  (testing "PROPERTY-RESULT carries the documented execution record"
    (let ((result (make-instance 'property-result
                                 :status :failed
                                 :property 'addition-preserves-order
                                 :trials 100
                                 :seed 42
                                 :counterexample '(7 -3)
                                 :shrunk-counterexample '(0 -1)
                                 :condition nil
                                 :elapsed 0.25)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq 'addition-preserves-order (property-result-property result)))
      (ok (eql 100 (property-result-trials result)))
      (ok (eql 42 (property-result-seed result)))
      (ok (equal '(7 -3) (property-result-counterexample result)))
      (ok (equal '(0 -1) (property-result-shrunk-counterexample result)))
      (ok (null (property-result-condition result)))
      (ok (eql 0.25 (property-result-elapsed result))))))

(deftest property-result-defaults
  (testing "a bare result reports :PENDING and no counterexample"
    (let ((result (make-instance 'property-result)))
      (ok (eq :pending (property-result-status result)))
      (ok (null (property-result-property result)))
      (ok (null (property-result-counterexample result)))
      (ok (null (property-result-shrunk-counterexample result))))))

(deftest runner-entry-points-are-stubs
  (testing "the runner signals NOT-IMPLEMENTED until the backend is wired up"
    (ok (signals (run-property 'addition-preserves-order) 'not-implemented))
    (ok (signals (run-properties '(addition-preserves-order)) 'not-implemented))
    (ok (signals (replay-property 'addition-preserves-order 42)
                 'not-implemented))))
