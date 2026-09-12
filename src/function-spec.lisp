;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unknown-function-spec
                #:unbound-target
                #:invalid-function-spec-form
                #:spec-violation)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-find-function-spec
                #:registry-register-function-spec)
  (:import-from #:cl-spec/src/schema
                #:definition-description #:definition-entity-kind #:definition-generation-schema
                #:resolve-definition)
  (:import-from #:cl-spec/src/ir #:tuple-spec)
  (:import-from #:cl-spec/src/property
                #:property #:property-argument-schema)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-schema-metadata #:property-result-budget
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
                #:property-result-failure-evidence #:property-result-shrunk-evidence
                #:property-result-shrunk-outcome #:property-result-rejected
                #:property-result-failure-reason #:property-result-explanation
                #:property-result-entity-kind)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:backend-default-trials)
  (:import-from #:cl-spec/src/execution
                #:evaluate-trial #:snapshot-value #:failure-identities-match-p)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:export #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-argument-generator #:function-spec-argument-schema
           #:function-spec-return-spec
           #:function-spec-preconditions
           #:function-spec-postconditions
           #:function-spec-precondition-function
           #:function-spec-postcondition-function
           #:function-spec-documentation
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:register-function-spec
           #:function-check-result
           #:function-check-result-function
           #:function-check-result-budget
           #:function-check-result-source-form
           #:function-check-result-rejected
           #:function-check-result-failure-reason
           #:function-check-result-explanation
           #:function-check-result-shrunk-outcome
           #:check-function))

(in-package #:cl-spec/src/function-spec)

(defclass function-spec ()
  ((name :initarg :name
         :initform nil
         :reader function-spec-name
         :documentation "Package-qualified symbol naming the specified function.")
   (argument-specs :initarg :argument-specs
                   :initform nil
                   :reader function-spec-argument-specs
                   :documentation "List of (PARAMETER SPEC) pairs in lambda list
order, from :ARGS.  SPEC is always a Semantic IR object: a designator handed to
the constructor is normalized in place, so every reader sees one shape.  Each
PARAMETER is named once.")
   (argument-generator :initarg :argument-generator
                       :initform nil
                       :reader function-spec-argument-generator
                       :documentation "Name of a registered no-argument generator returning
the entire positional argument list, or NIL for independent argument generation.
Each draw is checked against the argument specs before preconditions or the target.")
   (return-spec :initarg :return-spec
                :initform nil
                :reader function-spec-return-spec
                :documentation "Semantic IR object the return value must
satisfy, from :RETURNS, or NIL when the contract names none.")
   (preconditions :initarg :preconditions
                  :initform nil
                  :reader function-spec-preconditions
                  :documentation "The :PRE forms as written, kept for reading
(specification §19).  PRECONDITION-FUNCTION is what actually runs.")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-spec-postconditions
                   :documentation "The :POST forms as written, kept for reading.
POSTCONDITION-FUNCTION is what actually runs.")
   (precondition-function :initarg :precondition-function
                          :initform nil
                          :reader function-spec-precondition-function
                          :documentation "Compiled predicate over the parameters,
true when every :PRE form holds, or NIL when the contract has no :PRE.

Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.")
   (postcondition-function :initarg :postcondition-function
                           :initform nil
                           :reader function-spec-postcondition-function
                           :documentation "Compiled predicate over the return
value followed by the parameters, true when every :POST form holds, or NIL when
the contract has no :POST. To identify a failed form for shrinking, return
(values nil index :cl-spec-post-form-failure), where INDEX is its zero-based
position in POSTCONDITIONS. A one-value predicate remains valid, but its failures
have unknown form identity and cannot be accepted as shrink reductions.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader function-spec-documentation
                         :documentation "Docstring of the contract, or NIL.

This is the contract's own prose, not the function's: it says what the contract
claims, which is what an agent asking \"what may I pass here\" needs.")
   (source-form :initarg :source-form
                :initform nil
                :reader function-spec-source-form
                :documentation "The whole DEFSPEC-FUNCTION form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader function-spec-source-location
                    :documentation "Source location plist, or NIL.")
   (metadata :initarg :metadata
             :initform nil
             :reader function-spec-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "A contract attached to an existing function by name.

The function is never redefined, so an existing codebase adopts cl-spec one
function at a time (specification §3.2)."))

(defparameter *function-spec-slot-names*
  '(name argument-specs argument-generator return-spec preconditions postconditions
    precondition-function postcondition-function documentation-string
    source-form source-location metadata)
  "Every slot of FUNCTION-SPEC, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod shared-initialize :around ((contract function-spec) slot-names &rest initargs)
  "Leave CONTRACT as it was when initialization is refused.

The :AFTER method below validates, but by the time it runs the standard method
has already written the initargs into the slots.  So catching its refusal left
the object holding exactly the state the check exists to refuse -- and
discarding it is not open to the caller, because REGISTER-FUNCTION-SPEC stores
the object by identity: the registry, FIND-FUNCTION-SPEC, FUNCTION-SPEC-DATA
and CHECK-FUNCTION are all aliased to that one instance.  A refused
REINITIALIZE-INSTANCE could leave a registered contract whose :PRECONDITIONS
the checker then ignored while reporting :PASSED, or whose argument specs no
longer normalized, and a refused :RETURN-SPEC typo destroyed a return spec that
had been fine.

Restoring an unbound slot writes NIL rather than making it unbound again, which
matters only during MAKE-INSTANCE -- where the object is discarded anyway."
  (flet ((supplied (key)
           ;; Keys only.  MEMBER matched values as well, which both refused a
           ;; contract whose :METADATA happened to be the keyword :PRECONDITIONS
           ;; and, worse, let the real case through when the other keyword sat
           ;; in a value position -- the guard reporting itself satisfied by the
           ;; very shape it exists to catch.
           (loop for (k) on initargs by #'cddr thereis (eq k key))))
    ;; Both halves of a clause change together or not at all.  The :AFTER
    ;; method sees only the final state, which is consistent when one half is
    ;; new and the other is left over -- so REINITIALIZE-INSTANCE with
    ;; :PRECONDITIONS alone paired new text with the stale compiled predicate,
    ;; and the checker ran the old claim while introspection showed the new
    ;; one.  It reported :PASSED for a contract that is false.
    (when (or (and (supplied :preconditions) (not (supplied :precondition-function)))
              (and (supplied :precondition-function) (not (supplied :preconditions))))
      (error 'invalid-function-spec-form
             :form (getf initargs :preconditions)
             :reason ":preconditions and :precondition-function change together"))
    (when (or (and (supplied :postconditions) (not (supplied :postcondition-function)))
              (and (supplied :postcondition-function) (not (supplied :postconditions))))
      (error 'invalid-function-spec-form
             :form (getf initargs :postconditions)
             :reason ":postconditions and :postcondition-function change together")))
  (let ((snapshot (loop for slot in *function-spec-slot-names*
                        collect (cons slot (when (slot-boundp contract slot)
                                             (slot-value contract slot)))))
        (committed nil))
    (unwind-protect
         (multiple-value-prog1 (apply #'call-next-method contract slot-names initargs)
           (setf committed t))
      (unless committed
        (loop for (slot . value) in snapshot
              do (setf (slot-value contract slot) value))))))

(defmethod shared-initialize :after ((contract function-spec) slot-names &key)
  "Refuse a contract that could not be honoured, and normalize what can be.

Enforced here rather than in CHECK-FUNCTION because the class and
REGISTER-FUNCTION-SPEC are both public: a contract can be built without the
DSL, and every consumer -- the checker, FUNCTION-SPEC-DATA, a future printer --
would otherwise have to re-derive the same invariants or be handed an object
the others rejected.

On SHARED-INITIALIZE rather than INITIALIZE-INSTANCE, because MAKE-INSTANCE is
not the only standard way to fill these slots: REINITIALIZE-INSTANCE and
CHANGE-CLASS reach them too, and a check that covers only the first lets the
second put back exactly the states it exists to refuse.

Three invariants:

A clause's forms and its compiled predicate are present together or not at all.
Forms alone cannot be run -- §60 forbids runtime EVAL, so the predicate cannot
be recovered from them -- and the checker would report :PASSED for a claim it
ignored.  A predicate alone is the same failure seen from the other side: it
runs, so inputs are refused and results judged, while FUNCTION-SPEC-DATA
reports the contract as having no such clause.

A parameter is named once.  §14's counterexample is a {name value} plist, and
one built over a name bound twice is not one: GETF answers with the first
value and the second cannot be recovered, so the counterexample reported for a
failure cannot reproduce it.

Spec designators are normalized rather than refused, because unlike a
predicate they can be recovered: NORMALIZE-SPEC-FORM is pure, and returns an
already-normalized spec unchanged, so the DSL's output passes through
untouched.  Without this a contract built through the class reached the
generator as a bare symbol and signalled NO-APPLICABLE-METHOD."
  (declare (ignore slot-names))
  (flet ((refuse (form reason)
           (error 'invalid-function-spec-form :form form :reason reason))
         (half (forms-initarg function-initarg forms predicate)
           (cond ((and forms (null predicate))
                  (format nil "~A was given without ~A, and a compiled ~
predicate cannot be recovered from the forms"
                          forms-initarg function-initarg))
                 ((and predicate (null forms))
                  (format nil "~A was given without ~A, so the predicate ~
would run while introspection reported no such clause"
                          function-initarg forms-initarg)))))
    (let ((pre (half ":preconditions" ":precondition-function"
                     (function-spec-preconditions contract)
                     (function-spec-precondition-function contract)))
          (post (half ":postconditions" ":postcondition-function"
                      (function-spec-postconditions contract)
                      (function-spec-postcondition-function contract))))
      (when pre
        (refuse (or (function-spec-preconditions contract)
                    (function-spec-precondition-function contract))
                pre))
      (when post
        (refuse (or (function-spec-postconditions contract)
                    (function-spec-postcondition-function contract))
                post)))
    (let ((seen '()))
      (setf (slot-value contract 'argument-specs)
            (loop for entry in (function-spec-argument-specs contract)
                  do (unless (and (consp entry)
                                  (= 2 (length entry))
                                  (first entry)
                                  (symbolp (first entry))
                                  (not (keywordp (first entry))))
                       ;; Not merely malformed: (amount integer extra) would
                       ;; otherwise pass through with EXTRA silently dropped.
                       (refuse entry "expected (parameter spec)"))
                     (when (member (first entry) seen)
                       (refuse entry "the same parameter is named twice"))
                     (push (first entry) seen)
                  collect (list (first entry) (normalize-spec-form (second entry))))))
    (let ((generator (function-spec-argument-generator contract)))
      (unless (or (null generator)
                  (and (symbolp generator) (not (keywordp generator))))
        (refuse generator ":argument-generator must be NIL or a registered generator name")))
    (let ((returns (function-spec-return-spec contract)))
      (when returns
        (setf (slot-value contract 'return-spec) (normalize-spec-form returns))))))

(defun function-spec-argument-schema (contract)
  "Derive the whole argument tuple schema from CONTRACT's current declarations."
  (make-instance 'tuple-spec
                 :element-specs (mapcar #'second (function-spec-argument-specs contract))
                 :generator (function-spec-argument-generator contract)))

(defun register-function-spec (function-spec &optional (registry *registry*))
  "Register FUNCTION-SPEC in REGISTRY under its own name and return it."
  (registry-register-function-spec registry
                                   (function-spec-name function-spec)
                                   function-spec))

(defun resolve-function-spec (designator registry)
  "Return the function spec DESIGNATOR names, signalling UNKNOWN-FUNCTION-SPEC.

This lives here rather than beside RESOLVE-SPEC and RESOLVE-PROPERTY because
CHECK-FUNCTION needs the property runner, which needs SRC/RESOLVE: putting the
function spec case there would close the dependency graph into a cycle."
  (if (typep designator 'function-spec)
      designator
      (multiple-value-bind (entry found-p)
          (registry-find-function-spec registry designator)
        (if found-p
            entry
            (error 'unknown-function-spec :name designator)))))

(defclass function-check-result (property-result)
  ((source-form :initarg :source-form
                :initform nil
                :reader function-check-result-source-form
                :documentation "The contract's own source form, as it was when
the run started.

The run holds the contract by identity, but the result identified it only by
name.  Re-registering that name -- a reload, an edit -- leaves the result
saying \"F passed\" while the contract now under F is one F fails, with nothing
to notice it by.")
   (rejected :initarg :rejected
             :initform 0
             :reader function-check-result-rejected
             :documentation "Generated argument lists the preconditions refused.

TRIALS counts what the backend generated; TRIALS minus this is the number of
trials that reached the function.  Reporting only the first would let a run
that rejected every input read as a run that checked every input (§19, §73.3).

Not the number of calls: shrinking may invoke the function on candidate inputs.
Classification itself makes no additional call. This counts generated trials.")
   (failure-reason :initarg :failure-reason
                   :initform nil
                   :reader function-check-result-failure-reason
                   :documentation "Which half of the contract broke:
:RETURN-SPEC, :POSTCONDITION, :CONDITION, :CONTRACT-ERROR, or NIL.

:CONTRACT-ERROR is not a half breaking: the contract's own predicate or spec
signalled on the value the function returned, so the fault may be either
side's.

It describes the counterexample this result puts forward -- the shrunk one
when there is one, the original otherwise -- and the status agrees with it.

There is no :PRECONDITION: the trial predicate answers true for every input
:PRE refuses, so one can never be the reason a run failed.

NIL on a passing or skipped run. Failure reasons come from the recorded
invocation, including for a function that would not answer the same way twice.")
   (explanation :initarg :explanation
                :initform nil
                :reader function-check-result-explanation
                :documentation "EXPLAIN-DATA for a :RETURN-SPEC failure, else NIL.

\"The return value is wrong\" is not actionable on its own; this says which
part of the return spec the value missed.")
   (shrunk-outcome :initarg :shrunk-outcome
                   :initform nil
                   :reader function-check-result-shrunk-outcome
                   :documentation "What became of the shrink candidate: :USED, :NONE or
:DIFFERENT-FAILURE, or NIL when no failure was reported.

A NIL SHRUNK-COUNTEREXAMPLE cannot say this on its own -- it reads the same
whether the shrinker found nothing smaller or produced a candidate the checker
refused to put forward -- and on a failing contract run the second reading is the
common one.  :USED means the value in SHRUNK-COUNTEREXAMPLE is the candidate.
:DIFFERENT-FAILURE means incompatible failures were rejected and no matching
reduction was observed. :NONE means no reduction was observed, including when
there were no arguments, shrinking was disabled, or argument mutation stopped it.
When a matching candidate is observed, :USED takes precedence over earlier
rejections. The original evidence remains available in every case."))
  (:documentation "Outcome of checking a function against its registered contract.

A PROPERTY-RESULT, so one set of readers covers a DEFPROPERTY run and a
CHECK-FUNCTION run alike.  That is also the rule for which reader to reach for:
everything a property run also has -- STATUS, TRIALS, SEED, PROFILE, both
counterexamples, CONDITION, ELAPSED -- is read with PROPERTY-RESULT-, and only
what a contract run adds is read with FUNCTION-CHECK-RESULT-.  There is no
FUNCTION-CHECK-RESULT-STATUS, and asking for one is a reader error rather than
an undefined function, so it takes the whole enclosing form with it.

The inherited PROPERTY slot holds the specified function's name: the run's
identity is the contract, and the contract is registered under that name.  The
name alone does not pin the contract down, though -- re-registering it leaves
this result describing a definition that is no longer there -- so SOURCE-FORM
records what was actually run."))

(defmethod function-check-result-budget ((result function-check-result))
  "Return the trial budget stored in the shared property result."
  (property-result-budget result))

(defun function-check-result-function (result)
  "Return the name of the function RESULT checked.

The same symbol PROPERTY-RESULT-PROPERTY returns, under the name that says what
it is here."
  (property-result-property result))

(defun function-spec-target (contract)
  "Return the function CONTRACT specifies, signalling UNDEFINED-FUNCTION otherwise.

A contract may be registered before the function it describes exists -- §3.2
adopts cl-spec one function at a time -- so the absence is reported at check
time rather than at definition time."
  (let ((name (function-spec-name contract)))
    (unless (fboundp name)
      (error 'unbound-target :name name))
    (symbol-function name)))

(defun precondition-refuses-p (precondition arguments)
  "Return true when PRECONDITION refuses ARGUMENTS, NIL when it admits them.

A :PRE written with CL-SPEC:VALIDATE signals SPEC-VIOLATION instead of answering
NIL, because judging that a value misses a spec is what VALIDATE does.  That
signal is a refusal, not an unevaluable contract: left to the trial loop's error
handler it ended the run as :ERROR / :CONTRACT-ERROR at the first input the
contract did not admit, so a run that passes on every input it accepts was
reported as a failure of the function (§73.4 #1).

SPEC-VIOLATION is a refusal only here.  One raised by :POST, by :RETURNS or by
the target is about a value the function produced, and stays a contract error or
a finding exactly as it was."
  (and precondition
       (handler-case (not (apply precondition arguments))
         (spec-violation () t))))

(defparameter *failure-shape-keys*
  '(:kind :expected :violated-bound :predicate :condition-type :expected-length
    :status :tuple-path)
  "The EXPLAIN-DATA error keys FAILURE-SHAPE keeps, because they come from the SPEC.

A whitelist, not a list of keys to strip.  Stripping by name failed three times in
review: :ACTUAL first, then :ACTUAL-LENGTH (a tuple's actual arity) and :PATH (a
position inside the value), then :CONDITION-REPORT (a condition's text, which
embeds the value).  Each varies with the input, so two instances of one failure
compared unequal and a legitimate reduction was thrown away.  A key derived from
the spec is safe to compare; a new EXPLAIN-DATA key is treated as value-derived
until someone classifies it here, and EVERY-EXPLAINED-ERROR-KEY-IS-CLASSIFIED
fails until they do.")

(defparameter *failure-shape-containers* '(:errors :branches :conjuncts)
  "EXPLAIN-DATA error keys whose value is a list of error-shaped plists to walk.

:ERRORS is the conjunct and negation case, :BRANCHES an OR's, and :CONJUNCTS the
per-conjunct descriptors an :AND reports.")

(defun failure-shape (error-datum)
  "Return the SPEC-derived part of one EXPLAIN-DATA error datum, recursively.

The shape of a failure is what EXPLAIN-DATA says about the spec, without the value
it was found on: two failures have the same shape exactly when the same clause of
the spec was missed in the same way.  A value differs between an input and any
shrink of it by construction, so every key derived from one -- :ACTUAL,
:ACTUAL-LENGTH, a :PATH into the value, a condition's :CONDITION-REPORT -- stays
out of the shape, and every key derived from the spec -- :KIND, the :EXPECTED
descriptor, :EXPECTED-LENGTH, :VIOLATED-BOUND, :PREDICATE, :CONDITION-TYPE, a
conjunct's :STATUS and fixed :TUPLE-PATH -- stays in. See *FAILURE-SHAPE-KEYS*
for why that is a whitelist rather than a list of keys to strip."
  (loop for (key value) on error-datum by #'cddr
        when (member key *failure-shape-containers*)
          append (list key (mapcar #'failure-shape value))
        when (member key *failure-shape-keys*)
          append (list key value)))

(defun failure-signature (reason explanation condition)
  "Return a comparable key for a classified failure, or NIL when there is none.

REASON alone is too coarse to compare two classifications with: every signalled
condition collapses to :CONDITION and every return-spec violation to
:RETURN-SPEC, so two unrelated failures of the same shape compared equal and a
shrink candidate that had walked out of the failing region was reported as its
reduction (§73.4 #2).  The key carries the detail the keyword throws away -- the
condition's type, and for a return-spec violation the shape of the EXPLAIN-DATA
errors.

Those errors are where the detail lives.  A return spec's EXPLAIN-DATA has no
:KIND at its top level at all, and its :PATH is NIL, so reading those two keys
gave every return-spec failure the same key: a candidate that crossed from one
conjunct of :RETURNS to another compared equal to the finding and was put forward
as its reduction.  The shapes come from the nested errors instead."
  (case reason
    (:return-spec
     (list :return-value :return-spec
           (mapcar #'failure-shape (getf explanation :errors))))
    (:postcondition (list :return-value :postcondition explanation))
    (:condition (list :target-signal (type-of condition)))
    (:contract-error (list :contract-error (type-of condition)))
    (t nil)))

(defun same-failure-p (original candidate)
  "Compare function failure identities using the shared execution protocol."
  (failure-identities-match-p original candidate))

(defclass function-check-property (property)
  ((contract :initarg :contract :reader checked-contract)
   (target :initarg :target :reader checked-target))
  (:documentation "Internal property adapter whose trial evaluation records the contract outcome."))

(defmethod property-argument-schema ((property function-check-property))
  "Use the function's whole argument schema, including its custom generator."
  (function-spec-argument-schema (checked-contract property)))

(defmethod evaluate-trial ((property function-check-property) arguments &key context)
  "Call the target once and classify that invocation before returning its evidence."
  (let* ((contract (checked-contract property))
         (registry (getf context :registry))
         (returns (function-spec-return-spec contract))
         (pre (function-spec-precondition-function contract))
         (post (function-spec-postcondition-function contract)))
    (flet ((failure (reason detail condition &optional value)
             (values (if condition :error :failed) reason
                     (failure-signature reason detail condition) detail condition value)))
      (handler-case
          (if (precondition-refuses-p pre arguments)
              (values :rejected nil nil nil nil nil)
              (multiple-value-bind (value condition)
                  (handler-case (values (apply (checked-target property) arguments) nil)
                    (error (condition) (values nil condition)))
                (if condition
                    (failure :condition nil condition)
                    (let ((explanation (when returns
                                         (explain-data returns value :registry registry))))
                      (cond
                        ((and explanation (not (getf explanation :valid)))
                         (failure :return-spec explanation nil value))
                        (post
                         (multiple-value-bind (holds index tag)
                             (apply post value arguments)
                           (if holds
                               (values :passed nil nil nil nil value)
                               (failure :postcondition
                                        (when (and (eq tag :cl-spec-post-form-failure)
                                                   (integerp index)
                                                   (<= 0 index)
                                                   (< index
                                                      (length
                                                       (function-spec-postconditions contract))))
                                          (list :post-form index))
                                        nil value))))
                        (t (values :passed nil nil nil nil value)))))))
        ;; Structural errors in the contract itself still abort an initial trial.
        ;; The backend rejects these if encountered only during shrinking.
        ((and error (not undefined-function) (not program-error)) (condition)
          (failure :contract-error nil condition))))))

(defmethod property-result-entity-kind ((result function-check-result))
  :function-spec)

(defmethod resolve-definition ((designator symbol) (kind (eql :function-spec)) registry)
  (registry-find-function-spec registry designator))

(defmethod definition-entity-kind ((contract function-spec)) :function-spec)

(defmethod definition-generation-schema ((contract function-spec))
  (function-spec-argument-schema contract))

(defmethod definition-description ((contract function-spec))
  "Describe the contract declaration, not the target implementation."
  (values
   (list :entity-kind :function-spec :name (function-spec-name contract)
         :variables (mapcar #'first (function-spec-argument-specs contract))
         :documentation (function-spec-documentation contract)
         :source (function-spec-source-form contract)
         :pre (function-spec-preconditions contract) :post (function-spec-postconditions contract)
         :returns (not (null (function-spec-return-spec contract)))
         :generator (function-spec-argument-generator contract)
         :metadata (function-spec-metadata contract))
   (append (mapcar #'second (function-spec-argument-specs contract))
           (when (function-spec-return-spec contract)
             (list (function-spec-return-spec contract))))
   (when (function-spec-argument-generator contract)
     (list (cons :generator (function-spec-argument-generator contract))))
   (and (eq (class-name (class-of contract)) 'function-spec)
        (or (not (or (function-spec-precondition-function contract)
                     (function-spec-postcondition-function contract)))
            (not (null (function-spec-source-form contract)))))))

(defmethod definition-description ((property function-check-property))
  (definition-description (checked-contract property)))

(defmethod definition-entity-kind ((property function-check-property)) :function-spec)

(defun check-function (function-designator &key trials seed options (registry *registry*))
  "Check a function contract using evidence captured during each invocation.
No target or predicate is called again to classify the result. Shrinking still
executes candidate inputs; only candidates with the original failure identity
are accepted. A run with no admitted trials is :SKIPPED."
  (unless (or (null trials) (and (integerp trials) (not (minusp trials))))
    (error 'type-error :datum trials :expected-type '(or null (integer 0 *))))
  (unless (or (null seed) (typep seed 'property-result)
              (and (integerp seed) (not (minusp seed))))
    (error 'type-error :datum seed
                      :expected-type '(or null property-result (integer 0 *))))
  (let* ((budget (or trials
                     (when (typep seed 'function-check-result)
                       (function-check-result-budget seed))
                     (backend-default-trials (current-generator-backend))))
         (seed (if (typep seed 'property-result) (property-result-seed seed) seed))
         (contract (resolve-function-spec function-designator registry))
         (name (function-spec-name contract))
         (source (snapshot-value (function-spec-source-form contract)))
         (property (make-instance 'function-check-property
                                  :contract contract :target (function-spec-target contract)
                                  :name name :arguments (function-spec-argument-specs contract)
                                  :targets (list name) :kind :function-spec
                                  :documentation (function-spec-documentation contract)
                                  :trials (list :normal budget)
                                  :source-form source
                                  :source-location (function-spec-source-location contract)
                                  :metadata (list :shrink t)))
         (result (run-property property :seed seed :options options :registry registry)))
    (make-instance 'function-check-result
                   :schema-metadata (property-result-schema-metadata result)
                   :status (property-result-status result)
                   :property name :budget budget :source-form source
                   :trials (property-result-trials result)
                   :seed (property-result-seed result)
                   :profile (property-result-profile result)
                   :counterexample (property-result-counterexample result)
                   :shrunk-counterexample (property-result-shrunk-counterexample result)
                   :failure-evidence (property-result-failure-evidence result)
                   :shrunk-evidence (property-result-shrunk-evidence result)
                   :shrunk-outcome (property-result-shrunk-outcome result)
                   :condition (property-result-condition result)
                   :elapsed (property-result-elapsed result)
                   :rejected (property-result-rejected result)
                   :failure-reason (property-result-failure-reason result)
                   :explanation (property-result-explanation result))))
