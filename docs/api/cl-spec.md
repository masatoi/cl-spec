# cl-spec

Semantic IR, validation, structured explain, introspection, registry and the DSL.

System `cl-spec`, 253 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Macros**: [`defgenerator`](#defgenerator) · [`defproperty`](#defproperty) · [`defspec`](#defspec) · [`defspec-function`](#defspec-function)

**Functions**: [`capture-error-data`](#capture-error-data) · [`case-selection-error-data`](#case-selection-error-data) · [`check-function`](#check-function) · [`clear-registry`](#clear-registry) · [`compile-explainer`](#compile-explainer) · [`compile-validator`](#compile-validator) · [`counterexample-artifact-data`](#counterexample-artifact-data) · [`current-generator-backend`](#current-generator-backend) · [`definition-digest`](#definition-digest) · [`definition-metadata`](#definition-metadata) · [`describe-property`](#describe-property) · [`describe-spec`](#describe-spec) · [`deserialize-counterexample-artifact`](#deserialize-counterexample-artifact) · [`explain`](#explain) · [`explain-data`](#explain-data) · [`failure-identities-match-p`](#failure-identities-match-p) · [`find-function-spec`](#find-function-spec) · [`find-generator`](#find-generator) · [`find-property`](#find-property) · [`find-spec`](#find-spec) · [`function-check-result-function`](#function-check-result-function) · [`function-spec-argument-schema`](#function-spec-argument-schema) · [`function-spec-data`](#function-spec-data) · [`generation-budget-exhausted-attempts`](#generation-budget-exhausted-attempts) · [`generation-budget-exhausted-budget`](#generation-budget-exhausted-budget) · [`generation-budget-exhausted-path`](#generation-budget-exhausted-path) · [`generation-budget-exhausted-phase`](#generation-budget-exhausted-phase) · [`generation-budget-exhausted-rejections`](#generation-budget-exhausted-rejections) · [`generator-for`](#generator-for) · [`list-function-specs`](#list-function-specs) · [`list-generators`](#list-generators) · [`list-properties`](#list-properties) · [`list-specs`](#list-specs) · [`make-counterexample-artifact`](#make-counterexample-artifact) · [`make-hash-table-registry`](#make-hash-table-registry) · [`make-trial-observation`](#make-trial-observation) · [`normalize-spec-form`](#normalize-spec-form) · [`observation-failure-p`](#observation-failure-p) · [`observe-trial`](#observe-trial) · [`properties-for`](#properties-for) · [`properties-with-tag`](#properties-with-tag) · [`property-data`](#property-data) · [`property-result-explanation`](#property-result-explanation) · [`property-result-failure-reason`](#property-result-failure-reason) · [`property-result-failure-signature`](#property-result-failure-signature) · [`recheck-counterexample`](#recheck-counterexample) · [`register-function-spec`](#register-function-spec) · [`register-generator`](#register-generator) · [`register-property`](#register-property) · [`register-spec`](#register-spec) · [`replay-property`](#replay-property) · [`result-data`](#result-data) · [`run-properties`](#run-properties) · [`run-property`](#run-property) · [`sample`](#sample) · [`schema-info`](#schema-info) · [`semantic-data`](#semantic-data) · [`serialize-counterexample-artifact`](#serialize-counterexample-artifact) · [`source-location-file`](#source-location-file) · [`source-location-package`](#source-location-package) · [`spec-data`](#spec-data) · [`state-post-error-data`](#state-post-error-data) · [`tagged-union-branch`](#tagged-union-branch) · [`trial-observation-arguments`](#trial-observation-arguments) · [`trial-observation-arguments-mutated-p`](#trial-observation-arguments-mutated-p) · [`trial-observation-case`](#trial-observation-case) · [`trial-observation-condition`](#trial-observation-condition) · [`trial-observation-condition-report`](#trial-observation-condition-report) · [`trial-observation-explanation`](#trial-observation-explanation) · [`trial-observation-outcome`](#trial-observation-outcome) · [`trial-observation-reason`](#trial-observation-reason) · [`trial-observation-signature`](#trial-observation-signature) · [`trial-observation-state`](#trial-observation-state) · [`trial-observation-status`](#trial-observation-status) · [`trial-observation-value`](#trial-observation-value) · [`validate`](#validate) · [`validp`](#validp)

**Generic functions**: [`backend-capabilities`](#backend-capabilities) · [`backend-default-trials`](#backend-default-trials) · [`compile-generator`](#compile-generator) · [`definition-description`](#definition-description) · [`definition-validation-slots`](#definition-validation-slots) · [`evaluate-trial`](#evaluate-trial) · [`function-check-result-budget`](#function-check-result-budget) · [`generate-value`](#generate-value) · [`property-argument-schema`](#property-argument-schema) · [`property-call-arguments-p`](#property-call-arguments-p) · [`property-named-arguments`](#property-named-arguments) · [`property-result-entity-kind`](#property-result-entity-kind) · [`registry-clear`](#registry-clear) · [`registry-find-function-spec`](#registry-find-function-spec) · [`registry-find-generator`](#registry-find-generator) · [`registry-find-property`](#registry-find-property) · [`registry-find-spec`](#registry-find-spec) · [`registry-list-function-specs`](#registry-list-function-specs) · [`registry-list-generators`](#registry-list-generators) · [`registry-list-properties`](#registry-list-properties) · [`registry-list-specs`](#registry-list-specs) · [`registry-properties-for`](#registry-properties-for) · [`registry-properties-with-tag`](#registry-properties-with-tag) · [`registry-register-function-spec`](#registry-register-function-spec) · [`registry-register-generator`](#registry-register-generator) · [`registry-register-property`](#registry-register-property) · [`registry-register-spec`](#registry-register-spec) · [`run-generated-test`](#run-generated-test) · [`spec-children`](#spec-children) · [`spec-kind`](#spec-kind) · [`validate-definition`](#validate-definition)

**Accessors**: [`capture-error-binding`](#capture-error-binding) · [`capture-error-captured`](#capture-error-captured) · [`capture-error-function`](#capture-error-function) · [`capture-error-index`](#capture-error-index) · [`capture-error-original-condition`](#capture-error-original-condition) · [`case-selection-error-case`](#case-selection-error-case) · [`case-selection-error-cases`](#case-selection-error-cases) · [`case-selection-error-function`](#case-selection-error-function) · [`case-selection-error-kind`](#case-selection-error-kind) · [`case-selection-error-original-condition`](#case-selection-error-original-condition) · [`custom-generator-documentation`](#custom-generator-documentation) · [`custom-generator-function`](#custom-generator-function) · [`custom-generator-name`](#custom-generator-name) · [`custom-generator-shrinker`](#custom-generator-shrinker) · [`custom-generator-source-form`](#custom-generator-source-form) · [`custom-generator-source-location`](#custom-generator-source-location) · [`function-check-result-case-report`](#function-check-result-case-report) · [`function-check-result-explanation`](#function-check-result-explanation) · [`function-check-result-failure-reason`](#function-check-result-failure-reason) · [`function-check-result-rejected`](#function-check-result-rejected) · [`function-check-result-shrunk-outcome`](#function-check-result-shrunk-outcome) · [`function-check-result-source-form`](#function-check-result-source-form) · [`function-spec-argument-generator`](#function-spec-argument-generator) · [`function-spec-argument-specs`](#function-spec-argument-specs) · [`function-spec-documentation`](#function-spec-documentation) · [`function-spec-metadata`](#function-spec-metadata) · [`function-spec-name`](#function-spec-name) · [`function-spec-post-value-variables`](#function-spec-post-value-variables) · [`function-spec-postcondition-function`](#function-spec-postcondition-function) · [`function-spec-postconditions`](#function-spec-postconditions) · [`function-spec-precondition-function`](#function-spec-precondition-function) · [`function-spec-preconditions`](#function-spec-preconditions) · [`function-spec-return-spec`](#function-spec-return-spec) · [`function-spec-signal-spec`](#function-spec-signal-spec) · [`function-spec-source-form`](#function-spec-source-form) · [`function-spec-source-location`](#function-spec-source-location) · [`generation-budget-exhausted-report`](#generation-budget-exhausted-report) · [`generation-budget-exhausted-request`](#generation-budget-exhausted-request) · [`generator-unavailable-reason`](#generator-unavailable-reason) · [`generator-unavailable-spec`](#generator-unavailable-spec) · [`invalid-backend-result-reason`](#invalid-backend-result-reason) · [`invalid-counterexample-artifact-reason`](#invalid-counterexample-artifact-reason) · [`invalid-function-spec-form-form`](#invalid-function-spec-form-form) · [`invalid-function-spec-form-reason`](#invalid-function-spec-form-reason) · [`invalid-generated-arguments-generator`](#invalid-generated-arguments-generator) · [`invalid-generated-arguments-reason`](#invalid-generated-arguments-reason) · [`invalid-generated-arguments-value`](#invalid-generated-arguments-value) · [`invalid-generator-form-form`](#invalid-generator-form-form) · [`invalid-generator-form-reason`](#invalid-generator-form-reason) · [`invalid-property-form-form`](#invalid-property-form-form) · [`invalid-property-form-reason`](#invalid-property-form-reason) · [`invalid-spec-form-form`](#invalid-spec-form-form) · [`invalid-spec-form-reason`](#invalid-spec-form-reason) · [`not-implemented-operator`](#not-implemented-operator) · [`property-arguments`](#property-arguments) · [`property-body`](#property-body) · [`property-documentation`](#property-documentation) · [`property-function`](#property-function) · [`property-kind`](#property-kind) · [`property-metadata`](#property-metadata) · [`property-name`](#property-name) · [`property-result-budget`](#property-result-budget) · [`property-result-condition`](#property-result-condition) · [`property-result-counterexample`](#property-result-counterexample) · [`property-result-elapsed`](#property-result-elapsed) · [`property-result-failure-evidence`](#property-result-failure-evidence) · [`property-result-failure-phase`](#property-result-failure-phase) · [`property-result-generation-report`](#property-result-generation-report) · [`property-result-options`](#property-result-options) · [`property-result-profile`](#property-result-profile) · [`property-result-property`](#property-result-property) · [`property-result-provenance`](#property-result-provenance) · [`property-result-rejected`](#property-result-rejected) · [`property-result-schema-metadata`](#property-result-schema-metadata) · [`property-result-seed`](#property-result-seed) · [`property-result-shrink-report`](#property-result-shrink-report) · [`property-result-shrunk-counterexample`](#property-result-shrunk-counterexample) · [`property-result-shrunk-evidence`](#property-result-shrunk-evidence) · [`property-result-shrunk-outcome`](#property-result-shrunk-outcome) · [`property-result-status`](#property-result-status) · [`property-result-trials`](#property-result-trials) · [`property-source-form`](#property-source-form) · [`property-source-location`](#property-source-location) · [`property-tags`](#property-tags) · [`property-targets`](#property-targets) · [`property-trials`](#property-trials) · [`spec-description`](#spec-description) · [`spec-generator-name`](#spec-generator-name) · [`spec-metadata`](#spec-metadata) · [`spec-name`](#spec-name) · [`spec-source-form`](#spec-source-form) · [`spec-source-location`](#spec-source-location) · [`spec-violation-errors`](#spec-violation-errors) · [`spec-violation-path`](#spec-violation-path) · [`spec-violation-spec`](#spec-violation-spec) · [`spec-violation-value`](#spec-violation-value) · [`state-post-error-case`](#state-post-error-case) · [`state-post-error-form`](#state-post-error-form) · [`state-post-error-function`](#state-post-error-function) · [`state-post-error-index`](#state-post-error-index) · [`state-post-error-original-condition`](#state-post-error-original-condition) · [`unknown-function-spec-name`](#unknown-function-spec-name) · [`unknown-property-name`](#unknown-property-name) · [`unknown-spec-name`](#unknown-spec-name) · [`unsupported-stateful-operation-function`](#unsupported-stateful-operation-function) · [`unsupported-stateful-operation-operation`](#unsupported-stateful-operation-operation) · [`unsupported-stateful-operation-reason`](#unsupported-stateful-operation-reason)

**Classes**: [`custom-generator`](#custom-generator) · [`function-check-result`](#function-check-result) · [`function-spec`](#function-spec) · [`hash-table-registry`](#hash-table-registry) · [`property`](#property) · [`property-result`](#property-result) · [`spec`](#spec)

**Conditions**: [`capture-error`](#capture-error) · [`case-selection-error`](#case-selection-error) · [`cl-spec-error`](#cl-spec-error) · [`generation-budget-exhausted`](#generation-budget-exhausted) · [`generator-unavailable`](#generator-unavailable) · [`invalid-backend-result`](#invalid-backend-result) · [`invalid-counterexample-artifact`](#invalid-counterexample-artifact) · [`invalid-function-spec-form`](#invalid-function-spec-form) · [`invalid-generated-arguments`](#invalid-generated-arguments) · [`invalid-generator-form`](#invalid-generator-form) · [`invalid-property-form`](#invalid-property-form) · [`invalid-spec-form`](#invalid-spec-form) · [`no-generator-backend`](#no-generator-backend) · [`not-implemented`](#not-implemented) · [`spec-violation`](#spec-violation) · [`state-post-error`](#state-post-error) · [`unbound-target`](#unbound-target) · [`unknown-function-spec`](#unknown-function-spec) · [`unknown-property`](#unknown-property) · [`unknown-spec`](#unknown-spec) · [`unsupported-seed`](#unsupported-seed) · [`unsupported-stateful-operation`](#unsupported-stateful-operation)

**Structures**: [`counterexample-artifact`](#counterexample-artifact) · [`trial-observation`](#trial-observation)

**Variables**: [`*generator-backend*`](#generator-backend) · [`*registry*`](#registry) · [`*spec-primitives*`](#spec-primitives)

## Macros

<a name="defgenerator"></a>
### defgenerator

*Macro* · `(name lambda-list &body body)`

Define a custom generator named NAME (specification §11).

```text
Use this when a spec cannot express how values should be produced, for example
when generation must satisfy a global invariant:

  (defgenerator small-integer ()
    (random 100))

  (defspec small (and integer (range 0 100)) (:generator small-integer))

BODY produces one value per draw and is compiled into a function of no
arguments, so LAMBDA-LIST must be empty.  A generator that took parameters would
need a syntax for a spec to pass them and §11 defines none, and accepting one
would call the body without the bindings its author wrote.

For DEFSPEC uses, the value is not re-validated against the spec that names it.
For DEFSPEC-FUNCTION's :ARGS-GENERATOR, the whole argument list is validated
before the precondition or target runs.  A generator that
draws outside its spec makes a property report a counterexample the contract
refuses, which is a true statement about the generator rather than a silent pass;
the AND generator's residual filter is bounded by a shared candidate budget and
signals GENERATION-BUDGET-EXHAUSTED instead of retrying without limit.

An optional leading (:SHRINK (VALUE) BODY...) clause after documentation supplies
an ordered finite list of candidate values. Its one binding must be a valid variable.
A leading string in BODY is documentation when anything follows it, and the
generated value when the string is the whole body -- the rule DEFPROPERTY uses.
BODY is called for a value, so a body that returns a check-it generator produces
that object as the value rather than drawing from it.
```

<a name="defproperty"></a>
### defproperty

*Macro* · `(name arguments &body body)`

Define a property named NAME over generated ARGUMENTS.

```text
ARGUMENTS is a list of (VARIABLE SPEC-FORM) bindings.  BODY may start with a
docstring, then option clauses (:ABOUT ...), (:KIND ...), (:TAGS ...),
(:TRIALS ...) and (:SHRINK ...), followed by the forms of the predicate.  A NIL
result or a signalled condition counts as a failure.

Bindings must be exact pairs with distinct, bindable required variables.
Each leading option appears at most once; unknown leading keyword options,
missing/extra single-option values and malformed trial tables are refused with
INVALID-PROPERTY-FORM at macroexpansion. Trial budgets are nonnegative integers
with unique keyword profiles. At least one predicate form is required.
After the first non-option form, remaining forms are ordinary Lisp code.

  (defproperty addition-preserves-order
      ((x positive-integer) (y positive-integer))
    (:about +)
    (:kind :monotonicity)
    (> (+ x y) x))
```

<a name="defspec"></a>
### defspec

*Macro* · `(name form &body options)`

Define a spec named NAME from spec DSL FORM.

```text
FORM is normalized into a Semantic IR object and registered in *REGISTRY*.
The original form and the definition site are kept on the resulting spec.

  (defspec positive-integer
    (and integer (range 1 *)))

OPTIONS is a list of clauses.  The only one this version accepts is
(:GENERATOR NAME), naming a DEFGENERATOR generator whose values the backend draws
instead of deriving them from FORM (specification §11).  For an AND, a generator
on the whole AND wins.  Otherwise a unique conjunct that carries a custom
generator is used as the generation source and the whole AND filters its draws;
two or more such conjuncts signal GENERATOR-UNAVAILABLE, because the backend never
silently picks one or ignores one.  See the bounded-AND addendum in §73.5.
```

<a name="defspec-function"></a>
### defspec-function

*Macro* · `(name &body clauses)`

Attach a contract to the existing function NAME without redefining it.

```text
CLAUSES may start with a docstring, then any of (:ARGS (PARAMETER SPEC) ...),
(:ARGS-GENERATOR NAME), (:PRE FORM ...), (:CAPTURE (NAME FORM) ...),
(:RETURNS SPEC), (:POST FORM ...),
(:POST-VALUES (NAME ...) FORM ...), (:SIGNALS SPEC), or (:STATE-POST FORM ...),
each at most once. :ARGS-GENERATOR names a DEFGENERATOR returning the whole proper
argument list. Its output is validated before :PRE and the target; it has no
automatic shrink strategy.  :PRE
sees the parameters. :POST sees them and RESULT, the primary returned value.
(:RETURNS (VALUES SPEC ...)) checks an exact return count, including zero.
:POST-VALUES is exclusive with :POST and requires one unique name per fixed return.
It binds the returned values and keeps RESULT as the primary value. Missing values
bind to NIL if a consumer runs the post predicate without return validation.

:SIGNALS requires an error escaping the target to satisfy SPEC. Normal return
fails; :SIGNALS cannot coexist with :RETURNS or :POST. Warnings and non-error
signals keep their ordinary behavior and do not satisfy this clause.
PROGRAM-ERROR and UNDEFINED-FUNCTION (including subclasses) always remain
:CONDITION failures, even if SPEC would accept them.

Required, optional, rest and explicit keyword parameters are supported.
&OPTIONAL permits (PARAMETER SPEC [SUPPLIED-P]);
&REST takes one (PARAMETER WHOLE-LIST-SPEC) before any &KEY declarations.
Its predicate variable holds the raw remaining tail, including keyword pairs.
&KEY permits ((:KEY PARAMETER) SPEC [SUPPLIED-P]). A terminal &ALLOW-OTHER-KEYS
permits undeclared keywords. Predicates see NIL for omitted values and a boolean
supplied flag when declared. The first duplicate keyword value wins. Target
defaults are evaluated only by the target. Other lambda list keywords
and unknown clauses signal
INVALID-FUNCTION-SPEC-FORM rather than registering an unchecked claim
(specification §17, §73.1 D1).

:CAPTURE observes values before the call.  It appears at most once, at the top
level, and takes one or more exact (NAME FORM) bindings: NAME is a unique
bindable variable that collides with no argument, supplied-p variable,
:POST-VALUES name or RESULT, and each FORM runs once in declaration order and
sees the arguments and the capture values declared before it.  Only the primary
value is bound, and a captured NIL is a value rather than an absence.  A capture
variable is not a target argument: the argument schema, generator and actual
call are unchanged.  Capture observes a value, it does not copy the object, so
(:CAPTURE (BEFORE ACCOUNT)) does not preserve ACCOUNT's earlier contents; an
author who needs a pre-call representation reads a value out or copies the part
that matters.  Capture forms are contract-side code and must not modify the
inputs or anything reachable from them; cl-spec neither detects nor restores a
violation.

:STATE-POST checks state after the call.  A case-less contract may put one
top-level :STATE-POST; a case-carrying contract puts one inside each case, and
the two positions cannot be combined.  It takes one or more ordinary forms, runs
them in declaration order only after the outcome contract passed, and treats NIL
as a violation and a signalled error as a contract error.  It sees the arguments
and the capture values and binds no implicit RESULT, condition or raw outcome.
Its failure identity is (:STATE-POSTCONDITION INDEX), or
(:CASE NAME :STATE-POSTCONDITION INDEX) inside a case; a signalling form adds
its position too.  The target was called for such a failure, so it keeps the raw
outcome and counts as that case's call.

A state-observing contract is checked by CHECK-FUNCTION but is not shrunk,
replayed from a past result or persisted as a counterexample artifact in this
version, because none of those can rebuild the same initial state.  A
pure-looking use is not exempted, and this is a scope limit, not a claim that
state constraints are inherently unreproducible.

:CASES names the behaviour required of each admitted input, instead of one
outcome for all of them.  :CASES appears at most once and holds one or more
(:NAME [DOCSTRING] (:WHEN FORM) OUTCOME) cases; NAME is a unique keyword,
:WHEN takes exactly one form, and OUTCOME is exactly one of (:RETURNS SPEC) or
(:SIGNALS SPEC).  A :RETURNS case may add :POST or :POST-VALUES with the rules
above; a :SIGNALS case may not, in this version.  :ARGS, :ARGS-GENERATOR and the
common :PRE stay on the contract; a case cannot declare its own, nest :CASES,
or use :ELSE or a priority.

Selection is exclusive: after the common :PRE admits an input, every case's
:WHEN runs in declaration order and exactly one must be true.  :WHEN T is an
ordinary always-true form, not an implicit :ELSE, and :WHEN NIL is an ordinary
never-true one.  Zero matches, several matches, and a guard that signals are
contract-side selection errors: the target is not called, and the result is
:ERROR / :CONTRACT-ERROR with :FAILURE-PHASE :CASE-SELECTION and a structured
explanation naming the error and the cases.  A signal from a guard is such an
error even when it is a SPEC-VIOLATION; only the common :PRE treats that as a
refusal.  A selected case's own outcome judges the invocation by the established
rules, and its name joins the failure identity, so shrinking and rechecking stay
inside that case.

:CASES cannot be combined with a top-level :RETURNS, :SIGNALS, :POST,
:POST-VALUES or :STATE-POST.  CHECK-FUNCTION reports the cases that ran, and the ones no trial
reached, in FUNCTION-CHECK-RESULT-CASE-REPORT; :PASSED means no violation was
observed in the trials that ran, not that every case ran
(specification §17.2).

  (defspec-function remaining-balance
    (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
    (:cases
      (:sufficient-funds
        (:when (<= amount balance))
        (:returns (range integer 0 *))
        (:post (= result (- balance amount))))
      (:insufficient-funds
        (:when (> amount balance))
        (:signals (type insufficient-funds)))))
```


## Functions

<a name="capture-error-data"></a>
### capture-error-data

*Function* · `(condition)`

Project CONDITION as the explanation plist a function-check result carries.

```text
The shape is fixed: :KIND is always :CAPTURE-ERROR, :BINDING and :INDEX name the
form that signalled, and :CONDITION-TYPE and :CONDITION-REPORT describe the
original condition.  The values completed before the failure are the
observation's state evidence, not part of this explanation.
```

<a name="case-selection-error-data"></a>
### case-selection-error-data

*Function* · `(condition)`

Project CONDITION as the explanation plist a function-check result carries.

```text
The shape is fixed: :KIND is always :CASE-SELECTION-ERROR, :CASE-ERROR is the
selection error kind, :FUNCTION names the contract, :CASES lists the ambiguous
matches, and :CASE, :CONDITION-TYPE and :CONDITION-REPORT describe the guard that
signalled.  Unused keys are NIL rather than absent, so a consumer reads one
shape for every kind.
```

<a name="check-function"></a>
### check-function

*Function* · `(function-designator &key trials seed options (registry *registry*))`

Check a function contract using evidence captured during each invocation.

```text
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
not the initial object state, which the author must build.
```

<a name="clear-registry"></a>
### clear-registry

*Function* · `(&optional (registry *registry*))`

Remove every entry from REGISTRY and return REGISTRY.

<a name="compile-explainer"></a>
### compile-explainer

*Function* · `(spec &key context)`

Compile SPEC into a function of (VALUE PATH) returning structured errors.

```text
CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The returned function returns an empty list exactly when VALUE satisfies SPEC,
which is what makes VALIDP and EXPLAIN-DATA incapable of disagreeing.
```

<a name="compile-validator"></a>
### compile-validator

*Function* · `(spec &key context)`

Compile SPEC into a function of one argument returning a generalized boolean.

```text
CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The validator is a thin wrapper over the explainer so that the two can never
disagree about whether a value is admissible.
```

<a name="counterexample-artifact-data"></a>
### counterexample-artifact-data

*Function* · `(artifact)`

Return fresh data, marking digest details absent in older artifacts as not collected.

<a name="current-generator-backend"></a>
### current-generator-backend

*Function*

Return *GENERATOR-BACKEND*, signalling NO-GENERATOR-BACKEND when it is NIL.

<a name="definition-digest"></a>
### definition-digest

*Function* · `(designator &key entity-kind (registry *registry*))`

Return DIGEST, COMPLETE-P and a stable list of digest omission records.
The first two values retain their version-one meaning and complete digest bytes.
Missing or opaque declarations return NIL/NIL with explanatory omissions.
Extension programming errors propagate rather than becoming incompleteness.

<a name="definition-metadata"></a>
### definition-metadata

*Function* · `(definition &key (registry *registry*) (capabilities nil capabilities-p))`

Return v1 metadata for a spec, property or function-spec definition.
Other objects, including custom-generator dependencies, signal TYPE-ERROR.
CAPABILITIES, when supplied, replaces the backend probe; execution uses this
to avoid compiling a disposable generator before constructing the actual one.

<a name="describe-property"></a>
### describe-property

*Function* · `(property-designator &optional (stream *standard-output*))`

Print a human readable rendering of (PROPERTY-DATA PROPERTY-DESIGNATOR) to
STREAM.  Returns NIL.

```text
Not implemented yet.
```

<a name="describe-spec"></a>
### describe-spec

*Function* · `(spec-designator &optional (stream *standard-output*))`

Print a human readable rendering of (SPEC-DATA SPEC-DESIGNATOR) to STREAM.

```text
Returns NIL.  This is a projection of SPEC-DATA and must not report anything
SPEC-DATA does not already carry.

Not implemented yet.
```

<a name="deserialize-counterexample-artifact"></a>
### deserialize-counterexample-artifact

*Function* · `(string)`

Decode and validate AV1 data without reader evaluation or symbol interning.

<a name="explain"></a>
### explain

*Function* · `(spec-designator value &key (stream *standard-output*) (registry *registry*))`

Print a human readable rendering of (EXPLAIN-DATA SPEC-DESIGNATOR VALUE).

```text
Writes to STREAM and returns NIL.  This is a projection of EXPLAIN-DATA and
must not compute anything EXPLAIN-DATA does not already report.
```

<a name="explain-data"></a>
### explain-data

*Function* · `(spec-designator value &key (registry *registry*))`

Return a plist describing whether VALUE satisfies SPEC-DESIGNATOR and why not.

```text
  (:valid <boolean> :spec <symbol> :value <value> :path () :errors (<plist> ...))

This is the primary representation; EXPLAIN, condition reports and any JSON or
MCP projection are derived from it.
```

<a name="failure-identities-match-p"></a>
### failure-identities-match-p

*Function* · `(original candidate)`

Compare observed failure signatures against the ORIGINAL trial.
False property results and conditions have distinct classes, and conditions
compare by type. Legacy primary-value return-spec/postcondition crossings retain
 their shared :RETURN-VALUE class; within each clause, shapes or indices must agree.
Fixed :RETURN-VALUES failures require the same clause and shape or post-form index;
this prevents a return-position violation from shrinking into a different post failure.
An unknown post-form identity never establishes a match, including clause crossings.
A function-spec case wraps that identity as (:CASE NAME . INNER): the case names
must be EQ and the inner comparison is exactly the one above, so the same
violation in a different case is a different failure while the rules inside a
case are unchanged.  A wrapped identity never matches an unwrapped one, so
evidence that names no case cannot be adopted for a case-carrying failure.

<a name="find-function-spec"></a>
### find-function-spec

*Function* · `(name &optional (registry *registry*))`

Return the function spec registered under NAME in REGISTRY, and found-p.

<a name="find-generator"></a>
### find-generator

*Function* · `(name &optional (registry *registry*))`

Return the custom generator registered under NAME, and a found-p second value.

<a name="find-property"></a>
### find-property

*Function* · `(name &optional (registry *registry*))`

Return the property registered under NAME in REGISTRY, and found-p.

<a name="find-spec"></a>
### find-spec

*Function* · `(name &optional (registry *registry*))`

Return the spec registered under NAME in REGISTRY, and a found-p second value.

<a name="function-check-result-function"></a>
### function-check-result-function

*Function* · `(result)`

Return the name of the function RESULT checked.

```text
The same symbol PROPERTY-RESULT-PROPERTY returns, under the name that says what
it is here.
```

<a name="function-spec-argument-schema"></a>
### function-spec-argument-schema

*Function* · `(contract &optional (layout (make-call-layout (function-spec-argument-specs contract))))`

Derive a raw argument schema with a fresh layout, or the supplied LAYOUT.
An installation may supply its private layout. Both paths isolate captured checks
from the contract's exposed layout cache.

<a name="function-spec-data"></a>
### function-spec-data

*Function* · `(function-spec-designator &key (registry *registry*))`

Return a plist describing the contract registered for FUNCTION-SPEC-DESIGNATOR.

```text
  (:name <symbol> :entity-kind :function-spec :kind :function-spec
   :documentation <string-or-nil>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :argument-generator <symbol-or-nil> :argument-schema <tuple spec-data>
   :preconditions (<form> ...) :returns <spec-data plist or NIL>
   :signals <spec-data plist or NIL>
   :postconditions (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>
   [:capture ((:name <symbol> :form <form>) ...)]
   [:state-post (<form> ...)]
   [:case-selection :exclusive
    :cases ((:name <keyword> :documentation <string-or-nil> :when <form>
             :outcome :returns-or-:signals
             :returns <spec-data plist or NIL> :signals <spec-data plist or NIL>
             :postconditions (<form> ...)
             [:state-post (<form> ...)]
             [:post-value-variables (<symbol> ...)]) ...)])

A case-carrying contract adds :CASE-SELECTION and its ordered :CASES.  A case-less
contract omits both keys, so its projection is exactly what it was.  Case guards
and case postconditions are compiled functions and are never projected; their
source forms are.

:CAPTURE lists the ordered capture bindings as declarations, not the values
observed at run time, and :STATE-POST lists the state-post forms.  A contract
that declares neither omits both keys, so its projection is unchanged.  Producing
this data runs no capture form, guard, state-post or target.

This is the projection that answers the two questions a caller asks before
editing a function: which inputs it accepts, and which output it must return
(§28).  :ARGUMENTS, :RETURNS and :SIGNALS carry normalized IR rather than the designators
as written, so a consumer reads one shape whether the contract named a spec or
inlined it.

:PRE and :POST are the forms as written.  Their compiled counterparts are not
projected: a function cannot be read, and a caller who wants to know whether
they hold runs CHECK-FUNCTION rather than inspecting them.

The root additionally carries :SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND,
:DEFINITION-DIGEST, :DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and
:CAPABILITIES (SCHEMA-INFO, §38.1). These envelope keys are always present.
Argument, return, signals and argument-schema nodes are plain IR projections.
Fixed return declarations use :KIND :VALUES with ordered children. Explicit
:POST-VALUES adds :POST-VALUE-VARIABLES; ordinary :POST omits that key.
```

<a name="generation-budget-exhausted-attempts"></a>
### generation-budget-exhausted-attempts

*Function* · `(condition)`

Return the candidate reservations the request made before exhaustion.

<a name="generation-budget-exhausted-budget"></a>
### generation-budget-exhausted-budget

*Function* · `(condition)`

Return the effective candidate budget of the exhausted request.

<a name="generation-budget-exhausted-path"></a>
### generation-budget-exhausted-path

*Function* · `(condition)`

Return the declaration path of the filter whose reservation was denied, or NIL.

<a name="generation-budget-exhausted-phase"></a>
### generation-budget-exhausted-phase

*Function* · `(condition)`

Return :GENERATION or :SHRINKING, the phase that owned the exhausted budget.

<a name="generation-budget-exhausted-rejections"></a>
### generation-budget-exhausted-rejections

*Function* · `(condition)`

Return the filter rejections the request recorded before exhaustion.

<a name="generator-for"></a>
### generator-for

*Function* · `(spec-designator &key context options (registry *registry*))`

Return a compiled generator for SPEC-DESIGNATOR using the current backend.

```text
SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
The result is opaque to everything but the backend and GENERATE-VALUE.
```

<a name="list-function-specs"></a>
### list-function-specs

*Function* · `(&optional (registry *registry*))`

Return the names of every function spec in REGISTRY, sorted.

<a name="list-generators"></a>
### list-generators

*Function* · `(&optional (registry *registry*))`

Return the names of every custom generator in REGISTRY, sorted.

<a name="list-properties"></a>
### list-properties

*Function* · `(&optional (registry *registry*))`

Return the names of every property in REGISTRY, sorted.

<a name="list-specs"></a>
### list-specs

*Function* · `(&optional (registry *registry*))`

Return the names of every spec in REGISTRY, sorted.

<a name="make-counterexample-artifact"></a>
### make-counterexample-artifact

*Function* · `(result &key (selection :selected))`

Freeze original and accepted shrunk evidence from RESULT.
SELECTION is :SELECTED (prefer shrunk), :ORIGINAL or :SHRUNK. Unsupported
evidence signals INVALID-COUNTEREXAMPLE-ARTIFACT; unsupported optional metadata
is represented by an unavailable placeholder and :METADATA-OMISSIONS.
A case-selection error never reached the target, so it is refused here rather
than persisted as a call that never happened.

<a name="make-hash-table-registry"></a>
### make-hash-table-registry

*Function*

Return a fresh empty HASH-TABLE-REGISTRY.

<a name="make-trial-observation"></a>
### make-trial-observation

*Function* · `(&key run property arguments arguments-mutated-p (status :passed) reason signature explanation condition condition-report (outcome :not-collected) value case state failure-phase)`

Create the evidence record for one invocation.

```text
RUN is the observation log the trial belongs to and PROPERTY is the property
that was run.  The accessors below expose the invocation's arguments, outcome
and failure evidence; see OBSERVE-TRIAL for how they are filled in.
```

<a name="normalize-spec-form"></a>
### normalize-spec-form

*Function* · `(form &key name generator source-location)`

Normalize spec DSL FORM into a Semantic IR object.

```text
NAME is the symbol the resulting spec will be registered under, or NIL for an
anonymous inline spec.  GENERATOR names a custom generator the backend should
draw this spec's values from (§11), or NIL to have it derive them from the spec.
SOURCE-LOCATION is a plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION.  When FORM is parsed
from a symbol or a list, all three are attached to the top level node only;
children carry their own source form and nothing else.

When FORM is already a SPEC object -- the branch programmatic and agent-driven
composition relies on -- it is returned unchanged, and NAME/SOURCE-LOCATION are
NOT attached even when supplied.  A GENERATOR alongside one is refused rather
than dropped: NAME and SOURCE-LOCATION are missing metadata, while a generator is
a claim about where values come from, and dropping it would leave the backend
deriving them from the spec the definition said not to use.  SPEC's NAME slot has
no writer, and the same object may already be registered elsewhere or shared as
a child of another
spec, so setting it in place could rename that other registration or a nested
node out from under whoever else holds a reference to it. Attaching a
different name would require returning a copy instead, which would need a
clone protocol across every concrete SPEC subclass; nothing in this codebase
needs that yet, so it has not been built. Callers that must name an
already-built spec should register it directly (see
CL-SPEC/SRC/REGISTRY:REGISTER-SPEC) rather than relying on NAME here.

The returned spec keeps FORM verbatim in its SPEC-SOURCE-FORM slot.
```

<a name="observation-failure-p"></a>
### observation-failure-p

*Function* · `(observation)`

Return true when OBSERVATION records a failed or signalled trial.

<a name="observe-trial"></a>
### observe-trial

*Function* · `(property arguments &key context)`

Evaluate generated objects once, snapshot evidence and record invocation provenance.
Mutations of conses and arrays, including changed sharing, stop backend shrinking.
The optional eighth EVALUATE-TRIAL value names the selected function-spec case, or
NIL when none was selected, and is recorded on the observation.  The optional
ninth is the failure phase the classifier recorded, or NIL for a target
observation; a recorded phase is checked to be consistent with the status and the
case.  The optional tenth is the trial's state evidence, recorded as captured.

<a name="properties-for"></a>
### properties-for

*Function* · `(target &optional (registry *registry*))`

Return the names of properties registered against TARGET in REGISTRY, sorted.

<a name="properties-with-tag"></a>
### properties-with-tag

*Function* · `(tag &optional (registry *registry*))`

Return the names of properties carrying TAG in REGISTRY, sorted.

<a name="property-data"></a>
### property-data

*Function* · `(property-designator &key (registry *registry*))`

Return a plist describing the registered property named by PROPERTY-DESIGNATOR.

```text
  (:name <symbol> :entity-kind :property :kind <author classification>
   :targets (<symbol> ...) :tags (<tag> ...)
   :documentation <string> :trials <plist>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :body (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>)

The root additionally carries the seven schema envelope keys described by
SCHEMA-INFO: :SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND, :DEFINITION-DIGEST,
:DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and :CAPABILITIES.
Nested specs are plain IR projections. :TRIALS is a profile table in this
definition record; result records carry executed counts under that key.
The body is the author's source rather than the compiled function (§39).
```

<a name="property-result-explanation"></a>
### property-result-explanation

*Function* · `(result)`

Return the selected failure explanation; internal post-form tags are excluded.

```text
:CONTRACT-ERROR is included because a function-spec case-selection error records
its structured explanation there, and :STATE-POSTCONDITION because a violated
:state-post records the case, form position and source.  A contract-side error
that records no explanation still reads NIL, so the projection of existing
contract errors does not change.
```

<a name="property-result-failure-reason"></a>
### property-result-failure-reason

*Function* · `(result)`

Return the selected observation's reason, a stored generation reason, or NIL.

<a name="property-result-failure-signature"></a>
### property-result-failure-signature

*Function* · `(result)`

Return the selected observation's failure identity, or NIL on success.

<a name="recheck-counterexample"></a>
### recheck-counterexample

*Function* · `(artifact &key (registry *registry*) (state-policy :unconfirmed) (target-revision :unknown))`

Recheck saved input once without generation or shrinking.
Execution requires :STATE-POLICY :STATELESS, a caller assertion that external
state needs no restoration. Definition identity must be complete and unchanged.
Returns a :RECHECK record; never mutates the saved artifact or original result.

<a name="register-function-spec"></a>
### register-function-spec

*Function* · `(function-spec &optional (registry *registry*))`

Register FUNCTION-SPEC in REGISTRY under its own name and return it.

<a name="register-generator"></a>
### register-generator

*Function* · `(generator &optional (registry *registry*))`

Register GENERATOR in REGISTRY under its own name and return it.

<a name="register-property"></a>
### register-property

*Function* · `(property &optional (registry *registry*))`

Register PROPERTY in REGISTRY under its own name and return PROPERTY.

```text
The target and tag index keys are taken from the property object, which is why
this function lives here rather than in the registry: the registry deliberately
knows nothing about property objects.
```

<a name="register-spec"></a>
### register-spec

*Function* · `(name spec &optional (registry *registry*))`

Register SPEC under NAME in REGISTRY and return SPEC.

<a name="replay-property"></a>
### replay-property

*Function* · `(property-designator seed &key profile options (registry *registry*))`

Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

```text
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
result's, so a caller can deliberately replay under a different budget. An
integer SEED carries no profile, so that spelling still requires the caller to
supply a matching PROFILE.

SEED must be a property-result or a non-negative integer, or an error is
signalled.

Passing a PROPERTY-RESULT asks to re-apply that past run.  A property whose
definition declares state constraints refuses that, before the integer seed is
extracted, with UNSUPPORTED-STATEFUL-OPERATION: nothing restores its state.  An
integer SEED starts a new run and stays allowed.
```

<a name="result-data"></a>
### result-data

*Function* · `(result)`

Return a versioned result record using metadata captured before execution.
Never resolve the current registry to describe an old result. Manually constructed
results without captured metadata have an explicitly incomplete digest.

<a name="run-properties"></a>
### run-properties

*Function* · `(property-designators &key profile options (registry *registry*))`

Run each property in PROPERTY-DESIGNATORS and return the results in order.

```text
Each run draws its own seed, so one failure can be replayed without re-running
the others.
```

<a name="run-property"></a>
### run-property

*Function* · `(property-designator &key profile seed options (registry *registry*))`

Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

```text
PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend.

A PROPERTY-RESULT supplied as SEED asks to re-apply a past run.  A property
whose definition declares state constraints refuses that with
UNSUPPORTED-STATEFUL-OPERATION before generation, capture or the target, because
nothing restores its state.  An integer SEED starts a new run and stays allowed.
```

<a name="sample"></a>
### sample

*Function* · `(spec-designator &key (count 10) seed (branch nil branch-p) (generation-budget nil generation-budget-p) (registry *registry*))`

Return (VALUES VALUES REPORT) for COUNT values generated from SPEC-DESIGNATOR.

```text
VALUES is the sampled list.  REPORT is the generation report for this one
request: the bounded-filter candidate budget, attempts, rejections and phases.

SEED, when supplied, makes the whole sequence reproducible.  BRANCH, when
supplied, samples only the named branch of a tagged union, which is how a caller
aims generation at one alternative; an explicitly supplied NIL is an unknown
branch and is refused rather than read as "no branch requested", so a caller
forwarding a computed branch value is told when it is bad.  GENERATION-BUDGET,
when supplied, is the request-wide bounded-filter candidate budget; explicit zero
is not an omission.  Intended for inspecting what a spec admits, from the REPL or
from an agent.
```

<a name="schema-info"></a>
### schema-info

*Function*

Describe version 1 of the Lisp definition/result schema, independent of MCP JSON.

<a name="semantic-data"></a>
### semantic-data

*Function* · `(symbol &key (registry *registry*))`

Return a routing table of what REGISTRY knows about SYMBOL.

```text
  (:symbol <symbol> :package <string-or-nil>
   :spec <symbol-or-nil> :function-spec <symbol-or-nil>
   :property <symbol-or-nil> :properties-about (<symbol> ...))

Every value is a name, or a list of names, never expanded content: pass
:SPEC to SPEC-DATA, and each of :PROPERTIES-ABOUT to PROPERTY-DATA, to fetch
the content itself. cl-mcp runs in the same Lisp image as cl-spec, so a
follow-up lookup is a function call rather than a round trip -- there is no
argument for inlining here that a round trip would otherwise supply. And
PROPERTY-DATA carries a property's body and source form while SPEC-DATA is
small, so inlining either here would make this response's size vary by an
order of magnitude depending on which symbol was asked about.

:SPEC and :FUNCTION-SPEC hold SYMBOL itself when something is registered under
it, NIL otherwise. This is redundant today, since lookup is by identity, but
it keeps the shape stable if lookup ever stops being identity, and lets the
caller pass the value straight into a follow-up call. :PROPERTY holds SYMBOL
when SYMBOL is itself the name of a registered property, which is a different
relationship from :PROPERTIES-ABOUT: the sorted names of properties registered
*about* SYMBOL (see PROPERTIES-FOR). A symbol can be both at once.

:PACKAGE is the name of SYMBOL's home package, or NIL when SYMBOL is
uninterned (specification §8).

SEMANTIC-DATA never signals for an unknown symbol: it returns the full shape
with every value NIL or empty. This is a deliberate asymmetry with SPEC-DATA,
which signals UNKNOWN-SPEC for an unregistered name. Callers such as cl-mcp's
describe_symbol call this on arbitrary symbols, most of which have nothing
registered, so signalling would force every caller to handle a condition for
what is the common case.

That guarantee covers an unknown symbol, not an unknown value: SYMBOL must be
a symbol, and passing anything else signals a TYPE-ERROR from SYMBOL-PACKAGE
before any lookup runs. A caller that takes a name from outside the image --
from JSON, say -- resolves it to a symbol first. Every key listed above is
always present, whatever its value: a key that appears and disappears with its
value would break JSON consumers, matching the rule SPEC-DATA already
follows.
```

<a name="serialize-counterexample-artifact"></a>
### serialize-counterexample-artifact

*Function* · `(artifact)`

Return bounded AV1 wire data, never a Lisp reader form.

<a name="source-location-file"></a>
### source-location-file

*Function* · `(location)`

Return the file namestring recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned.

<a name="source-location-package"></a>
### source-location-package

*Function* · `(location)`

Return the package name recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned.

<a name="spec-data"></a>
### spec-data

*Function* · `(spec-designator &key (registry *registry*))`

Return a plist describing the registered spec named by SPEC-DESIGNATOR.

```text
  (:name <symbol> :entity-kind :spec :kind <keyword> :generator <symbol or NIL>
   <node specific keys> :source-form <form>
   :source-location (:file <string> :package <string>)
   :children (<nested plist> ...))

:CHILDREN is present only on nodes that have children. A constrained LIST-OF or
VECTOR-OF adds :MIN-LENGTH, :MAX-LENGTH and :UNIQUE for the constraints it
declares; an unconstrained collection carries none of them. The root additionally
has :SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND, :DEFINITION-DIGEST,
:DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and :CAPABILITIES (see
SCHEMA-INFO, specification §38.1). Children are plain IR projections.
```

<a name="state-post-error-data"></a>
### state-post-error-data

*Function* · `(condition)`

Project CONDITION as the explanation plist a function-check result carries.

```text
The shape is fixed: :KIND is always :STATE-POST-ERROR, :CASE, :INDEX and :FORM
name the offending clause position, and :CONDITION-TYPE and :CONDITION-REPORT
describe the original condition.  Expected values are not extracted.
```

<a name="tagged-union-branch"></a>
### tagged-union-branch

*Function* · `(spec name)`

Return the branch spec of tagged union SPEC named NAME.

```text
Signals INVALID-SPEC-FORM when SPEC is not a tagged union or NAME is unknown, so
a caller aiming generation at one branch is told which branches exist.
```

<a name="trial-observation-arguments"></a>
### trial-observation-arguments

*Function* · `(instance)`

Snapshot of the argument list the invocation received, or NIL.

<a name="trial-observation-arguments-mutated-p"></a>
### trial-observation-arguments-mutated-p

*Function* · `(instance)`

True when the invocation changed the structure of its arguments.

```text
Conses and arrays are compared with SAME-VALUE-P before and after the call.
Arbitrary objects and external state are not checkpointed or compared.
```

<a name="trial-observation-case"></a>
### trial-observation-case

*Function* · `(instance)`

Name of the selected function-spec case, or NIL.

```text
A case-less contract, a precondition refusal and a case-selection error all have
no selected case, so this is NIL for them.  A failure of a selected case carries
the name in its signature as well, which is what keeps shrinking and rechecking
inside one case.

A contract error raised while classifying a selected case still records that
case: the target was called for it, so the failure belongs to it and the case
report must count the call.
```

<a name="trial-observation-condition"></a>
### trial-observation-condition

*Function* · `(instance)`

The condition object the invocation signalled, or NIL.

<a name="trial-observation-condition-report"></a>
### trial-observation-condition-report

*Function* · `(instance)`

Text of CONDITION rendered at observation time, or NIL.

```text
The condition object is retained for inspection, but a report is captured
first because not every condition can be printed again later.
```

<a name="trial-observation-explanation"></a>
### trial-observation-explanation

*Function* · `(instance)`

Structured EXPLAIN-DATA for the failed check, or NIL.

<a name="trial-observation-outcome"></a>
### trial-observation-outcome

*Function* · `(instance)`

Observed outcome plist, or :NOT-COLLECTED when the evaluator did not
report one.

```text
Distinguishes a call that returned zero values from one that returned a single
NIL, which the primary VALUE alone cannot.
```

<a name="trial-observation-reason"></a>
### trial-observation-reason

*Function* · `(instance)`

Machine-readable failure reason keyword, or NIL when the invocation
passed or was rejected.

<a name="trial-observation-signature"></a>
### trial-observation-signature

*Function* · `(instance)`

Failure identity a shrink candidate must preserve, or NIL.

```text
Status and reason alone do not pin a failure down: the signature says which
return spec or postcondition form broke, so shrinking cannot cross from one
failure into another.
```

<a name="trial-observation-state"></a>
### trial-observation-state

*Function* · `(instance)`

State evidence for a :CAPTURE / :STATE-POST trial, or NIL.

```text
A contract that declares neither clause records NIL, so a featureless run's
evidence is unchanged.  The plist carries :CAPTURE and :STATE-POST entries with
the statuses and details fixed by the specification; capture values are copied
with the same evidence snapshot as the other fields.
```

<a name="trial-observation-status"></a>
### trial-observation-status

*Function* · `(instance)`

One of :PASSED, :REJECTED, :FAILED or :ERROR.

<a name="trial-observation-value"></a>
### trial-observation-value

*Function* · `(instance)`

Snapshot of the primary value the invocation returned, or NIL.

<a name="validate"></a>
### validate

*Function* · `(spec-designator value &key (registry *registry*))`

Return VALUE when it satisfies SPEC-DESIGNATOR, otherwise signal SPEC-VIOLATION.

```text
The signalled condition carries the structured error list produced by
EXPLAIN-DATA so that callers do not have to re-run the check.
```

<a name="validp"></a>
### validp

*Function* · `(spec-designator value &key (registry *registry*))`

Return true when VALUE satisfies the spec named by SPEC-DESIGNATOR.

```text
SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
Signals UNKNOWN-SPEC when a symbol resolves to nothing.
```


## Generic functions

<a name="backend-capabilities"></a>
### backend-capabilities

*Generic function* · `(backend spec &key registry)`

Describe generation and shrinking without drawing or invoking user predicates.

<a name="backend-default-trials"></a>
### backend-default-trials

*Generic function* · `(backend)`

Return the trial count BACKEND uses when a property names none.

```text
The core cannot read check-it's own default, so the backend answers for it.
```

<a name="compile-generator"></a>
### compile-generator

*Generic function* · `(backend spec &key context options)`

Compile SPEC into a BACKEND-specific generator object.

```text
CONTEXT carries resolution state such as the registry; OPTIONS carries
generation parameters such as size limits.  The returned object is opaque to
everything except BACKEND and GENERATE-VALUE.
```

<a name="definition-description"></a>
### definition-description

*Generic function* · `(definition)`

Return values: declaration data, ordered child definitions,
registry links as (KIND . NAME) pairs, and whether the stored description is complete.
Do not invoke user code. Source locations and capabilities are excluded.

<a name="definition-validation-slots"></a>
### definition-validation-slots

*Generic function* · `(object)`

Append participating slot names from a definition and its subclasses.

<a name="evaluate-trial"></a>
### evaluate-trial

*Generic function* · `(property arguments &key context)`

Evaluate PROPERTY once, returning status, reason, signature,
explanation, condition and value. Status is :passed, :rejected, :failed or :error.
The optional seventh value is the captured target call outcome; the optional
eighth names the selected function-spec case, or NIL when none was selected; the
optional ninth is the failure phase the classifier recorded, or NIL for a target
observation.  A classifier records :CASE-SELECTION only when selection itself
failed, so nothing infers a phase from a condition's class; it records :CAPTURE
for a capture form that signalled and :STATE-POST for a state-post form that
failed or signalled, and only the latter means the target was called.  The
optional tenth is the trial's state evidence plist, or NIL when the contract
declares neither :CAPTURE nor :STATE-POST.
The first six keep their established meaning, so an existing specialization that
returns only those stays valid.
Backends call OBSERVE-TRIAL to capture these values with the input snapshot.
Specializations must classify during this invocation, never by rerunning it.

<a name="function-check-result-budget"></a>
### function-check-result-budget

*Generic function* · `(result)`

Return the trial budget stored in the shared property result.

<a name="generate-value"></a>
### generate-value

*Generic function* · `(backend compiled-generator &key seed)`

Produce one value from COMPILED-GENERATOR using BACKEND.

```text
SEED, when supplied, makes the value reproducible (specification §15).
```

<a name="property-argument-schema"></a>
### property-argument-schema

*Generic function* · `(property)`

Return the whole positional argument tuple spec compiled by a backend.

<a name="property-call-arguments-p"></a>
### property-call-arguments-p

*Generic function* · `(property arguments)`

Check raw call shape without running argument predicates or target code.

<a name="property-named-arguments"></a>
### property-named-arguments

*Generic function* · `(property arguments)`

Project raw call arguments to a plist of contract variable bindings.

<a name="property-result-entity-kind"></a>
### property-result-entity-kind

*Generic function* · `(result)`

Return :PROPERTY or :FUNCTION-SPEC, independently of author classification.

<a name="registry-clear"></a>
### registry-clear

*Generic function* · `(registry)`

Remove every entry from REGISTRY and return REGISTRY.

<a name="registry-find-function-spec"></a>
### registry-find-function-spec

*Generic function* · `(registry name)`

Return the function spec registered in REGISTRY under NAME.
Returns two values: the function spec (NIL when absent) and a found-p boolean.

<a name="registry-find-generator"></a>
### registry-find-generator

*Generic function* · `(registry name)`

Return the custom generator registered in REGISTRY under NAME.
Returns two values: the generator (NIL when absent) and a found-p boolean.

<a name="registry-find-property"></a>
### registry-find-property

*Generic function* · `(registry name)`

Return the property registered in REGISTRY under NAME.
Returns two values: the property (NIL when absent) and a found-p boolean.

<a name="registry-find-spec"></a>
### registry-find-spec

*Generic function* · `(registry name)`

Return the spec registered in REGISTRY under NAME.
Returns two values: the spec (NIL when absent) and a found-p boolean.

<a name="registry-list-function-specs"></a>
### registry-list-function-specs

*Generic function* · `(registry)`

Return the names of every function spec in REGISTRY, sorted.

<a name="registry-list-generators"></a>
### registry-list-generators

*Generic function* · `(registry)`

Return the names of every custom generator in REGISTRY, sorted.

<a name="registry-list-properties"></a>
### registry-list-properties

*Generic function* · `(registry)`

Return the names of every property in REGISTRY, sorted.

<a name="registry-list-specs"></a>
### registry-list-specs

*Generic function* · `(registry)`

Return the names of every spec in REGISTRY, sorted.

<a name="registry-properties-for"></a>
### registry-properties-for

*Generic function* · `(registry target)`

Return the names of properties registered against TARGET,
sorted.

<a name="registry-properties-with-tag"></a>
### registry-properties-with-tag

*Generic function* · `(registry tag)`

Return the names of properties carrying TAG, sorted.

<a name="registry-register-function-spec"></a>
### registry-register-function-spec

*Generic function* · `(registry name function-spec)`

Register FUNCTION-SPEC in REGISTRY under NAME, replacing any
previous definition.  Returns FUNCTION-SPEC.

<a name="registry-register-generator"></a>
### registry-register-generator

*Generic function* · `(registry name generator)`

Register GENERATOR in REGISTRY under NAME, replacing any
previous definition.  Returns GENERATOR.

<a name="registry-register-property"></a>
### registry-register-property

*Generic function* · `(registry name property &key targets tags)`

Register PROPERTY in REGISTRY under NAME.

```text
TARGETS is a list of symbols the property is about; TAGS is a list of tag
designators.  Both are indexed for reverse lookup.  Re-registering a name
replaces the previous definition and drops its stale index entries.
Returns PROPERTY.
```

<a name="registry-register-spec"></a>
### registry-register-spec

*Generic function* · `(registry name spec)`

Register SPEC in REGISTRY under NAME, replacing any previous
definition.  Returns SPEC.

<a name="run-generated-test"></a>
### run-generated-test

*Generic function* · `(backend property &key options)`

Run PROPERTY and return a validated backend outcome plist.
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
untested shrink return value as a counterexample. :PASSED consumes the full budget.

<a name="spec-children"></a>
### spec-children

*Generic function* · `(spec)`

Return the child specs of SPEC as a list, in definition order.

```text
Leaf nodes return NIL.  Callers use this to walk the IR without knowing which
slot a particular class stores its children in.
```

<a name="spec-kind"></a>
### spec-kind

*Generic function* · `(spec)`

Return the canonical keyword identifying SPEC's node type.

```text
The keyword is part of the public introspection contract: SPEC-DATA and the
MCP/JSON projections use it as the discriminator, so it must stay stable even
if class names change.
```

<a name="validate-definition"></a>
### validate-definition

*Generic function* · `(object)`

Validate and normalize a definition, returning OBJECT.


## Accessors

<a name="capture-error-binding"></a>
### capture-error-binding

*Accessor* of `capture-error` · `(condition)`

Name of the :capture binding whose form signalled.

<a name="capture-error-captured"></a>
### capture-error-captured

*Accessor* of `capture-error` · `(condition)`

Ordered (NAME . VALUE) pairs completed before the failure.
Only the bindings that finished are present; a later binding is never shown as
obtained, and a captured NIL is a pair with a NIL value rather than an absence.
A value the evidence snapshot cannot preserve is reported as an
(:unavailable :reason :opaque-value :type TYPE) placeholder rather than as a
live reference.

<a name="capture-error-function"></a>
### capture-error-function

*Accessor* of `capture-error` · `(condition)`

Name of the function whose contract was being checked.

<a name="capture-error-index"></a>
### capture-error-index

*Accessor* of `capture-error` · `(condition)`

Zero-based declaration position of the failing binding.

<a name="capture-error-original-condition"></a>
### capture-error-original-condition

*Accessor* of `capture-error` · `(condition)`

Condition the capture form signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again.

<a name="case-selection-error-case"></a>
### case-selection-error-case

*Accessor* of `case-selection-error` · `(condition)`

Case whose :WHEN signalled, for :CASE-GUARD-ERROR.  NIL otherwise.

<a name="case-selection-error-cases"></a>
### case-selection-error-cases

*Accessor* of `case-selection-error` · `(condition)`

Case names that matched more than once, for :AMBIGUOUS-CASE.
NIL for the other kinds.

<a name="case-selection-error-function"></a>
### case-selection-error-function

*Accessor* of `case-selection-error` · `(condition)`

Name of the function whose contract was being checked.

<a name="case-selection-error-kind"></a>
### case-selection-error-kind

*Accessor* of `case-selection-error` · `(condition)`

:NO-MATCHING-CASE, :AMBIGUOUS-CASE or :CASE-GUARD-ERROR.

<a name="case-selection-error-original-condition"></a>
### case-selection-error-original-condition

*Accessor* of `case-selection-error` · `(condition)`

Condition the case guard signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again.

<a name="custom-generator-documentation"></a>
### custom-generator-documentation

*Accessor* of `custom-generator` · `(object)`

The definition's docstring, or NIL.

<a name="custom-generator-function"></a>
### custom-generator-function

*Accessor* of `custom-generator` · `(object)`

Function of no arguments returning one generated
value.  The backend calls it once per draw.

<a name="custom-generator-name"></a>
### custom-generator-name

*Accessor* of `custom-generator` · `(object)`

Symbol this generator is registered under.  A spec
names it in a (:GENERATOR NAME) clause, and the backend resolves that name in
the same registry the spec was resolved in.

<a name="custom-generator-shrinker"></a>
### custom-generator-shrinker

*Accessor* of `custom-generator` · `(object)`

Optional function returning an ordered finite list of shrink candidates.

<a name="custom-generator-source-form"></a>
### custom-generator-source-form

*Accessor* of `custom-generator` · `(object)`

The whole DEFGENERATOR form, kept verbatim.

<a name="custom-generator-source-location"></a>
### custom-generator-source-location

*Accessor* of `custom-generator` · `(object)`

Source location plist, or NIL.

<a name="function-check-result-case-report"></a>
### function-check-result-case-report

*Accessor* of `function-check-result` · `(object)`

Per-case report of this run, or :NOT-COLLECTED.

```text
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
conclusion.
```

<a name="function-check-result-explanation"></a>
### function-check-result-explanation

*Accessor* of `function-check-result` · `(object)`

EXPLAIN-DATA for :RETURN-SPEC or :CONDITION-SPEC failures.
For :MISSING-CONDITION, a plist with the :EXPECTED descriptor. Otherwise NIL.
The data explains which part of the declared outcome the invocation missed.

<a name="function-check-result-failure-reason"></a>
### function-check-result-failure-reason

*Accessor* of `function-check-result` · `(object)`

Which half of the contract broke:
:RETURN-SPEC, :POSTCONDITION, :MISSING-CONDITION, :CONDITION-SPEC,
:CONDITION, :CONTRACT-ERROR, or NIL.

```text
:CONTRACT-ERROR is not a half breaking: the contract's own predicate or spec
signalled on the value the function returned, so the fault may be either
side's.

It describes the counterexample this result puts forward -- the shrunk one
when there is one, the original otherwise -- and the status agrees with it.

There is no :PRECONDITION: the trial predicate answers true for every input
:PRE refuses, so one can never be the reason a run failed.

NIL on a passing or skipped run. Failure reasons come from the recorded
invocation, including for a function that would not answer the same way twice.
```

<a name="function-check-result-rejected"></a>
### function-check-result-rejected

*Accessor* of `function-check-result` · `(object)`

Generated argument lists the preconditions refused.

```text
TRIALS counts what the backend generated; TRIALS minus this is the number of
trials that reached case selection.  Reporting only the first would let a run
that rejected every input read as a run that checked every input (§19, §73.3).

Not the number of target calls: a case-selection error calls no target, and
shrinking may invoke the function on candidate inputs.  Classification itself
makes no additional call.  This counts generated trials; read
FUNCTION-CHECK-RESULT-CASE-REPORT for per-case call counts.
```

<a name="function-check-result-shrunk-outcome"></a>
### function-check-result-shrunk-outcome

*Accessor* of `function-check-result` · `(object)`

What became of the shrink candidate: :USED, :NONE or
:DIFFERENT-FAILURE, or NIL when no failure was reported.

```text
A NIL SHRUNK-COUNTEREXAMPLE cannot say this on its own -- it reads the same
whether the shrinker found nothing smaller or produced a candidate the checker
refused to put forward -- and on a failing contract run the second reading is the
common one.  :USED means the value in SHRUNK-COUNTEREXAMPLE is the candidate.
:DIFFERENT-FAILURE means incompatible failures were rejected and no matching
reduction was observed. :NONE means no reduction was observed, including when
there were no arguments, shrinking was disabled, or argument mutation stopped it.
When a matching candidate is observed, :USED takes precedence over earlier
rejections. The original evidence remains available in every case.
```

<a name="function-check-result-source-form"></a>
### function-check-result-source-form

*Accessor* of `function-check-result` · `(object)`

The contract's own source form, as it was when
the run started.

```text
The run holds the contract by identity, but the result identified it only by
name.  Re-registering that name -- a reload, an edit -- leaves the result
saying "F passed" while the contract now under F is one F fails, with nothing
to notice it by.
```

<a name="function-spec-argument-generator"></a>
### function-spec-argument-generator

*Accessor* of `function-spec` · `(object)`

Name of a registered no-argument generator returning
the entire positional argument list, or NIL for independent argument generation.
Each draw is checked against the argument specs before preconditions or the target.

<a name="function-spec-argument-specs"></a>
### function-spec-argument-specs

*Accessor* of `function-spec` · `(object)`

Required (PARAMETER SPEC) pairs followed optionally by
&amp;OPTIONAL (PARAMETER SPEC [SUPPLIED-P]) and &amp;KEY ((:KEY PARAMETER) SPEC [SUPPLIED-P])
declarations. &amp;REST (PARAMETER WHOLE-LIST-SPEC) captures the raw remaining tail
before &amp;KEY. A terminal &amp;ALLOW-OTHER-KEYS permits extra keys. SPEC is normalized
to Semantic IR. Parameter and supplied-variable names are unique. Omitted values
bind to NIL in predicates without evaluating target defaults.

<a name="function-spec-documentation"></a>
### function-spec-documentation

*Accessor* of `function-spec` · `(object)`

Docstring of the contract, or NIL.

```text
This is the contract's own prose, not the function's: it says what the contract
claims, which is what an agent asking "what may I pass here" needs.
```

<a name="function-spec-metadata"></a>
### function-spec-metadata

*Accessor* of `function-spec` · `(object)`

Arbitrary plist for callers and future extensions.

<a name="function-spec-name"></a>
### function-spec-name

*Accessor* of `function-spec` · `(object)`

Package-qualified symbol naming the specified function.

<a name="function-spec-post-value-variables"></a>
### function-spec-post-value-variables

*Accessor* of `function-spec` · `(object)`

Use :PRIMARY for legacy post predicates, or an explicit
list of return names. Explicit predicates receive the full values list first.

<a name="function-spec-postcondition-function"></a>
### function-spec-postcondition-function

*Accessor* of `function-spec` · `(object)`

Compiled predicate over the return
value followed by the parameters, true when every :POST form holds, or NIL when
the contract has no :POST. To identify a failed form for shrinking, return
(values nil index :cl-spec-post-form-failure), where INDEX is its zero-based
position in POSTCONDITIONS. A one-value predicate remains valid, but its failures
have unknown form identity and cannot be accepted as shrink reductions.

<a name="function-spec-postconditions"></a>
### function-spec-postconditions

*Accessor* of `function-spec` · `(object)`

The :POST forms as written, kept for reading.
POSTCONDITION-FUNCTION is what actually runs.

<a name="function-spec-precondition-function"></a>
### function-spec-precondition-function

*Accessor* of `function-spec` · `(object)`

Compiled predicate over the parameters,
true when every :PRE form holds, or NIL when the contract has no :PRE.

```text
Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.
```

<a name="function-spec-preconditions"></a>
### function-spec-preconditions

*Accessor* of `function-spec` · `(object)`

The :PRE forms as written, kept for reading
(specification §19).  PRECONDITION-FUNCTION is what actually runs.

<a name="function-spec-return-spec"></a>
### function-spec-return-spec

*Accessor* of `function-spec` · `(object)`

Semantic IR object the return value must
satisfy, from :RETURNS, or NIL when the contract names none.

<a name="function-spec-signal-spec"></a>
### function-spec-signal-spec

*Accessor* of `function-spec` · `(object)`

Normalized spec required of an error escaping the target,
or NIL for an ordinary return contract. Normal return violates a signal contract.
Mutually exclusive with return-spec and postconditions. PROGRAM-ERROR and
UNDEFINED-FUNCTION are reserved execution failures, never accepted by this spec.

<a name="function-spec-source-form"></a>
### function-spec-source-form

*Accessor* of `function-spec` · `(object)`

The whole DEFSPEC-FUNCTION form, kept verbatim.

<a name="function-spec-source-location"></a>
### function-spec-source-location

*Accessor* of `function-spec` · `(object)`

Source location plist, or NIL.

<a name="generation-budget-exhausted-report"></a>
### generation-budget-exhausted-report

*Accessor* of `generation-budget-exhausted` · `(condition)`

Immutable snapshot of the request's generation report
at the moment the budget was exhausted.

<a name="generation-budget-exhausted-request"></a>
### generation-budget-exhausted-request

*Accessor* of `generation-budget-exhausted` · `(condition)`

Identity of the generation request whose budget ran out.

```text
Compared by the runner against the request it owns, so an inner public request's
or a target's condition of the same class is not misread as this request's own
depletion.  The live object is internal state, never wire metadata.
```

<a name="generator-unavailable-reason"></a>
### generator-unavailable-reason

*Accessor* of `generator-unavailable` · `(condition)`

Human readable explanation, or NIL.

<a name="generator-unavailable-spec"></a>
### generator-unavailable-spec

*Accessor* of `generator-unavailable` · `(condition)`

Spec no generator could be derived from.

<a name="invalid-backend-result-reason"></a>
### invalid-backend-result-reason

*Accessor* of `invalid-backend-result` · `(condition)`

Why the backend's returned value is invalid.

<a name="invalid-counterexample-artifact-reason"></a>
### invalid-counterexample-artifact-reason

*Accessor* of `invalid-counterexample-artifact` · `(condition)`

Why the serialized artifact cannot be accepted.

<a name="invalid-function-spec-form-form"></a>
### invalid-function-spec-form-form

*Accessor* of `invalid-function-spec-form` · `(condition)`

The clause, or the slot value, that could not be accepted.

<a name="invalid-function-spec-form-reason"></a>
### invalid-function-spec-form-reason

*Accessor* of `invalid-function-spec-form` · `(condition)`

Human readable explanation, or NIL.

<a name="invalid-generated-arguments-generator"></a>
### invalid-generated-arguments-generator

*Accessor* of `invalid-generated-arguments` · `(condition)`

Name of the argument-set generator that produced invalid output.

<a name="invalid-generated-arguments-reason"></a>
### invalid-generated-arguments-reason

*Accessor* of `invalid-generated-arguments` · `(condition)`

Why the generated value cannot be used as arguments.

<a name="invalid-generated-arguments-value"></a>
### invalid-generated-arguments-value

*Accessor* of `invalid-generated-arguments` · `(condition)`

Snapshot of the invalid generated argument set.

<a name="invalid-generator-form-form"></a>
### invalid-generator-form-form

*Accessor* of `invalid-generator-form` · `(condition)`

The DEFGENERATOR form that could not be accepted.

<a name="invalid-generator-form-reason"></a>
### invalid-generator-form-reason

*Accessor* of `invalid-generator-form` · `(condition)`

Human readable explanation, or NIL.

<a name="invalid-property-form-form"></a>
### invalid-property-form-form

*Accessor* of `invalid-property-form` · `(condition)`

The rejected DEFPROPERTY name, bindings, body, or option clause.

<a name="invalid-property-form-reason"></a>
### invalid-property-form-reason

*Accessor* of `invalid-property-form` · `(condition)`

Human readable explanation, or NIL.

<a name="invalid-spec-form-form"></a>
### invalid-spec-form-form

*Accessor* of `invalid-spec-form` · `(condition)`

The spec DSL form that could not be normalized.

<a name="invalid-spec-form-reason"></a>
### invalid-spec-form-reason

*Accessor* of `invalid-spec-form` · `(condition)`

Human readable explanation, or NIL.

<a name="not-implemented-operator"></a>
### not-implemented-operator

*Accessor* of `not-implemented` · `(condition)`

Symbol naming the operator that is still a stub.

<a name="property-arguments"></a>
### property-arguments

*Accessor* of `property` · `(object)`

List of (VARIABLE SPEC) bindings the generator
fills in.  SPEC is a normalized Semantic IR object; a spec written as a bare
symbol becomes a REFERENCE-SPEC, so a property may name a spec defined later.

<a name="property-body"></a>
### property-body

*Accessor* of `property` · `(object)`

Forms of the property predicate, kept verbatim so that
introspection can show the author's source.

<a name="property-documentation"></a>
### property-documentation

*Accessor* of `property` · `(object)`

Human readable description, or NIL.

<a name="property-function"></a>
### property-function

*Accessor* of `property` · `(object)`

The predicate compiled from BODY.
Kept alongside BODY rather than instead of it: a compiled function cannot be
read, and reading the property is half of what it is for (specification §39).

<a name="property-kind"></a>
### property-kind

*Accessor* of `property` · `(object)`

Classification keyword such as :INVARIANT or
:ROUND-TRIP (specification §6).

<a name="property-metadata"></a>
### property-metadata

*Accessor* of `property` · `(object)`

Arbitrary plist for callers and future extensions.

<a name="property-name"></a>
### property-name

*Accessor* of `property` · `(object)`

Package-qualified symbol naming this property.

<a name="property-result-budget"></a>
### property-result-budget

*Accessor* of `property-result` · `(object)`

Resolved trial budget, or NIL on a manually built result.

<a name="property-result-condition"></a>
### property-result-condition

*Accessor* of `property-result` · `(object)`

Condition signalled by the property
body, or NIL.

<a name="property-result-counterexample"></a>
### property-result-counterexample

*Accessor* of `property-result` · `(object)`

Arguments of the first failing trial.

<a name="property-result-elapsed"></a>
### property-result-elapsed

*Accessor* of `property-result` · `(object)`

Wall clock seconds the run took, or NIL.

<a name="property-result-failure-evidence"></a>
### property-result-failure-evidence

*Accessor* of `property-result` · `(object)`

Observation from the original failing trial.

<a name="property-result-failure-phase"></a>
### property-result-failure-phase

*Accessor* of `property-result` · `(object)`

:GENERATION when the run stopped in generation infrastructure rather
than on a target observation, else NIL.

<a name="property-result-generation-report"></a>
### property-result-generation-report

*Accessor* of `property-result` · `(object)`

Bounded-filter generation report captured by the backend,
or :NOT-COLLECTED when the backend did not collect one.

<a name="property-result-options"></a>
### property-result-options

*Accessor* of `property-result` · `(object)`

Caller options captured before backend execution.

<a name="property-result-profile"></a>
### property-result-profile

*Accessor* of `property-result` · `(object)`

Effective profile the run resolved its trial count from.
TRIALS records only the trial the run stopped at, not the budget it was
allowed, and that budget cannot be recovered from it -- REPLAY-PROPERTY needs
this slot to reproduce a run faithfully when it is handed the result instead
of the bare seed.

<a name="property-result-property"></a>
### property-result-property

*Accessor* of `property-result` · `(object)`

Name of the property that was run.

<a name="property-result-provenance"></a>
### property-result-provenance

*Accessor* of `property-result` · `(object)`

Run environment captured before execution; unknown fields are explicit.

<a name="property-result-rejected"></a>
### property-result-rejected

*Accessor* of `property-result` · `(object)`

Generated trials refused before invoking a function target.

<a name="property-result-schema-metadata"></a>
### property-result-schema-metadata

*Accessor* of `property-result` · `(object)`

Definition metadata captured before the run, or NIL.

<a name="property-result-seed"></a>
### property-result-seed

*Accessor* of `property-result` · `(object)`

Random seed the run started from, for replay.

<a name="property-result-shrink-report"></a>
### property-result-shrink-report

*Accessor* of `property-result` · `(object)`

Candidate count, budget and termination captured by the backend.

<a name="property-result-shrunk-counterexample"></a>
### property-result-shrunk-counterexample

*Accessor* of `property-result` · `(object)`

Observed failing arguments accepted during shrinking.
The failure identity matches the original trial. This is not a proof of global
minimality; NIL means no observed reduction was accepted.

<a name="property-result-shrunk-evidence"></a>
### property-result-shrunk-evidence

*Accessor* of `property-result` · `(object)`

Observed accepted shrink, or NIL.

<a name="property-result-shrunk-outcome"></a>
### property-result-shrunk-outcome

*Accessor* of `property-result` · `(object)`

:USED, :NONE or :DIFFERENT-FAILURE on a failure, else NIL.

<a name="property-result-status"></a>
### property-result-status

*Accessor* of `property-result` · `(object)`

One of :PASSED, :FAILED, :ERROR, :SKIPPED or
:PENDING.

<a name="property-result-trials"></a>
### property-result-trials

*Accessor* of `property-result` · `(object)`

Number of trials actually executed.

<a name="property-source-form"></a>
### property-source-form

*Accessor* of `property` · `(object)`

The whole DEFPROPERTY form, kept verbatim.

<a name="property-source-location"></a>
### property-source-location

*Accessor* of `property` · `(object)`

Source location plist, or NIL.

<a name="property-tags"></a>
### property-tags

*Accessor* of `property` · `(object)`

Tag designators, indexed for reverse lookup.

<a name="property-targets"></a>
### property-targets

*Accessor* of `property` · `(object)`

Symbols this property is about, from :ABOUT.
Indexed for reverse lookup.

<a name="property-trials"></a>
### property-trials

*Accessor* of `property` · `(object)`

Per-profile trial counts, for example
(:SMOKE 10 :NORMAL 100) (specification §33).

<a name="spec-description"></a>
### spec-description

*Accessor* of `spec` · `(object)`

Human readable description, or NIL.

<a name="spec-generator-name"></a>
### spec-generator-name

*Accessor* of `spec` · `(object)`

Symbol naming a custom generator, defined with
DEFGENERATOR, that produces this spec's values; or NIL when the backend derives
one from the spec itself (specification §11).

```text
Attached to the top level node only, like NAME and SOURCE-LOCATION: a
(:GENERATOR NAME) clause belongs to the definition, not to each conjunct of it.
```

<a name="spec-metadata"></a>
### spec-metadata

*Accessor* of `spec` · `(object)`

Arbitrary plist for callers and future extensions.

<a name="spec-name"></a>
### spec-name

*Accessor* of `spec` · `(object)`

Package-qualified symbol this spec is registered under,
or NIL for an anonymous inline spec.

<a name="spec-source-form"></a>
### spec-source-form

*Accessor* of `spec` · `(object)`

Original DSL s-expression this spec was
normalized from.  Kept verbatim so introspection can show what the author
wrote rather than what the normalizer produced.

<a name="spec-source-location"></a>
### spec-source-location

*Accessor* of `spec` · `(object)`

Source location plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION, or NIL.

<a name="spec-violation-errors"></a>
### spec-violation-errors

*Accessor* of `spec-violation` · `(condition)`

Structured error list as produced by EXPLAIN-DATA.

<a name="spec-violation-path"></a>
### spec-violation-path

*Accessor* of `spec-violation` · `(condition)`

Path from the root value down to the failing part.

<a name="spec-violation-spec"></a>
### spec-violation-spec

*Accessor* of `spec-violation` · `(condition)`

Spec designator the value was checked against.

<a name="spec-violation-value"></a>
### spec-violation-value

*Accessor* of `spec-violation` · `(condition)`

Value that failed the check.

<a name="state-post-error-case"></a>
### state-post-error-case

*Accessor* of `state-post-error` · `(condition)`

Selected case name, or NIL for a case-less contract.

<a name="state-post-error-form"></a>
### state-post-error-form

*Accessor* of `state-post-error` · `(condition)`

The :state-post form that signalled.

<a name="state-post-error-function"></a>
### state-post-error-function

*Accessor* of `state-post-error` · `(condition)`

Name of the function whose contract was being checked.

<a name="state-post-error-index"></a>
### state-post-error-index

*Accessor* of `state-post-error` · `(condition)`

Zero-based position of the :state-post form that signalled.

<a name="state-post-error-original-condition"></a>
### state-post-error-original-condition

*Accessor* of `state-post-error` · `(condition)`

Condition the state-post form signalled, or NIL.
Kept as a condition object for inspection; the explanation carries its type and
report text so evidence survives a condition that cannot be printed again.

<a name="unknown-function-spec-name"></a>
### unknown-function-spec-name

*Accessor* of `unknown-function-spec` · `(condition)`

Symbol that has no registered function spec.

<a name="unknown-property-name"></a>
### unknown-property-name

*Accessor* of `unknown-property` · `(condition)`

Symbol that is not registered as a property.

<a name="unknown-spec-name"></a>
### unknown-spec-name

*Accessor* of `unknown-spec` · `(condition)`

Symbol that is not registered as a spec.

<a name="unsupported-stateful-operation-function"></a>
### unsupported-stateful-operation-function

*Accessor* of `unsupported-stateful-operation` · `(condition)`

Name of the state-observing function spec.

<a name="unsupported-stateful-operation-operation"></a>
### unsupported-stateful-operation-operation

*Accessor* of `unsupported-stateful-operation` · `(condition)`

The refused operation, such as :REPLAY.

<a name="unsupported-stateful-operation-reason"></a>
### unsupported-stateful-operation-reason

*Accessor* of `unsupported-stateful-operation` · `(condition)`

Machine-readable reason the operation is unsupported.


## Classes

<a name="custom-generator"></a>
### custom-generator

*Class*

A value generator that a spec names instead of describing.

```text
An entity of its own rather than a slot on the spec, so that one generator can
be shared by several specs and found by name the way a spec or a contract can.
```

<a name="function-check-result"></a>
### function-check-result

*Class* · extends property-result

Outcome of checking a function against its registered contract.

```text
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
records what was actually run.
```

<a name="function-spec"></a>
### function-spec

*Class*

A contract attached to an existing function by name.

```text
The function is never redefined, so an existing codebase adopts cl-spec one
function at a time (specification §3.2).
```

<a name="hash-table-registry"></a>
### hash-table-registry

*Class*

In-image registry backed by hash tables.  The default backend.

<a name="property"></a>
### property

*Class*

A registered, executable statement about program behaviour.

<a name="property-result"></a>
### property-result

*Class*

Structured outcome of running one property.

```text
A property run is never reported as a bare boolean: the seed, the trial count
and the shrunk counterexample are what make a failure actionable.
```

<a name="spec"></a>
### spec

*Class*

Base class of every Semantic IR node.


## Conditions

<a name="capture-error"></a>
### capture-error

*Condition* · extends cl-spec-error

Signalled (as captured evidence) when a :capture form signals.

```text
Capture runs before the target, so the target was not called for such a trial:
this is a contract-side error, not a target failure, and it is neither a
counterexample nor a precondition rejection.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION.
```

<a name="case-selection-error"></a>
### case-selection-error

*Condition* · extends cl-spec-error

Signalled (as captured evidence) when case selection is not unique.

```text
Selection is exclusive: exactly one case must match the admitted input.  Zero
matches, several matches and a guard that signalled are contract-side errors,
not target failures.  The target is not invoked for any of them, so none of them
is a target counterexample or a precondition rejection.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION.
```

<a name="cl-spec-error"></a>
### cl-spec-error

*Condition* · extends error

Root of every condition signalled by cl-spec.

<a name="generation-budget-exhausted"></a>
### generation-budget-exhausted

*Condition* · extends generator-unavailable

Signalled when a request-owned candidate budget is exhausted.

```text
A subclass of GENERATOR-UNAVAILABLE, so a caller that already treats "this
generation could not complete" as one family keeps working, while a caller that
must tell a static no-strategy refusal from dynamic budget depletion handles this
type first.  The report and the message state explicitly that exhausting a
finite budget is not a proof that the spec admits no values.
```

<a name="generator-unavailable"></a>
### generator-unavailable

*Condition* · extends cl-spec-error

Signalled when an IR node has no generation strategy on this backend.

<a name="invalid-backend-result"></a>
### invalid-backend-result

*Condition* · extends cl-spec-error

A backend violated the required trial count or evidence protocol.

<a name="invalid-counterexample-artifact"></a>
### invalid-counterexample-artifact

*Condition* · extends error

Malformed, unsupported or excessive persisted counterexample data.

<a name="invalid-function-spec-form"></a>
### invalid-function-spec-form

*Condition* · extends cl-spec-error

Signalled when a function spec claims something the checker cannot honour.

```text
Specification §17 requires that a contract the checker cannot honour is refused
rather than partially accepted: one whose unsupported half is silently dropped
would report a verified result for a claim nothing checked.

Raised from two places, which is why the report does not name a macro: from
DEFSPEC-FUNCTION at macroexpansion time for syntax the MVP does not support,
and from the FUNCTION-SPEC class for a contract built directly through the
public CLOS API in a state its own consumers could not read.
```

<a name="invalid-generated-arguments"></a>
### invalid-generated-arguments

*Condition* · extends cl-spec-error

Signalled before invoking a target when an argument-set draw is invalid.

<a name="invalid-generator-form"></a>
### invalid-generator-form

*Condition* · extends cl-spec-error

Signalled when DEFGENERATOR cannot honour the definition it was given.

```text
The rule §17 follows for contracts: a definition this version cannot use is
refused rather than registered with part of its meaning dropped.  A generator
whose parameters were silently ignored would look like a working generator and
produce values from a body called without the bindings its author wrote.
```

<a name="invalid-property-form"></a>
### invalid-property-form

*Condition* · extends cl-spec-error

Signalled when DEFPROPERTY cannot parse a declaration fragment.

<a name="invalid-spec-form"></a>
### invalid-spec-form

*Condition* · extends cl-spec-error

Signalled when NORMALIZE-SPEC-FORM cannot make sense of a form.

<a name="no-generator-backend"></a>
### no-generator-backend

*Condition* · extends cl-spec-error

Signalled when generation is requested while *GENERATOR-BACKEND* is NIL.

<a name="not-implemented"></a>
### not-implemented

*Condition* · extends cl-spec-error

Signalled by skeleton stubs that carry a settled signature but no body.

<a name="spec-violation"></a>
### spec-violation

*Condition* · extends cl-spec-error

Signalled when a value fails to satisfy a spec.

<a name="state-post-error"></a>
### state-post-error

*Condition* · extends cl-spec-error

Signalled (as captured evidence) when a :state-post form signals.

```text
The target was called for this trial, so this is a contract-side evaluation
error that still owns the selected case and retains the captured target
outcome.

This is the condition carried by the trial observation of such a trial; it is
not raised out of CHECK-FUNCTION.
```

<a name="unbound-target"></a>
### unbound-target

*Condition* · extends cl-spec-error, undefined-function

Signalled when a contract's function is not defined.

```text
Inherits from both roots on purpose.  §21 promises a caller can trap the
framework as a whole, and CL-SPEC-ERROR calls itself the root of every
condition cl-spec signals -- a plain UNDEFINED-FUNCTION escaped that handler,
so one unadopted function lost a whole batch of checks.  It is still an
UNDEFINED-FUNCTION, because that is what it is, and a caller who wrote the
standard handler keeps it.
```

<a name="unknown-function-spec"></a>
### unknown-function-spec

*Condition* · extends cl-spec-error

Signalled when CHECK-FUNCTION is given a name with no contract.

```text
Distinct from a contract that holds: an agent that reads "nothing is
registered" as "nothing is wrong" would treat an unspecified function as a
verified one.
```

<a name="unknown-property"></a>
### unknown-property

*Condition* · extends cl-spec-error

Signalled when a property designator resolves to nothing.

<a name="unknown-spec"></a>
### unknown-spec

*Condition* · extends cl-spec-error

Signalled when a spec designator resolves to nothing.

<a name="unsupported-seed"></a>
### unsupported-seed

*Condition* · extends cl-spec-error

Signalled when an integer seed cannot be honoured on this implementation.

<a name="unsupported-stateful-operation"></a>
### unsupported-stateful-operation

*Condition* · extends cl-spec-error

Signalled when a state-observing contract is asked to replay a past run.

```text
A :capture / :state-post contract observes state and never restores it, so
reapplying a saved run against an unrestored state is refused explicitly rather
than performed silently.  A new run with an integer seed is not this operation
and is allowed.
```


## Structures

<a name="counterexample-artifact"></a>
### counterexample-artifact

*Structure*

Immutable serialized evidence for one concrete counterexample.

<a name="trial-observation"></a>
### trial-observation

*Structure*

Evidence from one invocation, with snapshots of its conses and arrays. Arbitrary objects and external state are not
checkpointed. CONDITION retains the actual condition; CONDITION-REPORT is its
text at observation time.


## Variables

<a name="generator-backend"></a>
### *generator-backend*

*Variable*

The generator backend in effect, or NIL when none is installed.

```text
Loading the CL-SPEC/CHECK-IT system installs a CHECK-IT-BACKEND here.  Rebind
it to swap backends for a dynamic extent, for example in tests.

A rebinding does not cross a thread boundary.  §48 puts the time limit on the
execution host, so a host that runs checks off the calling thread has to carry
this value over itself -- PROGV, or an explicit argument.  Without that, a run
started on another thread reads the global value, and if a backend is installed
there it generates rather than reporting NO-GENERATOR-BACKEND.
```

<a name="registry"></a>
### *registry*

*Variable*

Registry the front-end functions in this package operate on by default.
Rebind it to isolate specs and properties, for example in tests.

```text
A rebinding does not cross a thread boundary.  §48 puts the time limit on the
execution host, so a host that runs checks off the calling thread has to carry
this value over itself -- PROGV, or the :REGISTRY argument every entry point
takes.  Without that, a run started on another thread resolves names in the
global registry: if the same name is registered in both, it checks a different
definition and reports a verdict for it, with nothing on the result to say so.
```

<a name="spec-primitives"></a>
### *spec-primitives*

*Variable*

Spec DSL head names the MVP normalizer accepts (specification §9, §52).

```text
Heads are matched by SYMBOL-NAME, not by symbol identity: a DSL form is written
in the user's own package, so RANGE in (RANGE 1 *) there is not EQ to the RANGE
interned here.  Anything not named in this list is either a reference to a
registered spec or an error.
```

