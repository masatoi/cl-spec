;;;; tests/observed-outcome-test.lisp

(defpackage #:cl-spec/tests/observed-outcome-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:make-function-check-property)
  (:import-from #:cl-spec/src/execution #:observe-trial)
  (:import-from #:cl-spec/src/property-runner #:property-result #:result-data))

(in-package #:cl-spec/tests/observed-outcome-test)

(defvar *returned* nil)
(defvar *calls* 0)
(defun returned-values-target ()
  (incf *calls*)
  (values *returned* :extra))
(defun zero-target () (values))
(defun nil-target () nil)

(defun failing-observation-data (name)
  (let* ((contract (make-instance 'function-spec :name name :return-spec '(member t)))
         (property (make-function-check-property contract))
         (observation (observe-trial property nil)))
    (result-data (make-instance 'property-result :trials 1 :failure-evidence observation))))

(deftest full-return-outcome-is-captured-once-and-frozen
  (let* ((*returned* (list 3)) (*calls* 0)
         (data (failing-observation-data 'returned-values-target))
         (failure (getf data :failure)))
    (setf (car *returned*) 9)
    (ok (= 1 *calls*))
    (ok (equal '(3) (getf failure :value)))
    (ok (equal '(:kind :returned :values ((3) :extra)) (getf failure :outcome)))))

(deftest zero-values-and-one-nil-remain-distinct
  (let ((zero (getf (getf (failing-observation-data 'zero-target) :failure) :outcome))
        (one (getf (getf (failing-observation-data 'nil-target) :failure) :outcome)))
    (ok (eq :returned (getf zero :kind)))
    (ok (equal nil (getf zero :values :missing)))
    (ok (equal '(nil) (getf one :values :missing)))))

(defun signaled-target () (error "original target error"))

(deftest error-outcome-is-separate-from-contract-failure
  (let* ((data (failing-observation-data 'signaled-target))
         (failure (getf data :failure))
         (outcome (getf failure :outcome)))
    (ok (eq :condition (getf failure :reason)))
    (ok (eq :signaled (getf outcome :kind)))
    (ok (eq 'simple-error (getf outcome :condition-type)))
    (ok (search "original target error" (getf outcome :condition-report)))))
