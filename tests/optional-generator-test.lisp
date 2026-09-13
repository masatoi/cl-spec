;;;; tests/optional-generator-test.lisp

(defpackage #:cl-spec/tests/optional-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/optional-generator-test)

(defvar *defaults* 0)
(defvar *seen* nil)
(defun optional-target (&optional (value (progn (incf *defaults*) 42) supplied))
  (push (list supplied value) *seen*)
  value)

(deftest generated-optionals-preserve-omission-and-explicit-nil
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*defaults* 0) (*seen* nil))
    (cl-spec:defspec-function optional-target
      (:args &optional (value (member nil 7) supplied))
      (:returns (nullable integer))
      (:post (if supplied (eql result value) (= result 42))))
    (let ((result (cl-spec:check-function 'optional-target :trials 200 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 200 (length *seen*)))
      (ok (member '(nil 42) *seen* :test #'equal))
      (ok (member '(t nil) *seen* :test #'equal))
      (ok (member '(t 7) *seen* :test #'equal))
      (ok (= *defaults* (count nil *seen* :key #'first))))))

(defun optional-failure (&optional (value 99))
  (declare (ignore value))
  nil)

(deftest builtin-shrinking-can-remove-an-optional-suffix
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function optional-failure
      (:args &optional (value (range integer 20 40) supplied))
      (:returns (member t)))
    (let ((result
            (loop for seed from 1 to 30
                  for result = (cl-spec:check-function 'optional-failure :trials 1 :seed seed)
                  when (cl-spec:trial-observation-arguments
                        (cl-spec:property-result-failure-evidence result))
                    return result)))
      (ok result)
      (when result
        (ok (cl-spec:property-result-shrunk-evidence result))
        (ok (null (cl-spec:trial-observation-arguments
                   (cl-spec:property-result-shrunk-evidence result))))
        (ok (equal '(value nil supplied nil)
                   (cl-spec:property-result-shrunk-counterexample result)))
        (let ((artifact (cl-spec:make-counterexample-artifact result)))
          (ok (eq :same-failure
                  (getf (cl-spec:recheck-counterexample artifact :state-policy :stateless)
                        :status))))))))
