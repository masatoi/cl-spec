;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/function-spec-definition
                #:make-function-case-with-guard #:function-spec-fixture #:function-spec
                #:function-spec-name #:function-spec-argument-specs
                #:function-spec-argument-generator #:function-spec-argument-schema
                #:function-spec-call-layout #:function-spec-return-schema
                #:function-spec-return-spec #:function-spec-signal-spec
                #:function-spec-preconditions #:function-spec-postconditions
                #:function-spec-post-value-variables #:validate-post-value-variables
                #:function-spec-precondition-function #:function-spec-postcondition-function
                #:function-spec-documentation #:function-spec-source-form
                #:function-spec-source-location #:function-spec-metadata #:function-spec-cases
                #:function-spec-capture-bindings #:function-spec-capture-functions
                #:function-spec-state-frame #:function-spec-state-postconditions
                #:function-spec-state-postcondition-function #:function-case
                #:function-case-name #:function-case-documentation #:function-case-when-forms
                #:function-case-when-function #:function-case-outcome-kind
                #:function-case-outcome-spec #:function-case-postconditions
                #:function-case-postcondition-function #:function-case-post-value-variables
                #:function-case-state-postconditions
                #:function-case-state-postcondition-function #:function-case-source-form
                #:register-function-spec #:state-observing-contract-p)
  (:import-from #:cl-spec/src/time-limits
                #:mark-run-phase #:call-with-run-time-limits #:run-clock-start
                #:call-catching-run-timeout #:with-run-phase)
  (:import-from #:cl-spec/src/state-frame
                #:state-frame #:state-frame-clauses #:state-frame-observers
                #:capture-state-frame #:check-state-frame #:state-frame-error
                #:state-frame-error-data)
  (:import-from #:cl-spec/src/coverage
                #:definition-coverage-schema #:coverage-inputs #:coverage-bindings #:coverage-identity #:coverage-identity-from-metadata #:coverage-data #:copy-coverage-data
                #:normalize-coverage-options)
  (:import-from #:cl-spec/src/coverage-report
                #:*coverage-context* #:*coverage-trial* #:make-coverage-context-for
                #:coverage-note-unavailable-input #:coverage-report-data #:coverage-capture-input #:coverage-mark-stage
                #:coverage-fixture-p #:coverage-precondition-observed-p)
  (:import-from #:cl-spec/src/execution #:observe-coverage-trial)
  (:import-from #:cl-spec/src/call-schema #:bound-call-presence)
  (:import-from #:cl-spec/src/trial-report #:validate-case-trial-report)
  (:import-from #:cl-spec/src/evidence
                #:evidence-facts #:evidence-summary #:evidence-subject #:evidence-declared-cases
                #:single-observation-report)
  (:export #:make-function-case-with-guard)
  (:import-from #:cl-spec/src/fixture
                #:fixture-recipe-name #:fixture-recipe-spec #:fixture-data #:snapshot-fixture
                #:fixture-error)
  (:import-from #:cl-spec/src/fixture-execution #:call-with-fixture)
  (:import-from #:cl-spec/src/execution
                #:make-trial-observation #:*trial-observations*
                #:trial-observation-reason #:trial-observation-signature
                #:trial-observation-condition
                #:trial-observation-condition-report
                #:trial-observation-state
                #:trial-observation-lifecycle #:trial-observation-call-evidence
                #:render-condition-report)
  (:export #:function-spec-fixture #:fixture-check-property #:make-fixture-check-property
           #:check-fixture #:fixture-check-result #:fixture-check-data
           #:fixture-check-result-observation #:fixture-check-result-definition
           #:fixture-check-result-name #:fixture-check-result-coverage)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/definition-validation
                #:definition-validation-slots)
  (:import-from #:cl-spec/src/conditions
                #:unknown-function-spec
                #:unbound-target
                #:invalid-function-spec-form
                #:invalid-call-arguments
                #:case-selection-error
                #:case-selection-error-data
                #:case-selection-error-kind
                #:case-selection-error-case
                #:capture-error
                #:capture-error-data
                #:state-post-error
                #:state-post-error-data
                #:spec-violation)
  (:import-from #:cl-spec/src/utils/arguments
                #:check-argument #:check-keyword-arguments #:check-run-options)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:check-registry #:registry-find-function-spec)
  (:import-from #:cl-spec/src/schema
                #:definition-description #:definition-entity-kind #:definition-generation-schema
                #:resolve-definition #:definition-instrumentation-capability
                #:definition-shrink-enabled-p #:definition-state-constraints
                #:definition-metadata #:definition-fixture-metadata)
  (:import-from #:cl-spec/src/ir
                #:tuple-spec)
  (:import-from #:cl-spec/src/call-schema
                #:make-call-layout #:bind-call-arguments #:bound-call-values
                #:make-return-schema #:return-schema-value #:return-schema-mode
                #:call-layout-bindings #:call-layout-accepts-p #:bound-call-bindings
                #:call-layout-named-arguments #:call-layout-shape-error #:argument-binding-kind
                #:argument-binding-name #:argument-binding-spec #:argument-binding-supplied-name
                #:call-arguments-spec)
  (:import-from #:cl-spec/src/call-validation)
  (:import-from #:cl-spec/src/call-outcome
                #:invoke-target-once #:make-call-outcome
                #:call-outcome-kind #:call-outcome-values #:call-outcome-condition)
  (:import-from #:cl-spec/src/property
                #:property #:property-argument-schema #:validate-property-executable
                #:property-call-arguments-p #:property-named-arguments #:property-counterexample-layout
                #:property-source-form #:property-trials #:property-metadata)
  (:import-from #:cl-spec/src/property-runner
                #:prepare-property-run #:run-property-with-result-constructor
                #:preparation-timeout-initargs #:property-result-options
                #:property-result #:property-result-case-report #:property-result-entity-kind
                #:check-replayed-result
                #:property-result-budget #:property-result-property #:observation-data)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:backend-default-trials)
  (:import-from #:cl-spec/src/execution
                #:evaluate-trial #:snapshot-value #:failure-identities-match-p
                #:begin-trial-report #:note-trial-outcome #:observation-failure-phase
                #:observe-trial
                #:trial-observation-arguments
                #:trial-observation-case #:trial-observation-status)
  (:import-from #:cl-spec/src/explain
                #:explain-data #:expected-descriptor)
  (:export #:make-function-check-property #:precondition-refuses-p
           #:resolve-function-spec #:check-function-arguments
           #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-argument-generator #:function-spec-argument-schema
           #:function-spec-call-layout #:function-spec-return-schema
           #:function-spec-return-spec
           #:function-spec-signal-spec
           #:function-spec-preconditions
           #:function-spec-postconditions #:function-spec-post-value-variables
            #:validate-post-value-variables
           #:function-spec-precondition-function
           #:function-spec-postcondition-function
           #:function-spec-documentation
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:function-spec-cases
           #:function-spec-capture-bindings
           #:function-spec-capture-functions
           #:function-spec-state-frame
           #:function-spec-state-postconditions
           #:function-spec-state-postcondition-function
           #:function-case
           #:function-case-name
           #:function-case-documentation
           #:function-case-when-forms
           #:function-case-when-function
           #:function-case-outcome-kind
           #:function-case-outcome-spec
           #:function-case-postconditions
           #:function-case-postcondition-function
           #:function-case-post-value-variables
           #:function-case-state-postconditions
           #:function-case-state-postcondition-function
           #:function-case-source-form
           #:function-case-select
           #:function-case-outcome-parts
           #:case-selection-signature
           #:register-function-spec
           #:function-check-result
           #:function-check-result-function
           #:function-check-result-budget
           #:function-check-result-source-form
           #:function-check-result-rejected
           #:function-check-result-failure-reason
           #:function-check-result-explanation
           #:function-check-result-shrunk-outcome
           #:function-check-result-case-report
           #:check-function
           #:check-call
           #:call-check-result
           #:call-check-result-name
           #:call-check-result-arguments
           #:call-check-result-observation
           #:call-check-result-status
           #:call-check-result-failure-phase
           #:call-check-result-source-form
           #:call-check-result-definition
           #:call-check-data))

(in-package #:cl-spec/src/function-spec)

(defun function-case-select (cases bindings function &optional captures)
  "Select exactly one of CASES for BINDINGS, or report why that is impossible.

BINDINGS is the bound argument value list the common :PRE also sees. Guards run
in declaration order, including after a match. A guard error stops selection
at that case and yields :CASE-GUARD-ERROR. Zero and several matches yield
:NO-MATCHING-CASE and :AMBIGUOUS-CASE. The target is not called for any of
these errors. Returns (values CASE CONDITION) with exactly one non-NIL value."
  (let ((matches '()))
    (dolist (case cases)
      (handler-case
          (when (apply (function-case-when-function case)
                       (append bindings captures))
            (push case matches))
        (error (condition)
          (return-from function-case-select
            (values nil (make-condition 'case-selection-error
                                        :function function :kind :case-guard-error
                                        :case (function-case-name case)
                                        :original-condition condition))))))
    (case (length matches)
      (0 (values nil (make-condition 'case-selection-error
                                     :function function :kind :no-matching-case)))
      (1 (values (first matches) nil))
      (t (values nil (make-condition 'case-selection-error
                                     :function function :kind :ambiguous-case
                                     :cases (mapcar #'function-case-name
                                                    (reverse matches))))))))

(defun case-selection-signature (condition)
  "Return the failure identity of a case-selection CONDITION.

Selection errors never reached the target, so their identity is the selection
error kind rather than a target failure shape.  The guard-error form also names
the case, because two guards that signal different ways are different contract
faults."
  (case (case-selection-error-kind condition)
    (:case-guard-error (list :case-selection :case-guard-error
                             (case-selection-error-case condition)))
    (t (list :case-selection (case-selection-error-kind condition)))))

(defun function-case-outcome-parts (contract case)
  "Return the effective outcome declaration of CONTRACT with CASE selected.

Values are RETURN-SPEC SIGNAL-SPEC POST POST-FORMS VALUES-POST-P
STATE-POST-FUNCTION STATE-POST-FORMS.  With CASE NIL they are the contract's own
case-less declaration, so the two paths classify and check state through one
implementation.  The state-post pair is the selected case's clause, or the
contract's case-less one; a case-carrying contract never inherits a common
state-post."
  (if case
      (values (and (eq :returns (function-case-outcome-kind case))
                   (function-case-outcome-spec case))
              (and (eq :signals (function-case-outcome-kind case))
                   (function-case-outcome-spec case))
              (function-case-postcondition-function case)
              (function-case-postconditions case)
              (not (eq :primary (function-case-post-value-variables case)))
              (function-case-state-postcondition-function case)
              (function-case-state-postconditions case))
      (values (function-spec-return-spec contract)
              (function-spec-signal-spec contract)
              (function-spec-postcondition-function contract)
              (function-spec-postconditions contract)
              (not (eq :primary (function-spec-post-value-variables contract)))
              (function-spec-state-postcondition-function contract)
              (function-spec-state-postconditions contract))))

(defun run-captures (contract argument-values)
  "Run CONTRACT's :CAPTURE bindings once, in declaration order.

Returns (values VALUES CONDITION INDEX): VALUES is the ordered list of primary
values produced by the bindings that completed, CONDITION is the condition that
stopped the sequence or NIL, and INDEX is the zero-based position of the binding
that stopped it.  Binding i is called with the argument values followed by
capture values 0..i-1, so a later form sees earlier captures without any runtime
evaluation.  Nothing is re-run to build a report."
  (let ((captured '())
        (index 0))
    (dolist (function (function-spec-capture-functions contract))
      (handler-case
          (push (apply function (append argument-values (reverse captured))) captured)
        (error (condition)
          (return-from run-captures (values (nreverse captured) condition index))))
      (incf index))
    (values (nreverse captured) nil nil)))

(defun apply-state-post (predicate argument-values captures)
  "Run one state-post PREDICATE once and report its verdict.

Returns (values HOLDS INDEX TAG CONDITION).  HOLDS is true when every form held;
INDEX is the zero-based failing form position when the predicate reports one;
TAG is the clause family tag; CONDITION is the condition that stopped it, or
NIL.  The compiled predicate reports a signalling form's position as a value, so
no extra condition type is needed.  A hand-written programmatic predicate that
returns one value yields an unknown position rather than a guessed one."
  (mark-run-phase :state-post)
  (handler-case
      (multiple-value-bind (holds index tag condition)
          (apply predicate (append argument-values captures))
        (values holds index tag condition))
    (error (condition)
      (values nil nil nil condition))))

(defun unprojectable-diagnostic-leaf (value)
  "Return an opaque object reachable from VALUE, or NIL when none.

The evidence snapshot copies conses and arrays and keeps other objects by
identity.  A reachable object it does not copy and that is not a self-contained
atom (number, character, symbol) makes the whole capture value unprojectable:
reporting a copy of the outer structure would still carry a live reference to the
inner object, so a later change to that object would be visible through
\"saved\" diagnostics.  Cycles and shared structure are visited once.  This
defines the diagnostic projection's supported range; it is not a statement about
the object and adds no copy support.  The returned object is not published; the
caller projects its diagnostic type through DIAGNOSTIC-TYPE-DATA."
  (let ((seen (make-hash-table :test #'eq))
        (pending (list value)))
    (loop while pending
          for item = (pop pending)
          do (cond
               ((gethash item seen))
               ((consp item)
                (setf (gethash item seen) t)
                (push (car item) pending)
                (push (cdr item) pending))
               ((arrayp item)
                (setf (gethash item seen) t)
                (dotimes (index (array-total-size item))
                  (push (row-major-aref item index) pending)))
               ((or (numberp item) (characterp item) (symbolp item)))
               (t (return-from unprojectable-diagnostic-leaf item))))
    nil))

(defun diagnostic-type-data (object)
  "Return stable ordinary data describing OBJECT's diagnostic type.

A named type -- a CLOS, structure or condition class name, or a built-in type
such as HASH-TABLE or COMPILED-FUNCTION -- is reported as its name symbol, so
the common cases stay readable.  An object whose class has no name (an
anonymous CLOS class) has no such symbol, and TYPE-OF may legally return the
live class object itself; that is reported as
\(:KIND :ANONYMOUS-CLASS :METACLASS NAME), where NAME is the metaclass's name
\(or :ANONYMOUS-CLASS when even the metaclass is unnamed), so no class object is
embedded in historical evidence.  Any other type specifier degrades to :UNKNOWN
rather than carrying an implementation object.  The result is always ordinary
data: a symbol or a two-key plist."
  (let ((type (type-of object)))
    (cond
      ((symbolp type) type)
      ((typep type 'class)
       (list :kind :anonymous-class
             :metaclass (or (class-name (class-of type)) :anonymous-class)))
      (t :unknown))))

(defun capture-value-data (value)
  "Return VALUE as an explicit availability record for capture evidence.

The result is either

  (:availability :collected :value SNAPSHOT)

where SNAPSHOT is the application value projected as historical evidence, or

  (:availability :unavailable :reason :opaque-value :type TYPE)

where TYPE is ordinary data describing the reachable object the snapshot cannot
freeze: a named type symbol, (:kind :anonymous-class :metaclass NAME) for an
anonymous CLOS class whose TYPE-OF is the live class object, or the :UNKNOWN
fallback for a type specifier this projection cannot name.  No class object or
other live application object is ever published as the TYPE.

The diagnostic projection supports conses, arrays and self-contained atoms
\(numbers, characters, symbols); the existing evidence snapshot copies the first
two and returns the rest unchanged.  A value that is, or contains at any depth,
an object the snapshot keeps by identity -- a CLOS instance, structure, hash
table, function and the like -- is reported unavailable whole: a live reference
inside a copied outer structure is never published as if it were frozen
evidence.

Availability is framework metadata and :VALUE is application data, so a legal
application value that happens to look like an earlier placeholder is still
:COLLECTED with that value under :VALUE; nothing is classified from the shape
of :VALUE.  This is a report projection, not a deep copy and not a new snapshot;
the evaluation path keeps the original value."
  (let ((unprojectable (unprojectable-diagnostic-leaf value)))
    (if unprojectable
        (list :availability :unavailable :reason :opaque-value
              :type (diagnostic-type-data unprojectable))
        (list :availability :collected :value (snapshot-value value)))))

(defun project-capture-values (contract captured)
  "Zip the completed capture values CAPTURED with their binding names.

Returns an ordered list of per-binding records
\(:NAME NAME :AVAILABILITY ...) over the bindings that completed, or NIL when
CONTRACT declares no capture.  Each record carries its binding NAME explicitly,
so a caller reads it by name rather than reconstructing the pairing from
:DECLARED, and an application value is never confused with unavailability
metadata: :VALUE appears only under :AVAILABILITY :COLLECTED.  The raw value
list stays the evaluation form passed to later capture forms, guards and
predicates."
  (when (function-spec-capture-bindings contract)
    (loop for binding in (function-spec-capture-bindings contract)
          for value in captured
          collect (list* :name (first binding) (capture-value-data value)))))

(defun capture-evidence (contract status captured condition index)
  "Return the :CAPTURE half of a trial's state evidence, or NIL when undeclared.

STATUS is :NOT-EVALUATED, :COMPLETED or :ERROR.  CAPTURED holds only the value
of the bindings that completed, in declaration order, so a capture that failed
halfway never shows a later binding as obtained.  :VALUES is an ordered list of
per-binding records (:NAME NAME :AVAILABILITY ...): a collected binding carries
its application value under :VALUE, an unavailable one carries :REASON and
:TYPE and claims no value, and a captured NIL is a :COLLECTED record with a NIL
:VALUE rather than an absence."
  (when (function-spec-capture-bindings contract)
    (let ((bindings (function-spec-capture-bindings contract)))
      (list :status status
            :declared (mapcar #'first bindings)
            :values (project-capture-values contract captured)
            :error (when condition
                     (let ((failing (nth index bindings)))
                       (list :binding (first failing) :index index
                             :condition-type (type-of condition))))))))

(defun state-post-declared-p (contract case)
  "Return true when the effective state-post clause of CONTRACT under CASE exists.

A selected CASE rules its own clause.  With no case selected -- a capture or
case-selection failure, or a case-less contract -- the contract declares one
when its top-level clause exists or any of its cases carries one.  The
distinction keeps \"no state-post declared\" apart from \"declared but stopped
before a case was chosen\": the latter still reports :NOT-EVALUATED with a reason
and no case, rather than dropping the evidence entirely."
  (if case
      (and (function-case-state-postconditions case) t)
      (or (and (function-spec-state-postconditions contract) t)
          (some (lambda (candidate)
                  (and (function-case-state-postconditions candidate) t))
                (function-spec-cases contract)))))

(defun state-post-evidence (contract case status &key reason index form condition)
  "Return the :STATE-POST half of a trial's state evidence, or NIL when undeclared.

STATUS is :NOT-EVALUATED, :PASSED, :VIOLATION or :ERROR.  REASON explains a
:NOT-EVALUATED clause.  INDEX, FORM and CONDITION describe the form that did not
hold or that signalled."
  (when (state-post-declared-p contract case)
    (list :status status
          :reason reason
          :case (and case (function-case-name case))
          :index index
          :form form
          :condition-type (and condition (type-of condition)))))

(defun make-state-evidence (contract &key capture-status captured capture-condition
                                       capture-index
                                       state-status state-reason state-case
                                       state-index state-form state-condition)
  "Build state evidence for the observations declared by CONTRACT."
  (let ((capture (capture-evidence contract capture-status captured
                                   capture-condition capture-index))
        (state (state-post-evidence contract state-case state-status
                                    :reason state-reason :index state-index
                                    :form state-form :condition state-condition)))
    (append (when capture (list :capture capture))
            (when state (list :state-post state))
            (when (function-spec-state-frame contract)
              (list :frame (list :status :not-evaluated))))))

(defstruct (trial-classification (:copier nil))
  "Named evidence returned by the function-spec trial classifier."
  status reason signature explanation condition value outcome selected-case failure-phase state)

(defun trial-classification-values (classification)
  "Return CLASSIFICATION through the established EVALUATE-TRIAL value protocol."
  (values (trial-classification-status classification)
          (trial-classification-reason classification)
          (trial-classification-signature classification)
          (trial-classification-explanation classification)
          (trial-classification-condition classification)
          (trial-classification-value classification)
          (trial-classification-outcome classification)
          (trial-classification-selected-case classification)
          (trial-classification-failure-phase classification)
          (trial-classification-state classification)))

(defun classify-state-post (contract case argument-values captures value outcome
                            state-post-function state-post-forms)
  "Run the selected state-post and return the trial's final classification.

Called only after the outcome contract passed.  A contract that declares no
state-post keeps that :passed result.  A form returning NIL yields
:FAILED / :STATE-POSTCONDITION; a form that signals yields :ERROR /
:CONTRACT-ERROR with a STATE-POST-ERROR condition.  Both keep the captured target
outcome and the selected case, and neither is re-run for the report."
  (let ((case-name (and case (function-case-name case)))
        (function-name (function-spec-name contract)))
    (if (null state-post-function)
        (make-trial-classification
         :status :passed :value value :outcome outcome :selected-case case-name
         :state (make-state-evidence contract :capture-status :completed
                                     :captured captures
                                     :state-status :not-evaluated
                                     :state-reason :not-declared
                                     :state-case case))
        (multiple-value-bind (holds index tag condition)
            (apply-state-post state-post-function argument-values captures)
          (declare (ignore tag))
          (let ((form (and (integerp index) (<= 0 index)
                           (< index (length state-post-forms))
                           (nth index state-post-forms))))
            (cond
              (condition
               (let ((state-condition
                       (make-condition 'state-post-error
                                       :function function-name :case case-name
                                       :index index :form form
                                       :original-condition condition)))
                 (make-trial-classification
                  :status :error :reason :contract-error
                  :signature (if case
                                 (list :case case-name :state-post index
                                       :contract-error (type-of condition))
                                 (list :state-post index :contract-error (type-of condition)))
                  :explanation (state-post-error-data state-condition)
                  :condition state-condition :outcome outcome :selected-case case-name
                  :failure-phase :state-post
                  :state (make-state-evidence contract :capture-status :completed
                                              :captured captures
                                              :state-status :error
                                              :state-index index :state-form form
                                              :state-condition condition
                                              :state-case case))))
              (holds
               (make-trial-classification
                :status :passed :value value :outcome outcome :selected-case case-name
                :state (make-state-evidence contract :capture-status :completed
                                            :captured captures
                                            :state-status :passed
                                            :state-case case)))
              (t
               (make-trial-classification
                :status :failed :reason :state-postcondition
                :signature (if case
                               (list :case case-name :state-postcondition index)
                               (list :state-postcondition index))
                :explanation (list :kind :state-postcondition :function function-name
                                   :case case-name :index index :form form)
                :value value :outcome outcome :selected-case case-name
                :failure-phase :state-post
                :state (make-state-evidence contract :capture-status :completed
                                            :captured captures
                                            :state-status :violation
                                            :state-index index :state-form form
                                            :state-case case)))))))))

(defun classify-frame-failure (contract case captures value outcome frame &optional condition)
  "Classify a forbidden change or failed observer operation at its actual phase."
  (let ((case-name (and case (function-case-name case)))
         (signature (if condition
                        (list :state-frame :error (getf frame :observer)
                              (getf frame :stage) (getf frame :condition-type))
                        (list :state-frame (getf frame :observer) (getf frame :key))))
         (state (make-state-evidence contract :capture-status :completed :captured captures
                                    :state-status :not-evaluated :state-case case
                                    :state-reason (if condition :frame-error :frame-violation))))
    (setf (getf state :frame) frame)
    (make-trial-classification
     :status (if condition :error :failed)
     :reason (if condition :contract-error :state-postcondition)
     :signature (if case-name (list* :case case-name signature) signature)
     :explanation (list* :kind :state-frame :function (function-spec-name contract)
                         :case case-name frame)
     :condition condition :value value :outcome outcome :selected-case case-name
     :failure-phase (if outcome :state-post :capture) :state state)))

(defmethod definition-state-constraints ((contract function-spec))
  (when (state-observing-contract-p contract) :present))

(defmethod definition-shrink-enabled-p ((contract function-spec))
  "Allow state-observing shrinking only with explicit state reconstruction."
  (or (not (null (function-spec-fixture contract)))
      (not (state-observing-contract-p contract))))

(defun resolve-function-spec (designator registry)
  "Return the function spec DESIGNATOR names, signalling UNKNOWN-FUNCTION-SPEC.

This lives here rather than beside RESOLVE-SPEC and RESOLVE-PROPERTY because
CHECK-FUNCTION needs the property runner, which needs SRC/RESOLVE: putting the
function spec case there would close the dependency graph into a cycle.  An
entry that is not a function spec is refused with INVALID-FUNCTION-SPEC-FORM, as
RESOLVE-SPEC refuses a stored non-spec."
  (if (typep designator 'function-spec)
      designator
      (multiple-value-bind (entry found-p)
          (registry-find-function-spec registry designator)
        (cond ((not found-p) (error 'unknown-function-spec :name designator))
              ((typep entry 'function-spec) entry)
              (t (error 'invalid-function-spec-form
                        :form designator
                        :reason "the value registered under this name is not a function spec"))))))

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

TRIALS counts what the backend generated (§19, §73.3). TRIALS minus this
rejection count can include trials that stopped before case selection, such
as capture failures. Read FUNCTION-CHECK-RESULT-CASE-REPORT for target calls
and outcomes per case in ordinary trials.")
   (failure-reason :initarg :failure-reason
                   :initform nil
                   :reader function-check-result-failure-reason
                   :documentation "Which half of the contract broke:
:RETURN-SPEC, :POSTCONDITION, :MISSING-CONDITION, :CONDITION-SPEC,
:CONDITION, :CONTRACT-ERROR, or NIL.

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
                :documentation "EXPLAIN-DATA for :RETURN-SPEC or :CONDITION-SPEC failures.
For :MISSING-CONDITION, a plist with the :EXPECTED descriptor. Otherwise NIL.
The data explains which part of the declared outcome the invocation missed.")
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
rejections. The original evidence remains available in every case.")
   (case-report :initarg :case-report
                :initform :not-collected
                :reader function-check-result-case-report
                :documentation "Per-case report of this run, or :NOT-COLLECTED.

A plist with :SELECTION :EXCLUSIVE, :UNIT :NORMAL-TRIALS, :DECLARED-CASES,
:CASES, :CASE-SELECTION-ERRORS, :CAPTURE-ERRORS and :NEVER-CALLED; see
CHECK-FUNCTION.  The
counters come from the run's own ordinary trials and are snapshotted onto the
result, so two runs of one contract never share them.  A result that did not go
through a function-check run, and one whose backend never opened trial
reporting, both say :NOT-COLLECTED rather than reporting measured zeros.  A
participating backend opens reporting before its first draw, so zero trials and
a first draw that exhausted the generation budget report known zeros.

A trial that reached the target is counted for its selected case even when
classifying the result signalled, because the call happened and the case owned
it.  A case-selection error called no target, so it is counted separately and
never appears as a call of any case.  A capture failure called no target either:
it counts in :CAPTURE-ERRORS and is not a case-selection error.

:STATUS :PASSED means no violation was observed in the trials that ran.  It does
not mean every declared case ran; read :NEVER-CALLED before drawing that
conclusion."))
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

(defgeneric function-check-result-budget (result)
  (:documentation "Return the trial budget stored in the shared property result."))

(defmethod function-check-result-budget ((result function-check-result))
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
    :minimum-length :maximum-length :minimum-count :maximum-count :status
    :tuple-path :field-path :entry-path
    :branch :branch-path :known-tags)
  "The EXPLAIN-DATA error keys FAILURE-SHAPE keeps, because they come from the SPEC.

A whitelist, not a list of keys to strip.  Stripping by name failed three times in
review: :ACTUAL first, then :ACTUAL-LENGTH (a tuple's actual arity) and :PATH (a
position inside the value), then :CONDITION-REPORT (a condition's text, which
embeds the value).  Each varies with the input, so two instances of one failure
compared unequal and a legitimate reduction was thrown away.  A key derived from
the spec is safe to compare; a new EXPLAIN-DATA key is treated as value-derived
until someone classifies it here, and EVERY-EXPLAINED-ERROR-KEY-IS-CLASSIFIED
fails until they do. :FIELD-PATH contains only declared parent/field keys;
Unknown input key names in :KEY and :PATH are value-derived and remain discarded.
:ENTRY-PATH names only the key or value side of each map level, never a map key,
and :ACTUAL-COUNT is value-derived.")

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
conjunct's :STATUS, fixed :TUPLE-PATH, declared :FIELD-PATH and a map's :ENTRY-PATH --
stays in.  See *FAILURE-SHAPE-KEYS* for why that is a whitelist rather than a list of keys
to strip."
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
    (:missing-condition (list :missing-condition))
    (:condition-spec
     (list :condition-spec (type-of condition)
           (mapcar #'failure-shape (getf explanation :errors))))
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

(defmethod coverage-precondition-observed-p ((property function-check-property)) t)

(defmethod definition-validation-slots append ((property function-check-property))
  '(contract target))

(defmethod validate-property-executable ((property function-check-property))
  (unless (and (typep (checked-contract property) 'function-spec)
               (functionp (checked-target property)))
    (error 'invalid-function-spec-form :form nil :reason "invalid function trial adapter"))
  property)

(defmethod definition-instrumentation-capability ((property function-check-property))
  (definition-instrumentation-capability (checked-contract property)))

(defmethod definition-state-constraints ((property function-check-property))
  (definition-state-constraints (checked-contract property)))

(defmethod evidence-declared-cases ((property function-check-property))
  (mapcar #'function-case-name (function-spec-cases (checked-contract property))))

(defmethod definition-shrink-enabled-p ((property function-check-property))
  (not (state-observing-contract-p (checked-contract property))))

(defmethod property-argument-schema ((property function-check-property))
  "Use the function's whole argument schema, including its custom generator."
  (function-spec-argument-schema (checked-contract property)))

(defmethod property-call-arguments-p ((property function-check-property) arguments)
  (call-layout-accepts-p (function-spec-call-layout (checked-contract property)) arguments))

(defmethod property-named-arguments ((property function-check-property) arguments)
  (call-layout-named-arguments (function-spec-call-layout (checked-contract property)) arguments))

(defmethod property-counterexample-layout ((property function-check-property))
  (when (eq (class-of property) (find-class 'function-check-property))
    (make-call-layout (function-spec-argument-specs (checked-contract property)))))

(defmethod coverage-bindings ((property function-check-property) arguments)
  (let* ((layout (function-spec-call-layout (checked-contract property)))
         (bound (handler-case (bind-call-arguments layout arguments)
                  (program-error ()
                    (return-from coverage-bindings (values nil :unavailable))))))
    (loop for binding in (call-layout-bindings layout)
          for present in (bound-call-presence bound)
          for name = (argument-binding-name binding)
          when present append (list name (cdr (assoc name (bound-call-bindings bound)))))))

(defmethod coverage-inputs ((property function-check-property))
  (coverage-inputs (checked-contract property)))

(defmethod definition-coverage-schema ((property function-check-property) registry options)
  (definition-coverage-schema (checked-contract property) registry options))

(defun classify-target-outcome (return-spec signal-spec post post-forms values-post-p
                                bound-values captures raw-outcome registry)
  "Classify one captured target invocation against its outcome declaration.

Return a named trial classification; this function never calls the target again.
CAPTURES follow BOUND-VALUES as arguments to the postcondition."
  (let* ((return-schema (make-return-schema :primary-spec return-spec))
         (condition (when (eq :signaled (call-outcome-kind raw-outcome))
                      (call-outcome-condition raw-outcome)))
         (returned (call-outcome-values raw-outcome))
         (value (first returned)))
    (flet ((failure (reason detail condition &optional value)
             (make-trial-classification
              :status (if condition :error :failed) :reason reason
              :signature (let ((signature (failure-signature reason detail condition)))
                           (if (or (and (eq reason :return-spec)
                                        (eq :values (return-schema-mode return-schema)))
                                   (and (eq reason :postcondition) values-post-p))
                               (cons :return-values (cdr signature))
                               signature))
              :explanation detail :condition condition :value value)))
      (cond
        ;; Broad expected-error contracts must not certify a broken call.
        ((typep condition '(or program-error undefined-function))
         (failure :condition nil condition))
        (signal-spec
         (if condition
             (let ((explanation (explain-data signal-spec condition :registry registry)))
               (if (getf explanation :valid)
                   (make-trial-classification :status :passed :value value)
                   (failure :condition-spec explanation condition)))
             (failure :missing-condition
                      (list :expected (expected-descriptor signal-spec)) nil value)))
        (condition (failure :condition nil condition))
        (t
         (let ((explanation (when return-spec
                              (explain-data return-spec
                                            (return-schema-value return-schema returned)
                                            :registry registry))))
           (cond
             ((and explanation (not (getf explanation :valid)))
              (failure :return-spec explanation nil value))
             (post
              (multiple-value-bind (holds index tag)
                  (apply post (if values-post-p returned value)
                         (append bound-values captures))
                (if holds
                    (make-trial-classification :status :passed :value value)
                    (failure :postcondition
                             (when (and (eq tag :cl-spec-post-form-failure)
                                        (integerp index)
                                        (<= 0 index)
                                        (< index (length post-forms)))
                               (list :post-form index))
                             nil value))))
             (t (make-trial-classification :status :passed :value value)))))))))

(defmethod evaluate-trial ((property function-check-property) arguments &key context)
  "Capture state, select a case, call the target once, classify, then check state.

The common :PRE admits the input first.  :CAPTURE runs next, once per trial and
in declaration order; a capture that signals stops the trial before the target
and is a contract-side error.  Exclusive case selection follows, then the
target's single invocation, then outcome classification. An optional frame
snapshots state just before calling the target. A passing outcome runs the
frame comparison and then the selected :STATE-POST. An earlier failure keeps
its classification. Nothing is re-run to build the evidence."
  (let* ((contract (checked-contract property))
         (registry (getf context :registry))
         (cases (function-spec-cases contract))
         (pre (function-spec-precondition-function contract))
         (outcome nil)
         (selected-case nil)
         (captured-values nil)
         (capture-status :not-evaluated)
         (capture-condition nil)
         (capture-index nil)
         (target-called-p nil))
    (labels ((selection-failure (condition)
               ;; A selection error owns no case and cannot call the target.
               (make-trial-classification
                :status :error :reason :contract-error
                :signature (case-selection-signature condition)
                :explanation (case-selection-error-data condition)
                :condition condition :outcome outcome :failure-phase :case-selection
                :state (make-state-evidence contract :capture-status capture-status
                                            :captured captured-values
                                            :state-status :not-evaluated
                                            :state-reason :case-selection-failed
                                            :state-case selected-case)))
             (contract-failure (condition)
               ;; Preserve the selected case and captured outcome after a call.
               (make-trial-classification
                :status :error :reason :contract-error
                :signature (if selected-case
                               (cons :case (cons (function-case-name selected-case)
                                                 (list :contract-error (type-of condition))))
                               (list :contract-error (type-of condition)))
                :condition condition :outcome outcome
                :selected-case (and selected-case (function-case-name selected-case))
                :state (make-state-evidence contract :capture-status capture-status
                                            :captured captured-values
                                            :capture-condition capture-condition
                                            :capture-index capture-index
                                            :state-status :not-evaluated
                                            :state-reason (if target-called-p
                                                              :outcome-failed
                                                              :contract-error)
                                            :state-case selected-case)))
             (evaluate ()
               (mark-run-phase :binding)
               (let* ((bound (bind-call-arguments (function-spec-call-layout contract) arguments))
                      (argument-values (bound-call-values bound)))
                 (mark-run-phase :pre)
                 (when (precondition-refuses-p pre argument-values)
                   (return-from evaluate
                     (make-trial-classification
                      :status :rejected
                      :state (make-state-evidence contract :capture-status :not-evaluated
                                                  :state-status :not-evaluated
                                                  :state-reason :precondition-rejected))))
                 (coverage-mark-stage :pre-admitted)
                 (mark-run-phase :capture)
                 (multiple-value-bind (captures condition index)
                     (run-captures contract argument-values)
                   (setf captured-values captures
                         capture-condition condition
                         capture-index index
                         capture-status (if condition :error :completed))
                   (when condition
                     (let ((capture-error
                             (make-condition
                              'capture-error
                              :function (function-spec-name contract)
                              :binding (first (nth index
                                                   (function-spec-capture-bindings contract)))
                              :index index
                              :captured (project-capture-values contract captures)
                              :original-condition condition)))
                       (return-from evaluate
                         (make-trial-classification
                          :status :error :reason :contract-error
                          :signature (list :capture index :contract-error (type-of condition))
                          :explanation (capture-error-data capture-error)
                          :condition capture-error :outcome outcome :failure-phase :capture
                          :state (make-state-evidence contract :capture-status :error
                                                      :captured captures
                                                      :capture-condition condition
                                                      :capture-index index
                                                      :state-status :not-evaluated
                                                      :state-reason :capture-failed)))))
                   (mark-run-phase :case-selection)
                   (multiple-value-bind (case selection-condition)
                       (if cases
                           (function-case-select cases argument-values
                                                 (function-spec-name contract) captures)
                           (values nil nil))
                     (when selection-condition
                       (return-from evaluate (selection-failure selection-condition)))
                     (setf selected-case case)
                     (multiple-value-bind
                           (returns signals post post-forms values-post-p
                            state-post-function state-post-forms)
                         (function-case-outcome-parts contract case)
                        (let* ((frame-declaration (function-spec-state-frame contract))
                               (state-frame
                                 (when frame-declaration
                                   (mark-run-phase :capture)
                                   (capture-state-frame frame-declaration
                                                        argument-values captures)))
                               (target-entry (getf context :fixture-target-entry))
                               (raw-outcome
                                 (progn
                                   (mark-run-phase :target)
                                   (when target-entry (funcall target-entry))
                                   (invoke-target-once (checked-target property) arguments)))
                              (target-condition
                                (when (eq :signaled (call-outcome-kind raw-outcome))
                                  (call-outcome-condition raw-outcome))))
                         (coverage-mark-stage :target-observed)
                         (setf target-called-p t
                               outcome (make-call-outcome
                                        :kind (call-outcome-kind raw-outcome)
                                        :values (snapshot-value (call-outcome-values raw-outcome))
                                        :condition target-condition))
                         (mark-run-phase :outcome)
                         (let ((classification
                                 (classify-target-outcome
                                  returns signals post post-forms values-post-p
                                  argument-values captures raw-outcome registry))
                               (case-name (and case (function-case-name case))))
                           (if (eq :passed (trial-classification-status classification))
                               (let ((value (trial-classification-value classification))
                                      (frame (when state-frame
                                               (mark-run-phase :state-post)
                                               (check-state-frame state-frame))))
                                 (if (eq :violation (getf frame :status))
                                     (classify-frame-failure
                                      contract case captures value outcome frame)
                                     (let ((state-classification
                                             (classify-state-post
                                              contract case argument-values captures
                                              value outcome
                                              state-post-function state-post-forms)))
                                       (when frame
                                         (setf (getf (trial-classification-state
                                                       state-classification) :frame)
                                               frame))
                                       state-classification)))
                               (progn
                                 (when (and case (consp (trial-classification-signature
                                                         classification)))
                                   (setf (trial-classification-signature classification)
                                         (cons :case
                                               (cons case-name
                                                     (trial-classification-signature
                                                      classification)))))
                                 (setf (trial-classification-outcome classification) outcome
                                       (trial-classification-selected-case classification) case-name
                                       (trial-classification-state classification)
                                       (make-state-evidence contract :capture-status :completed
                                                            :captured captures
                                                            :state-status :not-evaluated
                                                            :state-reason :outcome-failed
                                                            :state-case case))
                                 classification))))))))))
      (trial-classification-values
       (handler-case (evaluate)
         (state-frame-error (condition)
           (classify-frame-failure contract selected-case captured-values nil outcome
                                   (state-frame-error-data condition) condition))
         ((and error (not undefined-function) (not program-error)) (condition)
           (contract-failure condition)))))))

(defstruct (case-trial-counts (:constructor make-case-trial-counts ()))
  "Target invocations of one case during one function-check run."
  (called 0)
  (passed 0)
  (failed 0)
  (error 0))

(defstruct (case-run (:constructor %make-case-run (cases counts)))
  "One function-check run's per-case counters.

Owned by the run, never by the registered definition or a global table: a reused
contract must not carry counters from an earlier run into a later one.  MEASURED-P
is set when the backend opens reporting (BEGIN-TRIAL-REPORT) or records an
observation, so a backend that does not participate yields :NOT-COLLECTED instead
of zeros that read as measurements, while a participating backend that produced
no observation still reports known zeros."
  (cases nil :read-only t)
  (counts nil :read-only t)
  (measured-p nil)
  (selection-errors 0)
  (capture-errors 0)
  (fixture-errors nil))

(defvar *case-run* nil
  "The function-check run whose case report is being counted, or NIL.

Bound by CHECK-FUNCTION around the whole backend run.  The backend calls
NOTE-TRIAL-OUTCOME once per ordinary trial, and never for a shrink candidate, so
shrinking cannot inflate a case's call count.")

(defun make-case-run (contract)
  "Return a fresh run context for CONTRACT's declared cases."
  (let ((cases (function-spec-cases contract))
        (counts (make-hash-table :test #'eq)))
    (dolist (case cases)
      (setf (gethash (function-case-name case) counts) (make-case-trial-counts)))
    (let ((run (%make-case-run cases counts)))
      (when (function-spec-fixture contract)
        (setf (case-run-fixture-errors run) 0))
      run)))

(defmethod begin-trial-report ((property function-check-property))
  "Mark the active function-check run as measured before its first trial.

A participating backend calls this when it starts running trials, so a run that
produces no observation at all -- zero trials, or a first draw that exhausted the
generation budget -- reports the zeros it does know.  A backend that never calls
it leaves the run unmeasured, and the report says :NOT-COLLECTED."
  (declare (ignore property))
  (let ((run *case-run*))
    (when run (setf (case-run-measured-p run) t))))

(defmethod note-trial-outcome ((property function-check-property) observation)
  "Count one ordinary trial of PROPERTY for the active run's case report.

Reaching this method also marks the report measured, so a backend that reports
observations without calling BEGIN-TRIAL-REPORT still gets a measured report; a
backend that reaches neither leaves the run unmeasured, and the report says
:NOT-COLLECTED rather than reporting zeros for counters nothing kept.

A precondition refusal selected no case and called no target, so it contributes
nothing.  A capture failure called no target either and is counted separately, so
it never appears as a call of any case and is not a case-selection error.  A
case-selection error likewise called no target and is counted separately.  A
failure after the target was called -- including a state-post violation or a
state-post evaluation error -- is counted against the selected case once, from
the trial's final classification."
  (let ((run *case-run*))
    (when run
      (setf (case-run-measured-p run) t)
      (when (eq :fixture (observation-failure-phase observation))
        (incf (case-run-fixture-errors run)))
      (let ((status (trial-observation-status observation))
            (selected (trial-observation-case observation))
            (phase (or (getf (trial-observation-call-evidence observation) :failure-phase)
                       (observation-failure-phase observation))))
        (cond
          ((eq status :rejected))
          ((eq phase :capture)
           (incf (case-run-capture-errors run)))
          ((eq phase :case-selection)
           (incf (case-run-selection-errors run)))
          (selected
           (let ((counts (gethash selected (case-run-counts run))))
             (when counts
               (incf (case-trial-counts-called counts))
               (ecase status
                 (:passed (incf (case-trial-counts-passed counts)))
                 (:failed (incf (case-trial-counts-failed counts)))
                 (:error (incf (case-trial-counts-error counts))))))))))))

(defun case-run-report (run)
  "Project RUN's counters as the public run report, or :NOT-COLLECTED.

The counters are read, never recomputed: nothing here re-runs a guard or the
target.  Every declared case appears in :CASES order, and a case the run never
reached appears in :NEVER-CALLED rather than being silently absent.  Only a run
whose backend neither opened reporting nor recorded an observation answers
:NOT-COLLECTED; a run that opened reporting reports its known zeros even when it
produced no observation at all.  A capture failure calls no target, so it counts
in :CAPTURE-ERRORS and against no case, and it is not a case-selection error."
  (unless (case-run-measured-p run)
    (return-from case-run-report :not-collected))
  (let ((cases (case-run-cases run))
        (counts (case-run-counts run)))
    (list* :selection :exclusive
          :unit :normal-trials
          :declared-cases (mapcar #'function-case-name cases)
          :cases (loop for case in cases
                       for case-counts = (gethash (function-case-name case) counts)
                       collect (list :name (function-case-name case)
                                     :documentation (function-case-documentation case)
                                     :called (case-trial-counts-called case-counts)
                                     :passed (case-trial-counts-passed case-counts)
                                     :failed (case-trial-counts-failed case-counts)
                                     :error (case-trial-counts-error case-counts)))
          :case-selection-errors (case-run-selection-errors run)
          :capture-errors (case-run-capture-errors run)
          :never-called (loop for case in cases
                              for case-counts = (gethash (function-case-name case) counts)
                              when (zerop (case-trial-counts-called case-counts))
                                collect (function-case-name case))
          (when (case-run-fixture-errors run)
            (list :fixture-errors (case-run-fixture-errors run))))))

(defmethod definition-description ((case function-case))
  "Describe one case for the declaration digest and child traversal.

The outcome spec is a child definition rather than inline data, so its own
declaration is digested by the same walk as every other spec, and no executable
closure reaches the digest."
  (values
   (append
    (list :entity-kind :function-case
          :name (function-case-name case)
          :documentation (function-case-documentation case)
          :when (first (function-case-when-forms case))
          :outcome (function-case-outcome-kind case)
          :post (function-case-postconditions case)
          :post-value-variables (function-case-post-value-variables case))
    ;; A case state-post is part of the case declaration: changing its forms
    ;; changes the digest.  A case without one adds no key, so existing case
    ;; digests are unchanged.
    (when (function-case-state-postconditions case)
      (list :state-post (function-case-state-postconditions case))))
   (list (function-case-outcome-spec case))
   nil
   (and (function-case-when-function case)
        (or (null (function-case-postconditions case))
            (function-case-postcondition-function case))
        t)))

(defmethod property-result-entity-kind ((result function-check-result))
  :function-spec)

(defmethod property-result-case-report ((result function-check-result))
  "Route RESULT's own case report through the shared result projection."
  (function-check-result-case-report result))

(defmethod resolve-definition ((designator symbol) (kind (eql :function-spec)) registry)
  (registry-find-function-spec registry designator))

(defmethod definition-entity-kind ((contract function-spec)) :function-spec)

(defmethod definition-generation-schema ((contract function-spec))
  (if (function-spec-fixture contract)
      (make-instance 'tuple-spec :metadata '(:fixture-recipe t) :element-specs
                     (list (fixture-recipe-spec (function-spec-fixture contract))))
      (function-spec-argument-schema contract)))

(defmethod definition-description ((contract function-spec))
  "Describe the contract declaration, not the target implementation."
  (values
   (append
    (when (function-spec-fixture contract)
      (list :fixture (fixture-data (function-spec-fixture contract))))
    (when (function-spec-state-frame contract)
      (list :modifies (state-frame-clauses (function-spec-state-frame contract))))
    (unless (eq :primary (function-spec-post-value-variables contract))
      (list :post-value-variables (function-spec-post-value-variables contract)))
    ;; Capture names, order and source, and the case-less state-post forms, are
    ;; part of the declaration: changing any of them changes the digest.  A
    ;; contract that declares neither adds no key and keeps its digest bytes.
    (when (function-spec-capture-bindings contract)
      (list :capture (function-spec-capture-bindings contract)))
    (when (function-spec-state-postconditions contract)
      (list :state-post (function-spec-state-postconditions contract)))
    (list :entity-kind :function-spec :name (function-spec-name contract)
          :variables (loop for entry in (function-spec-argument-specs contract)
                           collect (if (consp entry)
                                       (if (third entry)
                                           (list (first entry) :supplied (third entry))
                                           (first entry))
                                       entry))
          :documentation (function-spec-documentation contract)
          :source (function-spec-source-form contract)
          :pre (function-spec-preconditions contract) :post (function-spec-postconditions contract)
          :returns (not (null (function-spec-return-spec contract)))
          :signals (not (null (function-spec-signal-spec contract)))
          :generator (function-spec-argument-generator contract)
          :metadata (function-spec-metadata contract)))
   (append (loop for entry in (function-spec-argument-specs contract)
                 when (consp entry) collect (second entry))
           (when (function-spec-return-spec contract)
             (list (function-spec-return-spec contract)))
           (when (function-spec-signal-spec contract)
             (list (function-spec-signal-spec contract)))
           ;; Cases are child definitions, so their names, order, guards, outcomes
           ;; and post bindings are digested by the same walk.  A case is described
           ;; by DEFINITION-DESCRIPTION ((CASE FUNCTION-CASE)) and contributes no
           ;; executable closure to the record.
           (function-spec-cases contract)
           (when (function-spec-fixture contract) (list (function-spec-fixture contract)))
           (when (function-spec-state-frame contract)
             (remove-duplicates (state-frame-observers (function-spec-state-frame contract))
                                :from-end t)))
   (when (function-spec-argument-generator contract)
     (list (cons :generator (function-spec-argument-generator contract))))
   (and (eq (class-name (class-of contract)) 'function-spec)
        (or (not (or (function-spec-precondition-function contract)
                     (function-spec-postcondition-function contract)
                     (function-spec-capture-functions contract)
                     (function-spec-state-postcondition-function contract)
                     (function-spec-cases contract)))
            (not (null (function-spec-source-form contract)))))))

(defmethod definition-description ((property function-check-property))
  (definition-description (checked-contract property)))

(defmethod definition-entity-kind ((property function-check-property)) :function-spec)

(defun function-check-bindings (contract)
  "Build required property bindings for the flattened predicate arguments."
  (loop for binding in (call-layout-bindings (function-spec-call-layout contract))
        append (append (list (list (argument-binding-name binding)
                                   (argument-binding-spec binding)))
                       (when (argument-binding-supplied-name binding)
                         (list (list (argument-binding-supplied-name binding)
                                     (normalize-spec-form 'boolean)))))))

(defmethod coverage-inputs ((contract function-spec))
  (loop for binding in (call-layout-bindings (function-spec-call-layout contract))
        collect (list (argument-binding-name binding) (argument-binding-spec binding))))

(defmethod definition-coverage-schema :around ((contract function-spec) registry options)
  (declare (ignore registry options))
  (let ((schema (call-next-method))
        (omittable (loop for binding in (call-layout-bindings (function-spec-call-layout contract))
                         when (member (argument-binding-kind binding) '(:optional :key))
                         collect (argument-binding-name binding))))
    (loop for cell on (getf schema :dimensions)
          for dimension = (car cell)
          when (member (getf dimension :argument) omittable)
            do (setf (getf dimension :targetable) nil
                     (car cell) (list* :targeting-reason :argument-supply-not-targeted dimension)))
    schema))

(defmethod coverage-identity ((definition function-spec) registry)
  (coverage-identity-from-metadata
   (definition-metadata definition :registry registry
                        :capabilities '(:generation :unknown :shrinking :unknown))))

(defun make-function-check-property (contract &key (budget 0))
  "Adapt CONTRACT to trial execution without requiring a generator backend."
  (unless (typep budget '(integer 0 *))
    (error 'type-error :datum budget :expected-type '(integer 0 *)))
  (let ((name (function-spec-name contract)))
    (make-instance 'function-check-property
                   :contract contract :target (function-spec-target contract)
                   :name name :arguments (function-check-bindings contract)
                   :targets (list name) :kind :function-spec
                   :documentation (function-spec-documentation contract)
                   :trials (list :normal budget)
                   :source-form (snapshot-value (function-spec-source-form contract))
                   :source-location (function-spec-source-location contract)
                   :metadata (list :shrink (definition-shrink-enabled-p contract)
                                   :state-constraints (definition-state-constraints contract)))))

(defclass fixture-check-property (function-check-property)
  ((inner :initarg :inner :reader fixture-inner-property)
   (fixture :initarg :fixture :reader checked-fixture))
  (:documentation "Adapt immutable recipe arguments to fresh function-call trials."))

(defmethod coverage-fixture-p ((property fixture-check-property)) t)

(defmethod property-argument-schema ((property fixture-check-property))
  (make-instance 'tuple-spec :metadata '(:fixture-recipe t)
                 :element-specs (list (fixture-recipe-spec (checked-fixture property)))))

(defmethod property-call-arguments-p ((property fixture-check-property) arguments)
  (and (finite-list-p arguments) (= 1 (length arguments))))

(defmethod property-named-arguments ((property fixture-check-property) arguments)
  (list (fixture-recipe-name (checked-fixture property)) (first arguments)))

(defmethod property-counterexample-layout ((property fixture-check-property))
  (when (eq (class-of property) (find-class 'fixture-check-property))
    (list (fixture-recipe-name (checked-fixture property)))))

(defmethod definition-shrink-enabled-p ((property fixture-check-property)) t)

(defun fixture-call-data (observation)
  "Freeze diagnostic call evidence without retaining opaque application objects."
  (when observation
    (let ((data (list* :failure-phase (observation-failure-phase observation)
                       (observation-data observation))))
      (dolist (key '(:arguments :value :outcome :explanation))
        (setf (getf data key) (capture-value-data (getf data key))))
      data)))

(defmethod observe-trial ((property fixture-check-property) arguments &key context)
  "Evaluate one recipe with fresh state and retain cleanup independently of the contract."
  (let* ((inner (fixture-inner-property property))
         (contract (checked-contract property))
         (registry (or (getf context :registry) *registry*))
         (observation nil) (call-data nil) (arguments-error nil) (target-entered nil)
         (coverage-context *coverage-context*)
         (coverage-trial *coverage-trial*)
         (inner-context (list* :fixture-target-entry (lambda () (setf target-entered t))
                               context))
         (result
           (call-with-fixture
            (checked-fixture property) (first arguments)
            (lambda (raw)
              ;; A nested check can invoke the outer thunk within its wrapper.
              (let ((*coverage-context* coverage-context) (*coverage-trial* coverage-trial))
                (mark-run-phase :fixture-arguments)
                (handler-case
                    (progn
                      (coverage-capture-input inner raw)
                      (validate-call-arguments contract (function-spec-name contract) raw registry)
                      (coverage-mark-stage :domain-valid))
                  (error (condition) (setf arguments-error condition)))
                (unless arguments-error
                  (setf observation (observe-trial inner raw :context inner-context)
                        call-data (fixture-call-data observation)))
                observation))
            :registry registry))
         (reason (or (getf result :reason)
                     (when arguments-error :fixture-arguments-error)))
         (condition (or (getf result :condition) arguments-error))
         (lifecycle (getf result :lifecycle)))
    (when arguments-error
      (setf (getf lifecycle :evaluation) :error
            (getf lifecycle :completion) :aborted)
      (push (list :phase :arguments :reason :fixture-arguments-error
                  :condition-type (type-of arguments-error)
                  :condition-report (render-condition-report arguments-error))
            (getf lifecycle :errors)))
    (coverage-note-unavailable-input (getf (first (getf lifecycle :errors)) :phase))
    (setf (getf lifecycle :target-called) target-entered)
    (make-trial-observation
     :run *trial-observations* :property property
     :arguments (list (getf result :recipe))
     :status (if reason :error (trial-observation-status observation))
     :reason (or reason (and observation (trial-observation-reason observation)))
     :signature (if reason (list :fixture reason)
                    (trial-observation-signature observation))
     :condition (or condition (and observation (trial-observation-condition observation)))
     :condition-report (if condition (render-condition-report condition)
                           (and observation (trial-observation-condition-report observation)))
     :explanation (and observation (getf call-data :explanation))
     :value (and observation (getf call-data :value))
     :outcome (and observation (getf call-data :outcome))
     :case (and observation (trial-observation-case observation))
     :state (and observation (trial-observation-state observation))
     :failure-phase (if reason :fixture
                        (and observation (observation-failure-phase observation)))
     :lifecycle lifecycle :call-evidence call-data)))

(defmethod definition-fixture-metadata ((contract function-spec))
  (when (function-spec-fixture contract)
    (fixture-data (function-spec-fixture contract))))

(defmethod definition-fixture-metadata ((property fixture-check-property))
  (fixture-data (checked-fixture property)))

(defun make-fixture-check-property (contract &key (budget 0))
  "Build a recipe adapter while retaining the ordinary call evaluator."
  (let ((fixture (function-spec-fixture contract)))
    (unless fixture (error 'fixture-error :reason :fixture-required))
    (setf fixture (snapshot-fixture fixture))
    (make-instance 'fixture-check-property
                   :contract contract :target (function-spec-target contract)
                   :inner (make-function-check-property contract :budget budget)
                   :fixture fixture :name (function-spec-name contract)
                   :arguments (list (list (fixture-recipe-name fixture)
                                          (fixture-recipe-spec fixture)))
                   :targets (list (function-spec-name contract)) :kind :function-spec
                   :trials (list :normal budget)
                   :source-form (snapshot-value (function-spec-source-form contract))
                   :source-location (function-spec-source-location contract)
                   :metadata (list :shrink t :state-constraints :present :fixture t))))

(defmethod prepare-property-run ((property fixture-check-property))
  "Capture current fixture hooks for this run, even when an adapter is reused."
  (let ((prepared (make-fixture-check-property (checked-contract property))))
    (reinitialize-instance prepared
                           :trials (snapshot-value (property-trials property))
                           :metadata (snapshot-value (property-metadata property)))
    prepared))

(defun direct-evidence-facts (name metadata observation declared)
  "Describe a single saved observation and its pre-call declared case names."
  (let ((status (trial-observation-status observation))
        (selected (trial-observation-case observation))
        (phase (or (getf (trial-observation-call-evidence observation) :failure-phase)
                   (observation-failure-phase observation))))
    (list :execution-status status :scope :single-call
          :subject (evidence-subject name metadata)
          :trial-report (single-observation-report status)
          :declared-cases declared
          :case-report
          (if (eq declared :not-collected) :not-collected
              (list :cases
                    (loop for case in declared
                          for called = (and (eq case selected)
                                            (not (eq status :rejected))
                                            (not (member phase '(:capture :case-selection))))
                          collect (list :name case :called (if called 1 0)
                                        :passed (if (and called (eq status :passed)) 1 0)
                                        :failed (if (and called (eq status :failed)) 1 0)
                                        :error (if (and called (eq status :error)) 1 0)))))
          :capabilities (getf metadata :capabilities :not-collected)
          :run-error (eq :fixture (observation-failure-phase observation)))))

(defclass fixture-check-result ()
  ((coverage :initarg :coverage :initform '(:availability :not-collected :reason :legacy-result)
              :reader fixture-check-result-coverage)
   (declared-cases :initarg :declared-cases :initform :not-collected
                   :reader fixture-check-result-declared-cases
                   :documentation "Case names captured before this direct execution.")
   (name :initarg :name :reader fixture-check-result-name)
   (observation :initarg :observation :reader fixture-check-result-observation)
   (definition :initarg :definition :reader fixture-check-result-definition))
  (:documentation "One recipe execution, with independent contract and lifecycle evidence."))

(defmethod coverage-data ((result fixture-check-result))
  (copy-coverage-data (fixture-check-result-coverage result)))

(defmethod evidence-facts ((result fixture-check-result))
  (append (list :coverage (coverage-data result))
          (direct-evidence-facts
           (fixture-check-result-name result) (fixture-check-result-definition result)
           (fixture-check-result-observation result) (fixture-check-result-declared-cases result))))

(defun fixture-check-data (result)
  "Return a version-two record for a one-shot fixture execution.

RESULT is what CHECK-FIXTURE returned; anything else is refused with
INVALID-ARGUMENT."
  (check-argument result 'fixture-check-result 'fixture-check-data :result)
  (let ((observation (fixture-check-result-observation result))
        (metadata (copy-list (fixture-check-result-definition result))))
    (setf (getf metadata :schema-version) 2
          (getf metadata :record-kind) :fixture-check)
    (snapshot-value
     (append metadata
             (list :coverage (coverage-data result) :evidence (evidence-summary result)
                   :name (fixture-check-result-name result)
                   :execution-mode :fixture
                   :recipe (first (trial-observation-arguments observation))
                   :status (trial-observation-status observation)
                   :reason (trial-observation-reason observation)
                   :failure-phase (observation-failure-phase observation)
                   :lifecycle (trial-observation-lifecycle observation)
                   :observation (trial-observation-call-evidence observation))))))

(defun check-fixture (function-designator recipe &rest keyword-arguments
                      &key coverage (registry *registry*) &allow-other-keys)
  "Check RECIPE once with the declared fixture, without generation, shrinking or replay.
The fixture may use :FRESH or :AROUND isolation."
  (check-keyword-arguments keyword-arguments '(:coverage :registry) 'check-fixture)
  (setf registry (check-registry registry 'check-fixture))
  ;; Keep enclosing deadlines armed while giving this one-shot call no local clock.
  (call-with-run-time-limits
   nil
   (lambda ()
     (let* ((coverage-options (normalize-coverage-options coverage :direct t))
            (*coverage-trial* nil)
            (contract (resolve-function-spec function-designator registry))
            (property (make-fixture-check-property contract))
            (*coverage-context* (when coverage-options
                                  (make-coverage-context-for property coverage-options registry
                                                             :single-call nil nil)))
            (metadata (definition-metadata
                       contract :registry registry
                       :capabilities '(:generation :unknown :shrinking :unknown))))
       (make-instance 'fixture-check-result :name (function-spec-name contract)
                      :definition metadata
                      :declared-cases (snapshot-value (evidence-declared-cases property))
                      :observation (observe-coverage-trial property (list recipe)
                                                           :context (list :registry registry))
                      :coverage (coverage-report-data *coverage-context*))))))

(defun check-function-run-options (operator keyword-arguments trials seed options)
  "Validate arguments independent of registry lookup."
  (check-keyword-arguments keyword-arguments '(:trials :seed :options :registry) operator)
  (check-argument trials '(or null (integer 0 *)) operator :trials)
  (check-argument seed '(or null property-result (integer 0 *)) operator :seed)
  (check-run-options options operator))

(defun check-function-arguments (operator keyword-arguments trials seed options registry)
  "Validate the generated-check parameters for OPERATOR and return the effective registry."
  (check-function-run-options operator keyword-arguments trials seed options)
  (check-registry registry operator))

(defun check-function (function-designator &rest keyword-arguments
                       &key trials seed (options nil options-p) (registry *registry*)
                         &allow-other-keys)
  "Check a function contract using evidence captured during each invocation.

No target or predicate is called again to classify the result.  Shrinking still
executes candidate inputs; only candidates with the original failure identity are
accepted.  A run with no admitted trials is :SKIPPED.

A contract with :CASES requires exactly one match when selection runs and judges
the invocation by the selected case's outcome. FUNCTION-CHECK-RESULT-CASE-REPORT
lists the declared cases, target calls and outcomes per case, selection errors,
and cases that were never called. A contract error while classifying the outcome
of a target call counts as that case's :ERROR and keeps the case in the failure
identity. Read :NEVER-CALLED alongside :PASSED to see which cases ran. TRIALS
minus REJECTED can include trials that stopped before selection, such as a
capture failure. Use each case's :CALLED for target calls and
:CASE-SELECTION-ERRORS for selection failures. A backend that neither opens
trial reporting nor records an observation leaves the report :NOT-COLLECTED.
A participating backend's zero-trial and first-draw-exhaustion runs report
known zeros.

A contract with :CAPTURE or :STATE-POST observes state.  Capture runs after the
common :PRE admits an input and before case selection; state-post runs only after
the outcome contract passed.  The per-case report adds :CAPTURE-ERRORS, a capture
failure counts no case as called, and a state-post violation or evaluation error
counts as that case's :FAILED or :ERROR. Without :FIXTURE it is not shrunk -- its
shrink report says :STATE-RESTORATION-UNAVAILABLE -- and replaying a past result
as :SEED is refused with UNSUPPORTED-STATEFUL-OPERATION before the target is
called, as is MAKE-COUNTEREXAMPLE-ARTIFACT with :STATEFUL-CONTRACT-UNSUPPORTED.
A new run with an integer seed is allowed; the seed reproduces a random stream,
not the initial object state, which the author must build.

With :FIXTURE, the runner generates recipes and reconstructs fresh state for each
trial and shrink candidate. A result supplied as :SEED requires matching complete
declaration identity, options, profile and budget. Cleanup failures stop the run
with phase :FIXTURE. :RUN-ERROR retains that evidence separately from any earlier
contract failure. Fixture results and artifacts use version 2.

OPTIONS accepts :TIMEOUT, :TRIAL-TIMEOUT and :CLEANUP-TIMEOUT in wall clock
seconds. The result retains these limits when replayed."
  (when (and (not options-p) (typep seed 'property-result))
    (setf options (property-result-options seed)))
  (check-function-run-options 'check-function keyword-arguments trials seed options)
  (call-with-run-time-limits
   options
   (lambda ()
     (let* ((start (run-clock-start))
            (requested-name (when (symbolp function-designator) function-designator))
            (seed-result (and (typep seed 'property-result) seed))
            (budget (or trials
                        (when (typep seed-result 'function-check-result)
                          (function-check-result-budget seed-result))))
            (prepared
              (call-catching-run-timeout
               (lambda ()
                 (with-run-phase (:preparation)
                   (when (typep function-designator 'function-spec)
                     (setf requested-name (function-spec-name function-designator)))
                   (setf registry (check-registry registry 'check-function))
                   (unless budget
                     (setf budget (backend-default-trials (current-generator-backend))))
                   (let* ((contract (resolve-function-spec function-designator registry))
                          (name (if (eq contract function-designator)
                                    requested-name
                                    (setf requested-name (function-spec-name contract))))
                          (property (if (function-spec-fixture contract)
                                        (make-fixture-check-property contract :budget budget)
                                        (make-function-check-property contract :budget budget))))
                     (check-replayed-result seed-result :function-spec name 'check-function)
                     (list property name (property-source-form property)
                           (make-case-run contract)))))
               (lambda (timeout)
                 (return-from check-function
                   (apply #'make-instance 'function-check-result
                          (preparation-timeout-initargs
                           timeout requested-name seed options start :budget budget)))))))
       (destructuring-bind (property name source case-run) prepared
         (let ((enclosing-case-run *case-run*)
               (*case-run* case-run))
           (run-property-with-result-constructor
            property
            (lambda (initargs failure-reason explanation)
              ;; Initialize the result in the caller's case context.
              (let ((*case-run* enclosing-case-run))
                (setf (getf initargs :property) name
                      (getf initargs :budget) budget
                      (getf initargs :source-form) source
                      (getf initargs :failure-reason) failure-reason
                      (getf initargs :explanation) explanation
                      (getf initargs :case-report)
                      (validate-case-trial-report (getf initargs :trial-report)
                                                  (case-run-report case-run)))
                (apply #'make-instance 'function-check-result initargs)))
            :seed seed :registry registry :options options)))))
   'check-function))

;;; One concrete caller-supplied invocation (no generation).

(defun validate-call-arguments (contract name arguments registry)
  "Refuse ARGUMENTS unless they are an admitted call of CONTRACT.

Returns NIL when the call satisfies CONTRACT's layout and declared argument
specs, otherwise signals INVALID-CALL-ARGUMENTS before any target is called.

The call layout answers the shape question, not the error kind: the same
:WRONG-LENGTH, :UNKNOWN-KEY or :NOT-A-SEQUENCE datum is produced by a malformed
call and by a value that misses a composite argument spec, so only
CALL-LAYOUT-SHAPE-ERROR can say which happened.  A layout refusal is :SHAPE; a
call the layout accepts whose value fails a declared argument spec is
:ARGUMENT-SPEC.

Errors come from a CALL-ARGUMENTS-SPEC built on that layout, the same
presence-aware validator the generated path uses, so every refusal carries
standard EXPLAIN-DATA datums -- a non-list, vector, dotted or circular argument
list included -- and an omitted optional is not validated."
  (let* ((layout (function-spec-call-layout contract))
         (schema (make-instance 'call-arguments-spec :layout layout))
         (shape-error (call-layout-shape-error layout arguments))
         (explanation (explain-data schema arguments :registry registry)))
    (unless (getf explanation :valid)
      (error 'invalid-call-arguments
             :function name
             :arguments (snapshot-value arguments)
             :reason (if shape-error :shape :argument-spec)
             :errors (getf explanation :errors)))
    nil))

(defclass call-check-result ()
  ((coverage :initarg :coverage :initform '(:availability :not-collected :reason :legacy-result)
              :reader call-check-result-coverage)
   (declared-cases :initarg :declared-cases :initform :not-collected
                   :reader call-check-result-declared-cases
                   :documentation "Case names captured before this direct execution.")
   (name :initarg :name
         :reader call-check-result-name
         :documentation "Symbol naming the Function Spec that was checked.")
   (arguments :initarg :arguments
              :reader call-check-result-arguments
              :documentation "Snapshot of the raw argument list the caller supplied.")
   (observation :initarg :observation
                :reader call-check-result-observation
                :documentation "The TRIAL-OBSERVATION the shared single-trial path recorded.

It carries the same status, reason, failure identity, explanation, condition,
observed outcome, values, selected case and state evidence a generated trial
records, so both public entry points agree for the same invocation.")
   (source-form :initarg :source-form
                :initform nil
                :reader call-check-result-source-form
                :documentation "The contract's source form as it was when the check ran.")
   (definition :initarg :definition
               :initform nil
               :reader call-check-result-definition
               :documentation "Version 1 declaration metadata captured before the call.

The same envelope DEFINITION-METADATA builds for a definition: schema version,
digest and its completeness, omissions, exclusions, capabilities and any state
constraints.  The digest identifies the declaration and the dependencies it
names, never the target implementation."))
  (:documentation "Structured evidence from checking one caller-supplied invocation.

A dedicated record rather than a PROPERTY-RESULT: a direct check has no seed,
trial budget, profile, shrinking or generation, and filling those slots would
publish values that were never measured.  The observation inside keeps the
shared evidence model, and CALL-CHECK-DATA projects it with the existing
version 1 result envelope.  Created only by CHECK-CALL."))

(defmethod coverage-data ((result call-check-result))
  (copy-coverage-data (call-check-result-coverage result)))

(defmethod evidence-facts ((result call-check-result))
  (append (list :coverage (coverage-data result))
          (direct-evidence-facts
           (call-check-result-name result) (call-check-result-definition result)
           (call-check-result-observation result) (call-check-result-declared-cases result))))

(defun call-check-result-status (result)
  "Return the status of the invocation RESULT checked.

One of :PASSED, :FAILED, :ERROR or :REJECTED, from the observation.  :REJECTED
means the common :PRE refused the input, so the target was not called; it has no
failure reason or identity and is not a contract violation."
  (trial-observation-status (call-check-result-observation result)))

(defun call-check-result-failure-phase (result)
  "Return the phase that produced RESULT's observation, or NIL.

The classifier records :CASE-SELECTION when selection itself failed, :CAPTURE
when a capture form signalled, :STATE-POST when a state-post form failed or
signalled, and NIL for an ordinary target observation.  A :STATE-POST phase
means the target was called; the two pre-target phases mean it was not.  NIL is
also the answer for a passing or precondition-rejected invocation."
  (observation-failure-phase (call-check-result-observation result)))

(defun call-check-data (result)
  "Return RESULT as a version 1 structured record.

The declaration metadata captured before the call is reused as the envelope with
:RECORD-KIND :RESULT and :ENTITY-KIND :FUNCTION-SPEC, and the observation is
projected by OBSERVATION-DATA under :OBSERVATION.  :FAILURE-PHASE is lifted to
the top level because OBSERVATION-DATA does not carry it, so a reader does not
have to reach into the observation structure.  This is data, not prose: a caller
or an MCP projection reads :STATUS, :ARGUMENTS, :NAME and the observation
without re-running the target, its guards, its captures or its post forms."
  (check-argument result 'call-check-result 'call-check-data :result)
  (let ((metadata (copy-list (call-check-result-definition result))))
    (setf (getf metadata :record-kind) :result
          (getf metadata :entity-kind) :function-spec)
    (snapshot-value
     (append metadata
             (list :coverage (coverage-data result) :evidence (evidence-summary result)
                   :name (call-check-result-name result)
                   :status (call-check-result-status result)
                   :arguments (call-check-result-arguments result)
                   :failure-phase (call-check-result-failure-phase result)
                   :observation (observation-data
                                 (call-check-result-observation result)))))))

(defun check-call (function-designator arguments &rest keyword-arguments
                   &key coverage (registry *registry*) &allow-other-keys)
  "Check one caller-supplied invocation of a registered Function Spec.

FUNCTION-DESIGNATOR names a registered contract, or is the FUNCTION-SPEC object
itself.  ARGUMENTS is the explicit raw argument list, following the contract's
declared call layout exactly as APPLY on the target would: required, &optional,
explicit &key, &allow-other-keys and &rest are all honoured by the same binding
machinery a generated trial uses.  REGISTRY defaults to CL-SPEC:*REGISTRY*.

No input is generated, no seed is drawn, no shrinking or replay happens and no
trial count is reported.  The contract's common :PRE is applied, :CAPTURE runs,
exactly one named case is selected, the target is called at most once, and the
effective :RETURNS / :SIGNALS / :POST / :POST-VALUES outcome and :STATE-POST are
classified by the shared single-trial path.  When that evaluator produces an
observation, a non-NIL CALL-CHECK-RESULT is returned, passing or failing; an
evaluation that propagates a condition returns nothing.

Signals UNKNOWN-FUNCTION-SPEC for an unregistered name, UNBOUND-TARGET when the
target is not fbound, and INVALID-CALL-ARGUMENTS when ARGUMENTS is not an
admissible call of the contract -- the last covers both a refused call shape and
a present argument that fails its declared spec, and calls no target.  A :PRE
refusal is not an error: it is reported as a result whose status is :REJECTED.

Error handling is the shared evaluator's, unchanged.  Ordinary contract-side
evaluation errors are reported as results with status :ERROR exactly as generated
checking reports them; :CAPTURE, a case guard and :STATE-POST each observe every
ERROR, so an UNDEFINED-FUNCTION or PROGRAM-ERROR there becomes that clause's
structured contract error (:CAPTURE-ERROR, CASE-SELECTION-ERROR or
STATE-POST-ERROR) with the matching failure phase.  Where the evaluator does not
intercept them -- a broken :PRE, :POST or return/signal-spec predicate --
UNDEFINED-FUNCTION and PROGRAM-ERROR propagate to the caller rather than being
published as a counterexample, exactly as in CHECK-FUNCTION.  A target that
signals either condition is an ordinary target observation with reason
:CONDITION.

A state-observing contract may be checked once, because the caller supplies the
fresh state explicitly.  This does not make that state restorable, reproducible
or persistable, and it does not relax any existing stateful restriction."
  (check-keyword-arguments keyword-arguments '(:coverage :registry) 'check-call)
  (setf registry (check-registry registry 'check-call))
  (let* ((coverage-options (normalize-coverage-options coverage :direct t))
         (*coverage-trial* nil)
         (contract (resolve-function-spec function-designator registry))
         (name (function-spec-name contract))
         ;; Built first so an unbound target is reported before the arguments are
         ;; judged; it also snapshots the source form and holds the target object
         ;; the single invocation will use.
         (property (make-function-check-property contract :budget 0))
         (*coverage-context* (when coverage-options
                               (make-coverage-context-for property coverage-options registry
                                                          :single-call nil nil))))
    (validate-call-arguments contract name arguments registry)
    (let ((declared-cases (snapshot-value (evidence-declared-cases property)))
          (definition (definition-metadata
                       contract :registry registry
                       ;; Declare the capabilities without probing a backend:
                       ;; this path never compiles or draws a generator.
                       :capabilities '(:generation :unknown :shrinking :unknown)))
          (observation (observe-coverage-trial property arguments :domain-valid t
                                      :context (list :registry registry))))
      (when (function-spec-fixture contract)
        (remf definition :input-kind)
        (setf (getf definition :execution-mode) :direct-call))
      (make-instance 'call-check-result
                     :name name :declared-cases declared-cases
                     :coverage (coverage-report-data *coverage-context*)
                     ;; The observation snapshot was taken before the target
                     ;; could change the caller's list, so a mutating target
                     ;; cannot alter the arguments this record reports.
                     :arguments (trial-observation-arguments observation)
                     :observation observation
                     :source-form (property-source-form property)
                     :definition definition))))
