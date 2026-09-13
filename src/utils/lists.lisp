;;;; src/utils/lists.lisp

(defpackage #:cl-spec/src/utils/lists
  (:use #:cl)
  (:export #:finite-list-p))

(in-package #:cl-spec/src/utils/lists)

(defun finite-list-p (object)
  "Recognize a finite proper list in constant auxiliary space, without reading its elements."
  (let ((slow object)
        (fast object))
    (loop
      (when (null fast) (return t))
      (unless (consp fast) (return nil))
      (setf fast (cdr fast))
      (when (null fast) (return t))
      (unless (consp fast) (return nil))
      (setf fast (cdr fast)
            slow (cdr slow))
      (when (eq slow fast) (return nil)))))
