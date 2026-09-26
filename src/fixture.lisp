;;;; src/fixture.lisp
(defpackage #:cl-spec/src/fixture
  (:use #:cl)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots
                #:call-with-definition-rollback #:finite-definition-form-p)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/ir #:spec)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/schema #:definition-description)
  (:export #:trial-fixture #:fixture-recipe-name #:fixture-recipe-spec
           #:fixture-version #:fixture-isolation #:fixture-setup-function
           #:fixture-cleanup-function #:fixture-setup-forms #:fixture-cleanup-forms
           #:fixture-data #:fixture-error #:fixture-error-reason))
(in-package #:cl-spec/src/fixture)

(define-condition fixture-error (error)
  ((reason :initarg :reason :reader fixture-error-reason))
  (:documentation "An invalid fixture declaration or execution boundary.")
  (:report (lambda (condition stream)
             (format stream "Fixture error: ~A" (fixture-error-reason condition)))))

(defclass trial-fixture ()
  ((recipe-name :initarg :recipe-name :reader fixture-recipe-name)
   (recipe-spec :initarg :recipe-spec :reader fixture-recipe-spec)
   (version :initarg :version :reader fixture-version)
   (isolation :initarg :isolation :initform :fresh :reader fixture-isolation)
   (setup-function :initarg :setup-function :reader fixture-setup-function)
   (cleanup-function :initarg :cleanup-function :reader fixture-cleanup-function)
   (setup-forms :initarg :setup-forms :initform nil :reader fixture-setup-forms)
   (cleanup-forms :initarg :cleanup-forms :initform nil :reader fixture-cleanup-forms))
  (:documentation "A recipe schema and explicit fresh-state construction and cleanup hooks."))

(defmethod definition-validation-slots append ((fixture trial-fixture))
  '(recipe-name recipe-spec version isolation setup-function cleanup-function
    setup-forms cleanup-forms))

(defmethod shared-initialize :around ((fixture trial-fixture) slots &rest initargs)
  (declare (ignore slots))
  (flet ((supplied (key) (loop for (k) on initargs by #'cddr thereis (eq key k))))
    (call-with-definition-rollback
     fixture
     (lambda ()
       (dolist (pair '((:setup-forms :setup-function setup-forms)
                       (:cleanup-forms :cleanup-function cleanup-forms)))
         (destructuring-bind (forms-key function-key slot) pair
           (when (and (or (getf initargs forms-key)
                          (and (slot-boundp fixture slot) (slot-value fixture slot)))
                      (not (eq (not (supplied forms-key)) (not (supplied function-key)))))
             (error 'fixture-error :reason :hook-source-function-mismatch))))
       (when (and (supplied :recipe-name) (slot-boundp fixture 'recipe-name)
                  (not (eq (getf initargs :recipe-name) (fixture-recipe-name fixture)))
                  (not (every #'supplied '(:setup-forms :setup-function
                                           :cleanup-forms :cleanup-function))))
         (error 'fixture-error :reason :recipe-binding-change-requires-hooks))
       (prog1 (call-next-method) (validate-definition fixture))))))

(defmethod validate-definition ((fixture trial-fixture))
  (dolist (slot '(recipe-name recipe-spec version setup-function cleanup-function))
    (unless (slot-boundp fixture slot)
      (error 'fixture-error :reason :missing-slot)))
  (let ((name (fixture-recipe-name fixture)))
    (unless (and name (symbolp name) (not (keywordp name)) (not (constantp name))
                 (not (char= #\& (char (symbol-name name) 0))))
      (error 'fixture-error :reason :invalid-recipe-binding)))
  (unless (and (eq :fresh (fixture-isolation fixture))
               (typep (fixture-version fixture) '(integer 1 *))
               (functionp (fixture-setup-function fixture))
               (functionp (fixture-cleanup-function fixture)))
    (error 'fixture-error :reason :invalid-definition))
  (dolist (forms (list (fixture-setup-forms fixture) (fixture-cleanup-forms fixture)))
    (unless (and (finite-list-p forms) (finite-definition-form-p forms))
      (error 'fixture-error :reason :invalid-hook-forms)))
  (unless (typep (fixture-recipe-spec fixture) 'spec)
    (setf (slot-value fixture 'recipe-spec)
          (normalize-spec-form (fixture-recipe-spec fixture))))
  (validate-definition (fixture-recipe-spec fixture))
  fixture)

(defun fixture-data (fixture)
  "Return the fixture declaration without invoking its hooks."
  (list :isolation (fixture-isolation fixture)
        :version (fixture-version fixture)
        :recipe-name (fixture-recipe-name fixture)
        :setup (fixture-setup-forms fixture)
        :cleanup (fixture-cleanup-forms fixture)))

(defmethod definition-description ((fixture trial-fixture))
  (values (fixture-data fixture) (list (fixture-recipe-spec fixture)) nil
          (and (not (null (fixture-setup-forms fixture)))
               (not (null (fixture-cleanup-forms fixture))))))