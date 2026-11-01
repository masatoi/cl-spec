;;;; src/utils/numbers.lisp
;;;;
;;;; Numeric predicates shared by normalization, validation and generation.

(defpackage #:cl-spec/src/utils/numbers
  (:use #:cl)
  (:export #:not-a-number-p))

(in-package #:cl-spec/src/utils/numbers)

(defun not-a-number-p (value)
  "Return true when VALUE is a floating-point NaN.

NaN is unordered: every comparison with it is false and, under the default float
traps, signals FLOATING-POINT-INVALID-OPERATION.  Code that compares a value
against a bound has to recognise NaN first."
  (and (floatp value)
       #+sbcl (sb-ext:float-nan-p value)
       #-sbcl (/= value value)))
