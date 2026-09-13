;;;; src/backends/call-generators.lisp

(defpackage #:cl-spec/src/backends/call-generators
  (:use #:cl)
  (:import-from #:check-it #:generator #:generate #:shrink #:cached-value)
  (:import-from #:cl-spec/src/backends/check-it-generators #:spec-generator)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout
                #:call-layout-bindings #:call-layout-required-count #:argument-binding-spec)
  (:export #:call-arguments-generator))

(in-package #:cl-spec/src/backends/call-generators)

(defclass call-arguments-generator (generator)
  ((children :initarg :children :reader call-generator-children)
   (required-count :initarg :required-count :reader call-generator-required-count))
  (:documentation "Generate positional calls and shrink optional suffixes before individual values."))

(defmethod generate ((generator call-arguments-generator))
  (let* ((children (call-generator-children generator))
         (required (call-generator-required-count generator))
         (count (+ required (random (1+ (- (length children) required))))))
    (setf (cached-value generator)
          (loop for child in children for index from 0 below count collect (generate child)))))

(defmethod shrink ((generator call-arguments-generator) test)
  (loop for count from (call-generator-required-count generator)
        while (< count (length (cached-value generator)))
        do (let ((candidate (subseq (cached-value generator) 0 count)))
             (unless (funcall test candidate)
               (setf (cached-value generator) candidate))))
  (loop for child in (call-generator-children generator)
        for index from 0 below (length (cached-value generator))
        when (typep child 'generator)
          do (shrink child
                     (lambda (value)
                       (let ((candidate (copy-list (cached-value generator))))
                         (setf (nth index candidate) value)
                         (if (funcall test candidate)
                             t
                             (progn (setf (cached-value generator) candidate) nil))))))
  (cached-value generator))

(defmethod spec-generator ((spec call-arguments-spec) context)
  (let ((layout (call-arguments-spec-layout spec)))
    (make-instance 'call-arguments-generator
                   :required-count (call-layout-required-count layout)
                   :children
                   (mapcar (lambda (binding)
                             (spec-generator (argument-binding-spec binding) context))
                           (call-layout-bindings layout)))))
