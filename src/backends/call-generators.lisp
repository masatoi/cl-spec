;;;; src/backends/call-generators.lisp

(defpackage #:cl-spec/src/backends/call-generators
  (:use #:cl)
  (:import-from #:check-it #:generator #:generate #:shrink #:cached-value)
  (:import-from #:cl-spec/src/backends/check-it-generators #:spec-generator)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout
                #:call-layout-bindings #:call-layout-required-count #:call-layout-positional-count
                #:argument-binding-spec #:argument-binding-kind #:argument-binding-keyword)
  (:export #:call-arguments-generator #:call-generator-children #:call-generator-removable-p))

(in-package #:cl-spec/src/backends/call-generators)

(defclass call-arguments-generator (generator)
  ((children :initarg :children :reader call-generator-children)
   (layout :initarg :layout :reader call-generator-layout))
  (:documentation "Generate raw positional and keyword calls with declaration-aware shrinking."))

(defun call-generator-removable-p (generator)
  "Return true when a generated call can omit at least one declared parameter."
  (let ((layout (call-generator-layout generator)))
    (> (length (call-layout-bindings layout)) (call-layout-required-count layout))))

(defmethod generate ((generator call-arguments-generator))
  (let* ((layout (call-generator-layout generator))
         (children (call-generator-children generator))
         (required (call-layout-required-count layout))
         (positional (call-layout-positional-count layout))
         (count (+ required (random (1+ (- positional required))))))
    (setf (cached-value generator)
          (append
           (loop for child in children for index from 0 below count collect (generate child))
           (when (= count positional)
             (loop for binding in (nthcdr positional (call-layout-bindings layout))
                   for child in (nthcdr positional children)
                   when (zerop (random 2))
                     append (list (argument-binding-keyword binding) (generate child))))))))

(defun remove-call-key (arguments positional key)
  "Return a copied call and true when its keyword pair was removed."
  (when (>= (length arguments) positional)
    (let ((tail (copy-list (nthcdr positional arguments))))
      (when (remf tail key)
        (values (append (subseq arguments 0 positional) tail) t)))))

(defmethod shrink ((generator call-arguments-generator) test)
  (let* ((layout (call-generator-layout generator))
         (positional (call-layout-positional-count layout)))
    ;; Calls generated here have unique keys; removing a pair keeps their order.
    (loop for binding in (nthcdr positional (call-layout-bindings layout))
          for key = (argument-binding-keyword binding)
          do (multiple-value-bind (candidate removed)
                 (remove-call-key (cached-value generator) positional key)
               (when (and removed (not (funcall test candidate)))
                 (setf (cached-value generator) candidate))))
    ;; An optional prefix can only be shortened once the keyword tail is empty.
    (when (<= (length (cached-value generator)) positional)
      (loop for count from (call-layout-required-count layout)
            while (< count (length (cached-value generator)))
            do (let ((candidate (subseq (cached-value generator) 0 count)))
                 (unless (funcall test candidate)
                   (setf (cached-value generator) candidate)))))
    (loop for binding in (call-layout-bindings layout)
          for child in (call-generator-children generator)
          for position from 0
          for index = (if (eq :key (argument-binding-kind binding))
                          (loop for tail on (nthcdr (min positional
                                                         (length (cached-value generator)))
                                                    (cached-value generator)) by #'cddr
                                for i from positional by 2
                                when (eq (car tail) (argument-binding-keyword binding))
                                  return (1+ i))
                          (when (< position (length (cached-value generator))) position))
          when (and index (typep child 'generator))
            do (shrink child
                       (lambda (value)
                         (let ((candidate (copy-list (cached-value generator))))
                           (setf (nth index candidate) value)
                           (if (funcall test candidate)
                               t
                               (progn (setf (cached-value generator) candidate) nil)))))))
  (cached-value generator))

(defmethod spec-generator ((spec call-arguments-spec) context)
  (let ((layout (call-arguments-spec-layout spec)))
    (make-instance 'call-arguments-generator
                   :layout layout
                   :children
                   (mapcar (lambda (binding)
                             (spec-generator (argument-binding-spec binding) context))
                           (call-layout-bindings layout)))))
