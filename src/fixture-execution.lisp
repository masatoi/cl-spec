;;;; src/fixture-execution.lisp
(defpackage #:cl-spec/src/fixture-execution
  (:use #:cl)
  (:import-from #:cl-spec/src/time-limits #:mark-run-phase
                #:call-with-timed-fixture-cleanup)
  (:import-from #:cl-spec/src/fixture
                #:fixture-recipe-spec #:fixture-setup-function #:fixture-cleanup-function
                #:fixture-isolation #:fixture-around-function #:fixture-error)
  (:import-from #:cl-spec/src/definition-validation #:validate-definition)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/execution #:same-value-p #:render-condition-report)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:serialize-artifact-value #:deserialize-artifact-value)
  (:export #:call-with-fixture #:copy-recipe))
(in-package #:cl-spec/src/fixture-execution)

(defun copy-recipe (recipe)
  "Copy a bounded, reader-free recipe, refusing opaque, shared and cyclic values."
  (deserialize-artifact-value (serialize-artifact-value recipe)))

(defvar *fixture-around-tokens* nil
  "Identities of one-shot trial thunks whose wrapper extents are active.")

(defun invoke-fixture-around (around trial)
  "Run AROUND with a synchronous one-shot TRIAL, returning any lifecycle error."
  (let* ((token (list nil))
         (*fixture-around-tokens* (cons token *fixture-around-tokens*))
         (called nil)
         (completed nil)
         (repeated nil)
         (wrapper-error nil))
    ;; Transfers past the wrapper belong to their original destination.
    (handler-case
        (funcall around
                 (lambda ()
                   (unless (member token *fixture-around-tokens* :test #'eq)
                     (error 'fixture-error :reason :thunk-outside-around))
                   (when called
                     (setf repeated (make-condition 'fixture-error :reason :thunk-repeated))
                     (error repeated))
                   (setf called t)
                   (multiple-value-prog1 (funcall trial)
                     (setf completed t))))
      (error (condition) (setf wrapper-error condition)))
    (cond
      (repeated (values :fixture-around-thunk-repeated repeated))
      (wrapper-error (values :fixture-around-error wrapper-error))
      ((not called)
       (values :fixture-around-thunk-not-called
               (make-condition 'fixture-error :reason :thunk-not-called)))
      ((not completed)
       (values :fixture-around-nonlocal-exit
               (make-condition 'fixture-error :reason :around-nonlocal-exit))))))

(defun call-with-fixture (fixture recipe callback &key (registry *registry*))
  "Construct call arguments, call CALLBACK once, and always attempt cleanup.
Return recipe, callback value and separate lifecycle evidence. When a wrapper
is declared, construction, evaluation and cleanup all run within its extent.
The callback owns call-schema validation and target outcome classification."
  (validate-definition fixture)
  (let ((setup-function (fixture-setup-function fixture))
        (cleanup-function (fixture-cleanup-function fixture))
        (around-function (fixture-around-function fixture))
        (isolation (fixture-isolation fixture))
        (saved nil) (working nil) (context (make-hash-table :test #'eq))
        (setup :not-started) (evaluation :not-started) (cleanup :not-started)
        (around :not-started)
        (state :not-acquired) (value nil) (errors nil) (reason nil) (condition nil))
    (labels ((record-error (phase why error)
               (push (list :phase phase :reason why :condition-type (type-of error)
                           :condition-report (render-condition-report error))
                     errors)
               (setf reason why condition error))
             (result ()
               (list :recipe saved :value value :reason reason :condition condition
                     :lifecycle (append (list :setup setup :evaluation evaluation :cleanup cleanup
                                              :state state :errors (reverse errors)
                                              :completion (if reason :aborted :completed)
                                              :isolation isolation)
                                        (when around-function (list :around around)))))
             (check-recipe-mutation ()
               (unless (or reason (same-value-p saved working))
                 (record-error :recipe :fixture-recipe-mutation
                               (make-condition 'fixture-error :reason :recipe-mutation))))
             (run-trial ()
               (call-with-timed-fixture-cleanup
                (lambda ()
                  (mark-run-phase :fixture-setup)
                  (let ((arguments nil))
                    (setf setup :interrupted state :unknown)
                    (handler-case
                        (setf arguments (funcall setup-function working context)
                              setup :completed)
                      (error (error)
                        (setf setup :error)
                        (record-error :setup :fixture-setup-error error)))
                    (check-recipe-mutation)
                    (unless reason
                      (setf evaluation :interrupted)
                      (setf value (funcall callback arguments)
                            evaluation :completed))))
                (lambda ()
                  (setf cleanup :interrupted)
                  (handler-case
                      (progn (funcall cleanup-function working context)
                             (setf cleanup :completed state :released))
                    (error (error)
                      (setf cleanup :error state :unknown)
                      (record-error :cleanup :fixture-cleanup-error error)))
                  cleanup))
               (mark-run-phase :fixture-around)))
      (mark-run-phase :fixture-recipe)
      (handler-case
          (progn
            (setf saved (copy-recipe recipe) working (copy-recipe recipe))
            (unless (validp (fixture-recipe-spec fixture) working :registry registry)
              (error 'fixture-error :reason :recipe-schema))
            (unless (same-value-p saved working)
              (error 'fixture-error :reason :recipe-validation-mutation)))
        (error (error)
          (record-error :recipe :fixture-recipe-invalid error)
          (return-from call-with-fixture (result))))
      (if around-function
          (multiple-value-bind (why error)
              (progn (mark-run-phase :fixture-around)
                     (invoke-fixture-around around-function #'run-trial))
            (if why
                (progn
                  (setf around :error state :unknown)
                  (record-error :around why error))
                (setf around :completed)))
          (run-trial))
      (check-recipe-mutation)
      (result))))
