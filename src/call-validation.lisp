;;;; src/call-validation.lisp

(defpackage #:cl-spec/src/call-validation
 (:use #:cl)
 (:import-from #:cl-spec/src/call-schema
 #:call-arguments-spec #:call-arguments-spec-layout #:call-layout-bindings
 #:call-layout-data #:call-layout-required-count #:call-layout-accepts-p
 #:argument-binding-name #:argument-binding-spec)
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
       (cond
         ((not (finite-list-p value))
          (list (error-datum :not-a-list base-path value :expected expected)))
         ((not (call-layout-accepts-p layout value))
          (list (error-datum :wrong-length base-path value :expected expected
                            :minimum-length (call-layout-required-count layout)
                            :maximum-length (length compiled) :actual-length (length value))))
         (t
          (loop for item in value
                for function in compiled
                for binding in (call-layout-bindings layout)
                for index from 0
                append
                (loop for datum in (funcall function item
                                            (list* (argument-binding-name binding) index base-path))
                      collect (let ((copy (copy-list datum)))
                                (setf (getf copy :tuple-path)
                                      (cons index (getf datum :tuple-path)))
                                copy)))))))))

(defmethod expected-descriptor ((spec call-arguments-spec))
 (let ((layout (call-arguments-spec-layout spec)))
   (list :kind :call-arguments
         :arguments (loop for data in (call-layout-data layout)
                          for binding in (call-layout-bindings layout)
                          collect (append data
                                          (list :expected
                                                (expected-descriptor
                                                 (argument-binding-spec binding))))))))
