;;;; tests/property-runner-test.lisp

(defpackage #:cl-spec/tests/property-runner-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/dsl)
  (:import-from #:cl-spec/src/registry)
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
                #:replay-property)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/property-runner-test)

(defmacro with-fresh-registry (&body body)
  "Run BODY against a registry no other test can see."
  `(let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
     ,@body))

(deftest a-passing-property-reports-passed
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty always-holds ((x small))
             (:trials (:normal 25))
             (integerp x)))
    (let ((result (run-property 'always-holds)))
      (testing "the status and trial count are reported"
        (ok (eq :passed (property-result-status result)))
        (ok (= 25 (property-result-trials result))))
      (testing "the seed is recorded even on success"
        (ok (integerp (property-result-seed result))))
      (testing "no counterexample is reported"
        (ok (null (property-result-counterexample result))))
      (testing "the elapsed time is recorded"
        (ok (realp (property-result-elapsed result)))))))

(deftest a-failing-property-reports-a-named-counterexample
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty never-holds ((x small) (y small))
             (:trials (:normal 25))
             (and x y nil)))
    (let ((result (run-property 'never-holds)))
      (testing "the status is :FAILED"
        (ok (eq :failed (property-result-status result))))
      (testing "it stopped at the first failing trial"
        (ok (= 1 (property-result-trials result))))
      (testing "the counterexample is keyed by the argument names"
        (let ((counterexample (property-result-counterexample result)))
          (ok (integerp (getf counterexample 'x)))
          (ok (integerp (getf counterexample 'y))))))))

(deftest a-signalling-property-reports-error-and-keeps-the-condition
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty always-signals ((x small))
             (:trials (:normal 5))
             (error "boom ~S" x)))
    (let ((result (run-property 'always-signals)))
      (testing "the status distinguishes a signalled condition from a NIL result"
        (ok (eq :error (property-result-status result))))
      (testing "the condition itself is kept"
        (ok (typep (property-result-condition result) 'error))
        (ok (search "boom" (princ-to-string (property-result-condition result))))))))

(deftest failures-are-shrunk
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty stays-under-ten ((x small))
             (:trials (:normal 200))
             (< x 10)))
    (let* ((result (run-property 'stays-under-ten))
           (original (getf (property-result-counterexample result) 'x))
           (shrunk (getf (property-result-shrunk-counterexample result) 'x)))
      (testing "the property does fail"
        (ok (eq :failed (property-result-status result))))
      (testing "the shrunk value is no larger than the original"
        (ok (<= shrunk original)))
      (testing "the shrunk value still fails the property"
        (ok (>= shrunk 10)))
      (testing "the original counterexample survives shrinking"
        (ok (>= original 10))))))

(deftest shrinking-can-be-turned-off
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty unshrunk ((x small))
             (:trials (:normal 25))
             (:shrink nil)
             (and x nil)))
    (testing "no shrunk counterexample is produced"
      (ok (null (property-result-shrunk-counterexample (run-property 'unshrunk)))))))

(deftest an-unregistered-property-signals
  (with-fresh-registry
    (testing "RUN-PROPERTY signals UNKNOWN-PROPERTY"
      (ok (signals (run-property 'absent) 'cl-spec/src/conditions:unknown-property)))))
