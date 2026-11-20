;;;; tests/function-examples-test.lisp

(defpackage #:cl-spec/tests/function-examples-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defspec-function #:defgenerator
                #:check-function #:check-function-with-examples #:find-function-spec
                #:call-check-result-status #:call-check-result-observation
                #:call-check-result-failure-phase #:call-check-data #:result-data
                #:invalid-argument #:invalid-argument-operator #:unsupported-stateful-operation
                #:invalid-call-arguments #:invalid-call-arguments-reason
                #:trial-observation-reason
                #:trial-observation-outcome #:property-result-status #:property-result-seed
                #:property-result-trials #:function-check-result-case-report)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/function-examples-test)

(defvar *calls* nil)

(define-condition insufficient-funds (error) ())

(defun withdraw (balance amount)
  (push (list balance amount) *calls*)
  (random 10)
  (if (<= amount balance)
      (- balance amount)
      (error 'insufficient-funds)))

(defun register-withdraw ()
  (defspec-function withdraw
    (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
    (:cases
      (:sufficient-funds
        (:when (<= amount balance)) (:returns integer) (:post (= result (- balance amount))))
      (:insufficient-funds
        (:when (> amount balance)) (:signals (type insufficient-funds))))))

(deftest boundary-examples-precede-the-ordinary-seeded-run
  (let ((*registry* (make-hash-table-registry))
        (rows '((:sufficient-funds (100 100)) (:insufficient-funds (100 101)))))
    (register-withdraw)
    (dolist (seed '(17 82))
      (let* ((*calls* nil)
             (control (check-function 'withdraw :trials 8 :seed seed))
             (generated-calls (nreverse *calls*)))
        (setf *calls* nil)
        (let* ((report (check-function-with-examples 'withdraw rows :trials 8 :seed seed))
               (examples (getf report :examples))
               (generated (getf report :generated)))
          (ok (eq :passed (getf report :status)))
          (ok (= 2 (getf report :example-count) (length examples)))
          (ok (= 8 (getf report :generated-trials) (property-result-trials generated)))
          (ok (= seed (property-result-seed generated)))
          (ok (equal (append '((100 100) (100 101)) generated-calls) (nreverse *calls*)))
          (ok (equal (function-check-result-case-report control)
                     (function-check-result-case-report generated)))
          (ok (equal '(:sufficient-funds :insufficient-funds)
                     (mapcar (lambda (row) (getf row :actual-case)) examples)))
          (ok (equal '(:passed :passed) (mapcar (lambda (row) (getf row :status)) examples)))
          (ok (equal '(:returned :signaled)
                     (loop for row in examples
                           for observation = (call-check-result-observation (getf row :call))
                           collect (getf (trial-observation-outcome observation) :kind)))))))))

(deftest mismatch-retains-a-passing-call-and-does-not-stop-either-phase
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil))
    (register-withdraw)
    (let* ((report (check-function-with-examples
                    (find-function-spec 'withdraw)
                    '((:insufficient-funds (100 100)) (:insufficient-funds (100 101)))
                    :trials 2 :seed 19))
           (rows (getf report :examples))
           (mismatch (first rows)))
      (ok (eq :failed (getf report :status)))
      (ok (eq :failed (getf mismatch :status)))
      (ok (eq :case-mismatch (getf mismatch :reason)))
      (ok (eq :insufficient-funds (getf mismatch :expected-case)))
      (ok (eq :sufficient-funds (getf mismatch :actual-case)))
      (ok (eq :passed (call-check-result-status (getf mismatch :call))))
      (ok (eq :passed (getf (second rows) :status)))
      (ok (eq :passed (property-result-status (getf report :generated))))
      (ok (= 4 (length *calls*))))))

(defun remove-target-cases (step)
  (when (zerop step)
    (reinitialize-instance (find-function-spec 'remove-target-cases)
                           :cases nil :return-spec 'integer))
  step)

(deftest a-passing-call-must-still-select-its-expected-case
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function remove-target-cases
      (:args (step (range integer 0 9)))
      (:cases (:declared (:when t) (:returns integer))))
    (let* ((report (check-function-with-examples 'remove-target-cases
                                                 '((:declared (0)) (:declared (1)))
                                                 :trials 1 :seed 9))
           (row (second (getf report :examples))))
      (ok (eq :passed (call-check-result-status (getf row :call))))
      (ok (null (getf row :actual-case)))
      (ok (eq :failed (getf row :status)))
      (ok (eq :case-mismatch (getf row :reason)))
      (ok (eq :failed (getf report :status))))))

(deftest fixed-calls-do-not-consume-the-generated-runs-implicit-seed
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil)
        (initial-state (make-random-state t)))
    (register-withdraw)
    (let ((plain (let ((*random-state* (make-random-state initial-state)))
                   (check-function 'withdraw :trials 3)))
          (combined (let ((*random-state* (make-random-state initial-state)))
                      (check-function-with-examples
                       'withdraw '((:sufficient-funds (5 5))) :trials 3))))
      (ok (= (property-result-seed plain) (property-result-seed (getf combined :generated)))))))

(defvar *generated-mode* :ok)

(defun mode-target (mode)
  (push mode *calls*)
  mode)

(defun register-modes ()
  (defgenerator draw-mode () (list *generated-mode*))
  (defspec-function mode-target
    (:args (mode keyword))
    (:args-generator draw-mode)
    (:pre (or (not (eq mode :broken-pre)) (error 'program-error))
          (not (eq mode :rejected)))
    (:cases
      (:admitted
        (:when (or (not (eq mode :bad-guard)) (error "broken guard")))
        (:returns (member :ok))))))

(deftest all-fixed-rows-retain-their-admission-and-outcome-evidence
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil))
    (register-modes)
    (let* ((report (check-function-with-examples
                    'mode-target
                    '((:admitted (:rejected)) (:admitted (:wrong)) (:admitted (:bad-guard))
                      (:admitted (8)) (:admitted (:broken-pre)) (:admitted (:ok)))
                    :trials 2 :seed 17))
           (rows (getf report :examples)))
      (ok (eq :error (getf report :status)))
      (ok (equal '(:rejected :failed :error :error :error :passed)
                 (mapcar (lambda (row) (getf row :status)) rows)))
      (ok (eq :return-spec (trial-observation-reason
                            (call-check-result-observation (getf (second rows) :call)))))
      (ok (eq :case-selection (call-check-result-failure-phase (getf (third rows) :call))))
      (let ((condition (getf (fourth rows) :condition)))
        (ok (typep condition 'invalid-call-arguments))
        (ok (eq :argument-spec (invalid-call-arguments-reason condition))))
      (ok (typep (getf (fifth rows) :condition) 'program-error))
      (ok (null (getf (fifth rows) :call)))
      (ok (= 6 (getf report :example-count)))
      (ok (= 2 (getf report :generated-trials)))
      (ok (equal '(:wrong :ok :ok :ok) (reverse *calls*))))))

(deftest either-phase-can-make-the-combined-check-fail
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil))
    (register-modes)
    (let ((rejected (check-function-with-examples 'mode-target '((:admitted (:rejected)))
                                                  :trials 1 :seed 10))
          (failed (let ((*generated-mode* :wrong))
                    (check-function-with-examples 'mode-target '((:admitted (:ok))) :trials 4
                                                  :seed 10 :options '(:shrink-budget 0))))
          (skipped (check-function-with-examples 'mode-target '((:admitted (:ok)))
                                                 :trials 0 :seed 10)))
      (ok (eq :failed (getf rejected :status)))
      (ok (eq :failed (getf failed :status)))
      (ok (eq :passed (getf (first (getf failed :examples)) :status)))
      (ok (= 1 (getf failed :generated-trials)))
      (ok (eq :skipped (getf skipped :status)))
      (ok (= 0 (getf skipped :generated-trials))))))

(deftest malformed-tables-are-refused-before-any-target-call
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil)
        (circular (list nil)))
    (setf (cdr circular) circular)
    (register-modes)
    (dolist (table (list :atom circular (cons '(:admitted (:ok)) :dotted)
                         '((:admitted (:ok)) (:missing (:ok)))
                         '((:admitted (:ok)) (:admitted))
                         '((:admitted (:ok)) (:admitted (:ok) :extra))
                         '((:admitted (:ok)) (:admitted :not-an-argument-list))))
      (let ((refusal (handler-case
                         (progn (check-function-with-examples 'mode-target table :trials 1) nil)
                       (error (condition) condition))))
        (ok (typep refusal 'invalid-argument))
        (when (typep refusal 'invalid-argument)
          (ok (eq 'check-function-with-examples (invalid-argument-operator refusal))))))
    (ok (null *calls*))))

(defvar *rows-to-truncate* nil)

(defun truncate-input-list (step)
  (push step *calls*)
  (when (zerop step) (setf (cdr *rows-to-truncate*) nil))
  :ok)

(deftest target-mutation-cannot-remove-a-later-fixed-row
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil)
        (*rows-to-truncate* (list (list :called (list 0)) (list :called (list 1)))))
    (defspec-function truncate-input-list
      (:args (step integer))
      (:cases (:called (:when t) (:returns keyword))))
    (let ((report (check-function-with-examples 'truncate-input-list *rows-to-truncate*
                                                :trials 0 :seed 4)))
      (ok (= 1 (length *rows-to-truncate*)))
      (ok (= 2 (getf report :example-count)))
      (ok (equal '(:passed :passed)
                 (loop for row in (getf report :examples) collect (getf row :status))))
      (ok (equal '(1 0) *calls*)))))

(deftest runner-arguments-are-validated-before-examples
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil))
    (register-modes)
    (dolist (arguments '((:trials -1) (:seed :wrong) (:options (:shrink-budget -1)) (:trial 3)))
      (ok (handler-case
              (progn (apply #'check-function-with-examples
                            'mode-target '((:admitted (:ok))) arguments)
                     nil)
            (invalid-argument (condition)
              (eq 'check-function-with-examples (invalid-argument-operator condition))))))
    (ok (null *calls*))))

(defvar *setups* 0)

(defvar *cleanups* 0)

(defun increment-cell (cell)
  (push (car cell) *calls*)
  (incf (car cell)))

(deftest raw-examples-use-caller-state-and-only-generated-trials-run-fixture-hooks
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil)
        (*setups* 0)
        (*cleanups* 0)
        (cell (list 100)))
    (defspec-function increment-cell
      (:args (cell (list-of integer)))
      (:fixture
        (:isolation :fresh)
        (:version 1)
        (:recipe (start (range integer 1 5)))
        (:setup (context) (declare (ignore context)) (incf *setups*) (list (list start)))
        (:cleanup (context) (declare (ignore context start)) (incf *cleanups*)))
      (:capture (before (car cell)))
      (:cases (:increment (:when t) (:returns integer) (:state-post (= (car cell) (1+ before))))))
    (let* ((report (check-function-with-examples 'increment-cell
                                                 (list (list :increment (list cell)))
                                                 :trials 2 :seed 4 :registry nil))
           (call (getf (first (getf report :examples)) :call)))
      (ok (eq :passed (getf report :status)))
      (ok (= 101 (car cell)))
      (ok (= 3 (length *calls*)))
      (ok (= 2 *setups* *cleanups*))
      (ok (eq :direct-call (getf (call-check-data call) :execution-mode)))
      (ok (null (getf (call-check-data call) :input-kind)))
      (ok (eq :fixture-recipe (getf (result-data (getf report :generated)) :input-kind)))
      ;; Direct examples precede replay validation of the generated phase.
      (ok (handler-case
              (progn
                (check-function-with-examples 'increment-cell (list (list :increment (list cell)))
                                              :trials 3 :seed (getf report :generated))
                nil)
            (unsupported-stateful-operation () t)))
      (ok (= 102 (car cell)))
      (ok (= 2 *setups* *cleanups*)))))

(deftest replay-preserves-the-generated-runs-budget-and-omitted-options
  (let ((*registry* (make-hash-table-registry))
        (*calls* nil))
    (register-withdraw)
    (let ((original (check-function 'withdraw :trials 5 :seed 75 :options '(:shrink-budget 2)))
          (prior-calls (nreverse *calls*)))
      (setf *calls* nil)
      (let* ((report (check-function-with-examples 'withdraw nil :seed original))
             (data (result-data (getf report :generated))))
        (ok (= 0 (getf report :example-count)))
        (ok (= 5 (getf report :generated-trials)))
        (ok (= 75 (getf data :seed)))
        (ok (= 2 (getf (getf data :options) :shrink-budget)))
        (ok (equal prior-calls (nreverse *calls*)))))))
