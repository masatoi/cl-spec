;;;; src/definition-description.lisp

(defpackage #:cl-spec/src/definition-description
  (:use #:cl)
  (:export #:definition-description))

(in-package #:cl-spec/src/definition-description)

(defgeneric definition-description (definition)
  (:documentation "Return values: declaration data, ordered child definitions,
registry links as (KIND . NAME) pairs, and whether the stored description is complete.
Do not invoke user code. Source locations and capabilities are excluded."))

(defmethod definition-description ((definition t))
  (declare (ignore definition))
  (values nil nil nil nil))
