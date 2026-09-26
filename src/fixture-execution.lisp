;;;; src/fixture-execution.lisp
(defpackage #:cl-spec/src/fixture-execution
  (:use #:cl)
  (:import-from #:cl-spec/src/fixture
                #:fixture-recipe-spec #:fixture-setup-function #:fixture-cleanup-function
                #:fixture-error)
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

(defun call-with-fixture (fixture recipe callback &key (registry *registry*))
  "Construct fresh call arguments, call CALLBACK once, and always attempt cleanup.
Return recipe, callback value and separate lifecycle evidence. CALLBACK may
propagate nonlocal exits; cleanup runs without converting them into success.
The callback owns call-schema validation and target outcome classification."
  (validate-definition fixture)
  (let ((setup-function (fixture-setup-function fixture))
        (cleanup-function (fixture-cleanup-function fixture))
        (saved nil) (working nil) (context (make-hash-table :test #'eq))
        (setup :not-started) (evaluation :not-started) (cleanup :not-started)
        (state :not-acquired) (value nil) (errors nil) (reason nil) (condition nil))
    (labels ((record-error (phase why error)
               (push (list :phase phase :reason why :condition-type (type-of error)
                           :condition-report (render-condition-report error))
                     errors)
               (setf reason why condition error))
             (result ()
               (list :recipe saved :value value :reason reason :condition condition
                     :lifecycle (list :setup setup :evaluation evaluation :cleanup cleanup
                                      :state state :errors (reverse errors)
                                      :completion (if reason :aborted :completed)))))
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
      (unwind-protect
           (let ((arguments nil))
             (setf setup :interrupted state :unknown)
             (handler-case
                 (setf arguments (funcall setup-function working context)
                       setup :completed)
               (error (error)
                 (setf setup :error)
                 (record-error :setup :fixture-setup-error error)))
             (when (and (not reason) (not (same-value-p saved working)))
               (record-error :recipe :fixture-recipe-mutation
                             (make-condition 'fixture-error :reason :recipe-mutation)))
             (unless reason
               (setf evaluation :interrupted)
               (setf value (funcall callback arguments)
                     evaluation :completed)))
        (setf cleanup :interrupted)
        (handler-case
            (progn (funcall cleanup-function working context)
                   (setf cleanup :completed state :released))
          (error (error)
            (setf cleanup :error state :unknown)
            (record-error :cleanup :fixture-cleanup-error error))))
      (when (not (same-value-p saved working))
        (unless reason
          (record-error :recipe :fixture-recipe-mutation
                        (make-condition 'fixture-error :reason :recipe-mutation))))
      (result))))