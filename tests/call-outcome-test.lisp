;;;; tests/call-outcome-test.lisp

(defpackage #:cl-spec/tests/call-outcome-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/call-outcome
                #:invoke-target-once #:make-call-outcome #:call-outcome-kind
                #:call-outcome-values #:call-outcome-condition))

(in-package #:cl-spec/tests/call-outcome-test)

(deftest outcome-construction-validates-the-tagged-payload
  (let* ((values (list nil 3))
         (condition (make-condition 'simple-error :format-control "original"))
         (returned (make-call-outcome :kind :returned :values values))
         (signaled (make-call-outcome :kind :signaled :condition condition)))
    (ok returned)
    (ok signaled)
    (when returned (ok (eq values (call-outcome-values returned))))
    (when signaled (ok (eq condition (call-outcome-condition signaled))))
    (dolist (args (list (list :kind :other)
                       (list :kind :returned :condition condition)
                       (list :kind :signaled)
                       (list :kind :signaled :condition condition :values '(1))
                       (list :kind :returned :values '(1 . 2))))
      (ok (handler-case (progn (apply #'make-call-outcome args) nil) (error () t))))
    (let ((cycle (list 1)))
      (setf (cdr cycle) cycle)
      (ok (handler-case
              (progn (make-call-outcome :kind :returned :values cycle) nil)
            (error () t))))))

(deftest invocation-preserves-all-values-and-identities
  (let* ((calls 0)
         (object (list :value))
         (outcome (invoke-target-once
                   (lambda (argument)
                     (incf calls)
                     (values argument nil 3))
                   (list object))))
    (ok outcome)
    (ok (= 1 calls))
    (when outcome
      (ok (eq :returned (call-outcome-kind outcome)))
      (ok (= 3 (length (call-outcome-values outcome))))
      (ok (eq object (first (call-outcome-values outcome))))
      (ok (equal '(nil 3) (rest (call-outcome-values outcome))))
      (ok (null (call-outcome-condition outcome))))))

(deftest zero-values-differ-from-one-nil
  (let ((zero (invoke-target-once (lambda () (values)) nil))
        (one (invoke-target-once (lambda () nil) nil)))
    (ok zero)
    (ok one)
    (when (and zero one)
      (ok (null (call-outcome-values zero)))
      (ok (equal '(nil) (call-outcome-values one)))
      (ok (eq :returned (call-outcome-kind zero)))
      (ok (eq :returned (call-outcome-kind one))))))

(deftest escaping-error-is-the-original-condition
  (let* ((calls 0)
         (condition (make-condition 'simple-error :format-control "original"))
         (outcome (invoke-target-once
                   (lambda () (incf calls) (error condition)) nil)))
    (ok outcome)
    (ok (= 1 calls))
    (when outcome
      (ok (eq :signaled (call-outcome-kind outcome)))
      (ok (eq condition (call-outcome-condition outcome)))
      (ok (null (call-outcome-values outcome))))))

(deftest nonlocal-exits-and-handled-errors-are-not-fabricated-outcomes
  (ok (eq :escaped
          (catch 'escape
            (invoke-target-once (lambda () (throw 'escape :escaped)) nil))))
  (let ((outcome (invoke-target-once
                  (lambda () (handler-case (error "handled") (error () :recovered))) nil)))
    (ok outcome)
    (when outcome
      (ok (eq :returned (call-outcome-kind outcome)))
      (ok (equal '(:recovered) (call-outcome-values outcome))))))
