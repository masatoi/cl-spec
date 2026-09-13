;;;; tests/function-outcome-test.lisp
(defpackage #:cl-spec/tests/function-outcome-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-call-layout #:function-spec-return-schema
                #:make-function-check-property)
  (:import-from #:cl-spec/src/call-schema
                #:call-layout-bindings #:argument-binding-name #:return-schema-value)
  (:import-from #:cl-spec/src/call-outcome
                #:call-outcome-kind #:call-outcome-values #:call-outcome-condition)
  (:import-from #:cl-spec/src/execution #:evaluate-trial)
  (:import-from #:cl-spec/src/schema #:definition-digest))
(in-package #:cl-spec/tests/function-outcome-test)

(defvar *calls* 0)
(defvar *order* nil)
(defvar *mode* :multiple)
(defvar *condition* nil)

(defun outcome-target (&optional value)
  (incf *calls*)
  (push :target *order*)
  (ecase *mode*
    (:multiple (values value :secondary))
    (:zero (values))
    (:error (error *condition*))))

(defun evaluate-case (&rest contract-options)
  (let ((contract (apply #'make-instance 'function-spec :name 'outcome-target contract-options)))
    (multiple-value-list
      (evaluate-trial (make-function-check-property contract) '(3)))))

(deftest adapter-ir-does-not-change-existing-digest-bytes
  (let ((contract (make-instance 'function-spec :name 'identity
                                 :argument-specs '((car integer)) :return-spec 'integer)))
    (ok (equal "fnv1a64-v1:e7e7e6ce92aa950f" (definition-digest contract)))))

(deftest precondition-refusal-has-no-invoked-outcome
  (let ((*calls* 0) (*order* nil) (*mode* :multiple))
    (let ((evidence (evaluate-case :argument-specs '((x integer))
                                   :preconditions '(nil)
                                   :precondition-function (constantly nil))))
      (ok (eq :rejected (first evidence)))
      (ok (null (seventh evidence)))
      (ok (zerop *calls*)))))

(deftest contract-predicate-errors-retain-the-observed-target-outcome
  (let ((*calls* 0) (*order* nil) (*mode* :multiple))
    (let ((evidence (evaluate-case :argument-specs '((x integer))
                                   :return-spec 'integer
                                   :postconditions '(t)
                                   :postcondition-function
                                   (lambda (result x)
                                     (declare (ignore x))
                                     (exploding-return result)))))
      (ok (eq :error (first evidence)))
      (ok (eq :contract-error (second evidence)))
      (ok (typep (fifth evidence) 'simple-error))
      (ok (null (sixth evidence)))
      (ok (seventh evidence))
      (ok (= 1 *calls*)))))

(deftest signaled-outcomes-preserve-condition-identity-and-reserved-errors
  (let ((*calls* 0) (*order* nil) (*mode* :error)
        (*condition* (make-condition 'simple-error :format-control "expected")))
    (let ((evidence (evaluate-case :argument-specs '((x integer)) :signal-spec 'simple-error)))
      (ok (equal '(:passed nil nil nil nil nil) (subseq evidence 0 6)))
      (ok (eq :signaled (call-outcome-kind (seventh evidence))))
      (ok (eq *condition* (call-outcome-condition (seventh evidence))))
      (ok (= 1 *calls*)))
    (setf *condition* (make-condition 'program-error))
    (let ((evidence (evaluate-case :argument-specs '((x integer)) :signal-spec 'error)))
      (ok (eq :error (first evidence)))
      (ok (eq :condition (second evidence)))
      (ok (eq *condition* (fifth evidence)))
      (ok (seventh evidence))
      (ok (= 2 *calls*)))))

(deftest zero-return-values-still-project-to-nil-primary
  (let ((*calls* 0) (*order* nil) (*mode* :zero))
    (let ((evidence (evaluate-case :argument-specs '((x integer)) :return-spec 'null)))
      (ok (equal '(:passed nil nil nil nil nil) (subseq evidence 0 6)))
      (ok (eq :returned (call-outcome-kind (seventh evidence))))
      (ok (null (call-outcome-values (seventh evidence))))
      (ok (= 1 *calls*)))))

(deftest evaluation-keeps-primary-semantics-and-invocation-order
  (let ((*calls* 0) (*order* nil) (*mode* :multiple))
    (let ((evidence
            (evaluate-case
              :argument-specs '((x integer)) :return-spec 'integer
              :preconditions '((integerp x))
              :precondition-function (lambda (x) (push :pre *order*) (integerp x))
              :postconditions '((= result x))
              :postcondition-function (lambda (result x) (push :post *order*) (= result x)))))
      (ok (equal '(:passed nil nil nil nil 3) (subseq evidence 0 6)))
      (ok (eq :returned (call-outcome-kind (seventh evidence))))
      (ok (equal '(3 :secondary) (call-outcome-values (seventh evidence))))
      (ok (= 1 *calls*))
      (ok (equal '(:post :target :pre) *order*)))))

(defun exploding-return (value)
  (declare (ignore value))
  (error "Broken return predicate"))

(deftest adapters-are-derived-from-current-declaration
  (let* ((contract (make-instance 'function-spec :name 'outcome-target
                                 :argument-specs '((x integer)) :return-spec 'integer))
         (old-layout (function-spec-call-layout contract))
         (old-return (function-spec-return-schema contract)))
    (reinitialize-instance contract :argument-specs '((y string)) :return-spec 'string)
    (ok (equal '(x) (mapcar #'argument-binding-name (call-layout-bindings old-layout))))
    (ok (equal '(y) (mapcar #'argument-binding-name
                           (call-layout-bindings (function-spec-call-layout contract)))))
    (ok (not (eq old-return (function-spec-return-schema contract))))
    (ok (equal "new" (return-schema-value (function-spec-return-schema contract)
                                         '("new" :secondary))))))

(deftest outcome-values-are-frozen-before-postcondition-mutation
  (let* ((*calls* 0) (*order* nil) (*mode* :multiple)
         (contract (make-instance
                    'function-spec :name 'outcome-target
                    :argument-specs '((x list)) :return-spec 'list
                    :postconditions '(t)
                    :postcondition-function
                    (lambda (result x)
                      (declare (ignore x))
                      (setf (car result) :changed)
                      t)))
         (evidence (multiple-value-list
                     (evaluate-trial (make-function-check-property contract)
                                     (list (list :original))))))
    (ok (eq :passed (first evidence)))
    (ok (equal '(:changed) (sixth evidence)))
    (ok (equal '((:original) :secondary)
               (call-outcome-values (seventh evidence))))
    (ok (= 1 *calls*))))
