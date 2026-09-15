;;;; src/generator.lisp
;;;;
;;;; Generator backend protocol (specification §10, §12).  Neither the IR nor
;;;; the property runner may depend on a concrete generation engine, so the
;;;; engine is installed at load time into *GENERATOR-BACKEND* by a separate
;;;; system (CL-SPEC/CHECK-IT).  Adding an exhaustive, fuzzing or SMT backend
;;;; later means adding methods, not editing this file.

(defpackage #:cl-spec/src/generator
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions
                #:no-generator-backend
                #:invalid-backend-result
                #:generation-budget-exhausted)
  (:import-from #:cl-spec/src/generation-request
                #:make-generation-request
                #:*generation-request*
                #:generation-request-report
                #:generation-report-p
                #:record-generated-value
                #:owned-generation-exhaustion-p)
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
                #:*registry*)
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
           #:backend-default-trials #:backend-capabilities))

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
The outcome requires :STATUS (:passed, :failed, :error or :skipped) and :TRIALS,
the nonnegative count actually generated, never greater than the budget.
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
  "Recognize a bounded count report independently of backend-specific termination keywords."
  (or (null report)
      (and (proper-list-p report) (= 6 (length report))
           (let ((keys (loop for key in report by #'cddr collect key)))
             (and (= 3 (length (remove-duplicates keys)))
                  (every (lambda (key) (member key '(:candidates :budget :termination))) keys)))
           (typep (getf report :budget) '(integer 0 100000))
           (typep (getf report :candidates) '(integer 0 *))
           (<= (getf report :candidates) (getf report :budget))
           (keywordp (getf report :termination)))))

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

(defun validate-backend-outcome (outcome property budget)
  "Reject missing counts, contradictory statuses and unsupported shrink evidence."
  (flet ((refuse (reason)
           (error 'invalid-backend-result :reason reason)))
    (let ((tail outcome) (seen nil) (cells (make-hash-table :test #'eq)))
      (loop while tail
            do (unless (and (consp tail) (consp (cdr tail))
                            (keywordp (car tail))
                            (not (member (car tail) seen))
                            (not (gethash tail cells)))
                 (refuse "outcome must be a proper keyword plist without duplicate keys"))
               (setf (gethash tail cells) t)
               (push (car tail) seen)
               (setf tail (cddr tail))))
    (unless (shrink-report-p (getf outcome :shrink-report))
      (refuse ":shrink-report requires bounded candidate counts and a termination keyword"))
    (when (and (getf outcome :generation-report)
               (not (generation-report-p (getf outcome :generation-report))))
      (refuse ":generation-report requires a coherent bounded-filter report"))
    (when (and (getf outcome :capabilities)
               (not (capability-report-p (getf outcome :capabilities))))
      (refuse ":capabilities must report valid generation and shrinking states"))
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
      (unless (member status '(:passed :failed :error :skipped))
        (refuse "unknown or missing :status"))
      (cond
        ((generation-only-outcome-p outcome)
         (when (or original shrunk disposition)
           (refuse "a generation-only error cannot carry target failure evidence")))
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
                        (property-call-arguments-p property
                                                   (trial-observation-arguments observation))
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
         (unless (eq status (trial-observation-status selected))
           (refuse "status must describe the selected counterexample"))))
      outcome)))

(defmethod run-generated-test :around (backend property &key options)
  "Own one generation request and enforce the backend outcome protocol.

The request's candidate budget is shared by every bounded AND filter the run
reaches.  An explicit :GENERATION-BUDGET option is validated before execution;
otherwise the default coefficient applies.  The effective generation report is
attached to the outcome before validation, and a request-owned exhaustion that
reaches this boundary becomes the narrow generation-only error branch."
  (let ((budget (getf options :trials :missing))
        (*trial-observations* (list nil)))
    (unless (and (integerp budget) (not (minusp budget)))
      (error 'type-error :datum budget :expected-type '(integer 0 *)))
    (let* ((explicit (getf options :generation-budget :missing))
           (request (if (eq explicit :missing)
                        (make-generation-request :planned budget)
                        (make-generation-request :planned budget :budget explicit)))
           (*generation-request* request)
           (outcome (handler-case (call-next-method)
                      (generation-budget-exhausted (condition)
                        (if (owned-generation-exhaustion-p condition :generation)
                            (list :status :error
                                  :trials 0
                                  :rejected 0
                                  :failure-reason :generation-budget-exhausted
                                  :failure-phase :generation
                                  :condition condition)
                            (error condition))))))
      (validate-backend-outcome
       (list* :generation-report (generation-request-report request) outcome)
       property budget))))

(defgeneric backend-capabilities (backend spec &key registry)
  (:documentation "Describe generation and shrinking without drawing or invoking user predicates."))

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
from an agent."
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
