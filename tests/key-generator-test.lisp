;;;; tests/key-generator-test.lisp

(defpackage #:cl-spec/tests/key-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/key-generator-test)

(defvar *seen* nil)
(defvar *defaults* 0)
(defun keyed-target (&optional (prefix 10)
                     &key (limit (progn (incf *defaults*) 42) supplied))
  (push (list prefix supplied limit) *seen*)
  limit)

(deftest generated-keys-preserve-prefix-and-defaults
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*seen* nil) (*defaults* 0))
    (cl-spec:defspec-function keyed-target
      (:args &optional (prefix (member 10))
             &key ((:limit limit) (member nil 7) supplied))
      (:returns (nullable integer))
      (:post (if supplied (eql result limit) (= result 42))))
    (let ((result (cl-spec:check-function 'keyed-target :trials 200 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result)))
      (ok (= 200 (length *seen*)))
      (ok (member '(10 nil 42) *seen* :test #'equal))
      (ok (member '(10 t nil) *seen* :test #'equal))
      (ok (member '(10 t 7) *seen* :test #'equal))
      (ok (= *defaults* (count nil *seen* :key #'second))))))

(defun key-failure (&key value)
  (declare (ignore value))
  nil)

(deftest builtin-shrinking-removes-keyword-pairs
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function key-failure
      (:args &key ((:value value) (range integer 20 40) supplied))
      (:returns (member t)))
    (let ((result
            (loop for seed from 1 to 30
                  for result = (cl-spec:check-function 'key-failure :trials 1 :seed seed)
                  when (cl-spec:trial-observation-arguments
                        (cl-spec:property-result-failure-evidence result))
                    return result)))
      (ok result)
      (when result
        (ok (cl-spec:property-result-shrunk-evidence result))
        (ok (null (cl-spec:trial-observation-arguments
                   (cl-spec:property-result-shrunk-evidence result))))
        (ok (eq :same-failure
                (getf (cl-spec:recheck-counterexample
                       (cl-spec:make-counterexample-artifact result) :state-policy :stateless)
                      :status)))))))

(deftest empty-key-layout-has-no-shrink-strategy
  (let ((contract (make-instance 'cl-spec:function-spec :name 'key-failure
                                 :argument-specs '(&key) :return-spec t)))
    (ok (eq :none
            (getf (getf (cl-spec:definition-metadata contract) :capabilities) :shrinking)))))

(deftest suppressed-call-children-do-not-advertise-shrinking
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defgenerator empty-tail () nil)
    (cl-spec:defspec tail-list (list-of t) (:generator empty-tail))
    (dolist (arguments '((&rest (tail tail-list) &key ((:value value) integer))
                        (&rest (tail (list-of t)) &key)))
      (let ((contract (make-instance 'cl-spec:function-spec :name 'key-failure
                                     :argument-specs arguments :return-spec t)))
        (ok (eq :none
                (getf (getf (cl-spec:definition-metadata contract) :capabilities)
                      :shrinking)))))))

(deftest invalid-custom-keyword-values-never-reach-target
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*seen* nil) (*defaults* 0) (draws 0))
    (cl-spec:defgenerator invalid-limit () (incf draws) :invalid)
    (cl-spec:defspec limit-spec integer (:generator invalid-limit))
    (cl-spec:defspec-function keyed-target
      (:args &optional (prefix (member 10))
             &key ((:limit limit) limit-spec supplied))
      (:returns integer))
    (ok (handler-case
            (progn (cl-spec:check-function 'keyed-target :trials 200 :seed 42) nil)
          (cl-spec:invalid-generated-arguments () t)))
    (ok (= 1 draws))
    (ok (every (lambda (call) (equal call '(10 nil 42))) *seen*))
    (ok (= *defaults* (length *seen*)))))
