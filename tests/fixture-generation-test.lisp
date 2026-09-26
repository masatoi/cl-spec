;;;; tests/fixture-generation-test.lisp
(defpackage #:cl-spec/tests/fixture-generation-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/tests/fixture-function-test
                #:with-contract #:withdraw #:*mode* #:*setups* #:*cleanups* #:*calls*
                #:*objects*))
(in-package #:cl-spec/tests/fixture-generation-test)

(deftest generated-fixture-trials-are-independent
  (with-contract
    (let* ((result (cl-spec:check-function 'withdraw :trials 12 :seed 41))
           (data (cl-spec:result-data result)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 12 *setups* *cleanups*))
      (ok (= *calls* (length (remove-duplicates *objects* :test #'eq))))
      (ok (= 2 (getf data :schema-version)))
      (ok (eq :fixture-recipe (getf data :input-kind))))))

(deftest fixture-state-failure-shrinks-from-fresh-recipe
  (with-contract
    (let* ((*mode* :missing-update)
           (result (cl-spec:check-function 'withdraw :trials 30 :seed 41
                                           :options '(:shrink-budget 30)))
           (data (cl-spec:result-data result)))
      (ok (eq :failed (cl-spec:property-result-status result)))
      (ok (cl-spec:property-result-shrunk-counterexample result))
      (ok (equal '(:state-postcondition 0) (cl-spec:property-result-failure-signature result)))
      (ok (<= (getf (cl-spec:property-result-shrink-report result) :candidates) 30))
      (ok (= *setups* *cleanups*))
      (ok (> *setups* 1))
      (ok (eq :released (getf (getf (getf data :failure) :lifecycle) :state))))))

(deftest generated-cleanup-error-stops-run
  (with-contract
    (let* ((*mode* :cleanup-error)
           (result (cl-spec:check-function 'withdraw :trials 30 :seed 41)))
      (ok (eq :error (cl-spec:property-result-status result)))
      (ok (eq :fixture-cleanup-error (cl-spec:property-result-failure-reason result)))
      (ok (= 1 *setups* *cleanups*))
      (ok (getf (cl-spec:result-data result) :run-error)))))

(deftest fixture-result-replay
  (with-contract
    (let* ((*mode* :missing-update)
           (first (cl-spec:check-function 'withdraw :trials 30 :seed 41))
           (second (cl-spec:check-function 'withdraw :seed first)))
      (ok (equal (cl-spec:property-result-counterexample first)
                 (cl-spec:property-result-counterexample second)))
      (ok (equal (cl-spec:property-result-shrunk-counterexample first)
                 (cl-spec:property-result-shrunk-counterexample second))))))

(deftest fixture-replay-refuses-changed-budget-before-setup
  (with-contract
    (let* ((first (cl-spec:check-function 'withdraw :trials 4 :seed 41))
           (before *setups*))
      (ok (handler-case
              (progn (cl-spec:check-function 'withdraw :trials 5 :seed first) nil)
            (cl-spec:unsupported-stateful-operation () t)))
      (ok (= before *setups*)))))

(deftest fixture-custom-recipe-shrinking
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (calls 0) (cleanups 0) (seen nil))
    (cl-spec:defgenerator recipes ()
      (:shrink (value) (when (> value 1) (list 1)))
      10)
    (cl-spec:defspec saved-recipe integer (:generator recipes))
    (cl-spec:defspec-function identity
      (:args (value (list-of integer)))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe saved-recipe))
        (:setup (context)
          (declare (ignore context))
          (let ((object (list recipe))) (push object seen) (list object)))
        (:cleanup (context) (declare (ignore recipe context)) (incf cleanups)))
      (:returns (list-of integer))
      (:state-post (progn (incf calls) nil)))
    (let ((result (cl-spec:check-function 'identity :trials 1 :seed 3)))
      (ok (equal '(recipe 1) (cl-spec:property-result-shrunk-counterexample result)))
      (ok (= 2 calls cleanups))
      (ok (= 2 (length (remove-duplicates seen :test #'eq)))))))

(deftest shrinking-cleanup-failure-retains-original-and-stops
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (setups 0) (cleanups 0))
    (cl-spec:defgenerator abort-recipes ()
      (:shrink (value) (declare (ignore value)) '(5 1))
      10)
    (cl-spec:defspec abort-recipe integer (:generator abort-recipes))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe abort-recipe))
        (:setup (context) (declare (ignore context)) (incf setups) (list recipe))
        (:cleanup (context) (declare (ignore context)) (incf cleanups)
                  (when (= recipe 5) (error "cleanup failed"))))
      (:returns integer) (:state-post nil))
    (let* ((result (cl-spec:check-function 'identity :trials 1 :seed 3))
           (data (cl-spec:result-data result)))
      (ok (eq :error (cl-spec:property-result-status result)))
      (ok (eq :fixture-cleanup-error (cl-spec:property-result-failure-reason result)))
      (ok (equal '(recipe 10) (cl-spec:property-result-counterexample result)))
      (ok (eq :failed (getf (getf data :failure) :status)))
      (ok (getf data :run-error))
      (ok (= 2 setups cleanups))
      (ok (handler-case (progn (cl-spec:make-counterexample-artifact result) nil)
            (cl-spec:invalid-counterexample-artifact () t))))))

(deftest fixture-zero-trials-are-skipped
  (with-contract
    (let ((result (cl-spec:check-function 'withdraw :trials 0 :seed 1)))
      (ok (eq :skipped (cl-spec:property-result-status result)))
      (ok (zerop *setups*))
      (ok (zerop *calls*))
      (ok (zerop *cleanups*)))))