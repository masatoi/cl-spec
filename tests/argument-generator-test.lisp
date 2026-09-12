;;;; tests/argument-generator-test.lisp

(defpackage #:cl-spec/tests/argument-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/dsl #:defgenerator #:defspec-function #:defspec)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:check-function
                #:function-check-result-rejected #:function-check-result-shrunk-outcome)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-status #:property-result-trials
                #:property-result-counterexample #:property-result-shrunk-counterexample)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec-argument-generator #:function-spec-argument-schema)
  (:import-from #:cl-spec/src/introspection #:function-spec-data)
  (:import-from #:cl-spec/src/ir #:spec-generator-name #:spec-children)
  (:import-from #:cl-spec/src/conditions
                #:invalid-generated-arguments #:invalid-generated-arguments-generator
                #:invalid-generated-arguments-value #:invalid-function-spec-form
                #:generator-unavailable)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/argument-generator-test)

(defvar *calls* 0)
(defvar *inputs* nil)

(defun related-target (low high value)
  "Record an admitted call and return VALUE."
  (incf *calls*)
  (push (list low high value) *inputs*)
  value)

(defun related-contract (&optional generator)
  "Build a contract for three related integers."
  (make-instance 'function-spec
                 :name 'related-target
                 :argument-specs '((low (range integer 0 20))
                                   (high (range integer 0 20))
                                   (value (range integer 0 20)))
                 :argument-generator generator
                 :preconditions '((< low high) (<= low value high))
                 :precondition-function
                 (lambda (low high value) (and (< low high) (<= low value high)))
                 :return-spec 'integer))

(deftest coordinated-arguments-use-the-whole-trial-budget
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0)
        (*inputs* nil))
    (defgenerator related-arguments ()
      (let* ((low (random 10))
             (high (+ low 1 (random 10)))
             (value (+ low (random (1+ (- high low))))))
        (list low high value)))
    (let ((independent (check-function (related-contract) :trials 100 :seed 42)))
      (ok (plusp (function-check-result-rejected independent)))
      (ok (< *calls* 100)))
    (setf *calls* 0 *inputs* nil)
    (let ((result (check-function (related-contract 'related-arguments)
                                  :trials 100 :seed 42)))
      (ok (eq :passed (property-result-status result)))
      (ok (= 100 (property-result-trials result)))
      (ok (= 100 *calls*))
      (ok (zerop (function-check-result-rejected result)))
      (ok (every (lambda (args)
                   (destructuring-bind (low high value) args
                     (and (< low high) (<= low value high))))
                 *inputs*))
      (let ((first-inputs *inputs*))
        (setf *inputs* nil)
        (check-function (related-contract 'related-arguments) :seed result)
        (ok (equal first-inputs *inputs*))))))

(defun unary-target (x)
  "Record a unary call and return its input."
  (incf *calls*)
  x)

(defun nullary-target ()
  "Record a zero-argument call."
  (incf *calls*)
  1)

(deftest invalid-argument-tuples-never-call-the-target
  (let ((cycle (list 1)))
    (setf (cdr cycle) cycle)
    (dolist (output (list nil '(1 2) "x" #(1) '(1 . 2) cycle '("wrong")))
      (let ((*registry* (make-hash-table-registry))
            (*calls* 0)
            (draws 0))
        (defgenerator bad-arguments () (incf draws) output)
        (let ((contract (make-instance 'function-spec
                                      :name 'unary-target :argument-specs '((x integer))
                                      :argument-generator 'bad-arguments)))
          (ok (handler-case (progn (check-function contract :trials 10 :seed 42) nil)
                (invalid-generated-arguments (condition)
                  (and (eq 'bad-arguments (invalid-generated-arguments-generator condition))
                       (cl-spec/src/execution:same-value-p
                        output (invalid-generated-arguments-value condition))))))
          (ok (= 1 draws))
          (ok (zerop *calls*)))))))

(deftest custom-arguments-still-obey-preconditions
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defgenerator refused-arguments () '(10 0 5))
    (let ((result (check-function (related-contract 'refused-arguments)
                                  :trials 100 :seed 42)))
      (ok (eq :skipped (property-result-status result)))
      (ok (= 100 (property-result-trials result)))
      (ok (= 100 (function-check-result-rejected result)))
      (ok (zerop *calls*)))))

(deftest zero-argument-tuples-and-zero-budget
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0)
        (draws 0))
    (defgenerator empty-arguments () (incf draws) nil)
    (let* ((contract (make-instance 'function-spec :name 'nullary-target
                                   :argument-generator 'empty-arguments :return-spec 'integer))
           (zero (check-function contract :trials 0 :seed 42))
           (result (check-function contract :trials 7 :seed 42)))
      (ok (eq :skipped (property-result-status zero)))
      (ok (eq :passed (property-result-status result)))
      (ok (= 7 draws *calls*)))))

(deftest custom-argument-failures-keep-the-observed-tuple
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0)
        (draws 0))
    (defgenerator failing-arguments () (incf draws) '(6))
    (let* ((contract (make-instance 'function-spec :name 'unary-target
                                   :argument-specs '((x integer))
                                   :argument-generator 'failing-arguments
                                   :return-spec '(range integer 0 0)))
           (result (check-function contract :trials 100 :seed 42)))
      (ok (eq :failed (property-result-status result)))
      (ok (equal '(x 6) (property-result-counterexample result)))
      (ok (null (property-result-shrunk-counterexample result)))
      (ok (eq :none (function-check-result-shrunk-outcome result)))
      (ok (= 1 draws *calls*)))))

(deftest argument-generator-resolves-in-the-run-registry
  (let ((first-registry (make-hash-table-registry))
        (second-registry (make-hash-table-registry))
        (*calls* 0))
    (let ((*registry* first-registry))
      (defgenerator registered-arguments () '(1)))
    (let ((*registry* second-registry))
      (defgenerator registered-arguments () '(2)))
    (let ((contract (make-instance 'function-spec :name 'unary-target
                                   :argument-specs '((x integer))
                                   :argument-generator 'registered-arguments
                                   :return-spec '(range integer 0 0))))
      (ok (equal '(x 1)
                 (property-result-counterexample
                  (check-function contract :trials 1 :registry first-registry))))
      (ok (equal '(x 2)
                 (property-result-counterexample
                  (check-function contract :trials 1 :registry second-registry))))
      (ok (handler-case
              (progn (check-function contract :trials 1
                                     :registry (make-hash-table-registry))
                     nil)
            (generator-unavailable () t))))))

(deftest whole-argument-generation-bypasses-element-generator-derivation
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defspec odd-input (satisfies oddp))
    (defgenerator odd-arguments () '(3))
    (defspec-function unary-target
      (:args (x odd-input))
      (:args-generator odd-arguments)
      (:returns integer))
    (ok (eq :passed (property-result-status
                     (check-function 'unary-target :trials 10 :seed 42))))
    (ok (= 10 *calls*))))

(deftest argument-generator-introspection-and-closeness-to-current-contract
  (let* ((contract (related-contract 'related-arguments))
         (data (function-spec-data contract))
         (schema (function-spec-argument-schema contract)))
    (ok (eq 'related-arguments (getf data :argument-generator)))
    (ok (eq :tuple (getf (getf data :argument-schema) :kind)))
    (ok (eq 'related-arguments (spec-generator-name schema)))
    (ok (= 3 (length (spec-children schema))))
    (ok (handler-case
            (progn (reinitialize-instance contract :argument-generator #'list) nil)
          (invalid-function-spec-form () t)))
    (ok (eq 'related-arguments (function-spec-argument-generator contract)))
    (reinitialize-instance contract :argument-generator nil :argument-specs '((x integer)))
    (ok (null (function-spec-argument-generator contract)))
    (ok (= 1 (length (spec-children (function-spec-argument-schema contract)))))))

(deftest malformed-generator-clauses-are-refused
  (dolist (clauses '(((:args-generator))
                     ((:args-generator nil))
                     ((:args-generator :keyword))
                     ((:args-generator (lambda () nil)))
                     ((:args-generator one two))
                     ((:args-generator one) (:args-generator two))))
    (ok (handler-case
            (progn (macroexpand-1 (list* 'defspec-function 'unary-target clauses)) nil)
          (invalid-function-spec-form () t)))))

(deftest argument-generator-errors-are-not-target-failures
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0)
        (draws 0))
    (defgenerator broken-arguments () (incf draws) (error "broken argument generator"))
    (let ((contract (make-instance 'function-spec :name 'unary-target
                                  :argument-specs '((x integer))
                                  :argument-generator 'broken-arguments)))
      (ok (handler-case (progn (check-function contract :trials 100 :seed 42) nil)
            (simple-error (condition)
              (string= "broken argument generator" (princ-to-string condition)))))
      (ok (= 1 draws))
      (ok (zerop *calls*)))))

(defun mutating-argument-predicate (x)
  "Mutate a tuple element while claiming to validate it."
  (setf (car x) "invalid")
  t)

(deftest argument-validation-mutation-cannot-create-a-target-counterexample
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defgenerator mutable-arguments () (list (list 1)))
    (let ((contract
            (make-instance 'function-spec :name 'unary-target
                           :argument-specs
                           '((x (and (tuple integer) (satisfies mutating-argument-predicate))))
                           :argument-generator 'mutable-arguments
                           :return-spec 'integer)))
      (ok (handler-case (progn (check-function contract :trials 1) nil)
            (invalid-generated-arguments () t)))
      (ok (zerop *calls*)))))

(deftest nested-circular-lists-are-invalid-generated-arguments
  (let ((*registry* (make-hash-table-registry))
        (*calls* 0))
    (defgenerator circular-argument ()
      (let ((value (list 1)))
        (setf (cdr value) value)
        (list value)))
    (let ((contract (make-instance 'function-spec :name 'unary-target
                                  :argument-specs '((x (list-of integer)))
                                  :argument-generator 'circular-argument)))
      (ok (handler-case (progn (check-function contract :trials 1) nil)
            (invalid-generated-arguments () t)))
      (ok (zerop *calls*)))))

(deftest argument-generator-clause-is-accepted
  (ok (consp (macroexpand-1
              '(defspec-function related-target
                 (:args (low integer) (high integer) (value integer))
                 (:args-generator related-arguments)
                 (:returns integer))))))
