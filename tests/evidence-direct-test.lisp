;;;; tests/evidence-direct-test.lisp
(defpackage #:cl-spec/tests/evidence-direct-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/tests/fixture-function-test
                #:with-contract #:fixture-check #:*mode* #:*calls* #:*setups* #:*cleanups*))
(in-package #:cl-spec/tests/evidence-direct-test)

(defvar *target-calls* 0)

(defun counted (x)
  (incf *target-calls*)
  x)

(deftest direct-evidence-does-not-reexecute-and-keeps-declared-cases
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*target-calls* 0))
    (cl-spec:defspec-function counted
      (:args (x integer))
      (:cases (:normal (:when (>= x 0)) (:returns integer))
              (:negative (:when (< x 0)) (:returns integer))))
    (let* ((result (cl-spec:check-call 'counted '(3)))
           (policy '(:policy-version 1 :requirements
                     ((:kind :all-declared-cases :min-checked 1))))
           (assessment (cl-spec:assess-evidence result policy)))
      (ok (eq :insufficient (getf assessment :assessment)))
      (ok (eq :negative (getf (first (getf assessment :gaps)) :case)))
      (ok (eq :single-call (getf (cl-spec:evidence-summary result) :scope)))
      (ok (eq :single-call
              (getf (find :declared-cases (getf (cl-spec:evidence-summary result) :dimensions)
                          :key (lambda (entry) (getf entry :kind))) :unit)))
      (ok (getf (cl-spec:call-check-data result) :evidence))
      (cl-spec:defspec-function counted (:args (x integer)) (:returns integer))
      (ok (equal assessment (cl-spec:assess-evidence result policy)))
      (setf (getf (getf assessment :subject) :name) 'changed)
      (ok (eq 'counted (getf (getf (cl-spec:evidence-summary result) :subject) :name)))
      (ok (= 1 *target-calls*)))))

(deftest direct-pre-refusal-and-contract-errors-are-not-checked
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (x integer)) (:pre (plusp x)) (:returns integer)
      (:state-post (error "contract probe")))
    (dolist (input '((-1) (1)))
      (let* ((result (cl-spec:check-call 'identity input))
             (assessment (cl-spec:assess-evidence result
                           '(:policy-version 1 :requirements
                             ((:kind :min-checked-trials :count 1))))))
        (ok (eq :insufficient (getf assessment :assessment)))
        (ok (eql 0 (getf (first (getf assessment :gaps)) :observed)))))))

(deftest direct-expected-signals-count-as-checked
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function error (:args (message string)) (:signals simple-error))
    (let ((assessment (cl-spec:assess-evidence (cl-spec:check-call 'error '("expected"))
                        '(:policy-version 1 :requirements
                          ((:kind :min-checked-trials :count 1))))))
      (ok (eq :passed (getf assessment :execution-status)))
      (ok (eq :satisfied (getf assessment :assessment))))))

(deftest direct-budget-is-not-applicable
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity (:args (x integer)) (:returns integer))
    (ok (eq :not-assessed
            (getf (cl-spec:assess-evidence (cl-spec:check-call 'identity '(1))
                     '(:policy-version 1 :requirements
                       ((:kind :requested-trials-completed))))
                  :assessment)))))

(deftest fixture-summary-uses-final-classification
  (with-contract
    (dolist (mode '(:missing-update :cleanup-error))
      (let ((*mode* mode))
        (let* ((result (fixture-check '(30 10)))
               (assessment (cl-spec:assess-evidence result
                             '(:policy-version 1 :requirements
                               ((:kind :min-checked-trials :count 1))))))
          (ok (eq (if (eq mode :missing-update) :satisfied :insufficient)
                  (getf assessment :assessment)))
          (ok (getf (cl-spec:fixture-check-data result) :evidence)))))
    (ok (= 2 *calls* *setups* *cleanups*))))
