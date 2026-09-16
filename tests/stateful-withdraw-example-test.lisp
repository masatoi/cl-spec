;;;; tests/stateful-withdraw-example-test.lisp
;;;;
;;;; Runs the executable example in examples/stateful-withdraw.lisp.  The tests
;;;; call the example's own demo entry points rather than copying their logic, so
;;;; a change that breaks the walkthrough fails the normal suite.

(defpackage #:cl-spec/tests/stateful-withdraw-example-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry
                #:list-function-specs)
  (:import-from #:cl-spec/examples/stateful-withdraw
                #:make-example-registry #:register-example!
                #:balance-verification-failed
                #:demo-successful-withdrawal #:demo-missing-update
                #:demo-refusal-that-mutated #:demo-renumbered-account
                #:demo-verification-error #:demo-limits))

(in-package #:cl-spec/tests/stateful-withdraw-example-test)

(defun demo-case (summary name)
  "Return the :CASES entry of SUMMARY's report for NAME."
  (find name (getf summary :cases) :key (lambda (entry) (getf entry :name))))

(defun state-post (summary)
  "Return SUMMARY's :STATE-POST evidence."
  (getf (getf summary :state) :state-post))

(deftest example-registration-leaves-the-user-registry-untouched
  (let ((*registry* (make-hash-table-registry))
        (example (make-example-registry)))
    (register-example! example)
    (testing "the example registers into the registry it is given"
      (ok (member 'cl-spec/examples/stateful-withdraw:withdraw!
                  (list-function-specs example))))
    (testing "the caller's registry is neither read nor written"
      (ok (null (list-function-specs *registry*))))))

(deftest example-checks-a-successful-update-and-a-correct-refusal
  (let ((summary (demo-successful-withdrawal)))
    (testing "both the update and the refusal pass"
      (ok (eq :passed (getf summary :status)))
      (ok (eq 2 (getf summary :target-calls)))
      (ok (= 1 (getf (demo-case summary :sufficient-funds) :passed)))
      (ok (= 1 (getf (demo-case summary :insufficient-funds) :passed)))
      (ok (null (getf summary :never-called))))
    (testing "a passing run keeps no failure evidence"
      (ok (null (getf summary :state))))))

(deftest example-detects-a-missing-update
  (let ((summary (demo-missing-update)))
    (testing "the outcome contract passed but the state relation did not"
      (ok (eq :failed (getf summary :status)))
      (ok (eq :state-post (getf summary :failure-phase)))
      (ok (eq :state-postcondition (getf summary :failure-reason)))
      (ok (equal '(:case :sufficient-funds :state-postcondition 0)
                 (getf summary :signature))))
    (testing "the evidence says which form failed and what was captured"
      (ok (eq :violation (getf (state-post summary) :status)))
      (ok (= 0 (getf (state-post summary) :index)))
      (ok (eq :completed (getf (getf (getf summary :state) :capture) :status))))))

(deftest example-detects-a-refusal-that-mutated
  (let ((summary (demo-refusal-that-mutated)))
    (testing "signalling the expected error does not excuse the state change"
      (ok (eq :failed (getf summary :status)))
      (ok (eq :state-postcondition (getf summary :failure-reason)))
      (ok (= 1 (getf (demo-case summary :insufficient-funds) :failed)))
      (ok (= 0 (getf (demo-case summary :insufficient-funds) :passed))))))

(deftest example-detects-an-unrelated-value-changing
  (let ((summary (demo-renumbered-account)))
    (testing "the balance is right but the observed identifier changed"
      (ok (eq :failed (getf summary :status)))
      (ok (equal '(:case :sufficient-funds :state-postcondition 1)
                 (getf summary :signature)))
      (ok (= 1 (getf (state-post summary) :index))))))

(deftest example-distinguishes-a-violation-from-a-verification-error
  (let ((summary (demo-verification-error)))
    (testing "a state-post form that signals is a contract error, not a violation"
      (ok (eq :error (getf summary :status)))
      (ok (eq :contract-error (getf summary :failure-reason)))
      (ok (eq :state-post (getf summary :failure-phase)))
      (ok (eq :error (getf (state-post summary) :status)))
      (ok (eq 'balance-verification-failed
              (getf (state-post summary) :condition-type))))))

(deftest example-reports-the-first-version-limits
  (let ((limits (demo-limits)))
    (testing "shrinking and artifacts say why they are unsupported"
      (ok (eq :state-restoration-unavailable (getf limits :shrink-termination)))
      (ok (eq :present (getf limits :state-constraints)))
      (ok (eq :stateful-contract-unsupported (getf limits :artifact))))
    (testing "replaying a past result is refused with the same reason"
      (ok (eq :state-restoration-unavailable (getf limits :replay))))))
