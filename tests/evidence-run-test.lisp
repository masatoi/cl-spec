;;;; tests/evidence-run-test.lisp
(defpackage #:cl-spec/tests/evidence-run-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/evidence #:evidence-summary #:assess-evidence)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/tests/fixture-function-test
                #:with-contract #:withdraw #:*mode* #:*setups*)
  (:import-from #:cl-spec/src/generator #:*generator-backend* #:run-generated-test))
(in-package #:cl-spec/tests/evidence-run-test)

(defun checked-dimension (result)
  (find :checked-trials (getf (evidence-summary result) :dimensions)
        :key (lambda (entry) (getf entry :kind))))

(deftest generated-normal-trials-have-measured-counts
  (with-contract
    (let ((result (cl-spec:check-function 'withdraw :trials 10 :seed 41)))
      (let ((dimension (checked-dimension result)))
        (ok (eq :collected (getf dimension :availability)))
        (ok (= (- 10 (cl-spec:property-result-rejected result)) (getf dimension :value)))
        (ok (eq :not-assessed (getf (getf (cl-spec:result-data result) :evidence) :assessment)))))))

(deftest unknown-target-revisions-remain-explicit-limitations
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty revision-probe ((x integer)) (:trials (:normal 1)) t)
    (dolist (options '(nil (:target-revision nil) (:target-revision :unknown)
                      (:target-revision "commit-123")))
      (let* ((result (cl-spec:run-property 'revision-probe :seed 1 :options options))
             (summary (evidence-summary result))
             (assessment (assess-evidence result
                           '(:policy-version 1 :requirements
                             ((:kind :min-checked-trials :count 1)))))
             (unknown (not (equal "commit-123" (getf options :target-revision)))))
        (dolist (data (list summary assessment))
          (ok (eql unknown
                   (not (null (member :target-revision-unknown (getf data :limitations)))))))
        (ok (eq :satisfied (getf assessment :assessment)))))))

(deftest zero-and-all-rejected-are-measured-zero
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity (:args (x integer)) (:pre nil) (:returns integer))
    (dolist (count '(0 5))
      (let ((result (cl-spec:check-function 'identity :trials count :seed 1)))
        (ok (eq :skipped (cl-spec:property-result-status result)))
        (ok (eql 0 (getf (checked-dimension result) :value)))
        (ok (eq :insufficient
                (getf (assess-evidence result
                         '(:policy-version 1 :requirements
                           ((:kind :min-checked-trials :count 1))))
                      :assessment)))))))

(deftest shrinking-does-not-inflate-normal-trial-counts
  (with-contract
    (let ((*mode* :missing-update))
      (let* ((result (cl-spec:check-function 'withdraw :trials 30 :seed 41))
             (dimension (checked-dimension result)))
        (ok (> *setups* (cl-spec:property-result-trials result)))
        (ok (eql 1 (getf dimension :value)))
        (ok (eql 1 (getf (getf dimension :counts) :failed)))))))

(deftest shrink-cleanup-abort-retains-only-normal-verdicts
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (setups 0))
    (cl-spec:defgenerator abort-recipes ()
      (:shrink (value) (declare (ignore value)) '(5 1))
      10)
    (cl-spec:defspec abort-recipe integer (:generator abort-recipes))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe abort-recipe))
        (:setup (context) (declare (ignore context)) (incf setups) (list recipe))
        (:cleanup (context) (declare (ignore context))
                  (when (= recipe 5) (error "cleanup failed"))))
      (:cases (:only (:when t) (:returns integer) (:state-post nil))))
    (let* ((result (cl-spec:check-function 'identity :trials 1 :seed 3))
           (assessment (assess-evidence result
                         '(:policy-version 1 :requirements
                           ((:kind :min-checked-trials :count 1)
                            (:kind :all-declared-cases :min-checked 1))))))
      (ok (= 2 setups))
      (ok (eq :error (getf assessment :execution-status)))
      (ok (eq :satisfied (getf assessment :assessment)))
      (ok (equal '(:passed 0 :failed 1 :rejected 0 :error 0)
                 (getf (checked-dimension result) :counts))))))

(deftest fixture-cleanup-errors-are-not-checked-trials
  (with-contract
    (let ((*mode* :cleanup-error))
      (let ((dimension (checked-dimension (cl-spec:check-function 'withdraw :trials 3 :seed 41))))
        (ok (eql 0 (getf dimension :value)))
        (ok (eql 1 (getf (getf dimension :counts) :error)))))))

(deftest declared-cases-survive-registry-redefinition
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (x integer))
      (:cases (:normal (:when t) (:returns integer))
              (:overflow (:when nil) (:returns integer))))
    (let* ((result (cl-spec:check-function 'identity :trials 3 :seed 1))
           (policy '(:policy-version 1 :requirements
                     ((:kind :all-declared-cases :min-checked 1))))
           (first (assess-evidence result policy)))
      (ok (eq :insufficient (getf first :assessment)))
      (ok (eq :overflow (getf (first (getf first :gaps)) :case)))
      (cl-spec:defspec-function identity (:args (x integer)) (:returns integer))
      (ok (equal first (assess-evidence result policy))))))

(deftest a-called-case-with-a-contract-error-is-not-checked
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (x integer))
      (:cases (:only (:when t) (:returns integer) (:post (error "bad contract")))))
    (let* ((result (cl-spec:check-function 'identity :trials 1 :seed 3))
           (assessment (assess-evidence result
                         '(:policy-version 1 :requirements
                           ((:kind :all-declared-cases :min-checked 1))))))
      (ok (eq :insufficient (getf assessment :assessment)))
      (ok (eql 0 (getf (first (getf assessment :gaps)) :observed)))
      (ok (eql 0 (getf (checked-dimension result) :value))))))

(defclass legacy-backend () ())

(defmethod run-generated-test ((backend legacy-backend) property &key options)
  (declare (ignore backend property))
  (list :status :passed :trials (getf options :trials) :rejected 0))

(deftest legacy-backend-does-not-invent-checked-counts
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*generator-backend* (make-instance 'legacy-backend)))
    (cl-spec:defproperty legacy ((x integer)) (:trials (:normal 3)) t)
    (let ((data (assess-evidence (cl-spec:run-property 'legacy :seed 1)
                  '(:policy-version 1 :requirements
                    ((:kind :min-checked-trials :count 1))))))
      (ok (eq :unknown (getf data :assessment)))
      (ok (eq :passed (getf data :execution-status))))))

(deftest old-manual-results-do-not-claim-case-absence
  (let ((result (make-instance 'cl-spec:property-result :trials 0 :status :passed)))
    (ok (eq :unknown
            (getf (assess-evidence result
                     '(:policy-version 1 :requirements
                       ((:kind :all-declared-cases :min-checked 1))))
                  :assessment)))))
