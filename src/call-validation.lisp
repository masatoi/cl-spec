;;;; src/call-validation.lisp

(defpackage #:cl-spec/src/call-validation
 (:use #:cl)
 (:import-from #:cl-spec/src/call-schema
 #:call-arguments-spec #:call-arguments-spec-layout #:call-layout-bindings
 #:call-layout-data #:call-layout-required-count
 #:argument-binding-name #:argument-binding-spec #:argument-binding-kind
 #:argument-binding-keyword #:bind-call-arguments #:bound-call-bindings #:bound-call-presence
 #:call-layout-shape-error #:call-layout-key-p #:call-layout-allow-other-keys-p)
 (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
 (:import-from #:cl-spec/src/explain #:compile-node #:expected-descriptor #:error-datum))

(in-package #:cl-spec/src/call-validation)

(defmethod compile-node ((spec call-arguments-spec) context)
 (let* ((layout (call-arguments-spec-layout spec))
        (compiled (mapcar (lambda (binding) (compile-node (argument-binding-spec binding) context))
                          (call-layout-bindings layout)))
        (expected (expected-descriptor spec)))
   (lambda (value path)
     (let ((base-path (or path '(:args))))
       (multiple-value-bind (kind key) (call-layout-shape-error layout value)
         (if kind
             (list (error-datum kind base-path value :expected expected
                               :minimum-length (call-layout-required-count layout)
                               :maximum-length (unless (call-layout-key-p layout) (length compiled))
                               :actual-length (when (finite-list-p value) (length value))
                               :key key))
             (let* ((bound (bind-call-arguments layout value))
                    (bindings (bound-call-bindings bound)))
               (loop for binding in (call-layout-bindings layout)
                     for function in compiled
                     for present-p in (bound-call-presence bound)
                     for index from 0
                     when present-p append
                     (loop for datum in
                           (funcall function
                                    (cdr (assoc (argument-binding-name binding) bindings))
                                    (if (eq :key (argument-binding-kind binding))
                                        (cons (argument-binding-keyword binding) base-path)
                                        (list* (argument-binding-name binding) index base-path)))
                           collect (let ((copy (copy-list datum)))
                                     (setf (getf copy :tuple-path)
                                           (cons index (getf datum :tuple-path)))
                                     copy))))))))))

(defmethod expected-descriptor ((spec call-arguments-spec))
 (let ((layout (call-arguments-spec-layout spec)))
   (list :kind :call-arguments
         :key-p (call-layout-key-p layout)
         :allow-other-keys (call-layout-allow-other-keys-p layout)
         :arguments (loop for data in (call-layout-data layout)
                          for binding in (call-layout-bindings layout)
                          collect (append data
                                          (list :expected
                                                (expected-descriptor
                                                 (argument-binding-spec binding))))))))
