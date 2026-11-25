;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
  (:import-from #:cl-spec/src/time-limits #:with-native-candidate #:with-native-shrink)
  (:import-from #:cl-spec/src/time-limits
                #:call-catching-run-timeout #:with-trial-clock #:with-run-phase)
  (:import-from #:cl-spec/src/generator #:backend-time-limit-protocol)
  (:import-from #:cl-spec/src/coverage-report #:coverage-enable-stage
                #:begin-coverage-report #:end-coverage-report #:deferred-coverage-p)
  (:import-from #:cl-spec/src/coverage #:backend-coverage-protocol #:backend-coverage-capabilities)
  (:import-from #:cl-spec/src/backends/check-it-coverage
                #:check-it-coverage-capabilities #:prepare-coverage-plan
                #:next-coverage-target #:*coverage-target*)
  (:import-from #:cl-spec/src/execution #:observe-coverage-trial)
  (:import-from #:cl-spec/src/generator #:backend-trial-reporting)
  (:import-from #:cl-spec/src/trial-report #:end-trial-report)
  (:import-from #:cl-spec/src/ir #:spec-metadata #:tuple-spec-element-specs)
  (:import-from #:cl-spec/src/function-spec #:fixture-check-property)
  (:import-from #:cl-spec/src/generator #:backend-trial-lifecycle)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-lifecycle #:trial-observation-reason
                #:trial-observation-condition)
  (:import-from #:cl-spec/src/backends/call-generators
                #:call-arguments-generator #:call-generator-children #:call-generator-removable-p
                #:call-generator-rest-driven-p)
  (:import-from #:check-it
                #:*num-trials*
                #:generate
                #:*size*
                #:*list-size*
                #:*list-size-decay*
                #:*bias-sensitivity*
                #:*recursive-bias-decay*
                #:cached-value
                #:shrink
                #:tuple-generator #:mapped-generator #:guard-generator
                #:sub-generators #:sub-generator)
  (:import-from #:cl-spec/src/backends/check-it-generators
                #:compile-spec-generator #:custom-value-generator #:custom-value-generator-shrinker
                #:*declaration-path* #:*argument-names* #:effective-generator-name
                #:bounded-filter-generator #:bounded-filter-sub-generator
                #:plist-value-generator #:plist-generator-fields #:plist-generator-children
                #:keyed-value-generator #:keyed-generator-fields #:keyed-generator-children
                #:bounded-collection-generator #:bounded-generator-min-length
                #:bounded-generator-max-length #:bounded-generator-domain-size
                #:bounded-generator-element-probe
                #:map-value-generator #:map-generator-min-count #:map-generator-max-count
                #:map-generator-domain-size #:map-generator-key-probe
                #:map-generator-value-probe)
  (:import-from #:cl-spec/src/field-spec #:field-required-p)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:backend-default-trials #:backend-capabilities
                #:backend-reports-generation)
  (:import-from #:cl-spec/src/generation-request
                #:record-generated-value
                #:record-generation-interruption
                #:with-generation-phase
                #:owned-generation-exhaustion-p)
  (:import-from #:cl-spec/src/execution
                #:snapshot-value #:observe-trial #:observation-failure-p
                #:observation-failure-phase #:begin-trial-report #:note-trial-outcome
                #:failure-identities-match-p #:same-value-p
                #:trial-observation-arguments #:trial-observation-arguments-mutated-p
                #:trial-observation-status
                #:trial-observation-signature)
  (:import-from #:cl-spec/src/conditions
                #:invalid-generated-arguments
                #:generation-budget-exhausted
                #:generator-unavailable #:generator-unavailable-spec
                #:generator-unavailable-reason #:generator-unavailable-kind
                #:generator-unavailable-argument)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/ir #:spec-generator-name)
  (:import-from #:cl-spec/src/validator #:compile-validator)
  (:import-from #:cl-spec/src/property
                #:property-arguments #:property-argument-schema #:property-arguments-spec
                #:property-metadata)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:check-it-backend
           #:install-check-it-backend
           #:default-trials))

(in-package #:cl-spec/src/backends/check-it)

(defparameter *base-size* 10
  "The generation size a run starts from, independent of anything ambient.

A literal, not a snapshot of CHECK-IT:*SIZE*: snapshotting moved the dependency
from run time to load time without removing it, so an image that tuned check-it
before loading cl-spec replayed one seed to different inputs than an image that
did not, with nothing on the result to say so.  RUN-GENERATED-TEST
raises *SIZE* to whatever the widest argument bound needs, and reading the
ambient value made that raise cumulative: a run started inside another -- a
property body that calls CHECK-FUNCTION, a :POST that calls RUN-PROPERTY, both
of which this design invites -- inherited the outer run's size and generated
different inputs.  The same call then reported :FAILED nested and :PASSED alone,
and replaying the nested result contradicted it, which §72.3 forbids.")

(defparameter *base-list-size* 20
  "The longest list a run generates from, independent of anything ambient.

CHECK-IT:LIST-GENERATOR draws a length against *LIST-SIZE* and shrinks that
allowance for nested lists by *LIST-SIZE-DECAY*, so leaving the pair ambient made
a LIST-OF or VECTOR-OF argument's values depend on how the image happened to have
tuned check-it before cl-spec loaded.  These literals repeat check-it's own
defaults on purpose: the pin is what makes generation a function of the spec, the
seed and the backend (§73.4 #7).")

(defparameter *base-list-size-decay* 0.8
  "The factor *BASE-LIST-SIZE* shrinks by for a nested list.  See it for why.")

(defparameter *base-bias-sensitivity* 6.0
  "The sigmoid steepness CHECK-IT:CHOOSE-GENERATOR picks a branch with.

An OR, a MEMBER and a NULLABLE all draw through CHOOSE-GENERATOR, so an ambient
value here decides which branch a value comes from: the same seed picked
different branches in differently tuned images.  See *BASE-LIST-SIZE*.")

(defparameter *base-recursive-bias-decay* 1.5
  "The factor a recursive generator's bias decays by.  See *BASE-LIST-SIZE*.

No recursive spec has a generator in this version, so this changes nothing yet.
It is pinned with the rest so that adding one does not reintroduce an ambient
input -- the kind of gap that surfaces only as a replay disagreeing with the
result it was handed (§72.3).")

(defmacro with-generation-environment ((size &key trials) &body body)
  "Run BODY with every check-it special that decides what is generated pinned.

SIZE is the CHECK-IT:*SIZE* to bind, already raised to whatever the widest
argument's bounds need.  TRIALS, when supplied, also pins CHECK-IT:*NUM-TRIALS*
to the count this run resolved, so nothing reached from BODY reads a trial count
other than the one the run is running.  That count is not thereby hidden: it is
what RUN-PROPERTY resolved and recorded on the result.

Generation is documented as a function of the spec, the seed and the backend
(§15), and it was not one.  RUN-GENERATED-TEST pinned *SIZE* while *LIST-SIZE*,
*LIST-SIZE-DECAY*, *BIAS-SENSITIVITY* and *RECURSIVE-BIAS-DECAY* stayed ambient,
so one seed produced different arguments in a differently tuned image; and
GENERATE-VALUE read *SIZE* ambiently rather than from the generator it was given,
so SAMPLE could show a distribution no run draws (§73.4 #6, #7).  One place binds
them all, which is what keeps the two from drifting apart again."
  `(let ((*coverage-target* nil) ; Each root draw or run owns its targeting plan.
         (*size* ,size)
         (*list-size* *base-list-size*)
         (*list-size-decay* *base-list-size-decay*)
         (*bias-sensitivity* *base-bias-sensitivity*)
         (*recursive-bias-decay* *base-recursive-bias-decay*)
         ,@(when trials `((*num-trials* ,trials))))
     ,@body))

(defclass check-it-backend ()
  ()
  (:documentation "Generator backend delegating to the check-it library."))

(defun default-trials ()
  "Return check-it's current default number of trials per property run."
  *num-trials*)

(defstruct (compiled-generator (:constructor make-compiled-generator (generator size)))
  "A check-it generator together with the CHECK-IT:*SIZE* its bounds require.

Pairing the two is what stops check-it from clamping a range away: *SIZE* has to
be raised around GENERATE, and only the compiler knows how far."
  (generator nil :read-only t)
  (size 0 :read-only t))

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator paired with the size its bounds need.

OPTIONS is accepted for protocol compatibility; check-it takes its sizing from
its own specials rather than per-generator options."
  (declare (ignore backend options))
  (multiple-value-bind (generator size) (compile-spec-generator spec context)
    (make-compiled-generator generator size)))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally from a seeded state.

The generation environment is the one RUN-GENERATED-TEST binds, so a value drawn
here and a value drawn inside a run come from the same distribution, at the same
size -- the size COMPILED-GENERATOR's own bounds require, not whatever *SIZE*
happened to be ambient.  Reading the ambient value made a SAMPLE taken inside
another run inherit the outer run's size, and let a SAMPLE taken alone show a
distribution no run draws (§73.4 #6)."
  (declare (ignore backend))
  (flet ((draw ()
           (with-generation-environment
               ((max *base-size* (compiled-generator-size compiled-generator)))
             (generate (compiled-generator-generator compiled-generator)))))
    (if seed
        (let ((*random-state* (seed->random-state seed)))
          (draw))
        (draw))))

(defmethod backend-default-trials ((backend check-it-backend))
  "Return check-it's current default number of trials."
  (declare (ignore backend))
  *num-trials*)

(defmethod backend-reports-generation ((backend check-it-backend))
  "check-it participates in the request-scoped bounded-filter accounting."
  (declare (ignore backend))
  t)

(defun validate-generated-arguments (name validator arguments)
  "Reject invalid whole argument sets before evaluating a contract."
  (let ((before (snapshot-value arguments)))
    (unless (and (finite-list-p arguments) (funcall validator arguments))
      (error 'invalid-generated-arguments :generator name
             :value before :reason "the argument set does not satisfy its schema"))
    (unless (same-value-p before arguments)
      (error 'invalid-generated-arguments :generator name
             :value before :reason "validation mutated the generated argument set")))
  arguments)

(defun bounded-candidate-list (candidates limit)
  "Return a refusal keyword and inspected count, or NIL for a finite admissible batch.
Over-budget batches are refused before any candidate can invoke user predicates."
  (let ((seen (make-hash-table :test #'eq)) (count 0) (tail candidates))
    (loop
      (when (null tail) (return (values nil count)))
      (unless (and (consp tail) (not (gethash tail seen)))
        (return (values :invalid-candidates count)))
      (when (= count limit) (return (values :budget-exhausted count)))
      (setf (gethash tail seen) t tail (cdr tail))
      (incf count))))

(defun candidate-bucket-key (value)
  "Hash a bounded graph prefix; SAME-VALUE-P remains the equality authority.
Depth limits terminate cycles and bound work on large candidates. Sharing and
unvisited contents may collide, but equivalent snapshots always share a bucket."
  (labels ((prefix-hash (item depth)
             (cond
               ((zerop depth) 0)
               ((consp item)
                (sxhash (list :cons (prefix-hash (car item) (1- depth))
                              (prefix-hash (cdr item) (1- depth)))))
               ((arrayp item)
                (sxhash
                 (list :array (array-dimensions item) (array-element-type item)
                       (when (array-has-fill-pointer-p item) (fill-pointer item))
                       (loop for index below (min 4 (array-total-size item))
                             collect (prefix-hash (row-major-aref item index) (1- depth))))))
               (t (sxhash item)))))
    (prefix-hash value 4)))

(defun sole-custom-argument (generator)
  "Return the sole tuple child's custom generator when it has a value shrinker."
  (when (typep generator 'tuple-generator)
    (let* ((children (sub-generators generator))
           (child (first children)))
      (when (and (null (rest children))
                 (typep child 'custom-value-generator)
                 (custom-value-generator-shrinker child))
        child))))

(defun input-custom-generator (schema generator context)
  "Find the custom generator that can propose every input to one trial."
  (cond ((typep generator 'custom-value-generator) generator)
        ((getf (spec-metadata schema) :fixture-recipe) (sole-custom-argument generator))
        ((typep schema 'property-arguments-spec)
         ;; A single-branch OR or tagged union compiles to its child, but the
         ;; child's annotation still belongs to that branch, not the binding.
         (let ((custom (sole-custom-argument generator)))
           (when (and custom
                      (effective-generator-name (first (tuple-spec-element-specs schema))
                                                context :include-composites nil))
             custom)))))

(defstruct (check-it-progress (:copier nil))
  "Observations already committed to the running backend."
  (trials 0) (rejected 0) original accepted capabilities shrink-candidates)

(defvar *check-it-progress* nil
  "Progress for the active check-it run, including completed shrink observations.")

(defmacro with-shrink-clock (&body body)
  "Use a fresh candidate limit while preserving the failing ordinary trial number."
  `(with-trial-clock ((check-it-progress-trials *check-it-progress*))
     (with-run-phase (:shrinking)
       ,@body)))

(defun shrink-custom-arguments (generator property original validator context budget
                                &key single-value-p)
  "Search ordered candidates while retaining the original failure identity.
A whole-input shrinker proposes argument lists. A single-value shrinker receives
the value from the argument snapshot and each candidate binds that one argument."
  (let ((accepted nil) (different nil) (count 0)
        (current (trial-observation-arguments original))
        (visited (make-hash-table :test #'eql)))
    (setf (check-it-progress-shrink-candidates *check-it-progress*) 0)
    (push (snapshot-value current) (gethash (candidate-bucket-key current) visited))
    (labels ((finish (reason &optional abort)
               (return-from shrink-custom-arguments
                 (values accepted different
                         (list :candidates count :budget budget :termination reason) abort)))
             (consider (candidate)
               (setf (check-it-progress-shrink-candidates *check-it-progress*) (incf count))
               (with-shrink-clock
                 (let ((bucket (candidate-bucket-key candidate)))
                 (when (some (lambda (prior) (same-value-p prior candidate))
                             (gethash bucket visited))
                   (return-from consider nil))
                 (let* ((arguments (snapshot-value candidate))
                        (before (snapshot-value arguments)))
                   (push before (gethash bucket visited))
                   (let ((admitted
                           (handler-case (and (finite-list-p arguments)
                                              (funcall validator arguments))
                             (error () (finish :validation-error)))))
                     (unless (same-value-p before arguments) (finish :mutation))
                     (unless admitted (return-from consider nil)))
                   (let ((observation
                           (handler-case (observe-trial property arguments :context context)
                             (error () (finish :execution-error)))))
                     (when (eq :fixture (observation-failure-phase observation))
                       (finish :fixture-error observation))
                     (when (trial-observation-arguments-mutated-p observation) (finish :mutation))
                     (unless (observation-failure-p observation) (return-from consider nil))
                     (if (failure-identities-match-p (trial-observation-signature original)
                                                     (trial-observation-signature observation))
                         (progn (setf (check-it-progress-accepted *check-it-progress*) observation
                                      accepted observation
                                      current (trial-observation-arguments observation))
                                t)
                         (progn (setf different t) nil))))))))
      (loop
        (when (= count budget) (finish :budget-exhausted))
        (let* ((input (snapshot-value current))
               (candidates
                 (with-shrink-clock
                   (handler-case (funcall (custom-value-generator-shrinker generator)
                                          (if single-value-p (first input) input))
                     (error () (finish :shrinker-error))))))
          (unless (same-value-p input current) (finish :mutation))
          (multiple-value-bind (reason inspected)
              (bounded-candidate-list candidates (- budget count))
            (when reason
              (setf (check-it-progress-shrink-candidates *check-it-progress*)
                    (incf count inspected))
              (finish reason)))
          (unless (loop for value in candidates
                        thereis (consider (if single-value-p (list value) value)))
            (finish :exhausted)))))))

(defun refusing-argument (property context)
  "Return the name of the first argument of PROPERTY whose spec has no generator, or NIL."
  (loop for (name spec) in (property-arguments property)
        when (handler-case (progn (compile-spec-generator spec context) nil)
               (generator-unavailable () t))
          return name))

(defun compile-argument-generator (backend property schema context)
  "Compile SCHEMA for PROPERTY's run, naming the argument a refusal is about.

A GENERATOR-UNAVAILABLE from the argument schema names only the innermost node
that refused, which says nothing about which of several arguments needs a
generator.  The arguments are compiled one at a time only on that failure path,
and the refusal is signalled again with the first argument that reproduces it.

The schema is compiled as the root of the run's declaration paths, so a bounded
filter under an argument reports (:ARGS NAME ...) as where its budget ran out."
  (let ((*declaration-path* nil)
        (*argument-names* (mapcar #'first (property-arguments property))))
    (handler-bind ((generator-unavailable
                     (lambda (condition)
                       (when (and (eq (type-of condition) 'generator-unavailable)
                                  (null (generator-unavailable-argument condition)))
                         (let ((argument (refusing-argument property context)))
                           (when argument
                             (error 'generator-unavailable
                                    :spec (generator-unavailable-spec condition)
                                    :reason (generator-unavailable-reason condition)
                                    :kind (generator-unavailable-kind condition)
                                    :argument argument)))))))
      (compile-generator backend schema :context context))))

(defun record-checked-trial (property trial observation)
  "Commit the ordinary verdict to both the trial report and the run progress."
  (note-trial-outcome property observation)
  (setf (check-it-progress-trials *check-it-progress*) trial)
  (when (eq :rejected (trial-observation-status observation))
    (incf (check-it-progress-rejected *check-it-progress*)))
  (when (and (observation-failure-p observation)
             (not (eq :fixture (observation-failure-phase observation))))
    (setf (check-it-progress-original *check-it-progress*) observation)))

(defun timed-out-check-it-outcome (timeout options)
  "Keep completed trials and previously observed counterexamples on expiration."
  (let* ((progress *check-it-progress*)
         (original (check-it-progress-original progress))
         (accepted (check-it-progress-accepted progress))
         (candidates (check-it-progress-shrink-candidates progress)))
    (append (list :status :timeout :timeout timeout :failure-reason :timeout
                  :failure-phase (getf timeout :phase)
                  :trials (check-it-progress-trials progress)
                  :rejected (check-it-progress-rejected progress)
                  :capabilities (check-it-progress-capabilities progress))
            (when original
              (list :failure original :shrunk-failure accepted
                    :shrunk-outcome (if accepted :used :none)))
            (when candidates
              (list :shrink-report (list :candidates candidates
                                         :budget (getf options :shrink-budget 100)
                                         :termination :timeout))))))

(defmethod backend-time-limit-protocol ((backend check-it-backend))
  (when (eq (class-of backend) (find-class 'check-it-backend))
    :time-limits-v1))

(defgeneric run-check-it-test (backend property options)
  (:documentation "Execute the checked backend's ordinary or fixture trial loop."))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  (let ((*check-it-progress* (make-check-it-progress)))
    (begin-trial-report property)
    (begin-coverage-report property)
    (call-catching-run-timeout
     (lambda ()
       (let ((outcome (run-check-it-test backend property options)))
         (with-run-phase (:run (max 1 (getf outcome :trials)))
           outcome)))
     (lambda (timeout) (timed-out-check-it-outcome timeout options)))))

(defun shrink-native-arguments (generator property original validator context)
  "Search native candidates and retain each observed reduction as it is accepted."
  (let ((accepted nil) (different nil))
    (with-native-shrink ((check-it-progress-trials *check-it-progress*))
      (handler-case
          (block search
            (shrink
             generator
             (lambda (arguments)
               (with-native-candidate
                 (handler-case
                     (let ((before (snapshot-value arguments))
                           (admitted (and (finite-list-p arguments)
                                          (funcall validator arguments))))
                       (unless (same-value-p before arguments) (return-from search nil))
                       (if admitted
                           (let ((candidate (observe-trial property arguments :context context)))
                             (when (trial-observation-arguments-mutated-p candidate)
                               (return-from search nil))
                             (cond
                               ((not (observation-failure-p candidate)) t)
                               ((failure-identities-match-p
                                 (trial-observation-signature original)
                                 (trial-observation-signature candidate))
                                (unless (same-value-p (trial-observation-arguments original)
                                                      (trial-observation-arguments candidate))
                                  (setf (check-it-progress-accepted *check-it-progress*) candidate
                                        accepted candidate))
                                nil)
                               (t (setf different t) t)))
                           t))
                   (error () (setf different t) t))))))
        (generation-budget-exhausted (condition)
          (if (owned-generation-exhaustion-p condition :shrinking)
              (error condition)
              (progn (record-generation-interruption)
                     (setf different t))))
        (error ()
          (record-generation-interruption)
          (setf different t))))
    (values accepted different)))

(defmethod run-check-it-test ((backend check-it-backend) property options)
  "Generate trials and retain only admitted, observed reductions of the original failure.
The shrinker's return value is not evidence: some generators transform it after
the last callback. Reject internal representations and domain violations before
calling user code, and keep existing evidence if shrinking itself fails.
Running trials is reported before the first draw, so a run with no observation
still reports the zeros it knows.
A trial that stopped before the target -- a function-spec case-selection error --
is reported with its :FAILURE-PHASE and is not shrunk: repeating a failure the
target never produced is not a reduction of it."
  (let* ((progress *check-it-progress*)
         (shrink-budget (getf options :shrink-budget 100))
         (context (list :registry (getf options :registry)))
         (trials (getf options :trials))
         (shrink-p (getf (property-metadata property) :shrink t))
         (schema (with-run-phase (:generation) (property-argument-schema property)))
         (custom-name (spec-generator-name schema))
         (whole-validator (with-run-phase (:generation)
                            (compile-validator schema :context context)))
         (compiled (with-run-phase (:generation)
                     (compile-argument-generator backend property schema context)))
         (generator (compiled-generator-generator compiled))
         (custom (input-custom-generator schema generator context))
         (capabilities (compiled-capabilities generator custom shrink-p))
         (coverage-targets (with-run-phase (:generation) (prepare-coverage-plan property))))
    (check-argument shrink-budget '(integer 0 100000) 'run-generated-test :shrink-budget)
    (setf (check-it-progress-capabilities progress) capabilities)
    (when (or custom-name (typep generator 'call-arguments-generator))
      (unless (deferred-coverage-p) (coverage-enable-stage :domain-valid)))
    (with-generation-environment
        ((max *base-size* (compiled-generator-size compiled))
         :trials trials)
      (loop for trial from 1 to trials
            do (let ((original
                       (with-trial-clock (trial)
                         (handler-case
                             (progn
                               (let ((*coverage-target* (next-coverage-target coverage-targets)))
                                 (when coverage-targets (pop coverage-targets))
                                 (with-run-phase (:generation) (generate generator)))
                               (record-generated-value))
                           (generation-budget-exhausted (condition)
                             (if (owned-generation-exhaustion-p condition :generation)
                                 (return-from run-check-it-test
                                   (list :status :error :trials (1- trial)
                                         :rejected (check-it-progress-rejected progress)
                                         :capabilities capabilities
                                         :failure-reason :generation-budget-exhausted
                                         :failure-phase :generation :condition condition))
                                 (error condition))))
                         (observe-coverage-trial
                          property (cached-value generator) :context context :generated t
                          :domain-valid (and (typep generator 'call-arguments-generator)
                                             (call-generator-rest-driven-p generator))
                          :validator
                          (when (or custom-name
                                    (and (typep generator 'call-arguments-generator)
                                         (not (call-generator-rest-driven-p generator))))
                            (lambda ()
                              (validate-generated-arguments custom-name whole-validator
                                                            (cached-value generator))))))))
                 (record-checked-trial property trial original)
                 (when (observation-failure-p original)
                   (let ((accepted nil) (different nil) (report nil)
                         (phase (observation-failure-phase original)))
                     (if phase
                         (setf report (list :candidates 0 :budget shrink-budget
                                            ;; :STATE-POST runs after the target,
                                            ;; so its suppression is the
                                            ;; state-restoration limit, not an
                                            ;; un-called target.
                                            :termination (if (eq :state-post phase)
                                                             :state-restoration-unavailable
                                                             :not-a-target-failure)))
                         (with-run-phase (:shrinking trial)
                           (handler-case
                               (with-generation-phase (:shrinking)
                                 ;; A state-observing contract is not shrunk even
                                 ;; when its outcome contract failed first: the
                                 ;; target was called and its state was never
                                 ;; restored, so no candidate may call it again.
                                 (when (and (getf (property-metadata property)
                                                  :state-constraints)
                                            (null report))
                                   (setf report (list :candidates 0 :budget shrink-budget
                                                      :termination
                                                      :state-restoration-unavailable)))
                                 (when custom
                                   (let ((reason (cond ((getf (property-metadata property)
                                                              :state-constraints)
                                                        :state-restoration-unavailable)
                                                       ((not shrink-p) :disabled)
                                                       ((trial-observation-arguments-mutated-p
                                                         original)
                                                        :mutation)
                                                       ((null
                                                         (custom-value-generator-shrinker custom))
                                                        :no-shrinker))))
                                     (if reason
                                         (setf report (list :candidates 0 :budget shrink-budget
                                                            :termination reason))
                                         (multiple-value-setq (accepted different report)
                                           (shrink-custom-arguments
                                            custom property original whole-validator context
                                            shrink-budget
                                            :single-value-p (not (eq custom generator)))))))
                                 (when (and (not custom) shrink-p (property-arguments property)
                                            (not (trial-observation-arguments-mutated-p original)))
                                   (multiple-value-setq (accepted different)
                                     (shrink-native-arguments generator property original
                                                              whole-validator context))))
                             (generation-budget-exhausted (condition)
                             (if (owned-generation-exhaustion-p condition :shrinking)
                                 (when report
                                   (setf (getf report :termination)
                                         :generation-budget-exhausted))
                                 (error condition))))))
                     (return
                       (list :status (trial-observation-status (or accepted original))
                             :trials trial :rejected (check-it-progress-rejected progress)
                             :capabilities capabilities
                             :failure original :shrunk-failure accepted :shrink-report report
                             :failure-phase phase
                             :shrunk-outcome (cond (accepted :used)
                                                   (different :different-failure)
                                                   (t :none)))))))
            finally (return (list :status :passed :trials trials
                                   :rejected (check-it-progress-rejected progress)
                                   :capabilities capabilities))))))

(defun generator-shrink-strategy-p (generator)
  "Report known shrinking strategies, preserving legacy non-plist capability reporting.
Plists distinguish constant fields from generators; optional fields can be removed.
Lists can shrink in length even when their element generator cannot shrink."
  (typecase generator
    (custom-value-generator nil)
    (call-arguments-generator
     (or (call-generator-removable-p generator)
         (some (lambda (child)
                  (and (typep child 'check-it:generator)
                       (generator-shrink-strategy-p child)))
                (call-generator-children generator))))
    (plist-value-generator
     (or (some (lambda (field) (not (field-required-p field)))
               (plist-generator-fields generator))
         (some (lambda (child)
                  (and (typep child 'check-it:generator)
                       (generator-shrink-strategy-p child)))
                (plist-generator-children generator))))
    (keyed-value-generator
     (or (some (lambda (field) (not (field-required-p field)))
               (keyed-generator-fields generator))
         (some (lambda (child)
                 (and (typep child 'check-it:generator)
                      (generator-shrink-strategy-p child)))
               (keyed-generator-children generator))))
    (bounded-collection-generator
     (let* ((minimum (bounded-generator-min-length generator))
            (maximum (bounded-generator-max-length generator))
            (domain (bounded-generator-domain-size generator)))
       (if domain
           ;; UNIQUE draws from a fixed pool and keeps no element generators, and
           ;; generation truncates the requested length to that pool size.
           (> (if (eq maximum :unbounded) domain (min maximum domain)) minimum)
           (or (eq maximum :unbounded)
               (> maximum minimum)
               (let ((probe (bounded-generator-element-probe generator)))
                 (and (typep probe 'check-it:generator)
                      (generator-shrink-strategy-p probe)))))))
    (map-value-generator
     (let* ((minimum (map-generator-min-count generator))
            (maximum (map-generator-max-count generator))
            (domain (map-generator-domain-size generator))
            ;; Generation truncates the drawn count to a finite key domain.
            (upper (cond ((null domain) maximum)
                         ((eq maximum :unbounded) domain)
                         (t (min maximum domain)))))
       ;; A map that can only be empty has nothing to shrink, whatever its probes say.
       (and (not (eql upper 0))
            (or (eq upper :unbounded)
                (> upper minimum)
                (some (lambda (probe)
                        (and (typep probe 'check-it:generator)
                             (generator-shrink-strategy-p probe)))
                      (list (map-generator-key-probe generator)
                            (map-generator-value-probe generator)))))))
    ((or tuple-generator mapped-generator)
     (some #'generator-shrink-strategy-p (sub-generators generator)))
    (bounded-filter-generator
     (generator-shrink-strategy-p (bounded-filter-sub-generator generator)))
    (guard-generator (generator-shrink-strategy-p (sub-generator generator)))
    ;; Preserve capability reporting for existing non-plist constant specs.
    (t t)))

(defun compiled-capabilities (generator custom shrink-p)
  "Describe the native or custom shrink strategy available for this input."
  (list :generation :available
        :shrinking (if (and shrink-p
                            (if custom
                                (custom-value-generator-shrinker custom)
                                (generator-shrink-strategy-p generator)))
                       :available :none)))

(defmethod backend-capabilities ((backend check-it-backend) spec &key registry)
  "Probe the compiled root without drawing or invoking a shrinker."
  (handler-case
      (let* ((context (list :registry registry))
             (compiled (compile-generator backend spec :context context))
             (generator (compiled-generator-generator compiled)))
        (compiled-capabilities generator (input-custom-generator spec generator context) t))
    (error () (list :generation :unavailable :shrinking :unavailable))))

(defmethod backend-trial-lifecycle ((backend check-it-backend)) :fixture-v1)

(defmethod run-generated-test :after ((backend check-it-backend) property &key options)
  (declare (ignore options))
  (end-trial-report property)
  (end-coverage-report property))

(defmethod backend-trial-reporting ((backend check-it-backend)) (when (eq (class-of backend) (find-class 'check-it-backend)) :trial-report-v1))

(defmethod backend-coverage-protocol ((backend check-it-backend))
  (when (eq (class-of backend) (find-class 'check-it-backend)) :coverage-v1))

(defmethod backend-coverage-capabilities ((backend check-it-backend) schema options)
  (check-it-coverage-capabilities schema options))

(defun fixture-custom-shrinker (generator budget)
  "Lift a direct recipe custom shrinker to the runner's one-argument representation."
  (let ((child (sole-custom-argument generator)))
    (when child
      (make-instance
       'custom-value-generator :function (lambda () (cached-value generator))
       :shrinker
       (lambda (arguments)
         (let ((candidates (funcall (custom-value-generator-shrinker child) (first arguments))))
           (when (bounded-candidate-list candidates budget)
             (error "Recipe shrinker exceeded the candidate budget"))
           (mapcar #'list candidates)))))))

(defun shrink-fixture-arguments (generator property original validator context budget)
  "Shrink recipes only, aborting at the first fixture lifecycle failure."
  (let ((custom (fixture-custom-shrinker generator budget)))
    (when custom
      (return-from shrink-fixture-arguments
        (shrink-custom-arguments custom property original validator context budget))))
  (let ((accepted nil) (different nil) (count 0) (abort nil) (termination :exhausted))
    (setf (check-it-progress-shrink-candidates *check-it-progress*) 0)
    (with-native-shrink ((check-it-progress-trials *check-it-progress*))
      (block search
        (handler-case
            (shrink generator
                    (lambda (arguments)
                      (when (>= count budget)
                        (setf termination :budget-exhausted)
                        (return-from search nil))
                      (setf (check-it-progress-shrink-candidates *check-it-progress*) (incf count))
                      (with-native-candidate
                        (let ((before (snapshot-value arguments))
                             (admitted (and (finite-list-p arguments)
                                            (funcall validator arguments))))
                        (unless (same-value-p before arguments)
                          (setf termination :mutation)
                          (return-from search nil))
                        (if (not admitted)
                            t
                            (let ((observation (observe-trial property arguments :context context)))
                              (when (eq :fixture (observation-failure-phase observation))
                                (setf abort observation termination :fixture-error)
                                (return-from search nil))
                              (cond
                                ((not (observation-failure-p observation)) t)
                                ((failure-identities-match-p
                                  (trial-observation-signature original)
                                  (trial-observation-signature observation))
                                 (unless (same-value-p (trial-observation-arguments original)
                                                       (trial-observation-arguments observation))
                                   (setf (check-it-progress-accepted *check-it-progress*)
                                         observation
                                         accepted observation))
                                 nil)
                                (t (setf different t) t))))))))
          (generation-budget-exhausted (condition)
            (if (owned-generation-exhaustion-p condition :shrinking)
                (setf termination :generation-budget-exhausted)
                (error condition)))
          (error () (setf termination :shrinker-error)))))
    (values accepted different
            (list :candidates count :budget budget :termination termination) abort)))

(defmethod run-check-it-test ((backend check-it-backend) (property fixture-check-property)
                              options)
  "Run recipe trials and bounded shrinking through the shared fixture observer."
  (let* ((progress *check-it-progress*)
         (budget (getf options :trials))
         (shrink-budget (getf options :shrink-budget 100))
         (context (list :registry (getf options :registry)))
         (schema (with-run-phase (:generation) (property-argument-schema property)))
         (validator (with-run-phase (:generation) (compile-validator schema :context context)))
         (compiled (with-run-phase (:generation)
                     (compile-argument-generator backend property schema context)))
         (generator (compiled-generator-generator compiled))
         (shrink-p (getf (property-metadata property) :shrink t))
         (strategy (or (generator-shrink-strategy-p generator)
                       (fixture-custom-shrinker generator shrink-budget)))
         (capabilities (list :generation :available :shrinking
                             (if (and shrink-p strategy) :available :none))))
    (check-argument shrink-budget '(integer 0 100000) 'run-generated-test :shrink-budget)
    (setf (check-it-progress-capabilities progress) capabilities)
    (with-run-phase (:generation) (prepare-coverage-plan property))
    (labels ((finish (trials &key original accepted different report abort)
               (append
                (list :status (cond (abort :error)
                                    (original (trial-observation-status (or accepted original)))
                                    (t :passed))
                      :trials trials :rejected (check-it-progress-rejected progress)
                      :capabilities capabilities
                      :failure-phase (if abort :fixture
                                         (and original
                                              (observation-failure-phase
                                               (or accepted original)))))
                (when original
                  (list :failure original :shrunk-failure accepted
                        :shrink-report report
                        :shrunk-outcome (cond (accepted :used) (different :different-failure)
                                              (t :none))))
                (when abort
                  (list :run-error abort :failure-reason (trial-observation-reason abort)
                        :condition (trial-observation-condition abort))))))
      (with-generation-environment ((max *base-size* (compiled-generator-size compiled))
                                    :trials budget)
        (loop for trial from 1 to budget
              do (let ((original
                         (with-trial-clock (trial)
                           (handler-case
                               (progn (with-run-phase (:generation) (generate generator))
                                      (record-generated-value))
                             (generation-budget-exhausted (condition)
                               (if (owned-generation-exhaustion-p condition :generation)
                                   (return-from run-check-it-test
                                     (list :status :error :trials (1- trial)
                                           :rejected (check-it-progress-rejected progress)
                                           :capabilities capabilities
                                           :failure-reason :generation-budget-exhausted
                                           :failure-phase :generation :condition condition))
                                   (error condition))))
                           (observe-coverage-trial property (cached-value generator)
                                                   :context context))))
                   (record-checked-trial property trial original)
                   (cond
                     ((eq :fixture (observation-failure-phase original))
                      (return (finish trial :abort original)))
                     ((observation-failure-p original)
                      (if (and shrink-p strategy
                               (getf (trial-observation-lifecycle original) :target-called))
                          (multiple-value-bind (accepted different report abort)
                              (with-run-phase (:shrinking trial)
                                (with-generation-phase (:shrinking)
                                  (shrink-fixture-arguments generator property original validator
                                                            context shrink-budget)))
                            (return (finish trial :original original :accepted accepted
                                            :different different :report report :abort abort)))
                          (return
                            (finish trial :original original
                                    :report (list :candidates 0 :budget shrink-budget
                                                  :termination
                                                  (cond ((not shrink-p) :disabled)
                                                        ((not (getf (trial-observation-lifecycle original)
                                                                    :target-called))
                                                         :not-a-target-failure)
                                                        (t :no-shrinker)))))))))
              finally (return (finish budget)))))))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
