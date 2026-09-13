;;;; tests/multiple-values-evidence-test.lisp

(defpackage #:cl-spec/tests/multiple-values-evidence-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defspec-function #:defgenerator
                #:function-spec #:function-spec-data #:definition-digest #:check-function
                #:property-result-status #:property-result-shrunk-evidence
                #:trial-observation-arguments
                #:result-data #:make-counterexample-artifact #:counterexample-artifact-data
                #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
                #:recheck-counterexample))

(in-package #:cl-spec/tests/multiple-values-evidence-test)

(defvar *calls* 0)
(defvar *draws* 0)

(defun position-changing-values (n)
  (incf *calls*)
  (cond ((<= n 5) (values :bad n))
        (t (values n :bad))))

(deftest shrinking-keeps-return-position-and-direct-recheck-keeps-evidence
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0)
        (*draws* 0))
    (defgenerator values-arguments ()
      (:shrink (arguments)
        (if (> (first arguments) 6) '((1) (6)) nil))
      (incf *draws*)
      '(20))
    (let* ((contract
             (defspec-function position-changing-values
               (:args (n integer))
               (:args-generator values-arguments)
               (:returns (values integer integer))))
           (result (check-function contract :trials 1 :seed 42))
           (data (result-data result))
           (artifact (make-counterexample-artifact result :selection :shrunk))
           (saved (deserialize-counterexample-artifact
                   (serialize-counterexample-artifact artifact)))
           (calls-before *calls*))
      (ok (eq :failed (property-result-status result)))
      (ok (equal '(6) (trial-observation-arguments (property-result-shrunk-evidence result))))
      (ok (= 20 (getf (getf data :failure) :value)))
      (ok (equal '(:kind :returned :values (20 :bad))
                 (getf (getf data :failure) :outcome)))
      (ok (equal '(6) (getf (getf (counterexample-artifact-data saved) :shrunk) :arguments)))
      (ok (eq :same-failure (getf (recheck-counterexample saved :state-policy :stateless) :status)))
      (ok (= (1+ calls-before) *calls*))
      (ok (= 1 *draws*)))))

(deftest fixed-values-introspection-and-digest-record-mode-and-bindings
  (let ((*registry* (make-hash-table-registry)))
    (let* ((contract
             (defspec-function position-changing-values
               (:args (n integer))
               (:returns (values integer integer))
               (:post-values (low high) (< low high))))
           (data (function-spec-data contract))
           (returns (getf data :returns))
           (primary (make-instance 'function-spec :name 'position-changing-values
                                   :argument-specs '((n integer)) :return-spec 'integer))
           (tuple (make-instance 'function-spec :name 'position-changing-values
                                 :argument-specs '((n integer))
                                 :return-spec '(tuple integer integer)))
           (fixed (make-instance 'function-spec :name 'position-changing-values
                                 :argument-specs '((n integer))
                                 :return-spec '(values integer integer))))
      (ok (eq :values (getf returns :kind)))
      (ok (= 2 (length (getf returns :children))))
      (ok (equal '(low high) (getf data :post-value-variables)))
      (ok (getf data :definition-digest-complete))
      (ok (stringp (definition-digest fixed)))
      (ok (not (equal (definition-digest fixed) (definition-digest primary))))
      (ok (not (equal (definition-digest fixed) (definition-digest tuple)))))))

(deftest ordinary-return-normalization-preserves-condition-protocol
  (ok (handler-case
          (progn (make-instance 'function-spec :name 'position-changing-values
                                :return-spec '(range)) nil)
        (cl-spec:invalid-spec-form () t)))
  (ok (handler-case
          (progn (make-instance 'function-spec :name 'position-changing-values
                                :return-spec '(values (range))) nil)
        (cl-spec:invalid-function-spec-form () t))))
