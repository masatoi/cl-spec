;;;; src/coverage-report.lisp
(defpackage #:cl-spec/src/coverage-report
  (:use #:cl)
  (:import-from #:cl-spec/src/property #:property-argument-schema)
  (:import-from #:cl-spec/src/ir #:spec-generator-name)
  (:import-from #:cl-spec/src/coverage
                #:definition-coverage-schema #:observe-coverage-dimension #:coverage-bindings
                #:coverage-identity #:copy-coverage-data
                #:backend-coverage-capabilities #:bounded-list-p)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:export #:deferred-coverage-p #:begin-core-coverage-report #:collect-deferred-coverage-trial
           #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
           #:coverage-report-data #:call-with-coverage-trial #:coverage-capture-input
           #:coverage-note-unavailable-input #:coverage-mark-stage
           #:begin-coverage-report #:end-coverage-report #:validate-coverage-run
           #:coverage-enable-stage #:coverage-implicit-pre #:coverage-precondition-observed-p
           #:coverage-fixture-p #:coverage-context-schema
           #:coverage-context-options #:coverage-context-plan #:coverage-context-backend))
(in-package #:cl-spec/src/coverage-report)

(defvar *coverage-context* nil)
(defvar *coverage-trial* nil)
(defparameter +coverage-stages+ '(:generated :domain-valid :pre-admitted :target-observed :checked))

(defstruct coverage-context
  schema options backend capabilities rows owner deferred (phase :new)
  (scope :single-run) (trials 0) (input-unavailable 0) (plan nil)
  (unavailable-reasons (list :recipe 0 :setup 0 :argument-binding 0 :unknown 0)))

(defstruct coverage-trial owner hits stages captured-p reported-p (unavailable-reason :unknown))

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

(defun make-coverage-context-for (definition options registry scope backend generated-p
                                   &key deferred)
  "Snapshot schema and allocate counters independent of trial count."
  (let* ((schema (definition-coverage-schema definition registry options))
         (capabilities
           (progn
             (when (or (coverage-fixture-p definition)
                       (spec-generator-name (property-argument-schema definition)))
               (dolist (d (getf schema :dimensions)) (setf (getf d :targetable) nil)))
             (backend-coverage-capabilities backend schema options)))
         (context (make-coverage-context :schema schema :options options :scope scope
                                         :backend backend :capabilities capabilities
                                         :owner definition
                                         :deferred deferred
                                         :phase (if (or deferred (eq scope :single-call)) :open :new))))
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
                            do (when deferred (setf (getf row :availability)
                                                   (if (and (eq stage :generated) (not generated-p))
                                                       :not-applicable :not-collected)))
                               (setf (getf row :buckets)
                                     (loop for bucket in (getf d :buckets)
                                           collect (list bucket 0)))
                            collect row))))
    context))

(defun deferred-coverage-p ()
  "Whether legacy backend observations wait for an explicit ordinary-trial report."
  (and *coverage-context* (coverage-context-deferred *coverage-context*)))

(defun begin-core-coverage-report (definition)
  "Declare only checkpoints measured by core for a legacy backend's ordinary trials."
  (when (deferred-coverage-p)
    (unless (eq definition (coverage-context-owner *coverage-context*))
      (error 'invalid-backend-result :reason "foreign core coverage report"))
    (coverage-enable-stage :target-observed)
    (coverage-enable-stage :checked)
    (when (coverage-precondition-observed-p definition)
      (coverage-enable-stage :pre-admitted))
    (when (coverage-fixture-p definition)
      (coverage-enable-stage :domain-valid))))

(defun begin-coverage-report (definition)
  "Open measured ordinary trials for the context's owning definition exactly once."
  (when (and *coverage-context* (not (deferred-coverage-p)))
    (unless (and (eq definition (coverage-context-owner *coverage-context*))
                 (eq :new (coverage-context-phase *coverage-context*)))
      (error 'invalid-backend-result :reason "coverage report begin has wrong owner or phase"))
    (setf (coverage-context-phase *coverage-context*) :open)))

(defun end-coverage-report (definition)
  "Close the backend's report, including zero-trial runs."
  (when (and *coverage-context* (not (deferred-coverage-p)))
    (unless (and (eq definition (coverage-context-owner *coverage-context*))
                 (eq :open (coverage-context-phase *coverage-context*)))
      (error 'invalid-backend-result :reason "coverage report end has wrong owner or phase"))
    (setf (coverage-context-phase *coverage-context*) :closed)))

(defun validate-coverage-run (context outcome)
  "Reject contradictory counts; legacy backends may leave ordinary trials unreported."
  (when context
    (if (coverage-context-deferred context)
        (progn
          (when (> (coverage-context-trials context) (getf outcome :trials))
            (error 'invalid-backend-result :reason "too many core coverage trials"))
          (setf (coverage-context-phase context)
                (if (= (coverage-context-trials context) (getf outcome :trials))
                    :closed :partial)))
        (unless (and (eq :closed (coverage-context-phase context))
                     (eql (getf outcome :trials) (coverage-context-trials context)))
          (error 'invalid-backend-result
                 :reason "coverage report incomplete or trial counts disagree"))))
  outcome)

(defun coverage-note-unavailable-input (phase)
  "Record known fixture failure phase only when its call input was not captured."
  (when (and *coverage-trial* (not (coverage-trial-captured-p *coverage-trial*)))
    (setf (coverage-trial-unavailable-reason *coverage-trial*)
          (case phase (:recipe :recipe) (:setup :setup)
                      (:arguments :argument-binding) (otherwise :unknown)))))

(defun coverage-capture-input (definition arguments)
  "Freeze only bucket identities before application code can modify its inputs."
  (when (and *coverage-context* *coverage-trial*
             (not (coverage-trial-captured-p *coverage-trial*)))
    (multiple-value-bind (bindings unavailable) (coverage-bindings definition arguments)
      (when unavailable
        (setf (coverage-trial-unavailable-reason *coverage-trial*) :argument-binding))
      (unless unavailable
        (setf (coverage-trial-hits *coverage-trial*)
              (loop for d in (getf (coverage-context-schema *coverage-context*) :dimensions)
                    collect (observe-coverage-dimension (getf d :kind) d bindings))
              (coverage-trial-captured-p *coverage-trial*) t)))))

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

(defun validate-coverage-hits (context trial)
  "Reject malformed or duplicate bucket evidence before changing any counter."
  (let ((dimensions (getf (coverage-context-schema context) :dimensions))
        (hits (coverage-trial-hits trial)))
    (when (coverage-trial-captured-p trial)
      (unless (and (bounded-list-p hits (length dimensions))
                   (= (length hits) (length dimensions)))
        (error 'invalid-backend-result :reason "coverage dimensions disagree"))
      (loop for dimension in dimensions for buckets in hits
            for declared = (getf dimension :buckets)
            do (unless (or (member buckets '(:unknown :not-applicable))
                           (and (bounded-list-p buckets (length declared))
                                (= (length buckets)
                                   (length (remove-duplicates buckets :test #'equal)))
                                (every (lambda (bucket) (member bucket declared :test #'equal))
                                       buckets)))
                 (error 'invalid-backend-result :reason "invalid or duplicate coverage bucket"))))))

(defun collect-coverage-trial (context trial)
  "Aggregate stage facts without retaining the trial or any application value."
  (when (or (not (eq context (coverage-trial-owner trial)))
            (coverage-trial-reported-p trial))
    (error 'invalid-backend-result :reason "duplicate or foreign coverage trial"))
  (validate-coverage-hits context trial)
  (setf (coverage-trial-reported-p trial) t)
  (incf (coverage-context-trials context))
  (unless (coverage-trial-captured-p trial)
    (incf (coverage-context-input-unavailable context))
    (incf (getf (coverage-context-unavailable-reasons context)
                (coverage-trial-unavailable-reason trial))))
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

(defun collect-deferred-coverage-trial (trial)
  "Commit a legacy observation only when reported as an ordinary trial."
  (when (and trial (deferred-coverage-p))
    (collect-coverage-trial *coverage-context* trial)))

(defun call-with-coverage-trial (definition arguments function &key generated domain-valid defer)
  "Call FUNCTION once; it returns observation and final status as two values."
  (if (null *coverage-context*) (funcall function)
      (let* ((context *coverage-context*)
             (*coverage-trial* (make-coverage-trial :owner context
                            :unavailable-reason :unknown)))
        (unless (and (eq :open (coverage-context-phase context))
                     (eq definition (coverage-context-owner context)))
          (error 'invalid-backend-result :reason "coverage trial has wrong owner or phase"))
        (unless (coverage-fixture-p definition)
          (coverage-capture-input definition arguments))
        (when generated (coverage-mark-stage :generated))
        (when domain-valid (coverage-mark-stage :domain-valid))
        (multiple-value-bind (observation status) (funcall function)
          (when (member status '(:passed :failed)) (coverage-mark-stage :checked))
          (if defer
              (values observation *coverage-trial*)
              (progn (collect-coverage-trial context *coverage-trial*) observation))))))

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
             :scope (coverage-context-scope context)
             :collection (if (eq :partial (coverage-context-phase context)) :partial :complete)
             :schema (coverage-context-schema context)
             :capabilities (coverage-context-capabilities context)
             :options (coverage-context-options context)
             :plan (coverage-context-plan context)
             :trials (coverage-context-trials context)
             :input-unavailable (coverage-context-input-unavailable context)
             :input-unavailable-reasons (coverage-context-unavailable-reasons context)
             :dimensions (projected-coverage-rows context)
             :limitations '(:not-combinatorial :single-execution-only)))))
