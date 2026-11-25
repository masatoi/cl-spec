;;;; src/generator.lisp
;;;;
;;;; Generator backend protocol (specification §10, §12).  Neither the IR nor
;;;; the property runner may depend on a concrete generation engine, so the
;;;; engine is installed at load time into *GENERATOR-BACKEND* by a separate
;;;; system (CL-SPEC/CHECK-IT).  Adding an exhaustive, fuzzing or SMT backend
;;;; later means adding methods, not editing this file.

(defpackage #:cl-spec/src/generator
  (:use #:cl)
  (:import-from #:cl-spec/src/time-limits
                #:call-with-run-time-limits #:time-limits-requested-p
                #:run-timeout-data #:with-run-phase
                #:call-catching-run-timeout #:call-with-run-finalization)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:export #:backend-time-limit-protocol)
  (:import-from #:cl-spec/src/trial-report
                #:*trial-report-context* #:make-trial-report-context #:completed-trial-report)
  (:export #:backend-trial-reporting)
  (:import-from #:cl-spec/src/property #:property #:property-metadata)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-lifecycle #:observation-failure-phase #:trial-observation-reason)
  (:export #:backend-trial-lifecycle)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions
                #:no-generator-backend
                #:invalid-backend-result
                #:generation-budget-exhausted)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument)
  (:import-from #:cl-spec/src/generation-request
                #:make-generation-request
                #:*generation-request*
                #:generation-request-report
                #:generation-report-p
                #:record-generated-value #:record-generation-interruption)
  (:import-from #:cl-spec/src/property #:property-call-arguments-p)
  (:import-from #:cl-spec/src/execution
                #:*trial-observations* #:observation-from-current-run-p #:trial-observation-status
                #:trial-observation-arguments #:trial-observation-signature
                #:trial-observation-condition #:observation-failure-p
                #:failure-identities-match-p #:same-value-p)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition)
  (:import-from #:cl-spec/src/ir
                #:spec #:spec-children)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:check-registry)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-branch)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:*generator-backend*
           #:current-generator-backend
           #:compile-generator
           #:generate-value
           #:run-generated-test
           #:generator-for
           #:sample
           #:backend-default-trials #:backend-capabilities
           #:backend-reports-generation))

(in-package #:cl-spec/src/generator)

(defvar *generator-backend* nil
  "The generator backend in effect, or NIL when none is installed.

Loading the CL-SPEC/CHECK-IT system installs a CHECK-IT-BACKEND here.  Rebind
it to swap backends for a dynamic extent, for example in tests.

A rebinding does not cross a thread boundary.  §48 puts the time limit on the
execution host, so a host that runs checks off the calling thread has to carry
this value over itself -- PROGV, or an explicit argument.  Without that, a run
started on another thread reads the global value, and if a backend is installed
there it generates rather than reporting NO-GENERATOR-BACKEND.")

(defun current-generator-backend ()
  "Return *GENERATOR-BACKEND*, signalling NO-GENERATOR-BACKEND when it is NIL."
  (or *generator-backend*
      (error 'no-generator-backend)))

(defgeneric compile-generator (backend spec &key context options)
  (:documentation "Compile SPEC into a BACKEND-specific generator object.

CONTEXT carries resolution state such as the registry; OPTIONS carries
generation parameters such as size limits.  The returned object is opaque to
everything except BACKEND and GENERATE-VALUE."))

(defgeneric generate-value (backend compiled-generator &key seed)
  (:documentation "Produce one value from COMPILED-GENERATOR using BACKEND.

SEED, when supplied, makes the value reproducible (specification §15)."))

(defmethod generate-value :around (backend compiled-generator &key seed)
  "Own an implicit single-value request for a bare draw.

A caller that already owns a request (SAMPLE, a runner) keeps it, so the budget
is shared across the request's values.  Root counting belongs to those request
boundaries -- the runner and SAMPLE record their own roots -- so a nested
GENERATE-VALUE call made by user code inside a run does not inflate the root
count past the planned value count."
  (declare (ignore seed))
  (if *generation-request*
      (call-next-method)
      (let ((*generation-request* (make-generation-request :planned 1)))
        (call-next-method))))

(defgeneric run-generated-test (backend property &key options)
  (:documentation "Run PROPERTY and return a validated backend outcome plist.
OPTIONS must contain :TRIALS, a nonnegative integer budget, and may carry :REGISTRY.
The outcome requires :STATUS (:passed, :failed, :error, :skipped or :timeout)
and :TRIALS, the count of completed ordinary trials, at most the budget.
An owned :TIMEOUT record identifies an unfinished phase and the trial reached.
:REJECTED counts precondition refusals in generated trials, excluding shrinking.
Optional :CAPABILITIES reports :GENERATION and :SHRINKING from the actual compiled
generator, captured before trials; absent/NIL leaves result capabilities unknown.
Failures require :FAILURE (a TRIAL-OBSERVATION), :SHRUNK-OUTCOME (:none, :used or
:different-failure), and optionally :SHRUNK-FAILURE (an observed matching failure).
Only :used carries a shrink observation. Status describes the selected observation.
Backends must use OBSERVE-TRIAL, preserve original evidence, and never label an
untested shrink return value as a counterexample. :PASSED consumes the full budget."))

(defun proper-list-p (value)
  "Use the shared cycle-safe proper-list check."
  (finite-list-p value))

(defun finite-signature-p (value)
  "Require a proper signature spine and acyclic nested constants before comparison."
  (let ((active (make-hash-table :test #'eq)))
    (labels ((walk (item)
               (cond
                 ((null item) t)
                 ((atom item) t)
                 ((gethash item active) nil)
                 (t
                  (setf (gethash item active) t)
                  (prog1 (and (walk (car item)) (walk (cdr item)))
                    (remhash item active))))))
      (and (consp value) (proper-list-p value) (walk value)))))

(defun capability-report-p (report)
  "Recognize an optional backend capability plist with explicit supported states."
  (and (proper-list-p report)
       (evenp (length report))
       (let ((keys (loop for key in report by #'cddr collect key)))
         (and (every #'keywordp keys)
              (= (length keys) (length (remove-duplicates keys)))))
       (member (getf report :generation) '(:available :unavailable :unknown))
       (member (getf report :shrinking) '(:available :unavailable :unknown :none))))

(defun shrink-report-p (report)
  "Recognize shrink counts and the optional timed-out subset of attempted candidates."
  (or (null report)
      (and (proper-list-p report) (member (length report) '(6 8))
           (let ((keys (loop for key in report by #'cddr collect key))
                 (budget (getf report :budget))
                 (candidates (getf report :candidates))
                 (timed-out (getf report :timed-out-candidates 0)))
             (and (= (length keys) (length (remove-duplicates keys)))
                  (every (lambda (key)
                           (member key '(:candidates :budget :termination :timed-out-candidates)))
                         keys)
                  (typep candidates '(integer 0 *))
                  (or (eq :unbounded budget)
                      (and (typep budget '(integer 0 100000)) (<= candidates budget)))
                  (typep timed-out '(integer 0 *))
                  (<= timed-out candidates)
                  (keywordp (getf report :termination)))))))

(defun generation-only-outcome-p (outcome)
  "Recognize the narrow generation-only error branch with no target evidence.

It requires a validated request-owned exhaustion report for the generation phase,
and no target failure observation, counterexample input, or shrink disposition.
Relaxing evidence requirements is confined to this shape."
  (let ((report (getf outcome :generation-report)))
    (and (eq :error (getf outcome :status))
         (eq :generation-budget-exhausted (getf outcome :failure-reason))
         (eq :generation (getf outcome :failure-phase))
         (typep (getf outcome :condition) 'generation-budget-exhausted)
         (generation-report-p report)
         (eq :budget-exhausted (getf report :termination))
         (eq :generation (getf report :exhaustion-phase))
         (null (getf outcome :failure))
         (null (getf outcome :shrunk-failure))
         (null (getf outcome :shrunk-outcome)))))

(defun validate-fixture-run-error (outcome property budget fixture-p)
  "Check lifecycle abort evidence independently of any earlier counterexamples."
  (let ((abort (getf outcome :run-error))
        (original (getf outcome :failure))
        (shrunk (getf outcome :shrunk-failure))
        (trials (getf outcome :trials))
        (rejected (getf outcome :rejected 0)))
    (unless (and fixture-p
                 (eq :error (getf outcome :status))
                 (integerp trials) (<= 1 trials budget)
                 (integerp rejected) (<= 0 rejected trials)
                 (observation-from-current-run-p abort property)
                 (eq :error (trial-observation-status abort))
                 (eq :fixture (observation-failure-phase abort))
                 (typep (trial-observation-condition abort) 'error)
                 (eq :aborted (getf (trial-observation-lifecycle abort) :completion))
                 (eq (getf outcome :failure-reason)
                     (trial-observation-reason abort)))
      (error 'invalid-backend-result :reason "invalid fixture lifecycle abort"))
    (dolist (observation (remove nil (list original shrunk)))
      (unless (and (observation-from-current-run-p observation property)
                   (observation-failure-p observation)
                   (finite-signature-p (trial-observation-signature observation))
                   (proper-list-p (trial-observation-arguments observation))
                   (eq :completed (getf (trial-observation-lifecycle observation) :completion)))
        (error 'invalid-backend-result :reason "invalid retained fixture counterexample")))
    (when (and shrunk
               (or (null original)
                   (not (failure-identities-match-p
                         (trial-observation-signature original)
                         (trial-observation-signature shrunk)))))
      (error 'invalid-backend-result :reason "invalid retained fixture reduction"))
    outcome))

(defun validate-outcome-plist (outcome)
  "Refuse malformed backend data before any accessor traverses it."
  (let ((tail outcome) (seen nil) (cells (make-hash-table :test #'eq)))
    (loop while tail
          do (unless (and (consp tail) (consp (cdr tail))
                          (keywordp (car tail))
                          (not (member (car tail) seen))
                          (not (gethash tail cells)))
               (error 'invalid-backend-result
                      :reason "outcome must be a proper keyword plist without duplicate keys"))
             (setf (gethash tail cells) t)
             (push (car tail) seen)
             (setf tail (cddr tail))))
  outcome)

(defun validate-backend-outcome
    (outcome property budget &optional (fixture-p nil fixture-supplied-p))
  "Reject missing counts, contradictory statuses and unsupported shrink evidence."
  (flet ((refuse (reason)
           (error 'invalid-backend-result :reason reason)))
    (validate-outcome-plist outcome)
    (unless (shrink-report-p (getf outcome :shrink-report))
      (refuse ":shrink-report requires consistent candidate counts, budget and a termination keyword"))
    (when (and (getf outcome :generation-report)
               (not (generation-report-p (getf outcome :generation-report))))
      (refuse ":generation-report requires a coherent bounded-filter report"))
    (when (and (getf outcome :capabilities)
               (not (capability-report-p (getf outcome :capabilities))))
      (refuse ":capabilities must report valid generation and shrinking states"))
    (when (getf outcome :run-error)
      (when (or (getf outcome :timeout) (run-timeout-data))
        (refuse "a timeout cannot be disguised as a fixture error"))
      (validate-fixture-run-error outcome property budget
                                  (if fixture-supplied-p
                                      fixture-p
                                      (getf (property-metadata property) :fixture)))
      (return-from validate-backend-outcome
        (check-outcome-argument-shapes outcome property)))
    (let* ((status (getf outcome :status))
           (trials (getf outcome :trials :missing))
           (rejected (getf outcome :rejected 0))
           (original (getf outcome :failure))
           (shrunk (getf outcome :shrunk-failure))
           (disposition (getf outcome :shrunk-outcome))
           (selected (or shrunk original)))
      (unless (and (integerp trials) (<= 0 trials budget))
        (refuse ":trials is required and must be an integer between zero and the budget"))
      (unless (and (integerp rejected) (<= 0 rejected trials))
        (refuse ":rejected must count only generated trials"))
      (unless (member status '(:passed :failed :error :skipped :timeout))
        (refuse "unknown or missing :status"))
      (let ((timeout (getf outcome :timeout)))
        (when (or (eq :timeout status) timeout (run-timeout-data))
          (unless (and (eq :timeout status) (consp timeout) (eq timeout (run-timeout-data))
                       (<= (max 1 trials) (getf timeout :trial) (1+ trials))
                       (eq (getf outcome :failure-phase) (getf timeout :phase))
                       (eq :timeout (getf outcome :failure-reason)))
            (refuse "timeout must be owned by the active run and match its progress"))))
      (cond
        ((generation-only-outcome-p outcome)
         (when (or original shrunk disposition)
           (refuse "a generation-only error cannot carry target failure evidence")))
        ((and (eq :timeout status) (null original))
         (when (or shrunk disposition)
           (refuse "a timeout without an original failure cannot carry a shrink result")))
        ((member status '(:passed :skipped))
         (when (or original shrunk disposition)
           (refuse "a nonfailing outcome cannot carry failure evidence"))
         (when (and (eq status :passed) (/= trials budget))
           (refuse ":passed must account for the full trial budget"))
         (when (and (eq status :skipped) (/= trials rejected))
           (refuse ":skipped cannot contain admitted trials")))
        (t
         (unless (and (plusp trials) (< rejected trials)
                      (observation-failure-p original))
           (refuse "a failing outcome requires an observed original failure"))
         (dolist (observation (remove nil (list original shrunk)))
           (unless (and (observation-failure-p observation)
                        (finite-signature-p (trial-observation-signature observation))
                        (proper-list-p (trial-observation-arguments observation))
                        (observation-from-current-run-p observation property)
                        (if (eq :error (trial-observation-status observation))
                            (typep (trial-observation-condition observation) 'error)
                            (null (trial-observation-condition observation))))
             (refuse "failure evidence has invalid status, identity, arguments or condition")))
         (unless (member disposition '(:none :used :different-failure))
           (refuse "failures require an explicit :shrunk-outcome"))
         (unless (eq (not (null shrunk)) (eq disposition :used))
           (refuse ":used must identify an observed shrunk failure"))
         (when (and shrunk
                    (or (not (failure-identities-match-p
                              (trial-observation-signature original)
                              (trial-observation-signature shrunk)))
                        (same-value-p (trial-observation-arguments original)
                                      (trial-observation-arguments shrunk))))
           (refuse "shrunk evidence must preserve failure identity and change the input"))
         (unless (or (eq status :timeout) (eq status (trial-observation-status selected)))
           (refuse "status must describe the selected counterexample"))))
      (check-outcome-argument-shapes outcome property))))

(defgeneric backend-trial-reporting (backend)
  (:documentation "Return :TRIAL-REPORT-V1 when BACKEND measures every ordinary trial.")
  (:method ((backend t)) nil))

(defgeneric backend-trial-lifecycle (backend)
  (:documentation "Return :FIXTURE-V1 when the backend preserves independent fixture trials.")
  (:method ((backend t)) nil))

(defgeneric backend-time-limit-protocol (backend)
  (:documentation "Return :TIME-LIMITS-V1 when BACKEND bounds and reports generated execution.")
  (:method ((backend t)) nil))

(defgeneric backend-reports-generation (backend)
  (:documentation "Return true when BACKEND participates in the bounded-filter accounting.

Only a participating backend's run receives the request's synthesized generation
report.  A backend that never calls the accounting hooks leaves the report
:NOT-COLLECTED rather than publishing a fabricated zero-work report.")
  (:method ((backend t))
    (declare (ignore backend))
    nil))

(defun prepare-backend-run (backend property options)
  "Read extension capabilities before opening reports or invoking the backend."
  (let ((fixture-p (and (typep property 'property) (getf (property-metadata property) :fixture))))
    (when (and fixture-p (not (eq :fixture-v1 (backend-trial-lifecycle backend))))
      (error 'invalid-backend-result :reason "backend does not support fixture trials"))
    (when (and (time-limits-requested-p options)
               (not (eq :time-limits-v1 (backend-time-limit-protocol backend))))
      (error 'invalid-argument :operator 'run-generated-test :argument :options
             :datum options :expected-type '(not (satisfies time-limits-requested-p))
             :reason "run time limits require a participating backend"))
    (list fixture-p
          (eq :trial-report-v1 (backend-trial-reporting backend))
          (backend-reports-generation backend))))

(defun check-outcome-argument-shapes (outcome property)
  "Check saved counterexample shapes without losing prior observations on expiration."
  (let* ((keys (remove-if-not (lambda (key) (getf outcome key)) '(:failure :shrunk-failure)))
         (unchecked keys)
         (timeout
           (when keys
             (call-with-run-finalization
              (max 1 (getf outcome :trials))
              (lambda ()
                (dolist (key keys)
                  (unless (property-call-arguments-p
                           property (trial-observation-arguments (getf outcome key)))
                    (error 'invalid-backend-result :reason "counterexample arguments do not fit"))
                  (pop unchecked)))))))
    (when timeout
      (setf outcome (copy-list outcome))
      (setf (getf outcome :status) :timeout
            (getf outcome :timeout) timeout
            (getf outcome :failure-phase) (getf timeout :phase)
            (getf outcome :failure-reason) :timeout)
      (setf (getf outcome :unchecked-counterexamples) unchecked))
    outcome))

(defmethod run-generated-test :around (backend property &key options)
  "Own one generation request and enforce the backend outcome protocol.

The request's candidate budget is shared by every bounded AND filter the run
reaches.  An explicit :GENERATION-BUDGET option is validated before execution;
otherwise the default coefficient applies.  The effective generation report is
attached to the outcome before validation.  A participating backend converts its
own request-owned exhaustion into the narrow generation-only error branch with
the trial and precondition counts it collected; this boundary never fabricates
`:trials 0` for an exhaustion that generated roots."
  (call-with-run-time-limits
   options
   (lambda ()
     (let ((budget (getf options :trials :missing))
           (*trial-observations* (list nil))
           (prepared
             (call-catching-run-timeout
              (lambda ()
                (with-run-phase (:preparation) (prepare-backend-run backend property options)))
              (lambda (timeout)
                (return-from run-generated-test
                  (list :status :timeout :timeout timeout :failure-reason :timeout
                        :failure-phase (getf timeout :phase) :trials 0 :rejected 0))))))
       (unless (and (integerp budget) (not (minusp budget)))
         (error 'type-error :datum budget :expected-type '(integer 0 *)))
       (destructuring-bind (fixture-p trial-report-p generation-report-p) prepared
         (let* ((explicit (getf options :generation-budget :missing))
                (request (if (eq explicit :missing)
                             (make-generation-request :planned budget)
                             (make-generation-request :planned budget :budget explicit)))
                (*generation-request* request)
                (*trial-report-context* (when trial-report-p (make-trial-report-context property)))
                (outcome (call-next-method)))
           (validate-outcome-plist outcome)
           (when (loop for key in outcome by #'cddr thereis (eq key :trial-report))
             (error 'invalid-backend-result :reason "trial-report is owned by the runner"))
           (when *trial-report-context*
             (setf outcome (list* :trial-report
                                  (completed-trial-report property outcome) outcome)))
           (when (run-timeout-data) (record-generation-interruption))
           (when generation-report-p
             (setf outcome (list* :generation-report (generation-request-report request) outcome)))
           (validate-backend-outcome outcome property budget fixture-p)))))
   'run-generated-test))

(defgeneric backend-capabilities (backend spec &key registry)
  (:documentation "Describe generation and shrinking with the spec object SPEC as the root.
Resolve a registered spec name with FIND-SPEC. For an enclosing property's input
schema, consult PROPERTY-DATA or the run's RESULT-DATA. Probing capabilities
does not draw values or run user predicates."))

(defmethod backend-capabilities ((backend t) spec &key registry)
  "Unknown backends must opt in to capability reporting."
  (declare (ignore spec registry))
  (list :generation (if backend :unknown :unavailable)
        :shrinking (if backend :unknown :unavailable)))

(defgeneric backend-default-trials (backend)
  (:documentation "Return the trial count BACKEND uses when a property names none.

The core cannot read check-it's own default, so the backend answers for it."))

(defun validate-definition-tree (spec)
  "Validate SPEC and every spec it contains, returning SPEC.

A spec object handed straight to GENERATOR-FOR never passed through normalization
or the registry, so nothing else checks its constraints: a programmatically built
collection with a malformed bound would otherwise compile into a generator whose
values its own spec rejects.  Shared and circular object graphs are walked once."
  (let ((seen (make-hash-table :test #'eq)))
    (labels ((walk (node)
               (unless (gethash node seen)
                 (setf (gethash node seen) t)
                 (validate-definition node)
                 (dolist (child (spec-children node))
                   (walk child)))))
      (walk spec))
    spec))

(defun generator-for (spec-designator &key context options (registry *registry*))
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
The result is opaque to everything but the backend and GENERATE-VALUE."
  (setf registry (check-registry registry 'generator-for))
  (let ((spec (resolve-spec spec-designator registry)))
    (validate-definition-tree spec)
    (compile-generator (current-generator-backend) spec
                       :context (or context (list :registry registry))
                       :options options)))

(defun sample (spec-designator &key (count 10) seed (branch nil branch-p)
                                (generation-budget nil generation-budget-p)
                                (registry *registry*))
  "Return (VALUES VALUES REPORT) for COUNT values generated from SPEC-DESIGNATOR.

VALUES is the sampled list.  REPORT is the generation report for this one
request: the bounded-filter candidate budget, attempts, rejections and phases.

SEED, when supplied, makes the whole sequence reproducible.  BRANCH, when
supplied, samples only the named branch of a tagged union, which is how a caller
aims generation at one alternative; an explicitly supplied NIL is an unknown
branch and is refused rather than read as \"no branch requested\", so a caller
forwarding a computed branch value is told when it is bad.  GENERATION-BUDGET,
when supplied, is the request-wide bounded-filter candidate budget; explicit zero
is not an omission.  Intended for inspecting what a spec admits, from the REPL or
from an agent.

A COUNT, SEED or GENERATION-BUDGET that is not a nonnegative integer (SEED may
also be NIL) signals INVALID-ARGUMENT before anything is generated."
  (check-argument count '(integer 0 *) 'sample :count)
  (setf registry (check-registry registry 'sample))
  (check-argument seed '(or null (integer 0 *)) 'sample :seed)
  (when generation-budget-p
    (check-argument generation-budget '(integer 0 *) 'sample :generation-budget))
  (let* ((backend (current-generator-backend))
         (spec (if branch-p
                   (tagged-union-branch (resolve-spec spec-designator registry) branch)
                   spec-designator))
         (generator (generator-for spec :registry registry))
         (request (if generation-budget-p
                      (make-generation-request :planned count :budget generation-budget)
                      (make-generation-request :planned count)))
         (*generation-request* request))
    (flet ((draw ()
             (loop repeat count
                   collect (prog1 (generate-value backend generator)
                             (record-generated-value)))))
      (if seed
          (let ((*random-state* (seed->random-state seed)))
            (values (draw) (generation-request-report request)))
          (values (draw) (generation-request-report request))))))
