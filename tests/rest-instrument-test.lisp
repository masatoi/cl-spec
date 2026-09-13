;;;; tests/rest-instrument-test.lisp

(defpackage #:cl-spec/tests/rest-instrument-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/dsl #:defspec-function)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/conditions #:spec-violation-errors)
  (:import-from #:cl-spec/instrument
                #:instrument-function #:uninstrument-function #:instrumentation-violation
                #:instrumentation-violation-reason))

(in-package #:cl-spec/tests/rest-instrument-test)

(defvar *calls* 0)

(defun instrumented-rest-target (head &rest tail)
  (incf *calls*)
  (values (+ head (reduce #'+ tail :initial-value 0)) :secondary))

(deftest rest-arity-diagnostics-have-no-finite-maximum
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (defspec-function instrumented-rest-target
      (:args (head integer) &rest (tail (list-of integer)))
      (:returns integer))
    (unwind-protect
         (progn
           (instrument-function 'instrumented-rest-target)
           (let ((condition
                   (handler-case (progn (funcall (symbol-function 'instrumented-rest-target)) nil)
                     (instrumentation-violation (condition) condition))))
             (ok condition)
             (ok (eq :arity (instrumentation-violation-reason condition)))
             (let ((error (first (spec-violation-errors condition))))
               (ok (= 1 (getf error :minimum-length)))
               (ok (null (getf error :maximum-length)))
               (ok (not (member :expected-length error)))))
           (ok (zerop *calls*)))
      (uninstrument-function 'instrumented-rest-target))))

(deftest rest-wrappers-check-whole-tail-and-preserve-multiple-values
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (defspec-function instrumented-rest-target
      (:args (head integer) &rest (tail (list-of integer)))
      (:pre (<= (length tail) 3))
      (:returns integer)
      (:post (= result (+ head (reduce #'+ tail :initial-value 0)))))
    (unwind-protect
         (progn
           (instrument-function 'instrumented-rest-target)
           (ok (equal '(1 :secondary) (multiple-value-list (instrumented-rest-target 1))))
           (ok (equal '(6 :secondary) (multiple-value-list (instrumented-rest-target 1 2 3))))
           (let ((condition
                   (handler-case (progn (instrumented-rest-target 1 "bad") nil)
                     (instrumentation-violation (condition) condition))))
             (ok (eq :argument-spec (instrumentation-violation-reason condition))))
           (ok (= 2 *calls*)))
      (uninstrument-function 'instrumented-rest-target))))
