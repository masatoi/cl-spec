;;;; tests/function-invariants-test.lisp
(defpackage #:cl-spec/tests/function-invariants-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:register-function-spec)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry #:find-function-spec))
(in-package #:cl-spec/tests/function-invariants-test)

(defun refused-p (thunk)
  (handler-case (progn (funcall thunk) nil) (error () t)))

(deftest function-object-invariants
  (dolist (args '((:name nil) (:name t) (:name :keyword) (:name sample :argument-specs ((t integer)))
                  (:name sample :preconditions (t) :precondition-function 5)
                  (:name sample :metadata (:shrink))
                  (:name sample :documentation 42)))
    (ok (refused-p (lambda () (apply #'make-instance 'function-spec args))))))

(deftest adapter-refused-update-restores-own-slots
  (let* ((contract (make-instance 'function-spec :name 'identity :return-spec 'integer))
         (adapter (cl-spec/src/function-spec:make-function-check-property contract))
         (target (slot-value adapter 'cl-spec/src/function-spec::target)))
    (ok (refused-p (lambda () (reinitialize-instance adapter :target nil))))
    (ok (eq target (slot-value adapter 'cl-spec/src/function-spec::target)))))

(deftest registration-refuses-before-replacement
  (let ((registry (make-hash-table-registry))
         (old (make-instance 'function-spec :name 'sample :return-spec 'integer))
         (new (make-instance 'function-spec :name 'sample :return-spec 'string)))
    (register-function-spec old registry)
    (setf (slot-value new 'cl-spec/src/function-spec::preconditions) '(t))
    (ok (refused-p (lambda () (register-function-spec new registry))))
    (ok (eq old (find-function-spec 'sample registry)))))

(deftest malformed-argument-spines
  (let ((cycle (list '(x integer))))
    (setf (cdr cycle) cycle)
    (ok (refused-p (lambda () (make-instance 'function-spec :name 'sample
                                                          :argument-specs cycle)))))
  (ok (refused-p (lambda () (make-instance 'function-spec :name 'sample
                                                        :argument-specs '((x . integer)))))))
