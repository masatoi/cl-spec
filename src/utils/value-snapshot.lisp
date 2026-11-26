;;;; src/utils/value-snapshot.lisp

(defpackage #:cl-spec/src/utils/value-snapshot
  (:use #:cl)
  (:export #:snapshot-value))

(in-package #:cl-spec/src/utils/value-snapshot)

(defun snapshot-value (value)
  "Copy conses and arrays iteratively, preserving cycles and sharing within VALUE.
Other objects retain identity; arbitrary application state is not checkpointed."
  (let ((copies (make-hash-table :test #'eq))
        (pending nil))
    (labels ((allocate (item)
               (cond
                 ((gethash item copies))
                 ((or (consp item) (arrayp item))
                  (let ((copy
                          (if (consp item)
                              (cons nil nil)
                              (make-array
                               (array-dimensions item)
                               :element-type (array-element-type item)
                               :adjustable (adjustable-array-p item)
                               :fill-pointer (when (array-has-fill-pointer-p item)
                                               (fill-pointer item))))))
                    (setf (gethash item copies) copy)
                    (push (cons item copy) pending)
                    copy))
                 (t item))))
      (let ((result (allocate value)))
        (loop while pending
              for pair = (pop pending)
              for source = (car pair)
              for copy = (cdr pair)
              do (if (consp source)
                     (setf (car copy) (allocate (car source))
                           (cdr copy) (allocate (cdr source)))
                     (dotimes (i (array-total-size source))
                       (setf (row-major-aref copy i)
                             (allocate (row-major-aref source i))))))
        result))))
