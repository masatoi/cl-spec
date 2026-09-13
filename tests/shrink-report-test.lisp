;;;; tests/shrink-report-test.lisp

(defpackage #:cl-spec/tests/shrink-report-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/property #:property)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/property-runner #:run-property #:result-data)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:check-function)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend* #:run-generated-test #:backend-default-trials)
  (:import-from #:cl-spec/src/execution #:observe-trial)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:import-from #:cl-spec/src/counterexample
                #:make-counterexample-artifact #:counterexample-artifact-data))

(in-package #:cl-spec/tests/shrink-report-test)

(defclass report-backend () ())
(defvar *report* nil)
(defmethod backend-default-trials ((backend report-backend)) 1)
(defmethod run-generated-test ((backend report-backend) property &key options)
  (declare (ignore options))
  (let ((original (observe-trial property '(4))))
    (list :status :failed :trials 1 :failure original :shrunk-outcome :none
          :shrink-report *report*)))

(defun failing-target (value)
  (declare (ignore value))
  nil)

(deftest accepted-custom-shrink-rechecks-without-drawing
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (draws 0))
    (cl-spec:defgenerator recorded-arguments ()
      (:shrink (arguments)
        (unless (equal arguments '(0)) (list '(0))))
      (incf draws)
      (list 40))
    (cl-spec:register-function-spec
     (make-instance 'function-spec :name 'failing-target
                    :argument-specs '((value integer))
                    :argument-generator 'recorded-arguments :return-spec '(member t)))
    (let* ((result (check-function 'failing-target :trials 10 :seed 42))
           (artifact (make-counterexample-artifact result))
           (data (counterexample-artifact-data artifact)))
      (ok (equal '(0) (getf (getf data :shrunk) :arguments)))
      (ok (= 1 draws))
      (ok (eq :same-failure
              (getf (cl-spec:recheck-counterexample artifact :state-policy :stateless) :status)))
      (ok (= 1 draws)))))

(deftest reports-survive-results-and-artifacts
  (let* ((*generator-backend* (make-instance 'report-backend))
         (*report* (list :candidates 7 :budget 10 :termination :exhausted))
         (result (check-function
                  (make-instance 'function-spec :name 'failing-target
                                 :argument-specs '((value integer)) :return-spec '(member t))
                  :trials 1 :seed 42))
         (data (result-data result))
         (artifact (make-counterexample-artifact result)))
    (ok (= 1 (getf data :trials)))
    (ok (equal *report* (getf data :shrink-report)))
    (ok (equal *report* (getf (counterexample-artifact-data artifact) :shrink-report)))
    (setf (getf *report* :candidates) 9)
    (ok (= 7 (getf (getf (result-data result) :shrink-report) :candidates)))))

(deftest malformed-backend-shrink-reports-are-rejected
  (let ((*generator-backend* (make-instance 'report-backend))
        (property (make-instance 'property :name 'false :arguments '((x integer))
                                 :function (constantly nil))))
    (dolist (*report* '((:candidates -1 :budget 10 :termination :exhausted)
                       (:candidates 11 :budget 10 :termination :exhausted)
                       (:candidates 0 :budget 100001 :termination :exhausted)
                       (:candidates 1 :budget 10 :termination "wrong")
                       (:candidates 1 :budget 10)
                       (:candidates 1 :budget 10 :termination :exhausted :candidates 2)))
      (ok (signals (run-property property :seed 42) 'invalid-backend-result)))))
