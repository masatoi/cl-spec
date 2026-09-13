;;;; tests/return-values-schema-test.lisp
(defpackage #:cl-spec/tests/return-values-schema-test
 (:use #:cl)
 (:import-from #:rove #:deftest #:ok)
 (:import-from #:cl-spec/src/call-schema #:make-return-schema #:return-schema-mode
 #:return-schema-value)
 (:import-from #:cl-spec/src/call-validation)
 (:import-from #:cl-spec/src/ir #:tuple-spec-element-specs)
 (:import-from #:cl-spec/src/explain #:compile-node #:expected-descriptor)
 (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form))
(in-package #:cl-spec/tests/return-values-schema-test)
(defun return-declaration (form) (cl-spec/src/call-schema::normalize-return-declaration form))
(deftest fixed-values-preserve-count-and-identity
 (let* ((spec (return-declaration '(values integer string)))
        (schema (make-return-schema :primary-spec spec))
        (raw (list 1 "two"))
        (check (compile-node spec nil)))
   (ok (eq :values (return-schema-mode schema)))
   (ok (eq raw (return-schema-value schema raw)))
   (ok (null (funcall check raw nil)))
   (ok (eq :missing-values (getf (first (funcall check '(1) nil)) :kind)))
   (ok (eq :extra-values (getf (first (funcall check '(1 "two" 3) nil)) :kind)))
   (ok (equal '(:values (:type integer) (:type string)) (expected-descriptor spec)))
   (let ((error (first (funcall check '(1 2) nil))))
     (ok (equal '(1) (getf error :path)))
     (ok (equal '(1) (getf error :tuple-path))))))
(deftest zero-values-is-distinct-from-one-nil
 (let ((check (compile-node (return-declaration '(values)) nil)))
   (ok (null (funcall check nil nil)))
   (ok (eq :extra-values (getf (first (funcall check '(nil) nil)) :kind))))
 (let ((schema (make-return-schema :primary-spec (return-declaration 'integer))))
   (ok (eq :primary (return-schema-mode schema)))
   (ok (null (return-schema-value schema nil)))
   (ok (= 1 (return-schema-value schema '(1 2))))))
(deftest malformed-values-and-rollback
 (dolist (form '((values . integer) (values 42)))
   (ok (handler-case (progn (return-declaration form) nil)
         (invalid-function-spec-form () t))))
 (let ((cycle (list 'values))) (setf (cdr cycle) cycle)
   (ok (handler-case (progn (return-declaration cycle) nil)
         (invalid-function-spec-form () t))))
 (let* ((spec (return-declaration '(values integer)))
        (old (tuple-spec-element-specs spec)))
   (ok (handler-case (progn (reinitialize-instance spec :element-specs '(integer)) nil)
         (invalid-function-spec-form () t)))
   (ok (eq old (tuple-spec-element-specs spec)))))

(deftest fixed-values-constructor-refuses-malformed-elements
 (dolist (elements (list '(42) '(integer) '(nil) '(1 . 2)))
   (ok (handler-case
           (progn (make-instance 'cl-spec/src/call-schema:return-values-spec
                                  :element-specs elements) nil)
         (invalid-function-spec-form () t))))
 (let ((cycle (list (return-declaration 'integer))))
   (setf (cdr cycle) cycle)
   (ok (handler-case
           (progn (make-instance 'cl-spec/src/call-schema:return-values-spec
                                  :element-specs cycle) nil)
         (invalid-function-spec-form () t)))))

(deftest fixed-values-nested-position-and-count-identity
 (let* ((spec (return-declaration '(values integer (tuple integer string))))
        (check (compile-node spec nil))
        (error (first (funcall check '(1 (2 3)) nil))))
   (ok (equal '(1 1) (getf error :path)))
   (ok (equal '(1 1) (getf error :tuple-path)))
   (let ((zero (first (funcall check nil nil)))
         (one (first (funcall check '(1) nil))))
     (ok (eq (getf zero :kind) (getf one :kind)))
     (ok (= (getf zero :expected-length) (getf one :expected-length)))))
 (let ((cycle (list 1)))
   (setf (cdr cycle) cycle)
   (ok (eq :not-a-list
           (getf (first (funcall (compile-node (return-declaration '(values integer)) nil)
                                cycle nil)) :kind)))))

(deftest fixed-values-refuse-variable-arity-markers
 (dolist (marker (append lambda-list-keywords (list (make-symbol "&CUSTOM"))))
   (ok (handler-case
           (progn (return-declaration (list 'values marker 'integer)) nil)
         (invalid-function-spec-form () t)))))
