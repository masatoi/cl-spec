;;;; src/coverage-report.lisp
(defpackage #:cl-spec/src/coverage-report
  (:use #:cl)
  (:import-from #:cl-spec/src/property #:property-argument-schema)
  (:import-from #:cl-spec/src/ir #:spec-generator-name)
  (:import-from #:cl-spec/src/coverage
                #:definition-coverage-schema #:observe-coverage-dimension #:coverage-bindings #:coverage-identity #:copy-coverage-data
                #:backend-coverage-capabilities)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:export #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
           #:coverage-report-data #:call-with-coverage-trial #:coverage-capture-input
           #:coverage-mark-stage #:begin-coverage-report #:end-coverage-report #:validate-coverage-run
           #:coverage-enable-stage #:coverage-implicit-pre #:coverage-precondition-observed-p
           #:coverage-fixture-p #:coverage-context-schema
           #:coverage-context-options #:coverage-context-plan #:coverage-context-backend))
(in-package #:cl-spec/src/coverage-report)

(defvar *coverage-context* nil)
(defvar *coverage-trial* nil)
(defparameter +coverage-stages+ '(:generated :domain-valid :pre-admitted :target-observed :checked))

(defstruct coverage-context
  schema options backend capabilities rows owner (phase :new)
  (scope :single-run) (trials 0) (input-unavailable 0) (plan nil))

(defstruct coverage-trial owner hits stages captured-p)

(defgeneric coverage-fixture-p (definition)
  (:documentation "Whether ordinary inputs are recipes rather than live call arguments.")
  (:method ((definition t)) nil))

(defgeneric coverage-precondition-observed-p (definition)
  (:documentation "Whether the evaluator explicitly measures precondition admission.")
  (:method ((definition t)) nil))

(defun make-stage-row (stage generated-p)
  "Create a known-zero or inapplicable stage row."
  (list :stage stage :availability
        (if (and (eq stage :generated) (not generated-p)) :not-applicable
            (if (eq stage :domain-valid) :not-collected :collected))
        :observed-trials 0 :unknown-trials 0 :not-applicable-trials 0 :buckets nil))

(defun make-coverage-context-for (definition options registry scope backend generated-p)
  "Snapshot schema and allocate counters independent of trial count."
  (let* ((schema (definition-coverage-schema definition registry options))
         (capabilities
           (progn
             (when (or (coverage-fixture-p definition)
                       (spec-generator-name (property-argument-schema definition)))
               (dolist (d (getf schema :dimensions)) (setf (getf d :targetable) nil)))
             (backend-coverage-capabilities backend schema options)))
         (context (make-coverage-context :schema schema :options options :scope scope
                                         :backend backend :capabilities capabilities :owner definition
                                         :phase (if (eq scope :single-call) :open :new))))
    (setf (getf schema :subject) (coverage-identity definition registry)
          (coverage-context-schema context) schema)
    (setf (coverage-context-rows context)
          (loop for d in (getf schema :dimensions)
                collect
                (list :id (getf d :id) :kind (getf d :kind)
                      :stages
                      (loop for stage in +coverage-stages+
                            for row = (make-stage-row stage generated-p)
                            do (when (and (eq stage :pre-admitted)
                                          (not (coverage-precondition-observed-p definition)))
                                 (setf (getf row :availability) :not-collected))
                               (when (and (eq stage :domain-valid) (not generated-p))
                                 (setf (getf row :availability) :collected))
                            do (setf (getf row :buckets)
                                     (loop for bucket in (getf d :buckets)
                                           collect (list bucket 0)))
                            collect row))))
    context))

(defun begin-coverage-report (definition)
  "Open measured ordinary trials for the context's owning definition exactly once."
  (when *coverage-context*
    (unless (and (eq definition (coverage-context-owner *coverage-context*))
                 (eq :new (coverage-context-phase *coverage-context*)))
      (error 'invalid-backend-result :reason "coverage report begin has wrong owner or phase"))
    (setf (coverage-context-phase *coverage-context*) :open)))

(defun end-coverage-report (definition)
  "Close the backend's report, including zero-trial runs."
  (when *coverage-context*
    (unless (and (eq definition (coverage-context-owner *coverage-context*))
                 (eq :open (coverage-context-phase *coverage-context*)))
      (error 'invalid-backend-result :reason "coverage report end has wrong owner or phase"))
    (setf (coverage-context-phase *coverage-context*) :closed)))

(defun validate-coverage-run (context outcome)
  "Reject incomplete measurement and counts inconsistent with the ordinary run."
  (when context
    (unless (and (eq :closed (coverage-context-phase context))
                 (eql (getf outcome :trials) (coverage-context-trials context)))
      (error 'invalid-backend-result :reason "coverage report incomplete or trial counts disagree")))
  outcome)

(defun coverage-capture-input (definition arguments)
  "Freeze only bucket identities before application code can modify its inputs."
  (when (and *coverage-context* *coverage-trial*
             (not (coverage-trial-captured-p *coverage-trial*)))
    (let ((bindings (coverage-bindings definition arguments)))
      (setf (coverage-trial-hits *coverage-trial*)
            (loop for d in (getf (coverage-context-schema *coverage-context*) :dimensions)
                  collect (observe-coverage-dimension (getf d :kind) d bindings))
            (coverage-trial-captured-p *coverage-trial*) t))))

(defun coverage-enable-stage (stage)
  "Declare a checkpoint measured even when the run executes zero trials."
  (when *coverage-context*
    (dolist (row (coverage-context-rows *coverage-context*))
      (let ((entry (find stage (getf row :stages) :key (lambda (s) (getf s :stage)))))
        (unless entry (error 'invalid-backend-result :reason "unknown coverage stage"))
        (setf (getf entry :availability) :collected)))))

(defun coverage-mark-stage (stage)
  "Record an actual execution checkpoint for the active ordinary trial."
  (when *coverage-trial*
    (unless (and (eq (coverage-trial-owner *coverage-trial*) *coverage-context*)
                 (member stage +coverage-stages+)
                 (not (member stage (coverage-trial-stages *coverage-trial*))))
      (error 'invalid-backend-result :reason "invalid or duplicate coverage stage"))
    (push stage (coverage-trial-stages *coverage-trial*))))

(defun coverage-implicit-pre ()
  "An ordinary property admits an input only after an observed domain validation."
  (when (and *coverage-trial* (member :domain-valid (coverage-trial-stages *coverage-trial*)))
    (coverage-mark-stage :pre-admitted)))

(defun collect-coverage-trial (context trial)
  "Aggregate stage facts without retaining the trial or any application value."
  (incf (coverage-context-trials context))
  (unless (coverage-trial-captured-p trial)
    (incf (coverage-context-input-unavailable context)))
  (loop for row in (coverage-context-rows context)
        for remaining = (coverage-trial-hits trial) then (cdr remaining)
        for hits = (if (coverage-trial-captured-p trial) (car remaining) :unknown)
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
        (unless (and (eq :open (coverage-context-phase context))
                     (eq definition (coverage-context-owner context)))
          (error 'invalid-backend-result :reason "coverage trial has wrong owner or phase"))
        (unless (coverage-fixture-p definition)
          (coverage-capture-input definition arguments))
        (when generated (coverage-mark-stage :generated))
        (when domain-valid (coverage-mark-stage :domain-valid))
        (multiple-value-bind (observation status) (funcall function)
          (when (member status '(:passed :failed)) (coverage-mark-stage :checked))
          (collect-coverage-trial context *coverage-trial*)
          observation))))

(defun projected-coverage-rows (context)
  "Hide numeric counters for unmeasured or inapplicable stages."
  (let ((rows (copy-coverage-data (coverage-context-rows context))))
    (dolist (row rows)
      (dolist (stage (getf row :stages))
        (unless (eq :collected (getf stage :availability))
          (dolist (key '(:observed-trials :unknown-trials :not-applicable-trials :buckets))
            (remf stage key)))))
    rows))

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
             :dimensions (projected-coverage-rows context)
             :limitations '(:not-combinatorial :single-execution-only)))))
