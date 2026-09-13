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
                #:invalid-backend-result)
  (:import-from #:cl-spec/src/property #:property-arguments)
  (:import-from #:cl-spec/src/execution
                #:*trial-observations* #:observation-from-current-run-p #:trial-observation-status
                #:trial-observation-arguments #:trial-observation-signature
                #:trial-observation-condition #:observation-failure-p
                #:failure-identities-match-p #:same-value-p)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec)
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
                        (= (length (trial-observation-arguments observation))
                           (length (property-arguments property)))
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
  "Enforce the backend count and observation protocol at its public boundary."
  (let ((budget (getf options :trials :missing))
        (*trial-observations* (list nil)))
    (unless (and (integerp budget) (not (minusp budget)))
      (error 'type-error :datum budget :expected-type '(integer 0 *)))
    (validate-backend-outcome (call-next-method) property budget)))

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

(defun generator-for (spec-designator &key context options (registry *registry*))
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
The result is opaque to everything but the backend and GENERATE-VALUE."
  (let ((spec (resolve-spec spec-designator registry)))
    (compile-generator (current-generator-backend) spec
                       :context (or context (list :registry registry))
                       :options options)))

(defun sample (spec-designator &key (count 10) seed (registry *registry*))
  "Return a list of COUNT values generated from SPEC-DESIGNATOR.

SEED, when supplied, makes the whole sequence reproducible.  Intended for
inspecting what a spec admits, from the REPL or from an agent."
  (let ((backend (current-generator-backend))
        (generator (generator-for spec-designator :registry registry)))
    (flet ((draw ()
             (loop repeat count collect (generate-value backend generator))))
      (if seed
          (let ((*random-state* (seed->random-state seed)))
            (draw))
          (draw)))))
