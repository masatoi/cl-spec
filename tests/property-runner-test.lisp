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
        (ok (>= original 10)))
      (testing "shrinking actually ran: it converges on the exact minimal failing value"
        ;; CHECK-IT:SHRINK-INT is a bisection search; for (RANGE INTEGER 1 100)
        ;; against (< X 10) it always lands on exactly 10, the smallest integer
        ;; that still fails.  Pinning this catches a regression that turns
        ;; shrinking into a no-op -- the three assertions above would all still
        ;; pass even if SHRUNK-COUNTEREXAMPLE were just a copy of the original.
        (ok (eql 10 shrunk))))))

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

(deftest a-compound-counterexample-survives-shrinking
  ;; The property body claims every list has an even number of elements --
  ;; deliberately false, but chosen for its LENGTH's parity rather than its
  ;; elements' values.  That shape is what makes the failure (and the
  ;; corruption CHECK-IT:SHRINK's in-place mutation can cause without a deep
  ;; copy) reliable rather than a matter of luck: removing any one element
  ;; from an odd-length list always makes it even, i.e. always makes the
  ;; property pass, so CHECK-IT's remove-an-element shrink step is rejected
  ;; for every candidate at every length, and it falls straight to shrinking
  ;; XS's elements in place on the very list this test captured -- on every
  ;; failing trial, not just some of them.
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty list-argument-has-even-length ((xs (list-of small)))
             (:trials (:normal 25))
             (evenp (length xs))))
    (let* ((result (run-property 'list-argument-has-even-length))
           (original (getf (property-result-counterexample result) 'xs))
           (shrunk (getf (property-result-shrunk-counterexample result) 'xs)))
      (testing "the property does fail"
        (ok (eq :failed (property-result-status result))))
      (testing "the shrunk counterexample is a distinct object from the original"
        (ok (not (eq shrunk original))))
      (testing "the original counterexample is still a well-formed list of in-range integers"
        (ok (and (listp original)
                 (every (lambda (value) (and (integerp value) (<= 1 value 100))) original))))
      (testing "the shrunk counterexample is still a well-formed list of in-range integers"
        (ok (and (listp shrunk)
                 (every (lambda (value) (and (integerp value) (<= 1 value 100))) shrunk)))))))

(deftest replay-reproduces-a-run
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 1000)))
    ;; The range is wider than check-it's default size on purpose: the run only
    ;; reaches a counterexample if the required-size accounting works.
    (eval '(cl-spec/src/dsl:defproperty replayable ((x small))
             (:trials (:normal 200))
             (< x 500)))
    (let ((first-run (run-property 'replayable)))
      (testing "the property does fail, so there is something to reproduce"
        (ok (eq :failed (property-result-status first-run))))
      (testing "an integer seed reproduces the counterexample"
        (let ((again (replay-property 'replayable (property-result-seed first-run))))
          (ok (equal (property-result-counterexample first-run)
                     (property-result-counterexample again)))
          (ok (= (property-result-trials first-run) (property-result-trials again)))))
      (testing "a result object may be passed in place of its seed"
        (let ((again (replay-property 'replayable first-run)))
          (ok (eql (property-result-seed first-run) (property-result-seed again)))
          (ok (equal (property-result-counterexample first-run)
                     (property-result-counterexample again))))))))

(deftest replay-requires-matching-profile
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 1000)))
    ;; Define a property where :smoke runs only 5 trials but :normal runs 200.
    ;; This ensures a failure at the higher trial count.
    (eval '(cl-spec/src/dsl:defproperty profile-sensitive ((x small))
             (:trials (:smoke 5 :normal 200))
             (< x 500)))
    ;; DEFPROPERTY's :TRIALS clause takes exactly one plist argument, not one
    ;; sub-list per profile: (:trials (:smoke 5) (:normal 200)) would parse,
    ;; but EXPAND-PROPERTY-DEFINITION only keeps the first sub-list, silently
    ;; dropping :NORMAL and leaving RESOLVE-TRIALS to fall back to the
    ;; backend's default trial count instead of 200. Asserting the full plist
    ;; survived DEFPROPERTY is what makes the rest of this test discriminate
    ;; the fix from that bug, rather than passing whichever trial count wins.
    (testing "both profiles survive DEFPROPERTY, not just the first sub-clause"
      (ok (equal '(:smoke 5 :normal 200)
                 (cl-spec/src/property:property-trials
                  (cl-spec/src/registry:find-property 'profile-sensitive)))))
    ;; Run under :normal profile to guarantee finding a failure.
    (let ((normal-run (run-property 'profile-sensitive :profile :normal)))
      (testing "the property fails under :normal profile"
        (ok (eq :failed (property-result-status normal-run))))
      ;; Replay under the same :normal profile reproduces the exact failure.
      (let ((replayed (replay-property 'profile-sensitive
                                       (property-result-seed normal-run)
                                       :profile :normal)))
        (testing "replay under matching :normal profile reproduces the failure"
          (ok (eq :failed (property-result-status replayed)))
          (ok (equal (property-result-counterexample normal-run)
                     (property-result-counterexample replayed)))
          (ok (= (property-result-trials normal-run)
                 (property-result-trials replayed))))))))

(deftest replay-rejects-invalid-seeds
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty always-holds ((x small))
             (:trials (:normal 5))
             (integerp x)))
    (testing "nil is rejected as a seed"
      (ok (signals (replay-property 'always-holds nil) 'type-error)))
    (testing "negative integers are rejected as seeds"
      (ok (signals (replay-property 'always-holds -1) 'type-error)))
    (testing "arbitrary objects are rejected as seeds"
      (ok (signals (replay-property 'always-holds "not a seed") 'type-error)))))

(deftest run-properties-runs-each-one
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty holds ((x small)) (:trials (:normal 5)) (integerp x)))
    (eval '(cl-spec/src/dsl:defproperty fails ((x small)) (:trials (:normal 5)) (and x nil)))
    (let ((results (run-properties '(holds fails))))
      (testing "one result per designator, in order"
        (ok (= 2 (length results)))
        (ok (equal '(holds fails) (mapcar #'property-result-property results)))
        (ok (equal '(:passed :failed) (mapcar #'property-result-status results)))))))
