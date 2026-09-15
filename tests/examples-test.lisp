;;;; tests/examples-test.lisp
;;;;
;;;; Runs the executable integration example in examples/structured-data.lisp.
;;;; The tests call the example's own entry points rather than copying their
;;;; logic, so a change that breaks the walkthrough fails the normal suite.
;;;;
;;;; A demo that intentionally produces a failure (:FAILED contract, budget
;;;; exhaustion) is a success here when it produces the expected failure result;
;;;; none of these tests fail because a demo failed.

(defpackage #:cl-spec/tests/examples-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry
                #:list-specs #:list-properties #:validp)
  ;; A bare :IMPORT-FROM declares a load-time dependency without importing a
  ;; symbol, so running this suite on its own loads the check-it backend the
  ;; example's generation demos need instead of relying on a sibling suite.
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/examples/structured-data
                #:make-example-registry #:register-example!
                #:demo-validation #:demo-sample #:demo-check-function
                #:demo-property #:demo-discovery #:demo-replay
                #:demo-keyed-representations #:demo-object-source
                #:demo-tagged-union #:demo-budget-exhaustion
                #:demo-target-violation))

(in-package #:cl-spec/tests/examples-test)

(defun example-spec-name (name registry)
  "Return the example registry's spec named NAME, matched case-insensitively."
  (find (string-upcase name) (list-specs registry) :key #'symbol-name :test #'string=))

(deftest example-registration-leaves-the-user-registry-untouched
  (let ((*registry* (make-hash-table-registry))
        (example (make-example-registry)))
    (register-example! example)
    (testing "the example registers into the registry it is given"
      (ok (example-spec-name "WINDOW" example)))
    (testing "the caller's registry is neither read nor written"
      (ok (null (list-specs *registry*)))
      (ok (null (list-properties *registry*))))))

(deftest example-sample-values-satisfy-the-spec
  (let* ((registry (register-example!))
         (demo (demo-sample registry 5 42))
         (report (getf demo :report)))
    (ok (= 5 (length (getf demo :values))))
    (ok (getf demo :all-valid))
    (testing "the generation report separates roots from filter work"
      (ok (= 5 (getf report :requested-values)))
      (ok (= 5 (getf report :generated-values)))
      (ok (<= (getf report :rejections) (getf report :attempts)))
      (ok (<= (getf report :attempts) (getf report :budget)))
      (ok (eq :completed (getf report :termination))))
    (testing "the same seed reproduces the same values"
      (ok (equal (getf demo :values)
                 (getf (demo-sample registry 5 42) :values))))))

(deftest example-validation-distinguishes-good-and-bad
  (let ((demo (demo-validation)))
    (ok (getf demo :good-valid))
    (ok (not (getf demo :unordered-valid)))
    (ok (not (getf demo :missing-valid)))
    (testing "an unordered window fails the satisfies conjunct"
      (let* ((datum (first (getf demo :unordered-errors)))
             (nested (first (getf datum :errors))))
        (ok (eq :conjunct-failed (getf datum :kind)))
        (ok (eq :predicate-failed (getf nested :kind)))))
    (testing "a missing field is reported with its path"
      (let* ((datum (first (getf demo :missing-errors)))
             (nested (first (getf datum :errors))))
        (ok (eq :missing-key (getf nested :kind)))
        (ok (equal '(:end) (getf nested :path)))))))

(deftest example-check-function-passes
  (let ((demo (demo-check-function)))
    (ok (eq :passed (getf demo :status)))
    (ok (eq :completed (getf (getf demo :report) :termination)))))

(deftest example-properties-pass
  (let ((demo (demo-property)))
    (ok (eq :passed (getf demo :non-negative)))
    (ok (eq :passed (getf demo :additive)))))

(deftest example-discovery-finds-specs-contracts-and-properties
  (let ((demo (demo-discovery)))
    (ok (string= "WINDOW" (symbol-name (getf demo :spec-name))))
    (ok (eq :and (getf demo :spec-kind)))
    (ok (eq :function-spec (getf demo :contract-kind)))
    (ok (equal '(:generation :available :shrinking :available)
               (getf demo :capability)))
    (ok (find "SPAN-IS-NON-NEGATIVE" (getf demo :properties)
              :key #'symbol-name :test #'string=))))

(deftest example-replay-reproduces-the-recorded-run
  (let ((demo (demo-replay)))
    (ok (eq :failed (getf demo :original-status)))
    (ok (eq :failed (getf demo :replay-status)))
    (ok (eql (getf demo :original-seed) (getf demo :replay-seed)))
    (ok (equal (getf demo :original-counterexample)
               (getf demo :replay-counterexample)))))

(deftest example-keyed-representations-distinguish-absence-from-nil
  (let ((demo (demo-keyed-representations)))
    (ok (getf demo :alist-present-nil))
    (ok (not (getf demo :alist-missing)))
    (ok (getf demo :hash-present-nil))
    (ok (not (getf demo :hash-missing)))
    (testing "the missing alist key is a structured missing-key failure"
      (ok (eq :missing-key (getf (first (getf demo :alist-missing-errors)) :kind))))))

(deftest example-object-source-uses-readers-and-an-and-source
  (let ((demo (demo-object-source)))
    (ok (= 3 (length (getf demo :endpoints))))
    (ok (getf demo :all-ordered))
    (ok (eq :completed (getf demo :termination)))))

(deftest example-tagged-union-dispatches-by-tag
  (let ((demo (demo-tagged-union)))
    (ok (every (lambda (value) (eq :error (getf value :kind)))
               (getf demo :error-branch)))
    (testing "a failing branch names itself"
      (let ((datum (first (getf demo :wrong-value))))
        (ok (eq :type-failed (getf datum :kind)))
        (ok (eq :ok (getf datum :branch)))))
    (testing "an unknown tag lists the known tags"
      (let ((datum (first (getf demo :unknown-tag))))
        (ok (eq :no-branch (getf datum :kind)))
        (ok (eq :other (getf datum :observed-tag)))
        (ok (equal '(:ok :error) (getf datum :known-tags)))))))

(deftest example-budget-exhaustion-reports-the-budget
  (let ((demo (demo-budget-exhaustion 6)))
    (ok (eq :exhausted (getf demo :outcome)))
    (ok (= 6 (getf demo :attempts)))
    (ok (= 6 (getf demo :budget)))
    (ok (= 6 (getf demo :rejections)))
    (ok (eq :generation (getf demo :phase)))
    (ok (eq :budget-exhausted (getf (getf demo :report) :termination)))))

(deftest example-target-violation-is-not-generation-exhaustion
  (let* ((registry (register-example!))
         (demo (demo-target-violation registry))
         (shrunk (getf demo :shrunk-counterexample)))
    (ok (eq :failed (getf demo :status)))
    (ok (eq :return-spec (getf demo :failure-reason)))
    (ok (getf demo :counterexample))
    (testing "a reported reduction still satisfies the window spec"
      (when shrunk
        (ok (validp (example-spec-name "WINDOW" registry)
                    (second shrunk)
                    :registry registry))))))
