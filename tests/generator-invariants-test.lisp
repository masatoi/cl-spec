;;;; tests/generator-invariants-test.lisp

(defpackage #:cl-spec/tests/generator-invariants-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator #:custom-generator-name #:custom-generator-function
                #:custom-generator-documentation #:custom-generator-source-form
                #:custom-generator-source-location #:register-generator
                #:invalid-generator-form #:invalid-generator-form-reason
                #:invalid-generator-form-form)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry))

(in-package #:cl-spec/tests/generator-invariants-test)

(defun generator-error-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (invalid-generator-form (condition)
      (and (keywordp (invalid-generator-form-reason condition))
           (progn (invalid-generator-form-form condition) t)))))

(deftest constructor-invariants
  (dolist (name '(nil t :generator 4))
    (ok (generator-error-p
         (lambda () (make-instance 'custom-generator :name name :function #'identity)))))
  (dolist (function '(nil identity 4))
    (ok (generator-error-p
         (lambda () (make-instance 'custom-generator :name 'sample :function function)))))
  (dolist (args '((:documentation 3) (:source-form wrong)
                  (:source-form (a . b)) (:source-location (:file))
                  (:source-location (file "test"))))
    (ok (generator-error-p
         (lambda () (apply #'make-instance 'custom-generator
                           :name 'sample :function (lambda () 1) args)))))
  (let ((cycle (list 'source)))
    (setf (cdr cycle) cycle)
    (ok (generator-error-p
         (lambda () (make-instance 'custom-generator :name 'sample
                                   :function (lambda () 1) :source-form cycle)))))
  (let ((captured 4))
    (ok (= 4 (funcall (custom-generator-function
                       (make-instance 'custom-generator :name 'sample
                                      :function (lambda () captured))))))))

(deftest nested-cyclic-source-is-rejected
  (let* ((cycle (list 'source))
         (source (list 'quote cycle)))
    (setf (car cycle) source)
    (ok (generator-error-p
         (lambda () (make-instance 'custom-generator :name 'sample
                                   :function (lambda () 1) :source-form source))))
    (ok (generator-error-p
         (lambda () (make-instance 'custom-generator :name 'sample
                                   :function (lambda () 1)
                                   :source-location (list :form source)))))))

(deftest reinitialization-is-atomic
  (let* ((function (lambda () 4))
         (generator (make-instance 'custom-generator :name 'sample :function function
                                   :documentation "before" :source-form '(defgenerator sample () 4)
                                   :source-location '(:file "before"))))
    (ok (generator-error-p
         (lambda () (reinitialize-instance generator :name :bad :documentation "after"
                                                     :source-location '(:file "after")))))
    (ok (eq 'sample (custom-generator-name generator)))
    (ok (eq function (custom-generator-function generator)))
    (ok (equal "before" (custom-generator-documentation generator)))
    (ok (equal '(:file "before") (custom-generator-source-location generator)))
    (ok (generator-error-p
         (lambda () (reinitialize-instance generator :function (lambda () 5)))))
    (ok (generator-error-p
         (lambda () (reinitialize-instance generator :source-form '(defgenerator sample () 5)))))
    (ok (eq function (custom-generator-function generator)))
    (ok (equal '(defgenerator sample () 4) (custom-generator-source-form generator)))
    (reinitialize-instance generator :function (lambda () 5) :source-form nil)
    (ok (= 5 (funcall (custom-generator-function generator))))
    (ok (null (custom-generator-source-form generator)))))

(deftest registration-revalidates-generator
  (let ((generator (make-instance 'custom-generator :name 'sample :function (lambda () 1))))
    (setf (slot-value generator 'cl-spec/src/generator-definition::function) nil)
    (ok (generator-error-p
         (lambda () (register-generator generator (make-hash-table-registry)))))))
