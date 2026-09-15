;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
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
                #:bounded-filter-generator #:bounded-filter-sub-generator
                #:plist-value-generator #:plist-generator-fields #:plist-generator-children
                #:keyed-value-generator #:keyed-generator-fields #:keyed-generator-children
                #:bounded-collection-generator #:bounded-generator-min-length
                #:bounded-generator-max-length #:bounded-generator-domain-size
                #:bounded-generator-element-probe)
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
                #:failure-identities-match-p #:same-value-p
                #:trial-observation-arguments #:trial-observation-arguments-mutated-p
                #:trial-observation-status
                #:trial-observation-signature)
  (:import-from #:cl-spec/src/conditions
                #:invalid-generated-arguments
                #:generation-budget-exhausted)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/ir #:spec-generator-name)
  (:import-from #:cl-spec/src/validator #:compile-validator)
  (:import-from #:cl-spec/src/property
                #:property-arguments #:property-argument-schema
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
  `(let ((*size* ,size)
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

(defun shrink-custom-arguments (generator property original validator context budget)
  "Search correlated candidate argument sets while retaining original failure identity.
Return accepted observation, whether another failure occurred, and a bounded report."
  (let ((accepted nil) (different nil) (count 0)
        (current (trial-observation-arguments original))
        (visited (make-hash-table :test #'eql)))
    (push (snapshot-value current) (gethash (candidate-bucket-key current) visited))
    (labels ((finish (reason)
               (return-from shrink-custom-arguments
                 (values accepted different
                         (list :candidates count :budget budget :termination reason)))))
      (loop
        (when (= count budget) (finish :budget-exhausted))
        (let* ((input (snapshot-value current))
               (candidates
                 (handler-case (funcall (custom-value-generator-shrinker generator) input)
                   (error () (finish :shrinker-error)))))
          (unless (same-value-p input current) (finish :mutation))
          (multiple-value-bind (reason inspected)
              (bounded-candidate-list candidates (- budget count))
            (when reason (incf count inspected) (finish reason)))
          (let ((improved nil))
            (dolist (candidate candidates)
              (incf count)
              (unless (some (lambda (prior) (same-value-p prior candidate))
                            (gethash (candidate-bucket-key candidate) visited))
                (let* ((arguments (snapshot-value candidate))
                       (before (snapshot-value arguments)))
                  (push before (gethash (candidate-bucket-key before) visited))
                  (let ((admitted
                          (handler-case
                              (and (finite-list-p arguments) (funcall validator arguments))
                            (error () (finish :validation-error)))))
                    (unless (same-value-p before arguments) (finish :mutation))
                    (when admitted
                      (let ((observation
                              (handler-case (observe-trial property arguments :context context)
                                (error () (finish :execution-error)))))
                        (when (trial-observation-arguments-mutated-p observation)
                          (finish :mutation))
                        (when (observation-failure-p observation)
                          (if (failure-identities-match-p
                               (trial-observation-signature original)
                               (trial-observation-signature observation))
                              (progn
                                (setf accepted observation
                                      current (trial-observation-arguments observation)
                                      improved t)
                                (return))
                              (setf different t)))))))))
            (unless improved (finish :exhausted))))))))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Generate trials and retain only admitted, observed reductions of the original failure.
The shrinker's return value is not evidence: some generators transform it after
the last callback. Reject internal representations and domain violations before
calling user code, and keep existing evidence if shrinking itself fails."
  (let* ((shrink-budget (getf options :shrink-budget 100))
         (context (list :registry (getf options :registry)))
         (trials (getf options :trials))
         (shrink-p (getf (property-metadata property) :shrink t))
         (schema (property-argument-schema property))
         (custom-name (spec-generator-name schema))
         (whole-validator (compile-validator schema :context context))
         (compiled (compile-generator backend schema :context context))
         (capabilities (compiled-capabilities compiled shrink-p))
         (generator (compiled-generator-generator compiled))
         (rejected 0))
    (check-type shrink-budget (integer 0 100000))
    (with-generation-environment
        ((max *base-size* (compiled-generator-size compiled))
         :trials trials)
      (loop for trial from 1 to trials
            do (handler-case
                   (progn (generate generator)
                          (record-generated-value))
                 (generation-budget-exhausted (condition)
                   (if (owned-generation-exhaustion-p condition :generation)
                       (return (list :status :error
                                     :trials (1- trial)
                                     :rejected rejected
                                     :capabilities capabilities
                                     :failure-reason :generation-budget-exhausted
                                     :failure-phase :generation
                                     :condition condition))
                       (error condition))))
               (when (or custom-name
                         (and (typep generator 'call-arguments-generator)
                              (not (call-generator-rest-driven-p generator))))
                 (validate-generated-arguments custom-name whole-validator
                                               (cached-value generator)))
               (let ((original (observe-trial property (cached-value generator)
                                              :context context)))
                 (when (eq :rejected (trial-observation-status original))
                   (incf rejected))
                 (when (observation-failure-p original)
                   (let ((accepted nil) (different nil) (report nil))
                     (handler-case
                         (with-generation-phase (:shrinking)
                           (when (typep generator 'custom-value-generator)
                             (let ((reason (cond ((not shrink-p) :disabled)
                                                 ((trial-observation-arguments-mutated-p original)
                                                  :mutation)
                                                 ((null (custom-value-generator-shrinker generator))
                                                  :no-shrinker))))
                               (if reason
                                   (setf report (list :candidates 0 :budget shrink-budget
                                                      :termination reason))
                                   (multiple-value-setq (accepted different report)
                                     (shrink-custom-arguments generator property original
                                                              whole-validator context
                                                              shrink-budget)))))
                           (when (and (not (typep generator 'custom-value-generator))
                                      shrink-p (property-arguments property)
                                      (not (trial-observation-arguments-mutated-p original)))
                             (handler-case
                                 (block shrink-search
                                   (shrink
                                    generator
                                    (lambda (arguments)
                                      (handler-case
                                          (let ((before (snapshot-value arguments))
                                                (admitted (and (finite-list-p arguments)
                                                               (funcall whole-validator arguments))))
                                            (unless (same-value-p before arguments)
                                              (return-from shrink-search nil))
                                            (if (not admitted)
                                                t
                                                (let ((candidate
                                                        (observe-trial property arguments
                                                                       :context context)))
                                                  (when (trial-observation-arguments-mutated-p candidate)
                                                    (return-from shrink-search nil))
                                                  (cond
                                                    ((not (observation-failure-p candidate)) t)
                                                    ((failure-identities-match-p
                                                      (trial-observation-signature original)
                                                      (trial-observation-signature candidate))
                                                     (unless (same-value-p
                                                              (trial-observation-arguments original)
                                                              (trial-observation-arguments candidate))
                                                       (setf accepted candidate))
                                                     nil)
                                                    (t (setf different t) t)))))
                                        (error () (setf different t) t)))))
                               (generation-budget-exhausted (condition)
                                 (if (owned-generation-exhaustion-p condition :shrinking)
                                     (error condition)
                                     (progn (record-generation-interruption)
                                            (setf different t))))
                               (error ()
                                 (record-generation-interruption)
                                 (setf different t)))))
                       (generation-budget-exhausted (condition)
                         (if (owned-generation-exhaustion-p condition :shrinking)
                             (when report
                               (setf (getf report :termination)
                                     :generation-budget-exhausted))
                             (error condition))))
                     (return
                       (list :status (trial-observation-status (or accepted original))
                             :trials trial :rejected rejected :capabilities capabilities
                             :failure original :shrunk-failure accepted :shrink-report report
                             :shrunk-outcome (cond (accepted :used)
                                                   (different :different-failure)
                                                   (t :none)))))))
            finally (return (list :status :passed :trials trials :rejected rejected
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
    ((or tuple-generator mapped-generator)
     (some #'generator-shrink-strategy-p (sub-generators generator)))
    (bounded-filter-generator
     (generator-shrink-strategy-p (bounded-filter-sub-generator generator)))
    (guard-generator (generator-shrink-strategy-p (sub-generator generator)))
    ;; Preserve capability reporting for existing non-plist constant specs.
    (t t)))

(defun compiled-capabilities (compiled &optional (shrink-p t))
  "Describe actual strategies; custom candidate search is supported only at the root."
  (let ((generator (compiled-generator-generator compiled)))
    (list :generation :available
          :shrinking (if (and shrink-p
                              (if (typep generator 'custom-value-generator)
                                  (custom-value-generator-shrinker generator)
                                  (generator-shrink-strategy-p generator)))
                         :available :none))))

(defmethod backend-capabilities ((backend check-it-backend) spec &key registry)
  "Probe generator construction only; availability does not guarantee valid draws."
  (handler-case
      (compiled-capabilities (compile-generator backend spec :context (list :registry registry)))
    (error () (list :generation :unavailable :shrinking :unavailable))))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
