;;;; tests/rest-function-test.lisp

(defpackage #:cl-spec/tests/rest-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/dsl #:defspec-function #:defproperty)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:make-function-check-property #:function-spec-argument-specs
                #:check-function)
  (:import-from #:cl-spec/src/generator-definition #:custom-generator #:register-generator)
  (:import-from #:cl-spec/src/counterexample #:make-counterexample-artifact #:recheck-counterexample)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry #:find-function-spec)
  (:import-from #:cl-spec/src/property #:property-named-arguments)
  (:import-from #:cl-spec/src/schema #:definition-digest)
  (:import-from #:cl-spec/src/execution
                #:evaluate-trial #:observe-trial #:trial-observation-arguments
                #:trial-observation-arguments-mutated-p)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form #:invalid-property-form))

(in-package #:cl-spec/tests/rest-function-test)

(defvar *calls* 0)
(defvar *seen-tail* nil)

(defun rest-target (head &rest tail)
  (incf *calls*)
  (+ head (reduce #'+ tail :initial-value 0)))

(defun broken-rest-target (&rest tail)
  (declare (ignore tail))
  (incf *calls*)
  :wrong)

(defun mutating-rest-target (&rest values)
  (incf *calls*)
  (setf (caar values) :changed)
  :wrong)

(deftest rest-contract-binds-the-original-tail
  (let* ((*calls* 0) (*seen-tail* nil)
         (arguments (list 1 2 3))
         (contract (make-instance 'function-spec :name 'rest-target
                                 :argument-specs '((head integer) &rest (tail (list-of integer)))
                                 :return-spec 'integer
                                 :preconditions '(t)
                                 :precondition-function
                                 (lambda (head tail)
                                   (setf *seen-tail* tail)
                                   (integerp head))))
         (property (make-function-check-property contract)))
    (ok (eq :passed (evaluate-trial property arguments)))
    (ok (eq (cdr arguments) *seen-tail*))
    (ok (equal '(head 1 tail (2 3)) (property-named-arguments property arguments)))
    (ok (eq :passed (evaluate-trial property '(1))))
    (ok (null *seen-tail*))
    (ok (= 2 *calls*))))

(deftest rest-dsl-expands-and-property-syntax-remains-required
  (ok (macroexpand-1
       '(defspec-function rest-target
          (:args (head integer) &rest (tail (list-of integer)))
          (:pre (every #'integerp tail))
          (:returns integer))))
  (ok (signals (macroexpand-1 '(defproperty invalid (&rest (tail list)) t))
               'invalid-property-form)))

(deftest rest-dsl-pre-and-post-see-one-whole-tail
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (defspec-function rest-target
      (:args (head integer) &rest (tail (list-of integer)))
      (:pre (every #'integerp tail))
      (:returns integer)
      (:post (= result (+ head (reduce #'+ tail :initial-value 0)))))
    (let ((property (make-function-check-property (find-function-spec 'rest-target))))
      (dolist (arguments '((1) (1 2) (1 2 3 4)))
        (ok (eq :passed (evaluate-trial property arguments))))
      (ok (= 3 *calls*))
      (ok (signals (evaluate-trial property nil) 'program-error))
      (ok (= 3 *calls*)))))

(deftest invalid-rest-reinitialization-rolls-back
  (let* ((contract (make-instance 'function-spec :name 'rest-target
                                 :argument-specs '((head integer))))
         (before (function-spec-argument-specs contract)))
    (dolist (args '(((head integer) &rest (tail list supplied-p))
                   (&rest (tail list) &rest (more list))
                   (&aux (tail list))))
      (ok (signals (reinitialize-instance contract :argument-specs args)
                   'invalid-function-spec-form))
      (ok (eq before (function-spec-argument-specs contract))))))

(deftest optional-rest-and-key-bindings-share-the-raw-tail
  (let* ((arguments (list 1 nil :size 2 :size 9))
         (contract (make-instance
                    'function-spec :name 'rest-target
                    :argument-specs
                    '((head integer) &optional (option t option-p)
                      &rest (tail list) &key ((:size amount) integer amount-p))))
         (property (make-function-check-property contract))
         (named (property-named-arguments property arguments)))
    (ok (eq (cddr arguments) (getf named 'tail)))
    (ok (equal '(head 1 option nil option-p t tail (:size 2 :size 9)
                 amount 2 amount-p t)
               named))
    (ok (equal '(head 1 option :size option-p t tail nil amount nil amount-p nil)
               (property-named-arguments property '(1 :size))))))

(deftest rest-tail-spec-and-marker-affect-definition-identity
  (flet ((digest (arguments)
           (definition-digest
            (make-instance 'function-spec :name 'rest-target :argument-specs arguments))))
    (ok (not (equal (digest '((head integer) (tail list)))
                    (digest '((head integer) &rest (tail list))))))
    (ok (not (equal (digest '((head integer) &rest (tail (list-of integer))))
                    (digest '((head integer) &rest (tail (list-of string)))))))))

(deftest target-mutation-retains-original-rest-evidence
  (let* ((*calls* 0)
         (arguments (list (list :original)))
         (contract (make-instance 'function-spec :name 'mutating-rest-target
                                 :argument-specs '(&rest (tail (list-of list)))
                                 :return-spec 'integer))
         (observation (observe-trial (make-function-check-property contract) arguments)))
    (ok (trial-observation-arguments-mutated-p observation))
    (ok (equal '((:original)) (trial-observation-arguments observation)))
    (ok (equal '((:changed)) arguments))
    (ok (= 1 *calls*))))

(deftest rest-counterexample-rechecks-without-drawing-again
  (let ((*registry* (make-hash-table-registry)) (*calls* 0) (draws 0))
    (register-generator
     (make-instance 'custom-generator :name 'rest-arguments
                    :source-form '(defgenerator rest-arguments () (list 1 2 3))
                    :function (lambda () (incf draws) (list 1 2 3))))
    (defspec-function broken-rest-target
      (:args &rest (tail (list-of integer)))
      (:args-generator rest-arguments)
      (:returns integer))
    (let* ((result (check-function 'broken-rest-target :trials 1 :seed 17))
           (artifact (make-counterexample-artifact result)))
      (ok (= 1 draws))
      (ok (eq :same-failure
              (getf (recheck-counterexample artifact :state-policy :stateless) :status)))
      (ok (= 1 draws))
      (ok (= 2 *calls*)))))
