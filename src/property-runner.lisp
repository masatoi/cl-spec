;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/property #:property-arguments)
  (:import-from #:cl-spec/src/coverage #:coverage-inputs #:coverage-bindings #:coverage-data #:copy-coverage-data
                #:normalize-coverage-options #:backend-coverage-protocol
                #:unsupported-coverage-operation)
  (:import-from #:cl-spec/src/coverage-report
                #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
                #:coverage-report-data #:coverage-fixture-p)
  (:import-from #:cl-spec/src/evidence
                #:evidence-facts #:evidence-summary #:evidence-subject #:evidence-declared-cases)
  (:export #:property-result-trial-report #:property-result-declared-cases)
  (:import-from #:cl-spec/src/schema #:definition-fixture-metadata)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-lifecycle #:trial-observation-call-evidence)
  (:export #:property-result-run-error #:prepare-property-run)
  (:import-from #:cl-spec/src/schema #:definition-metadata
                #:definition-state-constraints)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-named-arguments
                #:property-trials)
  (:import-from #:cl-spec/src/conditions
                #:invalid-backend-result
                #:unsupported-stateful-operation)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-outcome #:snapshot-value #:trial-observation-condition-report #:trial-observation-value
                #:trial-observation-status #:trial-observation-case
                #:trial-observation-arguments #:trial-observation-condition
                #:trial-observation-reason #:trial-observation-signature
                #:trial-observation-explanation #:trial-observation-state)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
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
                  :documentation ":GENERATION when the run stopped in generation infrastructure rather
than on a target observation, else NIL.")
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
           :documentation "One of :PASSED, :FAILED, :ERROR, :SKIPPED or
:PENDING.")
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

(declaim (ftype (function ((or symbol property)
                           &key (:profile t) (:seed t) (:options t) (:registry t))
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

(defun property-result-failure-reason (result)
  "Return the selected observation's reason, a stored generation reason, or NIL."
  (or (property-result-stored-failure-reason result)
      (let ((evidence (selected-evidence result)))
        (when evidence (trial-observation-reason evidence)))))

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
  (let ((evidence (selected-evidence result)))
    (when (and evidence (member (trial-observation-reason evidence)
                                '(:return-spec :condition-spec :missing-condition
                                  :contract-error :state-postcondition)))
      (trial-observation-explanation evidence))))

(defun observation-data (observation)
  "Project captured trial evidence as Lisp data rather than a structure object.

:STATE is present only when the contract declared :CAPTURE or :STATE-POST and
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
          :generation-report (property-result-generation-report result)
          :shrink-report (property-result-shrink-report result)
          :capabilities (getf metadata :capabilities :not-collected)
          :run-error (not (null (property-result-run-error result))))))

(defun result-data (result)
  "Return a versioned result record using metadata captured before execution.
Never resolve the current registry to describe an old result. Manually constructed
results without captured metadata have an explicitly incomplete digest."
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
the profile in effect falls back to the backend's own default."
  (let ((table (property-trials property)))
    (or (and table (getf table (or profile :normal)))
        (backend-default-trials backend))))

(defun name-arguments (property values)
  "Project raw counterexamples through the property's binding protocol."
  (property-named-arguments property values))

(defparameter *cl-spec-version* "0.1.0"
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
  "Refuse changed or incomplete fixture definitions before replay causes side effects."
  (let ((saved (property-result-schema-metadata result))
        (current (definition-metadata property :registry registry
                                      :capabilities '(:generation :unknown :shrinking :unknown))))
    (unless (and (eq :fixture-recipe (getf saved :input-kind))
                 (getf saved :definition-digest-complete)
                 (getf current :definition-digest-complete)
                 (equal (getf saved :definition-digest) (getf current :definition-digest))
                 (equal options (property-result-options result)))
      (error 'unsupported-stateful-operation :operation :replay
             :function (property-name property)))))

(defun refuse-stateful-replay (property seed-result)
  "Refuse re-applying a past run to a state-observing PROPERTY, or return NIL.

A :CAPTURE / :STATE-POST function-check property observes state and never
restores it, so a saved run cannot be reapplied to it.  SEED-RESULT is the
PROPERTY-RESULT the caller is standing in for a run, or NIL when the caller
starts a new run (no seed, or an integer seed) which stays allowed.  The
refusal happens before metadata probing, generation, capture or the target run,
so no call counter moves.  Ordinary properties declare no state constraints, so
their existing replay is unchanged."
  (when (and seed-result (definition-state-constraints property)
             (not (definition-fixture-metadata property)))
    (error 'unsupported-stateful-operation :operation :replay
           :function (property-name property))))

(defgeneric prepare-property-run (property)
  (:documentation "Capture run-specific executable state before metadata and replay validation.")
  (:method ((property t)) property))

(defun run-property (property-designator &key profile seed options (registry *registry*))
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend.

A PROPERTY-RESULT supplied as SEED asks to re-apply a past run.  A property
whose definition declares state constraints without a fixture refuses that with
UNSUPPORTED-STATEFUL-OPERATION before generation, capture or the target, because
nothing restores its state.  An integer SEED starts a new run and stays allowed."
  ;; Guarded here rather than left to SEED->RANDOM-STATE, which answered an
  ;; unusable seed with a condition naming an internal symbol.  A result stands
  ;; in for its seed, as REPLAY-PROPERTY and CHECK-FUNCTION both allow.
  (unless (or (null seed)
              (typep seed 'property-result)
              (and (integerp seed) (not (minusp seed))))
    (error 'type-error :datum seed
                       :expected-type '(or null property-result (integer 0 *))))
  (let* ((seed-result (and (typep seed 'property-result) seed))
         (profile (or profile
                      ;; A result stands in for its whole run.  The seed alone
                      ;; is not it: the profile fixes the trial count, so
                      ;; digging out only the seed replayed a 400-trial failure
                      ;; as a 3-trial pass that contradicted the result it was
                      ;; handed.  REPLAY-PROPERTY has always carried both.
                      (and seed-result (property-result-profile seed-result))))
         (seed (if seed-result (property-result-seed seed-result) seed))
         ;; A result also carries the options its run was given, so an explicit
         ;; :GENERATION-BUDGET is reused when the caller omits options.  Otherwise
         ;; a run that exhausted a small budget would pass on replay under the
         ;; default budget, contradicting the result it was handed.
         (options (or options
                      (and seed-result (property-result-options seed-result))))
         (property (let ((resolved (prepare-property-run
                                    (resolve-property property-designator registry))))
                     ;; Refuse a state-observing property before metadata
                     ;; probing, generation, capture or the target run.
                     (refuse-stateful-replay resolved seed-result)
                      (when (and seed-result (definition-fixture-metadata resolved))
                        (validate-fixture-replay resolved seed-result options registry))
                     resolved))
         (backend (current-generator-backend))
         (coverage-options (normalize-coverage-options (getf options :coverage)))
         (*coverage-trial* nil)
         (*coverage-context*
           (when coverage-options
             (when (and (eq :exercise (getf coverage-options :mode))
                        (not (eq :coverage-v1 (backend-coverage-protocol backend))))
               (error 'unsupported-coverage-operation :reason :backend-not-participating))
             (when (eq :coverage-v1 (backend-coverage-protocol backend))
               (make-coverage-context-for property coverage-options registry :single-run backend
                                          (not (coverage-fixture-p property))))))
         (effective-seed (or seed (make-seed)))
         ;; Recorded on the result as-is (not the raw PROFILE argument) so a result
         ;; is self-describing -- :PROFILE :NORMAL tells an agent what ran, where NIL
         ;; would not -- and so replaying from the result reproduces this run by
         ;; construction rather than by both paths happening to default the same way.
         (effective-profile (or profile :normal))
         (trials (let ((count (resolve-trials property effective-profile backend)))
                    (when (and seed-result (definition-fixture-metadata property)
                               (or (not (eql count (property-result-budget seed-result)))
                                   (not (eq effective-profile (property-result-profile seed-result)))))
                      (error 'unsupported-stateful-operation :operation :replay
                             :function (property-name property)))
                    count))
         (metadata (definition-metadata
                    property :registry registry
                    :capabilities '(:generation :unknown :shrinking :unknown)))
         (declared-cases (snapshot-value (evidence-declared-cases property)))
         (captured-options (snapshot-value options))
         (provenance (capture-run-provenance backend options))
         (start (get-internal-real-time))
         ;; One binding covers generation and shrinking alike, because the whole
         ;; trial loop lives inside this single call.
         (outcome (let ((*random-state* (seed->random-state effective-seed)))
                    (run-generated-test backend property
                                        :options (list* :trials trials
                                                        :registry registry
                                                        options))))
         (elapsed (/ (float (- (get-internal-real-time) start))
                     internal-time-units-per-second))
         (original (getf outcome :failure))
         (shrunk (getf outcome :shrunk-failure))
         (selected (or shrunk original)))
    ;; Backends may report capabilities captured when they compiled the actual
    ;; generator. Older backends leave the pre-run UNKNOWN metadata intact.
    (when (getf outcome :capabilities)
      (let ((capabilities (copy-list (getf outcome :capabilities))))
        (when (eq :none (getf (getf metadata :capabilities) :shrinking))
          (setf (getf capabilities :shrinking) :none))
        (setf (getf capabilities :instrumentation)
              (getf (getf metadata :capabilities) :instrumentation)
              (getf metadata :capabilities) capabilities)))
    (make-instance 'property-result
                   ;; Zero generated trials or all preconditions rejected means
                   ;; no admitted trial supplied verification evidence.
                   :status (if (and (eq :passed (getf outcome :status))
                                    (= (getf outcome :trials) (getf outcome :rejected 0)))
                               :skipped
                               (getf outcome :status))
                   :coverage (coverage-report-data *coverage-context*
                                                   (if coverage-options :unsupported-backend :disabled))
                   :trial-report (getf outcome :trial-report :not-collected)
                   :declared-cases declared-cases
                   :run-error (getf outcome :run-error)
                   :schema-metadata metadata :budget trials
                   :options captured-options :provenance provenance
                   :property (property-name property)
                   :trials (getf outcome :trials)
                   :seed effective-seed
                   :profile effective-profile
                   :failure-evidence original :shrunk-evidence shrunk
                   :shrunk-outcome (getf outcome :shrunk-outcome)
                    :shrink-report (snapshot-value (or (getf outcome :shrink-report)
                                                      :not-collected))
                   :generation-report (snapshot-value
                                       (or (getf outcome :generation-report) :not-collected))
                   :failure-phase (getf outcome :failure-phase)
                   :failure-reason (getf outcome :failure-reason)
                   :rejected (getf outcome :rejected 0)
                   :counterexample (when original
                                     (name-arguments property
                                                     (trial-observation-arguments original)))
                   :shrunk-counterexample
                   (when shrunk
                     (name-arguments property (trial-observation-arguments shrunk)))
                   :condition (or (and (getf outcome :run-error) (getf outcome :condition))
                                  (when selected (trial-observation-condition selected))
                                  (getf outcome :condition))
                   :elapsed elapsed)))

(defun run-properties (property-designators &key profile options (registry *registry*))
  "Run each property in PROPERTY-DESIGNATORS and return the results in order.

Each run draws its own seed, so one failure can be replayed without re-running
the others."
  (mapcar (lambda (designator)
            (run-property designator :profile profile :options options :registry registry))
          property-designators))

(defun replay-property (property-designator seed &key profile options (registry *registry*))
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
  (unless (or (typep seed 'property-result)
              (and (integerp seed) (>= seed 0)))
    (error 'type-error
           :datum seed
           :expected-type '(or property-result (integer 0 *))))
  ;; Preserve the result through RUN-PROPERTY so fixture identity and run
  ;; parameters are validated before any hooks execute.
  (refuse-stateful-replay (resolve-property property-designator registry)
                          (and (typep seed 'property-result) seed))
  (run-property property-designator
                :seed seed
                :profile (or profile
                             (and (typep seed 'property-result)
                                  (property-result-profile seed)))
                :options (or options
                             (and (typep seed 'property-result)
                                  (property-result-options seed)))
                :registry registry))
