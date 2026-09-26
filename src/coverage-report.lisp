;;;; src/coverage-report.lisp
(defpackage #:cl-spec/src/coverage-report
  (:use #:cl)
  (:import-from #:cl-spec/src/coverage
                #:coverage-inputs #:coverage-bindings #:copy-coverage-data
                #:backend-coverage-capabilities)
  (:import-from #:cl-spec/src/coverage-plist #:plist-coverage-schema #:observe-dimension)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:export #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
           #:coverage-report-data #:call-with-coverage-trial #:coverage-capture-input
           #:coverage-mark-stage #:coverage-fixture-p #:coverage-context-schema
           #:coverage-context-options #:coverage-context-plan #:coverage-context-backend))
(in-package #:cl-spec/src/coverage-report)

(defvar *coverage-context* nil)
(defvar *coverage-trial* nil)
(defparameter +coverage-stages+ '(:generated :domain-valid :pre-admitted :target-observed :checked))

(defstruct coverage-context
  schema options backend capabilities rows
  (scope :single-run) (trials 0) (input-unavailable 0) (plan nil))

(defstruct coverage-trial owner hits stages captured-p)

(defgeneric coverage-fixture-p (definition)
  (:documentation "Whether ordinary inputs are recipes rather than live call arguments.")
  (:method ((definition t)) nil))

(defun make-stage-row (stage generated-p)
  "Create a known-zero or inapplicable stage row."
  (list :stage stage :availability
        (if (and (eq stage :generated) (not generated-p)) :not-applicable
            (if (eq stage :domain-valid) :not-collected :collected))
        :observed-trials 0 :unknown-trials 0 :not-applicable-trials 0 :buckets nil))

(defun make-coverage-context-for (definition options registry scope backend generated-p)
  "Snapshot schema and allocate counters independent of trial count."
  (let* ((schema (plist-coverage-schema (coverage-inputs definition) registry
                                       (getf options :dimension-limit)
                                       (getf options :depth-limit)))
         (capabilities (backend-coverage-capabilities backend schema options))
         (context (make-coverage-context :schema schema :options options :scope scope
                                         :backend backend :capabilities capabilities)))
    (setf (coverage-context-rows context)
          (loop for d in (getf schema :dimensions)
                collect
                (list :id (getf d :id) :kind (getf d :kind)
                      :stages
                      (loop for stage in +coverage-stages+
                            for row = (make-stage-row stage generated-p)
                            do (setf (getf row :buckets)
                                     (loop for bucket in (getf d :buckets)
                                           collect (list bucket 0)))
                            collect row))))
    context))

(defun coverage-capture-input (definition arguments)
  "Freeze only bucket identities before application code can modify its inputs."
  (when (and *coverage-context* *coverage-trial*
             (not (coverage-trial-captured-p *coverage-trial*)))
    (let ((bindings (coverage-bindings definition arguments)))
      (setf (coverage-trial-hits *coverage-trial*)
            (loop for d in (getf (coverage-context-schema *coverage-context*) :dimensions)
                  collect (observe-dimension d bindings))
            (coverage-trial-captured-p *coverage-trial*) t))))

(defun coverage-mark-stage (stage)
  "Record an actual execution checkpoint for the active ordinary trial."
  (when *coverage-trial*
    (unless (and (eq (coverage-trial-owner *coverage-trial*) *coverage-context*)
                 (member stage +coverage-stages+)
                 (not (member stage (coverage-trial-stages *coverage-trial*))))
      (error 'invalid-backend-result :reason "invalid or duplicate coverage stage"))
    (push stage (coverage-trial-stages *coverage-trial*))))

(defun collect-coverage-trial (context trial)
  "Aggregate stage facts without retaining the trial or any application value."
  (incf (coverage-context-trials context))
  (unless (coverage-trial-captured-p trial)
    (incf (coverage-context-input-unavailable context)))
  (loop for row in (coverage-context-rows context)
        for index from 0
        for hits = (if (coverage-trial-captured-p trial)
                       (nth index (coverage-trial-hits trial)) :unknown)
        do (dolist (stage (coverage-trial-stages trial))
             (let ((entry (find stage (getf row :stages)
                                :key (lambda (r) (getf r :stage)))))
               (setf (getf entry :availability) :collected)
               (case hits
                 (:unknown (incf (getf entry :unknown-trials)))
                 (:not-applicable (incf (getf entry :not-applicable-trials)))
                 (otherwise
                  (incf (getf entry :observed-trials))
                  (dolist (hit hits)
                    (let ((cell (assoc hit (getf entry :buckets))))
                      (unless cell
                        (error 'invalid-backend-result :reason "undeclared coverage bucket"))
                      (incf (second cell))))))))))

(defun call-with-coverage-trial (definition arguments function &key generated domain-valid)
  "Call FUNCTION once; it returns observation and final status as two values."
  (if (null *coverage-context*) (funcall function)
      (let* ((context *coverage-context*)
             (*coverage-trial* (make-coverage-trial :owner context)))
        (unless (coverage-fixture-p definition)
          (coverage-capture-input definition arguments))
        (when generated (coverage-mark-stage :generated))
        (when domain-valid (coverage-mark-stage :domain-valid))
        (multiple-value-bind (observation status) (funcall function)
          (when (member status '(:passed :failed)) (coverage-mark-stage :checked))
          (collect-coverage-trial context *coverage-trial*)
          observation))))

(defun coverage-report-data (context &optional (reason :disabled))
  "Return independent saved report data, or an explicit missing-measurement record."
  (if (null context) (list :availability :not-collected :reason reason)
      (copy-coverage-data
       (list :schema-version 1 :record-kind :coverage-report
             :scope (coverage-context-scope context) :collection :complete
             :schema (coverage-context-schema context)
             :capabilities (coverage-context-capabilities context)
             :options (coverage-context-options context)
             :plan (coverage-context-plan context)
             :trials (coverage-context-trials context)
             :input-unavailable (coverage-context-input-unavailable context)
             :dimensions (coverage-context-rows context)
             :limitations '(:not-combinatorial :single-execution-only)))))
