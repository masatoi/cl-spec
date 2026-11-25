;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/time-limits
                #:call-with-run-time-limits #:call-with-run-limit-handoff
                #:call-catching-run-timeout #:call-with-run-finalization
                #:run-clock-start #:with-run-phase)
  (:export #:preparation-timeout-initargs)
  (:import-from #:cl-spec/src/property #:property-arguments)
  (:import-from #:cl-spec/src/coverage #:coverage-inputs #:coverage-bindings #:coverage-identity #:coverage-identity-from-metadata #:coverage-data #:copy-coverage-data
                #:normalize-coverage-options #:backend-coverage-protocol
                #:unsupported-coverage-operation)
  (:import-from #:cl-spec/src/coverage-report
                #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
                #:coverage-report-data #:coverage-fixture-p #:validate-coverage-run)
  (:import-from #:cl-spec/src/evidence
                #:evidence-facts #:evidence-summary #:evidence-subject #:evidence-declared-cases)
  (:export #:property-result-trial-report #:property-result-declared-cases)
  (:import-from #:cl-spec/src/schema #:definition-fixture-metadata)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-lifecycle #:trial-observation-call-evidence #:same-value-p)
  (:export #:property-result-run-error #:prepare-property-run
           #:run-property-with-result-constructor)
  (:import-from #:cl-spec/src/schema #:definition-metadata
                #:definition-state-constraints)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-named-arguments
                #:property-trials
                #:+trial-profiles+)
  (:import-from #:cl-spec/src/conditions
                #:invalid-backend-result
                #:invalid-argument
                #:unsupported-stateful-operation)
  (:import-from #:cl-spec/src/utils/arguments
                #:check-argument #:check-keyword-arguments #:check-run-options)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-outcome #:snapshot-value #:trial-observation-condition-report #:trial-observation-value
                #:trial-observation-status #:trial-observation-case
                #:trial-observation-arguments #:trial-observation-condition
                #:trial-observation-reason #:trial-observation-signature
                #:trial-observation-explanation #:trial-observation-state)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:check-registry)
  (:import-from #:cl-spec/src/resolve
                #:resolve-property)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:run-generated-test
                #:backend-default-trials)
  (:import-from #:cl-spec/src/utils/random
                #:make-seed
                #:seed->random-state)
  (:export #:property-result-shrink-report #:property-result-options #:property-result-provenance
           #:result-data #:observation-data
           #:property-result-schema-metadata #:property-result-budget
           #:property-result-generation-report #:property-result-failure-phase
           #:property-result-entity-kind
           #:check-replayed-result
           #:property-result-case-report
           #:property-result-failure-evidence #:property-result-shrunk-evidence
           #:property-result-shrunk-outcome #:property-result-rejected
           #:property-result-failure-reason #:property-result-failure-signature
           #:property-result-explanation
           #:property-result
           #:property-result-status
           #:property-result-property
           #:property-result-trials
           #:property-result-seed
           #:property-result-profile
           #:property-result-counterexample
           #:property-result-shrunk-counterexample
           #:property-result-condition
           #:property-result-elapsed
           #:run-property
           #:run-properties
           #:replay-property))

(in-package #:cl-spec/src/property-runner)

(defclass property-result ()
  ((coverage :initarg :coverage :initform '(:availability :not-collected :reason :legacy-result)
              :reader property-result-coverage)
   (trial-report :initarg :trial-report :initform :not-collected
                  :reader property-result-trial-report
                  :documentation "Saved normal-trial measurements, or :NOT-COLLECTED.")
   (declared-cases :initarg :declared-cases :initform :not-collected
                   :reader property-result-declared-cases
                   :documentation "Declared case names at execution start, NIL or :NOT-COLLECTED.")
   (timeout :initarg :timeout :initform nil :reader property-result-timeout
            :documentation "Owned run, trial or cleanup deadline evidence, when timed out.")
   (run-error :initarg :run-error :initform nil :reader property-result-run-error
              :documentation "Lifecycle failure retained separately from counterexamples.")
   (shrink-report :initarg :shrink-report :initform :not-collected
                  :reader property-result-shrink-report
                  :documentation "Candidate count, budget and termination captured by the backend.")
   (generation-report :initarg :generation-report :initform :not-collected
                      :reader property-result-generation-report
                      :documentation "Bounded-filter generation report captured by the backend,
or :NOT-COLLECTED when the backend did not collect one.")
   (failure-phase :initarg :failure-phase :initform nil
                  :reader property-result-failure-phase
                  :documentation
                  "The backend phase when a generation budget or deadline was exhausted.")
   (stored-failure-reason :initarg :failure-reason :initform nil
                          :reader property-result-stored-failure-reason
                          :documentation "Failure reason for a result with no target observation,
such as the generation-only error branch.")
   (options :initarg :options :initform nil :reader property-result-options
            :documentation "Caller options captured before backend execution.")
   (provenance :initarg :provenance
               :initform (list :backend :unknown :lisp-implementation-type :unknown
                               :lisp-implementation-version :unknown
                               :cl-spec-version :unknown :target-revision :unknown
                                :collection-states
                                (list :backend :not-collected
                                      :lisp-implementation-type :not-collected
                                      :lisp-implementation-version :not-collected
                                      :cl-spec-version :not-collected
                                      :target-revision :not-collected))
               :reader property-result-provenance
               :documentation "Run environment captured before execution; unknown fields are explicit.")
   (schema-metadata :initarg :schema-metadata :initform nil
                    :reader property-result-schema-metadata
                    :documentation "Definition metadata captured before the run, or NIL.")
   (trial-budget :initarg :budget :initform nil :reader property-result-budget
                 :documentation "Resolved trial budget, or NIL on a manually built result.")
   (failure-evidence :initarg :failure-evidence :initform nil
                     :reader property-result-failure-evidence
                     :documentation "Observation from the original failing trial.")
   (shrunk-evidence :initarg :shrunk-evidence :initform nil
                    :reader property-result-shrunk-evidence
                    :documentation "Observed accepted shrink, or NIL.")
   (shrunk-outcome :initarg :shrunk-outcome :initform nil
                   :reader property-result-shrunk-outcome
                   :documentation ":USED, :NONE or :DIFFERENT-FAILURE on a failure, else NIL.")
   (rejected :initarg :rejected :initform 0 :reader property-result-rejected
             :documentation "Generated trials refused before invoking a function target.")
   (status :initarg :status
           :initform :pending
           :reader property-result-status
           :documentation "One of :PASSED, :FAILED, :ERROR, :SKIPPED, :TIMEOUT or :PENDING.")
   (property :initarg :property
             :initform nil
             :reader property-result-property
             :documentation "Name of the property that was run.")
   (trials :initarg :trials
           :initform (error 'invalid-backend-result :reason "result requires :trials")
           :reader property-result-trials
           :documentation "Number of trials actually executed.")
   (seed :initarg :seed
         :initform nil
         :reader property-result-seed
         :documentation "Random seed the run started from, for replay.")
   (profile :initarg :profile
            :initform nil
            :reader property-result-profile
            :documentation "Effective profile the run resolved its trial count from.
TRIALS records only the trial the run stopped at, not the budget it was
allowed, and that budget cannot be recovered from it -- REPLAY-PROPERTY needs
this slot to reproduce a run faithfully when it is handed the result instead
of the bare seed.")
   (counterexample :initarg :counterexample
                   :initform nil
                   :reader property-result-counterexample
                   :documentation "Arguments of the first failing trial.")
   (shrunk-counterexample :initarg :shrunk-counterexample
                          :initform nil
                          :reader property-result-shrunk-counterexample
                          :documentation "Observed failing arguments accepted during shrinking.
The failure identity matches the original trial. This is not a proof of global
minimality; NIL means no observed reduction was accepted.")
   (signalled-condition :initarg :condition
                        :initform nil
                        :reader property-result-condition
                        :documentation "Condition signalled by the property
body, or NIL.")
   (elapsed :initarg :elapsed
            :initform nil
            :reader property-result-elapsed
            :documentation "Wall clock seconds the run took, or NIL."))
  (:documentation "Structured outcome of running one property.

A property run is never reported as a bare boolean: the seed, the trial count
and the shrunk counterexample are what make a failure actionable."))

(defmethod coverage-data ((result property-result))
  (copy-coverage-data (property-result-coverage result)))

(defmethod initialize-instance :after ((result property-result) &key)
  "Require an explicit, nonnegative executed-trial count."
  (unless (and (integerp (property-result-trials result))
               (not (minusp (property-result-trials result))))
    (error 'invalid-backend-result :reason "result :trials must be a nonnegative integer")))

;; The designator is declared T and checked in the body, so a bad one is refused
;; as an INVALID-ARGUMENT rather than by the compiler's own type check (#79).
(declaim (ftype (function (t
                           &key (:profile t) (:seed t) (:options t) (:registry t)
                           &allow-other-keys)
                          (values property-result &optional))
                run-property))

(defgeneric property-result-entity-kind (result)
  (:documentation "Return :PROPERTY or :FUNCTION-SPEC, independently of author classification."))

(defmethod property-result-entity-kind ((result property-result))
  :property)

(defgeneric property-result-case-report (result)
  (:documentation "Return RESULT's per-case run report, or :NOT-COLLECTED.

Only a function-check run with named cases has one; a property run and a manually
built result answer :NOT-COLLECTED rather than measured zeros for counters
nothing kept.  The public reader for the report is
FUNCTION-CHECK-RESULT-CASE-REPORT, which keeps the PROPERTY-RESULT /
FUNCTION-CHECK-RESULT reader split.")
  (:method ((result property-result))
    (declare (ignore result))
    :not-collected))

(defun selected-evidence (result)
  "Return the observation that RESULT puts forward."
  (or (property-result-shrunk-evidence result)
      (property-result-failure-evidence result)))

(defun selected-evidence-reason (stored-reason evidence)
  "Return STORED-REASON, or the reason in selected EVIDENCE."
  (or stored-reason (and evidence (trial-observation-reason evidence))))

(defun selected-evidence-explanation (evidence)
  "Return the public explanation captured in selected EVIDENCE."
  (when (and evidence (member (trial-observation-reason evidence)
                              '(:return-spec :condition-spec :missing-condition
                                :contract-error :state-postcondition :observation-mismatch
                                :invariant-violation :machine-error)))
    (trial-observation-explanation evidence)))

(defun property-result-failure-reason (result)
  "Return the selected observation's reason, a stored generation reason, or NIL."
  (or (property-result-stored-failure-reason result)
      (selected-evidence-reason nil (selected-evidence result))))

(defun property-result-failure-signature (result)
  "Return the selected observation's failure identity, or NIL on success."
  (let ((evidence (selected-evidence result)))
    (when evidence (trial-observation-signature evidence))))

(defun property-result-explanation (result)
  "Return the selected failure explanation; internal post-form tags are excluded.

:CONTRACT-ERROR is included because a function-spec case-selection error records
its structured explanation there, and :STATE-POSTCONDITION because a violated
:state-post records the case, form position and source.  A contract-side error
that records no explanation still reads NIL, so the projection of existing
contract errors does not change."
  (selected-evidence-explanation (selected-evidence result)))

(defun observation-data (observation)
  "Project captured trial evidence as Lisp data rather than a structure object.

:STATE is present when the contract declared :CAPTURE, :STATE-POST or :MODIFIES and
the evaluator reported state evidence; a featureless failure omits it, so its
projection is unchanged.  The state plist says whether capture ran to completion
and whether state-post was not evaluated (with a reason), passed, was violated or
itself signalled.  Each completed capture binding is a per-binding record
\(:NAME NAME :AVAILABILITY :COLLECTED :VALUE VALUE) or
\(:NAME NAME :AVAILABILITY :UNAVAILABLE :REASON :OPAQUE-VALUE :TYPE TYPE), so a
reader never has to classify application data by its shape."
  (when observation
    (append
     (when (trial-observation-lifecycle observation)
       (list :input-kind :fixture-recipe
             :lifecycle (trial-observation-lifecycle observation)
             :call-evidence (trial-observation-call-evidence observation)))
     (list :arguments (trial-observation-arguments observation)
           :status (trial-observation-status observation)
           :reason (trial-observation-reason observation)
           :signature (trial-observation-signature observation)
           :explanation (trial-observation-explanation observation)
           :outcome (trial-observation-outcome observation)
           :value (trial-observation-value observation)
           :case (trial-observation-case observation)
           :condition-report (trial-observation-condition-report observation))
     (let ((state (trial-observation-state observation)))
       (when state (list :state state))))))

(defmethod evidence-declared-cases ((property property)) nil)

(defmethod coverage-bindings ((property property) arguments)
  (property-named-arguments property arguments))

(defmethod coverage-inputs ((property property)) (property-arguments property))

(defmethod coverage-identity ((definition property) registry)
  (coverage-identity-from-metadata
   (definition-metadata definition :registry registry
                        :capabilities '(:generation :unknown :shrinking :unknown))))

(defmethod evidence-facts ((result property-result))
  (let ((metadata (property-result-schema-metadata result))
        (case-report (property-result-case-report result))
        (declared (property-result-declared-cases result)))
    (when (and (eq declared :not-collected) (listp case-report))
      (setf declared (getf case-report :declared-cases :not-collected)))
    (list :execution-status (property-result-status result) :scope :single-run
          :subject (evidence-subject (property-result-property result) metadata
                                    (property-result-provenance result))
          :trial-report (property-result-trial-report result)
          :declared-cases declared :case-report case-report
          :trials (property-result-trials result) :budget (property-result-budget result)
          :rejected (property-result-rejected result)
          :coverage (coverage-data result)
          :generation-report (property-result-generation-report result)
          :shrink-report (property-result-shrink-report result)
          :capabilities (getf metadata :capabilities :not-collected)
          :run-error (not (null (property-result-run-error result))))))

(defun result-data (result)
  "Return a versioned result record using metadata captured before execution.
RESULT must be a PROPERTY-RESULT, or INVALID-ARGUMENT is signalled.
Never resolve the current registry to describe an old result. Manually constructed
results without captured metadata have an explicitly incomplete digest."
  (check-argument result 'property-result 'result-data :result)
  (let ((metadata
          (copy-list
           (or (property-result-schema-metadata result)
               (list :schema-version 1 :definition-digest nil
                     :definition-digest-complete nil
                     :digest-omissions :not-collected :digest-exclusions :not-collected
                     :definition-digest-covers :declaration-and-registered-dependencies
                     :capabilities '(:generation :unknown :shrinking :unknown
                                     :instrumentation :unknown))))))
    (dolist (field '(:digest-omissions :digest-exclusions))
      (setf (getf metadata field) (getf metadata field :not-collected)))
    (when (eq :fixture-recipe (getf metadata :input-kind))
      (setf (getf metadata :schema-version) 2))
    (setf (getf metadata :record-kind) :result
          (getf metadata :entity-kind) (property-result-entity-kind result))
    (snapshot-value
     (append metadata
             (when (property-result-timeout result)
               (list :timeout (property-result-timeout result)))
             (when (property-result-run-error result)
               (list :run-error (observation-data (property-result-run-error result))))
             (list :coverage (coverage-data result) :evidence (evidence-summary result)
                    :name (property-result-property result)
                   :status (property-result-status result)
                   :trials (property-result-trials result)
                   :budget (property-result-budget result)
                   :rejected (property-result-rejected result)
                   :seed (property-result-seed result)
                   :profile (property-result-profile result)
                   :options (property-result-options result)
                   :provenance (property-result-provenance result)
                   :counterexample (property-result-counterexample result)
                   :shrunk-counterexample (property-result-shrunk-counterexample result)
                   :shrunk-outcome (property-result-shrunk-outcome result)
                    :shrink-report (property-result-shrink-report result)
                   :generation-report (property-result-generation-report result)
                   :failure-phase (property-result-failure-phase result)
                   :failure-reason (property-result-failure-reason result)
                   :case-report (property-result-case-report result)
                   :failure (observation-data (property-result-failure-evidence result))
                   :shrunk-failure (observation-data (property-result-shrunk-evidence result))
                   :elapsed (property-result-elapsed result))))))

(defun resolve-trials (property profile backend)
  "Return the trial count for PROPERTY under PROFILE (specification §33).

PROPERTY-TRIALS is a plist keyed by profile; a property that names no count for
the profile in effect falls back to the backend's own default.  PROFILE is one
of +TRIAL-PROFILES+ (see CHECK-PROFILE), so the fallback means only that the
table leaves this profile out, never that the profile was misspelled."
  (let ((table (property-trials property)))
    (or (and table (getf table (or profile :normal)))
        (backend-default-trials backend))))

(defun check-profile (profile operator)
  "Return PROFILE when it is NIL or a §33 profile, else signal INVALID-ARGUMENT for OPERATOR."
  (check-argument profile `(or null (member ,@+trial-profiles+)) operator :profile))

(defun check-replayed-result (seed-result entity-kind name operator)
  "Refuse SEED-RESULT unless it is a result of the ENTITY-KIND definition NAME.

A result handed as a seed stands in for its whole run -- seed, profile and
options -- so one from another property or contract would replay a run that
never happened, and a failure could look fixed (issue #84).  An integer seed
stays the way to borrow a random stream on purpose.  NIL is accepted."
  (when (and seed-result
             (not (and (eq entity-kind (property-result-entity-kind seed-result))
                       (eq name (property-result-property seed-result)))))
    (error 'invalid-argument
           :datum seed-result :expected-type 'property-result
           :operator operator :argument :seed
           :reason (format nil "the result belongs to the ~(~A~) ~S, not to the ~(~A~) ~S; ~
                                pass its integer seed to start a new run instead"
                           (property-result-entity-kind seed-result)
                           (property-result-property seed-result)
                           entity-kind name))))

(defun name-arguments (property values)
  "Project raw counterexamples through the property's binding protocol."
  (property-named-arguments property values))

(defparameter *cl-spec-version* "1.0.0"
  "Implementation version recorded in provenance; keep in sync with cl-spec.asd.")

(defun capture-run-provenance (backend options)
  "Capture environment labels and distinguish unavailable from uncollected information."
  (let* ((class-name (class-name (class-of backend)))
         (backend-name (if (and class-name (symbol-package class-name))
                           (format nil "~A::~A" (package-name (symbol-package class-name))
                                   (symbol-name class-name))
                           :unknown))
         (revision (getf options :target-revision :not-collected)))
    (snapshot-value
     (list :backend backend-name
           :lisp-implementation-type (lisp-implementation-type)
           :lisp-implementation-version (lisp-implementation-version)
           :cl-spec-version *cl-spec-version*
           :target-revision (if (eq revision :not-collected) :unknown revision)
           :collection-states
           (list :backend (if (eq backend-name :unknown) :unknown :known)
                 :lisp-implementation-type :known :lisp-implementation-version :known
                 :cl-spec-version (if *cl-spec-version* :known :unknown)
                 :target-revision (cond ((eq revision :not-collected) :not-collected)
                                        ((or (null revision) (eq revision :unknown)) :unknown)
                                        (t :known)))))))

(defun validate-fixture-replay (property result options registry)
  "Refuse changed or incomplete fixture definitions before replay causes side effects.
The refusal's reason names the cause: :INCOMPARABLE-DEFINITION, :DEFINITION-MISMATCH
or :RUN-OPTIONS-MISMATCH."
  (let* ((saved (property-result-schema-metadata result))
         (current (definition-metadata property :registry registry
                                       :capabilities '(:generation :unknown
                                                       :shrinking :unknown)))
         (reason (cond ((not (eq :fixture-recipe (getf saved :input-kind)))
                        :definition-mismatch)
                       ((not (and (getf saved :definition-digest-complete)
                                  (getf current :definition-digest-complete)))
                        :incomparable-definition)
                       ((not (equal (getf saved :definition-digest)
                                    (getf current :definition-digest)))
                        :definition-mismatch)
                       ((not (same-value-p options (property-result-options result)))
                        :run-options-mismatch))))
    (when reason
      (error 'unsupported-stateful-operation :operation :replay
             :function (property-name property) :reason reason))))

(defun validate-replay-state (property result options registry)
  "Check the saved input kind and any state reconstruction requirements before execution."
  (cond ((definition-fixture-metadata property)
         (validate-fixture-replay property result options registry))
        ((eq :fixture-recipe (getf (property-result-schema-metadata result) :input-kind))
         (error 'unsupported-stateful-operation :operation :replay
                :function (property-name property) :reason :definition-mismatch))
        ((definition-state-constraints property)
         (error 'unsupported-stateful-operation :operation :replay
                :function (property-name property)))))

(defgeneric prepare-property-run (property)
  (:documentation "Capture run-specific executable state before metadata and replay validation.")
  (:method ((property t)) property))

(defun preparation-timeout-initargs (timeout name seed options start &key profile budget)
  "Capture available result data for a timeout before generated execution starts."
  (list :status :timeout :timeout timeout :failure-reason :timeout
        :failure-phase (getf timeout :phase) :property name :trials 0 :budget budget
        :coverage '(:availability :not-collected :reason :preparation-timeout)
        :seed (or (if (typep seed 'property-result) (property-result-seed seed) seed)
                  (make-seed))
        :profile (or profile :normal) :options (snapshot-value options)
        :elapsed (/ (float (- (get-internal-real-time) start)) internal-time-units-per-second)))

(defun prepare-property-execution (resolved name registry profile seed-result options function-p)
  "Prepare the declaration and save the information needed by generated execution."
  (let* ((property (prepare-property-run resolved))
         (name (if (eq resolved property) name (property-name property))))
    ;; CHECK-FUNCTION validates its own result's name and kind.
    (unless function-p
      (check-replayed-result seed-result :property name 'run-property))
    (when seed-result
      (validate-replay-state property seed-result options registry))
    (let* ((backend (current-generator-backend))
           (coverage-options (normalize-coverage-options (getf options :coverage)))
           (*coverage-trial* nil)
           (*coverage-context*
             (when coverage-options
               (let ((participating (eq :coverage-v1 (backend-coverage-protocol backend))))
                 (when (and (eq :exercise (getf coverage-options :mode)) (not participating))
                   (error 'unsupported-coverage-operation :reason :backend-not-participating))
                 (make-coverage-context-for property coverage-options registry :single-run backend
                                            (not (coverage-fixture-p property))
                                            :deferred (not participating)))))
           (trials (resolve-trials property profile backend)))
      (when (and seed-result (definition-fixture-metadata property)
                 (or (not (eql trials (property-result-budget seed-result)))
                     (not (eq profile (property-result-profile seed-result)))))
        (error 'unsupported-stateful-operation :operation :replay
               :function name :reason :run-options-mismatch))
      (list registry property name backend coverage-options *coverage-context* trials
            (definition-metadata property :registry registry
                                 :capabilities '(:generation :unknown :shrinking :unknown))
            (snapshot-value (evidence-declared-cases property))
            (snapshot-value options)
            (capture-run-provenance backend options)
            (when (and (getf options :timeout)
                       (or (eq (class-of property) (find-class 'property))
                           (and function-p (coverage-fixture-p property))))
              (mapcar #'first (property-arguments property)))))))

(defun project-run-counterexamples (property outcome names timed-p)
  "Use completed projections, with saved raw inputs as a fallback."
  (let* ((unchecked (when (getf outcome :timeout) (getf outcome :unchecked-counterexamples)))
         (original (unless (member :failure unchecked) (getf outcome :failure)))
         (shrunk (unless (member :shrunk-failure unchecked) (getf outcome :shrunk-failure)))
         (original-args (when original (trial-observation-arguments original)))
         (shrunk-args (when shrunk (trial-observation-arguments shrunk))))
    (labels ((fallback (arguments)
               (if (and timed-p names)
                   (loop for name in names for value in arguments append (list name value))
                   arguments))
             (project (arguments)
               (name-arguments property (if timed-p (snapshot-value arguments) arguments))))
      (let ((first (fallback original-args))
            (second (fallback shrunk-args)))
        (flet ((format-inputs ()
                 (when original (setf first (project original-args)))
                 (when shrunk (setf second (project shrunk-args)))))
          (let ((timeout
                  (if timed-p
                      (call-with-run-finalization (max 1 (getf outcome :trials)) #'format-inputs)
                      (progn (format-inputs) (getf outcome :timeout)))))
            (list :counterexample first :shrunk-counterexample second :timeout timeout)))))))

(defun execute-property-run (property-designator profile seed options registry
                             &optional result-constructor)
  "Prepare and execute a property using the caller's run clock."
  (let* ((start (run-clock-start))
         (requested-name (when (symbolp property-designator) property-designator))
         (seed-result (and (typep seed 'property-result) seed))
         (effective-profile (or profile :normal))
         (effective-seed (or (if seed-result (property-result-seed seed-result) seed)
                             (make-seed)))
         (prepared
           (call-catching-run-timeout
            (lambda ()
              (with-run-phase (:preparation)
                (let* ((registry (check-registry registry 'run-property))
                       (resolved (resolve-property property-designator registry)))
                  (setf requested-name (property-name resolved))
                  (prepare-property-execution
                   resolved requested-name registry effective-profile
                   seed-result options (not (null result-constructor))))))
            (lambda (timeout)
              (let ((initargs (preparation-timeout-initargs
                               timeout requested-name effective-seed options start
                               :profile effective-profile)))
                (return-from execute-property-run
                  (if result-constructor
                      (funcall result-constructor initargs :timeout nil)
                      (apply #'make-instance 'property-result initargs))))))))
    (destructuring-bind (registry property name backend coverage-options
                         *coverage-context* trials metadata declared-cases
                         captured-options provenance counterexample-names)
        prepared
      (let* ((*coverage-trial* nil)
             (outcome (let ((*random-state* (seed->random-state effective-seed)))
                        (let ((backend-options (list* :trials trials :registry registry options)))
                          (call-with-run-limit-handoff
                           backend-options
                           (lambda ()
                             (run-generated-test backend property :options backend-options))))))
             (preparation-timeout-p (eq :preparation (getf (getf outcome :timeout) :phase)))
             (coverage-validation
               (unless preparation-timeout-p (validate-coverage-run *coverage-context* outcome)))
             (projections (project-run-counterexamples property outcome counterexample-names
                                                       (getf options :timeout)))
             (timeout (getf projections :timeout))
             (elapsed (/ (float (- (get-internal-real-time) start))
                         internal-time-units-per-second))
             (original (getf outcome :failure))
             (shrunk (getf outcome :shrunk-failure))
             (selected (or shrunk original)))
        (declare (ignore coverage-validation))
        ;; Backends may report capabilities captured when they compiled the actual
        ;; generator. Older backends leave the pre-run UNKNOWN metadata intact.
        (when (getf outcome :capabilities)
          (let ((capabilities (copy-list (getf outcome :capabilities))))
            (when (eq :none (getf (getf metadata :capabilities) :shrinking))
              (setf (getf capabilities :shrinking) :none))
            (setf (getf capabilities :instrumentation)
                  (getf (getf metadata :capabilities) :instrumentation)
                  (getf metadata :capabilities) capabilities)))
        (let ((initargs
                (list
                 ;; Zero trials or all preconditions rejected means no evidence.
                 :status (cond (timeout :timeout)
                               ((and (eq :passed (getf outcome :status))
                                     (= (getf outcome :trials) (getf outcome :rejected 0)))
                                :skipped)
                               (t (getf outcome :status)))
                 :coverage (if preparation-timeout-p
                               '(:availability :not-collected :reason :preparation-timeout)
                               (coverage-report-data
                                *coverage-context*
                                (if coverage-options :unsupported-backend :disabled)))
                 :trial-report (getf outcome :trial-report :not-collected)
                 :declared-cases declared-cases
                 :run-error (getf outcome :run-error)
                 :timeout timeout
                 :schema-metadata metadata :budget trials
                 :options captured-options :provenance provenance
                 :property name
                 :trials (getf outcome :trials)
                 :seed effective-seed
                 :profile effective-profile
                 :failure-evidence original :shrunk-evidence shrunk
                 :shrunk-outcome (getf outcome :shrunk-outcome)
                 :shrink-report (snapshot-value (or (getf outcome :shrink-report)
                                                    :not-collected))
                 :generation-report (snapshot-value
                                     (or (getf outcome :generation-report) :not-collected))
                 :failure-phase (if timeout (getf timeout :phase) (getf outcome :failure-phase))
                 :failure-reason (if timeout :timeout (getf outcome :failure-reason))
                 :rejected (getf outcome :rejected 0)
                 :counterexample (getf projections :counterexample)
                 :shrunk-counterexample (getf projections :shrunk-counterexample)
                 :condition (or (and (getf outcome :run-error) (getf outcome :condition))
                                (when selected (trial-observation-condition selected))
                                (getf outcome :condition))
                 :elapsed elapsed)))
          (if result-constructor
              (funcall result-constructor initargs
                       (selected-evidence-reason (getf initargs :failure-reason) selected)
                       (selected-evidence-explanation selected))
              (apply #'make-instance 'property-result initargs)))))))

(defun run-property-with-result-constructor
    (property-designator result-constructor &key seed options registry)
  "Execute PROPERTY-DESIGNATOR with RESULT-CONSTRUCTOR and the current run clock."
  (let ((enclosing-context *coverage-context*)
        (enclosing-trial *coverage-trial*))
    (execute-property-run
     property-designator nil seed options registry
     (lambda (initargs reason explanation)
       (let ((*coverage-context* enclosing-context)
             (*coverage-trial* enclosing-trial))
         (funcall result-constructor initargs reason explanation))))))

(defun run-property (property-designator &rest keyword-arguments
                     &key (profile nil profile-p) seed (options nil options-p)
                       (registry *registry*) &allow-other-keys)
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend. :TIMEOUT and :TRIAL-TIMEOUT in OPTIONS are wall clock limits in seconds.
:CLEANUP-TIMEOUT caps fixture cleanup. With a result as SEED, omitted PROFILE
and OPTIONS inherit their saved values. An explicit NIL selects profile
:NORMAL or the empty option list.

A PROPERTY-RESULT supplied as SEED asks to re-apply a past run.  A property
whose definition declares state constraints without a fixture refuses that with
UNSUPPORTED-STATEFUL-OPERATION before generation, capture or the target, because
nothing restores its state.  An integer SEED starts a new run and stays allowed."
  ;; Guarded here rather than left to SEED->RANDOM-STATE, which answered an
  ;; unusable seed with a condition naming an internal symbol.  A result stands
  ;; in for its seed, as REPLAY-PROPERTY and CHECK-FUNCTION both allow.
  (check-keyword-arguments keyword-arguments '(:profile :seed :options :registry)
                           'run-property)
  (check-argument property-designator '(or symbol property) 'run-property
                  :property-designator)
  (check-argument seed '(or null property-result (integer 0 *)) 'run-property :seed)
  ;; Resolve omissions before validating the effective settings, including saved data.
  (when (typep seed 'property-result)
    (unless profile-p (setf profile (property-result-profile seed)))
    (unless options-p (setf options (property-result-options seed))))
  (check-profile profile 'run-property)
  (check-run-options options 'run-property)
  (call-with-run-time-limits
   options
   (lambda () (execute-property-run property-designator profile seed options registry))
   'run-property))

(defun run-properties (property-designators &rest keyword-arguments
                       &key profile options (registry *registry*) &allow-other-keys)
  "Run each property in PROPERTY-DESIGNATORS and return the results in order.

Each run draws its own seed, so one failure can be replayed without re-running
the others.  PROFILE must be NIL or one of +TRIAL-PROFILES+; any other value
signals INVALID-ARGUMENT before the first property runs."
  (check-keyword-arguments keyword-arguments '(:profile :options :registry) 'run-properties)
  (check-argument property-designators '(satisfies finite-list-p) 'run-properties
                  :property-designators)
  (check-profile profile 'run-properties)
  (check-run-options options 'run-properties)
  (setf registry (check-registry registry 'run-properties))
  (mapcar (lambda (designator)
            (run-property designator :profile profile :options options :registry registry))
          property-designators))

(defun replay-property (property-designator seed &rest keyword-arguments
                        &key profile options (registry *registry*) &allow-other-keys)
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

SEED is either the integer seed of an earlier run or the PROPERTY-RESULT that
run produced, since section 15 shows both spellings and an agent holding a
result should not have to dig the seed out of it.

PROFILE selects a trial count from the property's :TRIALS table (§33), exactly
as run-property does. The PROFILE must match the original run's PROFILE for the
replay to reproduce it faithfully — the seed alone is not sufficient, because a
different profile changes the trial count. When SEED is a PROPERTY-RESULT, that
result carries its own PROPERTY-RESULT-PROFILE, and this function uses it when
PROFILE is not supplied -- so the recommended spelling, passing the result with
no :PROFILE, is faithful. An explicitly supplied PROFILE always wins over the
result's for stateless properties. Fixture results require an unchanged budget. An
integer SEED carries no profile, so that spelling still requires the caller to
supply a matching PROFILE.

SEED must be a property-result or a non-negative integer, or an error is
signalled.

Passing a PROPERTY-RESULT asks to re-apply that past run.  A property whose
definition declares state constraints without a fixture refuses that, before the seed is
extracted, with UNSUPPORTED-STATEFUL-OPERATION: nothing restores its state.  An
integer SEED starts a new run and stays allowed."
  (check-keyword-arguments keyword-arguments '(:profile :options :registry) 'replay-property)
  (check-argument seed '(or property-result (integer 0 *)) 'replay-property :seed)
  (check-profile profile 'replay-property)
  (check-run-options options 'replay-property)
  (check-registry registry 'replay-property)
  ;; Preserve the result through RUN-PROPERTY so fixture identity and run
  ;; parameters are validated before any hooks execute.
  (apply #'run-property property-designator :seed seed keyword-arguments))
