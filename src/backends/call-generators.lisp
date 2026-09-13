;;;; src/backends/call-generators.lisp

(defpackage #:cl-spec/src/backends/call-generators
  (:use #:cl)
  (:import-from #:check-it #:generator #:generate #:shrink #:cached-value)
  (:import-from #:cl-spec/src/backends/check-it-generators #:spec-generator)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout
                #:call-layout-bindings #:call-layout-required-count #:call-layout-positional-count
                #:call-layout-rest-binding #:call-layout-key-p
                #:argument-binding-spec #:argument-binding-kind #:argument-binding-keyword)
  (:import-from #:cl-spec/src/ir
                #:spec-generator-name #:list-of-spec #:collection-spec-element-spec
                #:type-spec #:type-spec-type-specifier)
  (:import-from #:cl-spec/src/validator #:compile-validator)
  (:import-from #:cl-spec/src/conditions #:generator-unavailable)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:call-arguments-generator #:call-generator-children #:call-generator-removable-p))

(in-package #:cl-spec/src/backends/call-generators)

(defclass call-arguments-generator (generator)
  ((children :initarg :children :reader call-generator-children)
   (layout :initarg :layout :reader call-generator-layout)
   (rest-driven-p :initarg :rest-driven-p :reader call-generator-rest-driven-p)
   (validator :initarg :validator :reader call-generator-validator)
   (spec :initarg :spec :reader call-generator-spec))
  (:documentation "Generate raw calls and shrink their positional, rest, or keyword values."))

(defun call-generator-removable-p (generator)
  "Return true when optional positional or generated keyword arguments can be omitted."
  (let ((layout (call-generator-layout generator)))
    (or (> (call-layout-positional-count layout) (call-layout-required-count layout))
        (and (not (call-generator-rest-driven-p generator))
             (some (lambda (binding) (eq :key (argument-binding-kind binding)))
                   (call-layout-bindings layout))))))

(defmethod generate ((generator call-arguments-generator))
  (let* ((layout (call-generator-layout generator))
         (children (call-generator-children generator))
         (bindings (call-layout-bindings layout))
         (required (call-layout-required-count layout))
         (positional (call-layout-positional-count layout))
         (rest-driven (call-generator-rest-driven-p generator)))
    (loop repeat 100
          for tail = (if rest-driven
                         (generate (nth positional children))
                         (loop for binding in bindings for child in children
                               when (and (eq :key (argument-binding-kind binding))
                                         (zerop (random 2)))
                                 append (list (argument-binding-keyword binding)
                                              (generate child))))
          for proper-tail = (if (finite-list-p tail) tail
                                (error 'generator-unavailable
                                       :spec (call-generator-spec generator)
                                       :reason "rest generator must produce a finite proper list"))
          for count = (if tail positional
                          (+ required (random (1+ (- positional required)))))
          for arguments = (append (loop for child in children for index from 0 below count
                                        collect (generate child))
                                  proper-tail)
          when (or (not rest-driven) (funcall (call-generator-validator generator) arguments))
            do (return-from generate (setf (cached-value generator) arguments)))
    (error 'generator-unavailable :spec (call-generator-spec generator)
           :reason "rest and keyword constraints rejected 100 generated calls")))

(defun remove-call-key (arguments positional key)
  "Return a copied call and true when its keyword pair was removed."
  (when (>= (length arguments) positional)
    (let ((tail (copy-list (nthcdr positional arguments))))
      (when (remf tail key)
        (values (append (subseq arguments 0 positional) tail) t)))))

(defmethod shrink ((generator call-arguments-generator) test)
  (let* ((layout (call-generator-layout generator))
         (positional (call-layout-positional-count layout)))
    (unless (call-generator-rest-driven-p generator)
      (loop for binding in (call-layout-bindings layout)
            when (eq :key (argument-binding-kind binding))
              do (multiple-value-bind (candidate removed)
                     (remove-call-key (cached-value generator) positional
                                      (argument-binding-keyword binding))
                   (when (and removed (not (funcall test candidate)))
                     (setf (cached-value generator) candidate)))))
    ;; Removing an optional argument must not consume a value from the remaining tail.
    (when (<= (length (cached-value generator)) positional)
      (loop for count from (call-layout-required-count layout)
            while (< count (length (cached-value generator)))
            do (let ((candidate (subseq (cached-value generator) 0 count)))
                 (unless (funcall test candidate)
                   (setf (cached-value generator) candidate)))))
    (loop for binding in (call-layout-bindings layout)
          for child in (call-generator-children generator)
          for position from 0
          for kind = (argument-binding-kind binding)
          for index = (case kind
                        (:rest (when (call-generator-rest-driven-p generator)
                                 (min positional (length (cached-value generator)))))
                        (:key (unless (call-generator-rest-driven-p generator)
                                (loop for tail on (nthcdr (min positional
                                                               (length (cached-value generator)))
                                                          (cached-value generator)) by #'cddr
                                      for i from positional by 2
                                      when (eq (car tail) (argument-binding-keyword binding))
                                        return (1+ i))))
                        (otherwise
                         (when (< position (length (cached-value generator))) position)))
          when (and index (typep child 'generator))
            do (shrink child
                       (lambda (value)
                         (let ((candidate
                                 (if (eq kind :rest)
                                     (when (finite-list-p value)
                                       (append (subseq (cached-value generator) 0 index) value))
                                     (let ((copy (copy-list (cached-value generator))))
                                       (setf (nth index copy) value)
                                       copy))))
                           (if (or (and (eq kind :rest) (not (finite-list-p value)))
                                   (funcall test candidate))
                               t
                               (progn (setf (cached-value generator) candidate) nil)))))))
  (cached-value generator))

(defun unconstrained-rest-list-p (spec)
  "Recognize an unannotated universal list without bypassing extension generators."
  (and (eq (class-of spec) (find-class 'list-of-spec))
       (null (spec-generator-name spec))
       (let ((element (collection-spec-element-spec spec)))
         (and (eq (class-of element) (find-class 'type-spec))
              (null (spec-generator-name element))
              (eq t (type-spec-type-specifier element))))))

(defmethod spec-generator ((spec call-arguments-spec) context)
  (let* ((layout (call-arguments-spec-layout spec))
         (rest (call-layout-rest-binding layout))
         (rest-driven (and rest
                           (not (and (call-layout-key-p layout)
                                     (unconstrained-rest-list-p
                                      (argument-binding-spec rest)))))))
    (make-instance 'call-arguments-generator
                   :layout layout :spec spec :rest-driven-p rest-driven
                   :validator (compile-validator spec :context context)
                   :children
                   (mapcar (lambda (binding)
                             (unless (or (and rest-driven
                                              (eq :key (argument-binding-kind binding)))
                                         (and (not rest-driven)
                                              (eq :rest (argument-binding-kind binding))))
                               (spec-generator (argument-binding-spec binding) context)))
                           (call-layout-bindings layout)))))
