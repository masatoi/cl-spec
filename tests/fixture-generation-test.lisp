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
      (ok (eq :fixture (cl-spec:property-result-failure-phase result)))
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
    (ok (eq :available (getf (getf (cl-spec:function-spec-data 'identity)
                                    :capabilities) :shrinking)))
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
      (:returns integer) (:state-post (error "original failure")))
    (let* ((result (cl-spec:check-function 'identity :trials 1 :seed 3))
           (data (cl-spec:result-data result)))
      (ok (eq :error (cl-spec:property-result-status result)))
      (ok (eq :fixture-cleanup-error (cl-spec:property-result-failure-reason result)))
      (ok (eq :fixture (cl-spec:property-result-failure-phase result)))
      (ok (equal '(recipe 10) (cl-spec:property-result-counterexample result)))
      (ok (eq :error (getf (getf data :failure) :status)))
      (ok (search "cleanup failed" (princ-to-string (cl-spec:property-result-condition result))))
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

(deftest fixture-case-report-separates-lifecycle-and-contract-errors
  (dolist (mode '(:setup :capture :guard :cleanup))
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec-function identity
        (:args (value integer))
        (:fixture
          (:isolation :fresh) (:version 1) (:recipe (recipe integer))
          (:setup (context) (declare (ignore context))
            (when (eq mode :setup) (error "setup")) (list recipe))
          (:cleanup (context) (declare (ignore recipe context)) (error "cleanup")))
        (:capture (before (if (eq mode :capture) (error "capture") value)))
        (:cases (:only (:when (if (eq mode :guard) (error "guard") t))
                       (:returns integer) (:state-post (= value before)))))
      (let* ((result (cl-spec:check-function 'identity :trials 3 :seed 1))
             (report (cl-spec:function-check-result-case-report result))
             (case (first (getf report :cases))))
        (ok (eq :error (cl-spec:property-result-status result)))
        (ok (eql 1 (getf report :fixture-errors)))
        (ok (= (if (eq mode :cleanup) 1 0) (getf case :called)))
        (ok (= (if (eq mode :cleanup) 1 0) (getf case :error)))
        (ok (= (if (eq mode :capture) 1 0) (getf report :capture-errors)))
        (ok (= (if (eq mode :guard) 1 0) (getf report :case-selection-errors)))))))

(deftest fixture-hooks-are-captured-for-the-whole-run
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (fixture nil) (setups 0) (cleanups 0) (replacement-calls 0))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe integer))
        (:setup (context)
          (declare (ignore context))
          (incf setups)
          (reinitialize-instance
           fixture
           :setup-forms '((replacement-setup))
           :setup-function (lambda (value context)
                             (declare (ignore context))
                             (incf replacement-calls) (list value))
           :cleanup-forms '((replacement-cleanup))
           :cleanup-function (lambda (value context)
                               (declare (ignore value context))
                               (incf replacement-calls)))
          (list recipe))
        (:cleanup (context) (declare (ignore recipe context)) (incf cleanups)))
      (:returns integer))
    (setf fixture (cl-spec:function-spec-fixture
                   (cl-spec/src/function-spec::resolve-function-spec
                    'identity cl-spec:*registry*)))
    (let ((result (cl-spec:check-function 'identity :trials 2 :seed 1)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 2 setups cleanups))
      (ok (zerop replacement-calls)))))

(deftest property-replay-preserves-fixture-result-validation
  (with-contract
    (let* ((contract (cl-spec/src/function-spec::resolve-function-spec
                      'withdraw cl-spec:*registry*))
           (adapter (cl-spec/src/function-spec:make-fixture-check-property
                     contract :budget 2))
           (first (cl-spec:run-property adapter :seed 4 :options '(:shrink-budget 2)))
           (before *setups*))
      (ok (handler-case
              (progn (cl-spec:replay-property adapter first
                                             :options '(:shrink-budget 3)) nil)
            (cl-spec:unsupported-stateful-operation () t)))
      (ok (= before *setups*)))))

(deftest reused-fixture-adapter-captures-each-new-run
  (with-contract
    (let* ((contract (cl-spec:find-function-spec 'withdraw))
           (adapter (cl-spec/src/function-spec:make-fixture-check-property
                     contract :budget 1))
           (fixture (cl-spec:function-spec-fixture contract)))
      (cl-spec:run-property adapter :seed 1)
      (reinitialize-instance
       fixture :version 2
       :setup-forms '((replacement-setup))
       :setup-function (lambda (recipe context)
                         (declare (ignore recipe context))
                         (error "replacement setup")))
      (let* ((result (cl-spec:run-property adapter :seed 1))
             (data (cl-spec:result-data result)))
        (ok (eq :fixture-setup-error (cl-spec:property-result-failure-reason result)))
        (ok (= 2 (getf (getf data :fixture) :version)))
        (ok (search "replacement setup"
                    (princ-to-string (cl-spec:property-result-condition result))))))))
