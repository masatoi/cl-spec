;;;; tests/recursive-validation-test.lisp
;;;;
;;;; Termination and cost of validating against specs that refer to themselves
;;;; (issues #58 and #59).

(defpackage #:cl-spec/tests/recursive-validation-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:invalid-spec-form
                #:invalid-spec-form-form
                #:invalid-spec-form-reason)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/recursive-validation-test)

(defun registry-with (&rest definitions)
  "Return a fresh registry holding DEFINITIONS, a list of (NAME FORM) pairs."
  (let ((registry (make-hash-table-registry)))
    (loop for (name form) in definitions
          do (registry-register-spec registry name (normalize-spec-form form :name name)))
    registry))

(defmacro within-seconds ((seconds) &body body)
  "Evaluate BODY, returning (:RETURNED VALUE), or :TIMED-OUT after SECONDS.

A regression in these tests is non-termination, so each check is bounded rather
than left to hang the suite."
  #+sbcl
  `(handler-case (sb-ext:with-timeout ,seconds (list :returned (progn ,@body)))
     (sb-ext:timeout () :timed-out))
  #-sbcl
  `(progn ,seconds (list :returned (progn ,@body))))

(defun refusal-of (thunk)
  "Return the CL-SPEC-ERROR THUNK signals within two seconds, :TIMED-OUT, or :NONE."
  (let ((outcome (within-seconds (2)
                   (handler-case (progn (funcall thunk) :none)
                     (cl-spec-error (condition) condition)))))
    (if (consp outcome) (second outcome) outcome)))

(defun self-containing-pair ()
  "Return the list (1 X) whose second element is the list itself."
  (let ((value (list 1 nil)))
    (setf (second value) value)
    value))

(defun add-chain (depth)
  "Return (:ADD (:ADD ... 1 1) 1) nested DEPTH times."
  (let ((value 1))
    (dotimes (index depth value)
      (setf value (list :add value 1)))))

(deftest a-reference-cycle-that-consumes-nothing-is-refused
  (let ((registry (registry-with '(alias-a alias-b) '(alias-b alias-a)
                                 '(self-and (and integer self-and)))))
    (testing "two aliases naming each other signal INVALID-SPEC-FORM instead of looping"
      (let ((condition (refusal-of (lambda () (validp 'alias-a 1 :registry registry)))))
        (ok (typep condition 'invalid-spec-form))
        (ok (and (typep condition 'invalid-spec-form)
                 (search "cycle" (invalid-spec-form-reason condition))))))
    (testing "a spec that reaches itself through AND on the same value is refused"
      (ok (typep (refusal-of (lambda () (validp 'self-and 1 :registry registry)))
                 'invalid-spec-form)))
    (testing "EXPLAIN-DATA refuses the same cycle"
      (ok (typep (refusal-of (lambda () (explain-data 'alias-a 1 :registry registry)))
                 'invalid-spec-form)))
    (testing "the refusal names the reference that closed the cycle"
      (let ((condition (refusal-of (lambda () (validp 'alias-a 1 :registry registry)))))
        (ok (and (typep condition 'invalid-spec-form)
                 (member (invalid-spec-form-form condition) '(alias-a alias-b))))))))

(deftest a-value-that-contains-itself-is-reported-not-followed
  (let ((registry (registry-with '(pair-tree (or null (tuple integer pair-tree))))))
    (testing "VALIDP answers NIL for a value reachable from itself"
      (ok (equal '(:returned nil)
                 (within-seconds (2)
                   (validp 'pair-tree (self-containing-pair) :registry registry)))))
    (testing "EXPLAIN-DATA names the cycle with a :CYCLIC-VALUE datum"
      (let* ((outcome (within-seconds (2)
                        (explain-data 'pair-tree (self-containing-pair) :registry registry)))
             (data (and (consp outcome) (second outcome))))
        (ok data)
        (ok (labels ((mentions-cycle-p (datums)
                       (some (lambda (datum)
                               (or (eq :cyclic-value (getf datum :kind))
                                   (mentions-cycle-p (getf datum :errors))
                                   (some (lambda (branch)
                                           (mentions-cycle-p (getf branch :errors)))
                                         (getf datum :branches))))
                             datums)))
              (mentions-cycle-p (getf data :errors))))))
    (testing "a finite value of the same shape is still admitted"
      (ok (validp 'pair-tree '(1 (2 (3 nil))) :registry registry)))))

(deftest recursive-disjunctions-validate-in-linear-time
  (let ((registry (registry-with '(ast (or integer
                                           (tuple (member :add) ast ast)
                                           (tuple (member :mul) ast ast))))))
    (testing "a 200-deep valid expression is checked within a second"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (and (validp 'ast (add-chain 200) :registry registry) t)))))
    (testing "EXPLAIN-DATA on the same value is just as fast"
      (ok (equal '(:returned t)
                 (within-seconds (1)
                   (getf (explain-data 'ast (add-chain 200) :registry registry) :valid)))))
    (testing "an invalid leaf deep in the expression is still found and located"
      (let ((value (add-chain 200)))
        (setf (third value) "x")
        (let ((outcome (within-seconds (1)
                         (explain-data 'ast value :registry registry))))
          (ok (consp outcome))
          (ok (and (consp outcome) (null (getf (second outcome) :valid)))))))))
