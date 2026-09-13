;;;; tests/optional-instrument-test.lisp

(defpackage #:cl-spec/tests/optional-instrument-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/instrument))

(in-package #:cl-spec/tests/optional-instrument-test)

(defvar *defaults* 0)
(defvar *calls* 0)
(defun guarded-optional (required &optional (value (progn (incf *defaults*) 42)))
  (declare (ignore required))
  (incf *calls*)
  (values value :extra))

(deftest guards-preserve-optional-defaults-and-reject-invalid-calls
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*defaults* 0) (*calls* 0))
    (cl-spec:defspec-function guarded-optional
      (:args (required integer) &optional (value (member nil 7) supplied))
      (:returns t)
      (:post (if supplied (eql result value) (= result 42))))
    (unwind-protect
         (progn
           (cl-spec/instrument:instrument-function 'guarded-optional)
           (ok (equal '(42 :extra) (multiple-value-list (guarded-optional 1))))
           (ok (equal '(nil :extra) (multiple-value-list (guarded-optional 1 nil))))
           (ok (equal '(7 :extra) (multiple-value-list (guarded-optional 1 7))))
           (ok (= 1 *defaults*))
           (ok (= 3 *calls*))
           (ok (signals (funcall 'guarded-optional)
                        'cl-spec/instrument:instrumentation-violation))
           (ok (signals (funcall 'guarded-optional 1 7 8)
                        'cl-spec/instrument:instrumentation-violation))
           (ok (signals (guarded-optional 1 "wrong")
                        'cl-spec/instrument:instrumentation-violation))
           (ok (= 3 *calls*)))
      (cl-spec/instrument:uninstrument-function 'guarded-optional))))

(deftest optional-introspection-describes-presence
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function guarded-optional
      (:args (required integer) &optional (value integer supplied))
      (:returns t))
    (let* ((data (cl-spec:function-spec-data 'guarded-optional))
           (optional (second (getf data :arguments))))
      (ok (getf data :definition-digest-complete))
      (ok (eq :optional (getf optional :kind)))
      (ok (eq 'supplied (getf optional :supplied-p)))
      (ok (eq :call-arguments (getf (getf data :argument-schema) :kind))))))

(deftest captured-precondition-spec-uses-optional-bindings
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*defaults* 0) (*calls* 0))
    (cl-spec:defspec-function guarded-optional
      (:args (required integer) &optional (value integer supplied))
      (:pre (and supplied (plusp value)))
      (:returns t))
    (unwind-protect
         (progn
           (cl-spec/instrument:instrument-function 'guarded-optional)
           (let ((condition
                   (handler-case (guarded-optional 1)
                     (cl-spec/instrument:instrumentation-violation (condition) condition))))
             (ok (typep condition 'cl-spec/instrument:instrumentation-violation))
             (ok (not (cl-spec:validp (cl-spec:spec-violation-spec condition)
                                     (cl-spec:spec-violation-value condition))))
             (ok (zerop *calls*))
             (ok (zerop *defaults*))))
      (cl-spec/instrument:uninstrument-function 'guarded-optional))))
