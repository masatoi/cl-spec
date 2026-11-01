;;;; src/utils/arguments.lisp

(defpackage #:cl-spec/src/utils/arguments
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:export #:check-argument))

(in-package #:cl-spec/src/utils/arguments)

(defun check-argument (value type operator argument)
  "Return VALUE when it is of TYPE, otherwise signal INVALID-ARGUMENT.

OPERATOR names the public function being called and ARGUMENT the parameter
VALUE was passed as, so the refusal says which one was wrong."
  (if (typep value type)
      value
      (error 'invalid-argument :datum value :expected-type type
                               :operator operator :argument argument)))
