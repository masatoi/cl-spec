;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots #:call-with-definition-rollback
                #:finite-definition-form-p #:definition-keyword-plist-p)
  (:import-from #:cl-spec/src/conditions
                #:unknown-function-spec
                #:unbound-target
                #:invalid-function-spec-form
                #:case-selection-error
                #:case-selection-error-data
                #:case-selection-error-kind
                #:case-selection-error-case
                #:capture-error
                #:capture-error-data
                #:state-post-error
                #:state-post-error-data
                #:unsupported-stateful-operation
                #:spec-violation)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-find-function-spec
                #:registry-register-function-spec)
  (:import-from #:cl-spec/src/schema
                #:definition-description #:definition-entity-kind #:definition-generation-schema
                #:resolve-definition #:definition-instrumentation-capability
                #:definition-shrink-enabled-p #:definition-state-constraints)
  (:import-from #:cl-spec/src/ir #:tuple-spec #:tuple-spec-element-specs)
  (:import-from #:cl-spec/src/call-schema
                #:make-call-layout #:bind-call-arguments #:bound-call-values
                #:make-return-schema #:return-schema-value #:return-schema-mode
                #:normalize-return-declaration #:return-values-spec #:call-declaration-variables
                #:normalize-call-declarations #:call-layout-required-only-p
                #:call-layout-bindings #:call-layout-accepts-p #:bound-call-bindings
                #:argument-binding-name #:argument-binding-spec #:argument-binding-supplied-name
                #:call-arguments-spec)
  (:import-from #:cl-spec/src/call-validation)
  (:import-from #:cl-spec/src/call-outcome
                #:invoke-target-once #:make-call-outcome
                #:call-outcome-kind #:call-outcome-values #:call-outcome-condition)
  (:import-from #:cl-spec/src/property
                #:property #:property-argument-schema #:validate-property-executable
                #:property-call-arguments-p #:property-named-arguments
                #:property-source-form)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-case-report
                #:property-result-schema-metadata #:property-result-budget
                #:property-result-options #:property-result-provenance
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
                #:property-result-shrunk-outcome #:property-result-shrink-report
                #:property-result-generation-report #:property-result-failure-phase
                #:property-result-rejected
                #:property-result-failure-reason #:property-result-explanation
                #:property-result-entity-kind)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:backend-default-trials)
  (:import-from #:cl-spec/src/execution
                #:evaluate-trial #:snapshot-value #:failure-identities-match-p
                #:begin-trial-report #:note-trial-outcome #:observation-failure-phase
                #:trial-observation-case #:trial-observation-status)
  (:import-from #:cl-spec/src/explain
                #:explain-data #:expected-descriptor)
  (:export #:make-function-check-property #:precondition-refuses-p
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
           #:check-function))

(in-package #:cl-spec/src/function-spec)

(defvar *case-owner* nil
  "The contract a case under construction belongs to, or NIL.

Bound only while a FUNCTION-SPEC validates its cases, so a case can check its
:post-values names against the contract's argument bindings without holding a
back-pointer that would make the declaration graph cyclic.  A case built on its
own validates its return arity only.")

(defclass function-case ()
  ((name :initarg :name
         :initform nil
         :reader function-case-name
         :documentation "Keyword naming this case, unique within its contract.
Names are declarations, not search keys: selection is by condition, and the name
exists so a result, a failure identity and a report can say which behaviour was
required.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader function-case-documentation
                         :documentation "Docstring of the case, or NIL.")
   (when-forms :initarg :when-forms
              :initform nil
              :reader function-case-when-forms
              :documentation "The :WHEN form as a one-element list, or NIL when absent.

A list, like the contract's :PRE forms, so that the form NIL -- an allowed
condition that never selects the case -- is distinguishable from no condition at
all; a bare NIL slot could not tell them apart and would let a guard run with no
source for introspection or the digest.")
   (when-function :initarg :when-function
                  :initform nil
                  :reader function-case-when-function
                  :documentation "Compiled predicate over the contract's argument bindings,
true when the input selects this case.

Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.  It is
evaluated once per admitted trial, for every case, so that duplicates are
observed rather than hidden behind first-match short-circuiting.")
   (outcome-kind :initarg :outcome-kind
                 :initform nil
                 :reader function-case-outcome-kind
                 :documentation ":RETURNS or :SIGNALS, the one outcome this case requires.")
   (outcome-spec :initarg :outcome-spec
                 :initform nil
                 :reader function-case-outcome-spec
                 :documentation "The normalized primary return spec for :RETURNS, or the
normalized required-condition spec for :SIGNALS.")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-case-postconditions
                   :documentation "The case's :POST or :POST-VALUES forms, or NIL.
Refused on a :SIGNALS case in this version.")
   (postcondition-function :initarg :postcondition-function
                           :initform nil
                           :reader function-case-postcondition-function
                           :documentation "Compiled case postcondition, or NIL.
To identify a failed form for shrinking, return
\(values nil index :cl-spec-post-form-failure) exactly as the contract-level
postcondition does.")
   (post-value-variables :initarg :post-value-variables
                         :initform :primary
                         :reader function-case-post-value-variables
                         :documentation ":PRIMARY, or the explicit return names of :POST-VALUES.")
   (state-postconditions :initarg :state-postconditions
                         :initform nil
                         :reader function-case-state-postconditions
                         :documentation "The case's :STATE-POST forms, or NIL.
A separate clause from :POST and :POST-VALUES: it runs only after the case's
outcome contract passed, and it may accompany :SIGNALS.")
   (state-postcondition-function :initarg :state-postcondition-function
                                 :initform nil
                                 :reader function-case-state-postcondition-function
                                 :documentation "Compiled case state-post, or NIL.
Sees the arguments and the contract's capture values.  To identify a failed
form, return (values nil index :cl-spec-state-post-form-failure).")
   (source-form :initarg :source-form
                :initform nil
                :reader function-case-source-form
                :documentation "The whole case form as written."))
  (:documentation "One named input condition and the outcome it requires.

A FUNCTION-SPEC holds an ordered list of these when it declares :CASES.  The case
rules its own outcome; the contract's common :ARGS, :ARGS-GENERATOR and :PRE stay
on the contract and apply to every case.  A case is not a separate public
function spec and is never registered under its own name."))

(defparameter *function-case-slot-names*
  '(name documentation-string when-forms when-function outcome-kind outcome-spec
    postconditions postcondition-function post-value-variables
    state-postconditions state-postcondition-function source-form)
  "Every slot of FUNCTION-CASE, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod definition-validation-slots append ((case function-case))
  (copy-list *function-case-slot-names*))

(defmethod shared-initialize :around ((case function-case) slot-names &rest initargs)
  "Validate a case and restore its participating slots on refusal.

A clause's forms and its compiled predicate must change together, on
construction and on reinitialization alike: new text with the old predicate (or
the reverse) would run one while introspection and the digest reported the
other, which is the failure the contract-level :PRE and :POST already refuse.  A
:post-values change is that failure seen from the return bindings, so it needs
new post forms and a new compiled predicate as well."
  (flet ((supplied (key)
           (loop for (k) on initargs by #'cddr thereis (eq k key))))
    (dolist (pair '((:when-forms :when-function)
                    (:postconditions :postcondition-function)
                    (:state-postconditions :state-postcondition-function)))
      (unless (eq (not (supplied (first pair))) (not (supplied (second pair))))
        (error 'invalid-function-spec-form :form pair
               :reason "case clause forms and compiled function must change together")))
    (when (and (supplied :post-value-variables)
               (slot-boundp case 'post-value-variables)
               (not (equal (getf initargs :post-value-variables)
                           (function-case-post-value-variables case)))
               (not (and (supplied :postconditions) (supplied :postcondition-function))))
      (error 'invalid-function-spec-form
             :form initargs
             :reason "Case post-value binding changes require new forms and a compiled predicate.")))
  (call-with-definition-rollback
   case (lambda () (apply #'call-next-method case slot-names initargs))))

(defmethod shared-initialize :after ((case function-case) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition case))

(defmethod validate-definition ((case function-case))
  "Refuse a case the checker could not honour, and normalize what can be.

The same invariant the contract applies to :PRE, :POST and :RETURNS holds per
case: a clause's forms and its compiled predicate are present together or not at
all, because a stored form cannot be run without runtime EVAL (§60) and a
predicate without its form would run while introspection reported no such clause."
  (flet ((refuse (reason)
           (error 'invalid-function-spec-form
                  :form (function-case-source-form case) :reason reason))
         (half (value function reason)
           ;; Exactly one half present: both absent is a case with no such clause.
           (cond ((and value (null function)) reason)
                 ((and function (null value)) reason))))
    (unless (keywordp (function-case-name case))
      (refuse "a case name must be a keyword"))
    (unless (typep (function-case-documentation case) '(or null string))
      (refuse "a case docstring must be NIL or a string"))
    (unless (and (finite-list-p (function-case-when-forms case))
                 (= 1 (length (function-case-when-forms case))))
      (refuse "a case requires exactly one :when form"))
    (unless (finite-definition-form-p (function-case-when-forms case))
      (refuse "a :when form must be an acyclic finite form"))
    (when (half (function-case-when-forms case) (function-case-when-function case)
                "a case :when form and compiled predicate must change together")
      (refuse "a case :when form and compiled predicate must change together"))
    (unless (functionp (function-case-when-function case))
      (refuse "a case :when predicate must be a function"))
    (unless (member (function-case-outcome-kind case) '(:returns :signals))
      (refuse "a case requires exactly one of :returns and :signals"))
    (unless (function-case-outcome-spec case)
      (refuse "a case outcome spec must be present"))
    (unless (finite-list-p (function-case-postconditions case))
      (refuse "case postconditions must be a finite proper list"))
    (when (half (function-case-postconditions case) (function-case-postcondition-function case)
                "case post forms and compiled predicate must change together")
      (refuse "case post forms and compiled predicate must change together"))
    (when (and (function-case-postconditions case)
               (not (functionp (function-case-postcondition-function case))))
      (refuse "a case postcondition predicate must be a function"))
    (when (and (eq :signals (function-case-outcome-kind case))
               (function-case-postconditions case))
      (refuse "a :signals case cannot carry :post or :post-values in this version"))
    (unless (finite-list-p (function-case-state-postconditions case))
      (refuse "case state-post forms must be a finite proper list"))
    (when (half (function-case-state-postconditions case)
                (function-case-state-postcondition-function case)
                "case state-post forms and compiled predicate must change together")
      (refuse "case state-post forms and compiled predicate must change together"))
    (when (and (function-case-state-postconditions case)
               (not (functionp (function-case-state-postcondition-function case))))
      (refuse "a case state-post predicate must be a function"))
    (unless (finite-definition-form-p (function-case-source-form case))
      (refuse "a case source form must be an acyclic finite form"))
    (let ((kind (function-case-outcome-kind case))
          (spec (function-case-outcome-spec case)))
      (setf (slot-value case 'outcome-spec)
            (if (eq kind :returns)
                (normalize-return-declaration spec)
                (normalize-spec-form spec))))
    (unless (eq :primary (function-case-post-value-variables case))
      (unless (and (typep (function-case-outcome-spec case) 'return-values-spec)
                   (function-case-postconditions case)
                   (function-case-postcondition-function case))
        (refuse "explicit post-value bindings require fixed returns and a post predicate"))
      (validate-post-value-variables
       (function-case-post-value-variables case)
       (length (tuple-spec-element-specs (function-case-outcome-spec case)))
       (when *case-owner*
         (call-declaration-variables (function-spec-argument-specs *case-owner*))))))
  case)

(defun function-case-select (cases bindings function &optional captures)
  "Select exactly one of CASES for BINDINGS, or report why that is impossible.

BINDINGS is the bound argument value list the common :PRE also sees.  Every guard
runs in declaration order and evaluation does not stop at the first true one:
duplicates have to be observed, not hidden.  Returns (values CASE CONDITION);
exactly one of them is non-NIL.  A guard that signals stops selection at that
case and yields a :CASE-GUARD-ERROR; zero and several matches yield
:NO-MATCHING-CASE and :AMBIGUOUS-CASE.  The target is not called for any of them."
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
  (handler-case
      (multiple-value-bind (holds index tag condition)
          (apply predicate (append argument-values captures))
        (values holds index tag condition))
    (error (condition)
      (values nil nil nil condition))))

(defun unprojectable-diagnostic-leaf (value)
  "Return the TYPE of an opaque value reachable from VALUE, or NIL when none.

The evidence snapshot copies conses and arrays and keeps other objects by
identity.  A reachable object it does not copy and that is not a self-contained
atom (number, character, symbol) makes the whole capture value unprojectable:
reporting a copy of the outer structure would still carry a live reference to the
inner object, so a later change to that object would be visible through
\"saved\" diagnostics.  Cycles and shared structure are visited once.  This
defines the diagnostic projection's supported range; it is not a statement about
the object and adds no copy support."
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
               (t (return-from unprojectable-diagnostic-leaf (type-of item)))))
    nil))

(defun project-capture-value (value)
  "Return VALUE as capture-report data, or an explicit unprojectable placeholder.

The diagnostic projection supports conses, arrays and self-contained atoms
\(numbers, characters, symbols); the existing evidence snapshot copies the first
two and returns the rest unchanged.  A value that is, or contains at any depth,
an object the snapshot keeps by identity -- a CLOS instance, structure, hash
table, function and the like -- is reported whole as
\(:UNAVAILABLE :REASON :OPAQUE-VALUE :TYPE TYPE), where TYPE names the value that
could not be projected.  A live reference inside a copied outer structure is
never published as if it were frozen evidence.  This is a report projection, not
a deep copy and not a new snapshot; the evaluation path keeps the original
value."
  (let ((unprojectable (unprojectable-diagnostic-leaf value)))
    (if unprojectable
        (list :unavailable :reason :opaque-value :type unprojectable)
        (snapshot-value value))))

(defun project-capture-values (contract captured)
  "Zip the completed capture values CAPTURED with their binding names.

Returns an ordered ((NAME . VALUE) ...) alist over the bindings that completed,
or NIL when CONTRACT declares no capture.  Each value is projected for the
report by PROJECT-CAPTURE-VALUE, so a caller reads a value with ASSOC rather
than reconstructing the pairing from :DECLARED.  The raw value list stays the
evaluation form passed to later capture forms, guards and predicates."
  (when (function-spec-capture-bindings contract)
    (loop for binding in (function-spec-capture-bindings contract)
          for value in captured
          collect (cons (first binding) (project-capture-value value)))))

(defun capture-evidence (contract status captured condition index)
  "Return the :CAPTURE half of a trial's state evidence, or NIL when undeclared.

STATUS is :NOT-EVALUATED, :COMPLETED or :ERROR.  CAPTURED holds only the value
of the bindings that completed, in declaration order, so a capture that failed
halfway never shows a later binding as obtained.  :VALUES pairs each completed
value with its binding name as ((NAME . VALUE) ...), and a captured NIL is a
(NAME . NIL) entry rather than an absence."
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
  "Build one trial's state evidence, or NIL when the contract declares neither clause."
  (let ((capture (capture-evidence contract capture-status captured
                                   capture-condition capture-index))
        (state (state-post-evidence contract state-case state-status
                                    :reason state-reason :index state-index
                                    :form state-form :condition state-condition)))
    (when (or capture state)
      (append (when capture (list :capture capture))
              (when state (list :state-post state))))))

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
        (values :passed nil nil nil nil value outcome case-name nil
                (make-state-evidence contract :capture-status :completed
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
                 (values :error :contract-error
                         (if case
                             (list :case case-name :state-post index
                                   :contract-error (type-of condition))
                             (list :state-post index :contract-error (type-of condition)))
                         (state-post-error-data state-condition)
                         state-condition nil outcome case-name :state-post
                         (make-state-evidence contract :capture-status :completed
                                              :captured captures
                                              :state-status :error
                                              :state-index index :state-form form
                                              :state-condition condition
                                              :state-case case))))
              (holds
               (values :passed nil nil nil nil value outcome case-name nil
                       (make-state-evidence contract :capture-status :completed
                                            :captured captures
                                            :state-status :passed
                                            :state-case case)))
              (t
               (values :failed :state-postcondition
                       (if case
                           (list :case case-name :state-postcondition index)
                           (list :state-postcondition index))
                       (list :kind :state-postcondition :function function-name
                             :case case-name :index index :form form)
                       nil value outcome case-name :state-post
                       (make-state-evidence contract :capture-status :completed
                                            :captured captures
                                            :state-status :violation
                                            :state-index index :state-form form
                                            :state-case case)))))))))

(defclass function-spec ()
  ((call-layout-cache :initform nil)
   (call-layout-declarations :initform nil)
   (call-layout-bindings-snapshot :initform nil)
   (name :initarg :name
         :initform nil
         :reader function-spec-name
         :documentation "Package-qualified symbol naming the specified function.")
   (argument-specs :initarg :argument-specs
                   :initform nil
                   :reader function-spec-argument-specs
                   :documentation "Required (PARAMETER SPEC) pairs followed optionally by
&OPTIONAL (PARAMETER SPEC [SUPPLIED-P]) and &KEY ((:KEY PARAMETER) SPEC [SUPPLIED-P])
declarations. &REST (PARAMETER WHOLE-LIST-SPEC) captures the raw remaining tail
before &KEY. A terminal &ALLOW-OTHER-KEYS permits extra keys. SPEC is normalized
to Semantic IR. Parameter and supplied-variable names are unique. Omitted values
bind to NIL in predicates without evaluating target defaults.")
   (argument-generator :initarg :argument-generator
                       :initform nil
                       :reader function-spec-argument-generator
                       :documentation "Name of a registered no-argument generator returning
the entire positional argument list, or NIL for independent argument generation.
Each draw is checked against the argument specs before preconditions or the target.")
   (signal-spec :initarg :signal-spec
                :initform nil
                :reader function-spec-signal-spec
                :documentation "Normalized spec required of an error escaping the target,
or NIL for an ordinary return contract. Normal return violates a signal contract.
Mutually exclusive with return-spec and postconditions. PROGRAM-ERROR and
UNDEFINED-FUNCTION are reserved execution failures, never accepted by this spec.")
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
   (post-value-variables :initarg :post-value-variables
                        :initform :primary
                        :reader function-spec-post-value-variables
                        :documentation "Use :PRIMARY for legacy post predicates, or an explicit
list of return names. Explicit predicates receive the full values list first.")
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
             :documentation "Arbitrary plist for callers and future extensions.")
   (cases :initarg :cases
          :initform nil
          :reader function-spec-cases
          :documentation "Ordered FUNCTION-CASE objects, or NIL for a case-less contract.

When present, exactly one case is selected per admitted trial and its own
:RETURNS or :SIGNALS outcome judges the invocation.  CASE-SELECTION is exclusive;
a case is not a priority rule.  :CASES is exclusive with the contract-level
:RETURNS, :SIGNALS, :POST and :POST-VALUES: there is no inherited common outcome
to override.")
   (capture-bindings :initarg :capture-bindings
                     :initform nil
                     :reader function-spec-capture-bindings
                     :documentation "Ordered (NAME FORM) pairs observed before the call, or NIL.
Each form's primary value is bound to NAME for the following forms, the case
guards, the postconditions and the state-post.  A capture variable is not a
target argument: the argument schema, generator and actual call are unchanged.")
   (capture-functions :initarg :capture-functions
                      :initform nil
                      :reader function-spec-capture-functions
                      :documentation "One compiled function per capture binding, aligned by position.
Binding i is called with the argument values followed by capture values 0..i-1,
so the forms have LET* visibility without runtime evaluation.  Present exactly
when CAPTURE-BINDINGS is, and supplied together with it.")
   (state-postconditions :initarg :state-postconditions
                         :initform nil
                         :reader function-spec-state-postconditions
                         :documentation "The case-less :STATE-POST forms, or NIL.
Runs only after the outcome contract passed, and only for a contract without
:CASES; a case-carrying contract carries the clause inside each case instead.")
   (state-postcondition-function :initarg :state-postcondition-function
                                 :initform nil
                                 :reader function-spec-state-postcondition-function
                                 :documentation "Compiled case-less state-post, or NIL.
Sees the arguments and the capture values, and no implicit RESULT, condition or
raw outcome.  To identify a failed form, return
(values nil index :cl-spec-state-post-form-failure)."))
  (:documentation "A contract attached to an existing function by name.

The function is never redefined, so an existing codebase adopts cl-spec one
function at a time (specification §3.2)."))

(defparameter *function-spec-slot-names*
  '(name argument-specs argument-generator return-spec signal-spec preconditions postconditions
    precondition-function postcondition-function post-value-variables documentation-string
    source-form source-location metadata cases
    capture-bindings capture-functions state-postconditions state-postcondition-function
    call-layout-cache call-layout-declarations call-layout-bindings-snapshot)
  "Every slot of FUNCTION-SPEC, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod definition-validation-slots append ((contract function-spec))
  (copy-list *function-spec-slot-names*))

(defmethod shared-initialize :around ((contract function-spec) slot-names &rest initargs)
  "Validate paired clauses and restore all participating slots on refusal."
  (flet ((supplied (key)
           (loop for (k) on initargs by #'cddr thereis (eq k key))))
    (when (and (supplied :post-value-variables)
               (slot-boundp contract 'post-value-variables)
               (not (equal (getf initargs :post-value-variables)
                           (function-spec-post-value-variables contract)))
               (not (and (supplied :postconditions) (supplied :postcondition-function))))
      (error 'invalid-function-spec-form :form initargs
             :reason "Post-value binding changes require new forms and a compiled predicate."))
    (dolist (pair '((:preconditions :precondition-function)
                    (:postconditions :postcondition-function)
                    (:capture-bindings :capture-functions)
                    (:state-postconditions :state-postcondition-function)))
      (unless (eq (not (supplied (first pair))) (not (supplied (second pair))))
        (error 'invalid-function-spec-form :form pair
               :reason "clause forms and compiled function must change together")))
    ;; A capture list is part of every compiled predicate that reads it: the
    ;; guard, post and state-post lambdas take the capture values as trailing
    ;; parameters, so a new list with the old closures would call them with the
    ;; wrong arity.  Require the dependent clauses to change with it.
    (when (and (supplied :capture-bindings)
               (slot-boundp contract 'capture-bindings)
               (not (equal (getf initargs :capture-bindings)
                           (function-spec-capture-bindings contract))))
      (dolist (key (append (list :capture-functions)
                           (when (or (function-spec-postconditions contract)
                                     (function-spec-postcondition-function contract))
                             (list :postcondition-function))
                           (when (or (function-spec-state-postconditions contract)
                                     (function-spec-state-postcondition-function contract))
                             (list :state-postcondition-function))
                           (when (function-spec-cases contract)
                             (list :cases))))
        (unless (supplied key)
          (error 'invalid-function-spec-form :form initargs
                 :reason (format nil "changing :capture-bindings requires new ~S ~
and the compiled predicates that read the capture values" key))))))
  (call-with-definition-rollback
   contract (lambda () (apply #'call-next-method contract slot-names initargs))))

(defun validate-post-value-variables (names count arguments)
  "Require COUNT unique bindable value names distinct from ARGUMENTS and RESULT."
  (unless (and (finite-list-p names) (= (length names) count)
               (every (lambda (name)
                        (and name (symbolp name) (not (constantp name))
                             (not (and (plusp (length (symbol-name name)))
                                       (char= #\& (char (symbol-name name) 0))))
                             (not (string-equal "RESULT" (symbol-name name)))
                             (not (member name arguments))))
                      names)
               (= (length names) (length (remove-duplicates names :test #'eq))))
    (error 'invalid-function-spec-form :form names
           :reason "Post-value names must match fixed returns and be unique, bindable variables."))
  names)

(defun contract-result-symbol (variables)
  "Return the symbol RESULT denotes for a contract over VARIABLES, or NIL.

The same lookup the DSL's RETURN-VALUE-SYMBOL performs for its own package
resolution; duplicated here because DSL depends on this file, so this file
cannot import from it."
  (let ((home (if variables (symbol-package (first variables)) *package*)))
    (and home (find-symbol "RESULT" home))))

(defun validate-capture-bindings (contract)
  "Refuse capture declarations the checker could not honour, and return them.

The DSL applies the same rules at macroexpansion time; enforcing them here as
well covers programmatic construction, reinitialization and registry
registration, which all reach the slots without going through the macro.  A
capture name is rejected when it collides with an argument or supplied-p
variable, the return-value binding RESULT, or an explicit :POST-VALUES name,
because the compiled predicates bind all of those in one lambda list."
  (let ((bindings (function-spec-capture-bindings contract))
        (functions (function-spec-capture-functions contract)))
    (flet ((refuse (reason)
             (error 'invalid-function-spec-form :form bindings :reason reason))
           (explicit (names)
             (unless (eq :primary names) names)))
      (unless (finite-list-p bindings)
        (refuse "capture bindings must be a finite proper list"))
      (unless (finite-list-p functions)
        (refuse "capture functions must be a finite proper list"))
      (let ((names '()))
        (dolist (binding bindings)
          (unless (and (consp binding) (finite-list-p binding) (= 2 (length binding)))
            (refuse "each capture binding must be an exact (NAME FORM) pair"))
          (let ((name (first binding)))
            (unless (and name (symbolp name) (not (keywordp name)) (not (constantp name))
                         (not (and (plusp (length (symbol-name name)))
                                   (char= #\& (char (symbol-name name) 0)))))
              (refuse "a capture name must be a bindable non-constant, non-keyword variable"))
            (when (member name names)
              (refuse "capture names must be unique"))
            (push name names)))
        (unless (and (= (length functions) (length bindings))
                     (every #'functionp functions))
          (refuse "capture bindings and compiled capture functions must align one to one"))
        (let* ((variables (call-declaration-variables (function-spec-argument-specs contract)))
               (result (contract-result-symbol variables))
               (contract-values (explicit (function-spec-post-value-variables contract)))
               (case-values (loop for case in (function-spec-cases contract)
                                  append (explicit
                                          (function-case-post-value-variables case)))))
          (dolist (name (reverse names))
            (cond
              ((member name variables)
               (refuse "a capture name cannot collide with an argument or supplied-p variable"))
              ((and result (eq name result))
               (refuse "a capture name cannot collide with the return-value binding RESULT"))
              ((or (member name contract-values) (member name case-values))
               (refuse "a capture name cannot collide with a :post-values name")))))))
    bindings))

(defun state-observing-contract-p (contract)
  "Return true when CONTRACT declares :CAPTURE or :STATE-POST.

Such a contract observes state and never restores it, so automatic shrinking,
replay of a past result and counterexample artifacts are unsupported for it.
The decision is structural: a pure-looking use is not exempted by inspecting
the target or the predicate bodies."
  (or (function-spec-capture-bindings contract)
      (function-spec-state-postconditions contract)
      (some (lambda (case) (function-case-state-postconditions case))
            (function-spec-cases contract))))

(defmethod definition-state-constraints ((contract function-spec))
  (when (state-observing-contract-p contract) :present))

(defmethod definition-shrink-enabled-p ((contract function-spec))
  "Automatic shrinking is unsupported for a state-observing contract."
  (not (state-observing-contract-p contract)))

(defmethod validate-definition ((contract function-spec))
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
    (unless (and (symbolp (function-spec-name contract))
                 (function-spec-name contract)
                 (not (keywordp (function-spec-name contract)))
                 (not (constantp (function-spec-name contract))))
      (refuse (function-spec-name contract) "expected a nonconstant function name"))
    (unless (and (finite-list-p (function-spec-argument-specs contract))
                 (finite-list-p (function-spec-preconditions contract))
                 (finite-list-p (function-spec-postconditions contract))
                 (finite-list-p (function-spec-capture-bindings contract))
                 (finite-list-p (function-spec-capture-functions contract))
                 (finite-list-p (function-spec-state-postconditions contract))
                 (finite-list-p (function-spec-source-form contract)))
      (refuse nil "arguments, clause forms and source must be finite proper lists"))
    (unless (every #'finite-definition-form-p
                   (list (function-spec-argument-specs contract)
                         (function-spec-return-spec contract) (function-spec-signal-spec contract)
                         (function-spec-preconditions contract)
                         (function-spec-postconditions contract)
                         (function-spec-capture-bindings contract)
                         (function-spec-state-postconditions contract)
                         (function-spec-source-form contract)))
      (refuse nil "definition forms must be acyclic"))
    (dolist (predicate (list (function-spec-precondition-function contract)
                             (function-spec-postcondition-function contract)
                             (function-spec-state-postcondition-function contract)))
      (unless (or (null predicate) (functionp predicate))
        (refuse nil "compiled clause predicates must be functions")))
    (unless (typep (function-spec-documentation contract) '(or null string))
      (refuse nil "documentation must be NIL or a string"))
    (dolist (plist (list (function-spec-metadata contract)
                         (function-spec-source-location contract)))
      (unless (definition-keyword-plist-p plist)
        (refuse nil "metadata and source-location must be keyword plists without duplicates")))
    (let ((pre (half ":preconditions" ":precondition-function"
                     (function-spec-preconditions contract)
                     (function-spec-precondition-function contract)))
          (post (half ":postconditions" ":postcondition-function"
                      (function-spec-postconditions contract)
                      (function-spec-postcondition-function contract)))
          (state (half ":state-postconditions" ":state-postcondition-function"
                       (function-spec-state-postconditions contract)
                       (function-spec-state-postcondition-function contract))))
      (when pre
        (refuse (or (function-spec-preconditions contract)
                    (function-spec-precondition-function contract))
                pre))
      (when post
        (refuse (or (function-spec-postconditions contract)
                    (function-spec-postcondition-function contract))
                post))
      (when state
        (refuse (or (function-spec-state-postconditions contract)
                    (function-spec-state-postcondition-function contract))
                state)))
    ;; Cases are validated here, not only at their own construction, because a
    ;; contract can be built with case objects that were made earlier and their
    ;; :post-values names can only be checked against this contract's arguments.
    (let ((cases (function-spec-cases contract)))
      (unless (and (finite-list-p cases)
                   (every (lambda (case) (typep case 'function-case)) cases))
        (refuse cases "cases must be a finite proper list of FUNCTION-CASE objects"))
      (let ((names (mapcar #'function-case-name cases)))
        (unless (every #'keywordp names)
          (refuse cases "case names must be keywords"))
        (unless (= (length names) (length (remove-duplicates names :test #'eq)))
          (refuse cases "case names must be unique within a contract")))
      (when (and cases
                 (or (function-spec-return-spec contract)
                     (function-spec-signal-spec contract)
                     (function-spec-postconditions contract)
                     (function-spec-postcondition-function contract)
                     (function-spec-state-postconditions contract)
                     (function-spec-state-postcondition-function contract)))
        (refuse cases
                ":cases cannot be combined with a top-level :returns, :signals, :post, ~
:post-values or :state-post; there is no inherited common outcome"))
      (let ((*case-owner* contract))
        (dolist (case cases) (validate-definition case))))
    ;; Capture is validated after the cases, because a capture name must not
    ;; collide with a case-level :post-values name either.
    (validate-capture-bindings contract)
    (setf (slot-value contract 'argument-specs)
          (normalize-call-declarations (function-spec-argument-specs contract)))
    (let ((generator (function-spec-argument-generator contract)))
      (unless (or (null generator)
                  (and (symbolp generator) (not (keywordp generator))))
        (refuse generator ":argument-generator must be NIL or a registered generator name")))
    (let ((signals (function-spec-signal-spec contract))
          (returns (function-spec-return-spec contract)))
      (when (and signals (or returns (function-spec-postconditions contract)
                             (function-spec-postcondition-function contract)))
        (refuse signals ":signal-spec cannot coexist with return-spec or postconditions"))
      (when signals
        (setf (slot-value contract 'signal-spec) (normalize-spec-form signals)))
      (when returns
        (setf (slot-value contract 'return-spec) (normalize-return-declaration returns)))))
  (unless (eq :primary (function-spec-post-value-variables contract))
    (unless (and (typep (function-spec-return-spec contract) 'return-values-spec)
                 (function-spec-postconditions contract)
                 (function-spec-postcondition-function contract))
      (error 'invalid-function-spec-form :form (function-spec-post-value-variables contract)
             :reason "Explicit post-value bindings require fixed returns and a post predicate."))
    (validate-post-value-variables
     (function-spec-post-value-variables contract)
     (length (tuple-spec-element-specs (function-spec-return-spec contract)))
     (call-declaration-variables (function-spec-argument-specs contract))))
  (setf (slot-value contract 'call-layout-cache) nil
        (slot-value contract 'call-layout-declarations) nil
        (slot-value contract 'call-layout-bindings-snapshot) nil)
  contract)

(defmethod shared-initialize :after ((contract function-spec) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition contract))

(defun function-spec-argument-schema
    (contract &optional (layout (make-call-layout (function-spec-argument-specs contract))))
  "Derive a raw argument schema with a fresh layout, or the supplied LAYOUT.
An installation may supply its private layout. Both paths isolate captured checks
from the contract's exposed layout cache."
  (if (call-layout-required-only-p layout)
      (make-instance 'tuple-spec
                     :element-specs (mapcar #'argument-binding-spec (call-layout-bindings layout))
                     :generator (function-spec-argument-generator contract))
      (make-instance 'call-arguments-spec :layout layout
                     :generator (function-spec-argument-generator contract))))

(defun function-spec-call-layout (contract)
  "Return a validated layout for CONTRACT's current argument declarations.
Reuse descriptors while declaration containers and exposed binding storage match
their snapshots. Spec objects retain their identity; their internals are not
layout data. Comparing against finite snapshots also bounds malformed cycles."
  (let ((declarations (function-spec-argument-specs contract))
        (cached (slot-value contract 'call-layout-cache)))
    (if (and cached
             (equal declarations (slot-value contract 'call-layout-declarations))
             (equal (call-layout-bindings cached)
                    (slot-value contract 'call-layout-bindings-snapshot)))
        cached
        (let ((layout (make-call-layout declarations)))
          (setf (slot-value contract 'call-layout-cache) layout
                (slot-value contract 'call-layout-declarations) (copy-tree declarations)
                (slot-value contract 'call-layout-bindings-snapshot)
                (copy-list (call-layout-bindings layout)))
          layout))))

(defun function-spec-return-schema (contract)
  "Derive the return schema from CONTRACT\'s current primary return declaration."
  (make-return-schema :primary-spec (function-spec-return-spec contract)))

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
trials that reached case selection.  Reporting only the first would let a run
that rejected every input read as a run that checked every input (§19, §73.3).

Not the number of target calls: a case-selection error calls no target, and
shrinking may invoke the function on candidate inputs.  Classification itself
makes no additional call.  This counts generated trials; read
FUNCTION-CHECK-RESULT-CASE-REPORT for per-case call counts.")
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
    :minimum-length :maximum-length :status :tuple-path :field-path
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
Unknown input key names in :KEY and :PATH are value-derived and remain discarded.")

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
conjunct's :STATUS, fixed :TUPLE-PATH and declared :FIELD-PATH -- stays in. See *FAILURE-SHAPE-KEYS*
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

(defmethod definition-shrink-enabled-p ((property function-check-property))
  (not (state-observing-contract-p (checked-contract property))))

(defmethod property-argument-schema ((property function-check-property))
  "Use the function's whole argument schema, including its custom generator."
  (function-spec-argument-schema (checked-contract property)))

(defmethod property-call-arguments-p ((property function-check-property) arguments)
  (call-layout-accepts-p (function-spec-call-layout (checked-contract property)) arguments))

(defmethod property-named-arguments ((property function-check-property) arguments)
  (loop for (name . value) in
        (bound-call-bindings
         (bind-call-arguments (function-spec-call-layout (checked-contract property)) arguments))
        append (list name value)))

(defun classify-target-outcome (return-spec signal-spec post post-forms values-post-p
                                bound-values captures raw-outcome registry)
  "Classify one target invocation against an effective outcome declaration.

Returns (values STATUS REASON SIGNATURE EXPLANATION CONDITION VALUE), the
classification CHECK-FUNCTION has always reported.  The case-less and
case-carrying paths both call this, so the rules exist once and a case cannot be
made to pass by relaxing them.  RAW-OUTCOME is the invocation already captured by
INVOKE-TARGET-ONCE; nothing here calls the target again.  CAPTURES are the values
observed before the call, appended after BOUND-VALUES for the post predicate; a
contract without :CAPTURE passes NIL and the call is byte-for-byte what it was."
  (let* ((return-schema (make-return-schema :primary-spec return-spec))
         (condition (when (eq :signaled (call-outcome-kind raw-outcome))
                      (call-outcome-condition raw-outcome)))
         (returned (call-outcome-values raw-outcome))
         (value (first returned)))
    (flet ((failure (reason detail condition &optional value)
             (values (if condition :error :failed) reason
                     (let ((signature (failure-signature reason detail condition)))
                       (if (or (and (eq reason :return-spec)
                                    (eq :values (return-schema-mode return-schema)))
                               (and (eq reason :postcondition) values-post-p))
                           (cons :return-values (cdr signature))
                           signature))
                     detail condition value)))
      (cond
        ;; Broad expected-error contracts must not certify a broken call.
        ((typep condition '(or program-error undefined-function))
         (failure :condition nil condition))
        (signal-spec
         (if condition
             (let ((explanation (explain-data signal-spec condition :registry registry)))
               (if (getf explanation :valid)
                   (values :passed nil nil nil nil value)
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
                    (values :passed nil nil nil nil value)
                    (failure :postcondition
                             (when (and (eq tag :cl-spec-post-form-failure)
                                        (integerp index)
                                        (<= 0 index)
                                        (< index (length post-forms)))
                               (list :post-form index))
                             nil value))))
             (t (values :passed nil nil nil nil value)))))))))

(defmethod evaluate-trial ((property function-check-property) arguments &key context)
  "Capture state, select a case, call the target once, classify, then check state.

The common :PRE admits the input first.  :CAPTURE runs next, once per trial and
in declaration order; a capture that signals stops the trial before the target
and is a contract-side error.  Exclusive case selection follows, then the
target's single invocation, then the existing outcome classification.  Only a
:passed outcome runs the selected :STATE-POST; an outcome that failed first
keeps its existing classification and leaves state-post explicitly
:not-evaluated.  Nothing is re-run to build the evidence."
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
               ;; Selection failed, so no case owns this trial and the target was
               ;; not called; the phase is recorded here rather than inferred later
               ;; from the condition's class.
               (values :error :contract-error
                       (case-selection-signature condition)
                       (case-selection-error-data condition)
                       condition nil outcome nil :case-selection
                       (make-state-evidence contract :capture-status capture-status
                                            :captured captured-values
                                            :state-status :not-evaluated
                                            :state-reason :case-selection-failed
                                            :state-case selected-case)))
             (contract-failure (condition)
               ;; The trial stopped in contract-side code.  When the target was
               ;; already invoked the selected case still owns the failure: name
               ;; it in the evidence and in the identity so the case report
               ;; counts the call and shrinking and artifacts stay inside the
               ;; case.  Before the target (a binding, :pre or capture error)
               ;; there is no target failure to own.
               (values :error :contract-error
                       (if selected-case
                           (cons :case (cons (function-case-name selected-case)
                                             (list :contract-error (type-of condition))))
                           (list :contract-error (type-of condition)))
                       nil condition nil outcome
                       (and selected-case (function-case-name selected-case))
                       nil
                       (make-state-evidence contract :capture-status capture-status
                                            :captured captured-values
                                            :capture-condition capture-condition
                                            :capture-index capture-index
                                            :state-status :not-evaluated
                                            :state-reason (if target-called-p
                                                              :outcome-failed
                                                              :contract-error)
                                            :state-case selected-case))))
      (handler-case
          (let* ((bound (bind-call-arguments (function-spec-call-layout contract) arguments))
                 (values (bound-call-values bound)))
            (if (precondition-refuses-p pre values)
                (values :rejected nil nil nil nil nil nil nil nil
                        (make-state-evidence contract :capture-status :not-evaluated
                                             :state-status :not-evaluated
                                             :state-reason :precondition-rejected))
                (multiple-value-bind (captures condition index)
                    (run-captures contract values)
                  (setf captured-values captures
                        capture-condition condition
                        capture-index index
                        capture-status (if condition :error :completed))
                  (if condition
                      (let ((capture-errors
                              (make-condition
                               'capture-error
                               :function (function-spec-name contract)
                               :binding (first (nth index
                                                    (function-spec-capture-bindings contract)))
                               :index index
                               :captured (project-capture-values contract captures)
                               :original-condition condition)))
                        (values :error :contract-error
                                (list :capture index :contract-error (type-of condition))
                                (capture-error-data capture-errors)
                                capture-errors nil outcome nil :capture
                                (make-state-evidence contract :capture-status :error
                                                     :captured captures
                                                     :capture-condition condition
                                                     :capture-index index
                                                     :state-status :not-evaluated
                                                     :state-reason :capture-failed)))
                      (multiple-value-bind (case selection-condition)
                          (if cases
                              (function-case-select cases values
                                                    (function-spec-name contract) captures)
                              (values nil nil))
                        (if selection-condition
                            (selection-failure selection-condition)
                            (progn
                              (setf selected-case case)
                              (multiple-value-bind
                                    (returns signals post post-forms values-post-p
                                     state-post-function state-post-forms)
                                  (function-case-outcome-parts contract case)
                                (let* ((raw-outcome (invoke-target-once
                                                     (checked-target property) arguments))
                                       (target-condition
                                         (when (eq :signaled (call-outcome-kind raw-outcome))
                                           (call-outcome-condition raw-outcome))))
                                  (setf target-called-p t)
                                  (setf outcome
                                        (make-call-outcome
                                         :kind (call-outcome-kind raw-outcome)
                                         :values (snapshot-value
                                                  (call-outcome-values raw-outcome))
                                         :condition target-condition))
                                  (multiple-value-bind
                                        (status reason signature explanation condition value)
                                      (classify-target-outcome returns signals post post-forms
                                                               values-post-p values captures
                                                               raw-outcome registry)
                                    (let ((case-name (and case (function-case-name case))))
                                      (if (eq status :passed)
                                          (classify-state-post
                                           contract case values captures value outcome
                                           state-post-function state-post-forms)
                                          (values status reason
                                                  (if (and case (consp signature))
                                                      (cons :case (cons case-name signature))
                                                      signature)
                                                  explanation condition value outcome
                                                  case-name nil
                                                  (make-state-evidence
                                                   contract :capture-status :completed
                                                   :captured captures
                                                   :state-status :not-evaluated
                                                   :state-reason :outcome-failed
                                                   :state-case case))))))))))))))
        ((and error (not undefined-function) (not program-error)) (condition)
          (contract-failure condition))))))

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
  (capture-errors 0))

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
    (%make-case-run cases counts)))

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
      (let ((status (trial-observation-status observation))
            (selected (trial-observation-case observation))
            (phase (observation-failure-phase observation)))
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
    (list :selection :exclusive
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
                                collect (function-case-name case)))))

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
  (function-spec-argument-schema contract))

(defmethod definition-description ((contract function-spec))
  "Describe the contract declaration, not the target implementation."
  (values
   (append
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
           (function-spec-cases contract))
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

(defun check-function (function-designator &key trials seed options (registry *registry*))
  "Check a function contract using evidence captured during each invocation.

No target or predicate is called again to classify the result.  Shrinking still
executes candidate inputs; only candidates with the original failure identity are
accepted.  A run with no admitted trials is :SKIPPED.

A contract with :CASES selects exactly one case per admitted trial and judges the
invocation by that case's outcome.  The result carries a per-case report
(FUNCTION-CHECK-RESULT-CASE-REPORT) with the declared cases, the target calls and
outcomes actually observed per case, the case-selection errors, and the cases no
trial reached.  A selected case owns its trial even when classifying the result
signalled -- the target was called, so the contract error is counted as that
case's :ERROR and keeps the case in its failure identity.  :PASSED says no
violation was observed in the trials that ran; it does not say every case ran, so
read :NEVER-CALLED as well.  TRIALS minus REJECTED is the number of trials that
reached case selection, not the number of target calls: a case-selection error
calls no target.  A backend that neither opens trial reporting nor records an
observation leaves the report :NOT-COLLECTED rather than measured zeros, while a
participating backend's zero-trial and first-draw-exhaustion runs report known
zeros.

A contract with :CAPTURE or :STATE-POST observes state.  Capture runs after the
common :PRE admits an input and before case selection; state-post runs only after
the outcome contract passed.  The per-case report adds :CAPTURE-ERRORS, a capture
failure counts no case as called, and a state-post violation or evaluation error
counts as that case's :FAILED or :ERROR.  Such a contract is not shrunk -- its
shrink report says :STATE-RESTORATION-UNAVAILABLE -- and replaying a past result
as :SEED is refused with UNSUPPORTED-STATEFUL-OPERATION before the target is
called, as is MAKE-COUNTEREXAMPLE-ARTIFACT with :STATEFUL-CONTRACT-UNSUPPORTED.
A new run with an integer seed is allowed; the seed reproduces a random stream,
not the initial object state, which the author must build."
  (unless (or (null trials) (and (integerp trials) (not (minusp trials))))
    (error 'type-error :datum trials :expected-type '(or null (integer 0 *))))
  (unless (or (null seed) (typep seed 'property-result)
              (and (integerp seed) (not (minusp seed))))
    (error 'type-error :datum seed
                      :expected-type '(or null property-result (integer 0 *))))
  (let* ((seed-result (and (typep seed 'property-result) seed))
         (budget (or trials
                     (when (typep seed-result 'function-check-result)
                       (function-check-result-budget seed-result))
                     (backend-default-trials (current-generator-backend))))
         (seed (if seed-result (property-result-seed seed-result) seed))
         (contract (resolve-function-spec function-designator registry))
         (name (function-spec-name contract))
         (property (make-function-check-property contract :budget budget))
         (source (property-source-form property))
         (case-run (make-case-run contract))
         (result (progn
                   ;; A past result stands in for a run: replaying it would
                   ;; reapply the saved inputs to a target whose state was never
                   ;; restored.  Refuse before the target is called.  An integer
                   ;; seed starts a new run and stays allowed.
                   (when (and seed-result (state-observing-contract-p contract))
                     (error 'unsupported-stateful-operation :operation :replay
                            :function name))
                   (let ((*case-run* case-run))
                     (run-property property
                                   :seed seed
                                   :options (or options
                                                (and seed-result
                                                     (property-result-options seed-result)))
                                   :registry registry)))))
    (make-instance 'function-check-result
                   :schema-metadata (property-result-schema-metadata result)
                   :options (property-result-options result)
                   :provenance (property-result-provenance result)
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
                   :case-report (case-run-report case-run)
                    :shrink-report (property-result-shrink-report result)
                   :generation-report (property-result-generation-report result)
                   :failure-phase (property-result-failure-phase result)
                   :condition (property-result-condition result)
                   :elapsed (property-result-elapsed result)
                   :rejected (property-result-rejected result)
                   :failure-reason (property-result-failure-reason result)
                   :explanation (property-result-explanation result))))
