;;;; tests/optional-function-test.lisp

(defpackage #:cl-spec/tests/optional-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/dsl #:defspec-function #:defproperty)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-spec-argument-specs #:make-function-check-property)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry #:registry-find-function-spec)
  (:import-from #:cl-spec/src/property #:property-named-arguments #:property-call-arguments-p)
  (:import-from #:cl-spec/src/schema #:definition-digest)
  (:import-from #:cl-spec/src/execution #:evaluate-trial)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form #:invalid-property-form))

(in-package #:cl-spec/tests/optional-function-test)

(defvar *defaults* 0)
(defvar *calls* 0)

(defun optional-target (a &optional (b (progn (incf *defaults*) 10)))
  (incf *calls*)
  (+ a (or b 0)))

(deftest direct-optional-contract-preserves-target-defaults
  (let* ((*defaults* 0) (*calls* 0)
         (contract (make-instance 'function-spec :name 'optional-target
                                 :argument-specs '((a integer) &optional (b (or null integer) b-p))
                                 :return-spec 'integer
                                 :preconditions '(t)
                                 :precondition-function
                                 (lambda (a b b-p)
                                   (and (= a 2) (null b) (typep b-p 'boolean)))))
         (property (make-function-check-property contract)))
    (ok (zerop *defaults*))
    (ok (eq :passed (evaluate-trial property '(2))))
    (ok (= 1 *defaults*))
    (ok (eq :passed (evaluate-trial property '(2 nil))))
    (ok (= 1 *defaults*))
    (ok (= 2 *calls*))))

(deftest optional-dsl-expands-and-properties-stay-required
  (ok (macroexpand-1
       '(defspec-function optional-target
          (:args (a integer) &optional (b integer b-p))
          (:pre (or (not b-p) (integerp b)))
          (:returns integer))))
  (ok (signals (macroexpand-1 '(defproperty invalid (&optional (b integer)) t))
               'invalid-property-form)))

(deftest optional-dsl-predicates-distinguish-omission-and-explicit-nil
  (let ((*registry* (make-hash-table-registry)) (*defaults* 0) (*calls* 0))
    (defspec-function optional-target
      (:args (a integer) &optional (b (or null integer) b-p))
      (:pre (and (= a 2) (null b)))
      (:returns integer)
      (:post (= result (if b-p 2 12))))
    (let* ((contract (registry-find-function-spec *registry* 'optional-target))
           (property (make-function-check-property contract)))
      (ok (eq :passed (evaluate-trial property '(2))))
      (ok (eq :passed (evaluate-trial property '(2 nil))))
      (ok (equal '(a 2 b nil b-p nil) (property-named-arguments property '(2))))
      (ok (equal '(a 2 b nil b-p t) (property-named-arguments property '(2 nil))))
      (ok (property-call-arguments-p property '(2)))
      (ok (not (property-call-arguments-p property nil)))
      (ok (not (property-call-arguments-p property '(2 3 4))))
      (ok (= 1 *defaults*))
      (ok (= 2 *calls*)))))

(deftest malformed-optional-reinitialization-rolls-back
  (let* ((contract (make-instance 'function-spec :name 'optional-target
                                 :argument-specs '((a integer))))
         (before (function-spec-argument-specs contract)))
    (ok (signals (reinitialize-instance contract
                                       :argument-specs '((a integer) &optional (b integer a)))
                 'invalid-function-spec-form))
    (ok (eq before (function-spec-argument-specs contract)))))

(deftest deferred-call-syntax-stays-rejected
  (dolist (args '((&rest (a integer)) (&key (a integer))
                 ((a integer supplied)) (&optional (a integer) &optional (b integer))))
    (ok (signals (make-instance 'function-spec :name 'optional-target :argument-specs args)
                 'invalid-function-spec-form))))

(deftest optional-and-supplied-variable-semantics-affect-the-digest
  (flet ((digest (args)
           (definition-digest
            (make-instance 'function-spec :name 'optional-target :argument-specs args))))
    (ok (not (equal (digest '((a integer) (b integer)))
                    (digest '((a integer) &optional (b integer))))))
    (ok (not (equal (digest '((a integer) &optional (b integer b-p)))
                    (digest '((a integer) &optional (b integer supplied-p))))))))

(deftest omitted-optionals-do-not-run-defaults-when-precondition-refuses
  (let ((*defaults* 0) (*calls* 0)
         (contract (make-instance 'function-spec :name 'optional-target
                                 :argument-specs '((a integer) &optional (b integer b-p))
                                 :preconditions '(nil)
                                 :precondition-function
                                 (lambda (a b b-p)
                                   (declare (ignore a b b-p))
                                   nil))))
    (ok (eq :rejected (evaluate-trial (make-function-check-property contract) '(2))))
    (ok (zerop *defaults*))
    (ok (zerop *calls*))))
