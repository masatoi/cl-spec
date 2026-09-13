;;;; src/call-outcome.lisp

(defpackage #:cl-spec/src/call-outcome
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:call-outcome #:make-call-outcome #:invoke-target-once
           #:call-outcome-kind #:call-outcome-values #:call-outcome-condition))

(in-package #:cl-spec/src/call-outcome)

(defstruct (call-outcome (:constructor %make-call-outcome (kind values condition)) (:copier nil))
  "Tagged result of one target invocation, retaining raw values or the original error."
  (kind :returned :type (member :returned :signaled) :read-only t)
  (values nil :type list :read-only t)
  (condition nil :type (or null error) :read-only t))

(defun make-call-outcome (&key (kind :returned) values condition)
  "Construct a consistent tagged outcome without copying its application values.
Returned outcomes have a finite values list and no condition. Signaled outcomes
have the original ERROR and no returned values."
  (check-type kind (member :returned :signaled))
  (unless (finite-list-p values) (error 'program-error))
  (ecase kind
    (:returned (when condition (error 'program-error)))
    (:signaled
     (check-type condition error)
     (when values (error 'program-error))))
  (%make-call-outcome kind values condition))

(defun invoke-target-once (target raw-arguments)
  "Invoke TARGET once and retain all returned values or the escaping ERROR.
This checker helper unwinds errors. Instrumentation must preserve target restart
contexts and should not use this catcher. Non-error nonlocal exits propagate."
  (handler-case
      (%make-call-outcome :returned (multiple-value-list (apply target raw-arguments)) nil)
    (error (condition) (%make-call-outcome :signaled nil condition))))
