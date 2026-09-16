;;;; tests/function-spec-cases-example-test.lisp
;;;;
;;;; Runs the executable example in examples/function-spec-cases.lisp.  The tests
;;;; call the example's own demo entry points rather than copying their logic, so
;;;; a change that breaks the walkthrough fails the normal suite.

(defpackage #:cl-spec/tests/function-spec-cases-example-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry
                #:list-function-specs)
  (:import-from #:cl-spec/examples/function-spec-cases
                #:make-example-registry #:register-example!
                #:demo-both-outcomes #:demo-wrong-implementation
                #:demo-selection-errors #:demo-unchecked-cases))

(in-package #:cl-spec/tests/function-spec-cases-example-test)

(defun demo-case (summary name)
  "Return the :CASES entry of SUMMARY's report for NAME."
  (find name (getf summary :cases) :key (lambda (entry) (getf entry :name))))

(deftest example-registration-leaves-the-user-registry-untouched
  (let ((*registry* (make-hash-table-registry))
        (example (make-example-registry)))
    (register-example! example)
    (testing "the example registers into the registry it is given"
      (ok (member 'cl-spec/examples/function-spec-cases:remaining-balance
                  (list-function-specs example))))
    (testing "the caller's registry is neither read nor written"
      (ok (null (list-function-specs *registry*))))))

(deftest example-checks-a-return-case-and-an-expected-error-case
  (let ((summary (demo-both-outcomes)))
    (testing "the run passes and both cases were exercised"
      (ok (eq :passed (getf summary :status)))
      (ok (eq 2 (getf summary :target-calls)))
      (ok (null (getf summary :never-called)))
      (ok (= 1 (getf (demo-case summary :sufficient-funds) :passed)))
      (ok (= 1 (getf (demo-case summary :insufficient-funds) :passed))))
    (testing "an expected error is a pass for its case, not a failure"
      (ok (= 0 (getf (demo-case summary :insufficient-funds) :failed)))
      (ok (= 0 (getf summary :case-selection-errors))))))

(deftest example-attributes-a-target-bug-to-its-case
  (let ((summary (demo-wrong-implementation)))
    (testing "the failure is a target bug reported under the case that required the error"
      (ok (eq :failed (getf summary :status)))
      (ok (eq :insufficient-funds (getf summary :case)))
      (ok (eq :missing-condition (getf summary :failure-reason)))
      (ok (equal '(:case :insufficient-funds :missing-condition)
                 (getf summary :signature)))
      (ok (null (getf summary :failure-phase))))
    (testing "the case that demanded a return was never reached"
      (ok (eq 1 (getf summary :target-calls)))
      (ok (= 1 (getf (demo-case summary :insufficient-funds) :failed)))
      (ok (equal '(:sufficient-funds) (getf summary :never-called))))))

(deftest example-distinguishes-selection-errors-from-target-bugs
  (let ((summary (demo-selection-errors)))
    (testing "both a duplicated and a missing condition are contract-side errors"
      (dolist (key '(:ambiguous :missing))
        (let ((run (getf summary key)))
          (ok (eq :error (getf run :status)))
          (ok (eq :case-selection (getf run :failure-phase)))
          (ok (eq :contract-error (getf run :failure-reason)))
          (ok (= 0 (getf run :target-calls)))
          (ok (null (getf run :case)))
          (ok (= 1 (getf run :case-selection-errors))))))
    (testing "the explanation kind says which selection error it is"
      (ok (eq :ambiguous-case (getf (getf summary :ambiguous) :selection-error)))
      (ok (eq :no-matching-case (getf (getf summary :missing) :selection-error))))
    (testing "the failure identities separate the two kinds"
      (ok (equal '(:case-selection :ambiguous-case)
                 (getf (getf summary :ambiguous) :signature)))
      (ok (equal '(:case-selection :no-matching-case)
                 (getf (getf summary :missing) :signature))))))

(deftest example-shows-unchecked-cases-in-a-passing-run
  (let ((summary (demo-unchecked-cases)))
    (testing "the status is passed because nothing that ran was violated"
      (ok (eq :passed (getf summary :status)))
      (ok (= 1 (getf (demo-case summary :sufficient-funds) :passed))))
    (testing "but the case no trial reached is reported"
      (ok (= 0 (getf (demo-case summary :insufficient-funds) :called)))
      (ok (equal '(:insufficient-funds) (getf summary :never-called))))))
