# Explicit pre-observation and post-run state constraints for Function Specs

Status: **design record; implemented on this branch.**
Date: **2026-09-17**.
Baseline: `3084d51` / origin/main `e92e4cd` (PR #30 merged).
Normative contract: the "Pre-observation and state constraints" addendum and
§17.3 of `docs/cl-spec-specification-v0.2-draft.md`.
Runnable tour: `docs/guides/state-observation-walkthrough.md` and
`examples/stateful-withdraw.lisp`.

## 1. Purpose

A Function Spec today can constrain the inputs (`:args`, `:pre`), the returned
values (`:returns`, `:post`, `:post-values`) and the expected error
(`:signals`). It cannot say what an operation did to state that it was allowed,
or required, to change. This design adds two clauses:

- `:capture` observes values *before* the target is called, in declaration
  order, so a later clause can compare against them.
- `:state-post` checks *after* the call that the observed state relates the way
  the contract requires to the inputs and the captured values.

This is state **observation**, not state restoration. The feature detects that a
declared observation changed and that a declared relation failed; it does not
freeze objects, deep-copy them, restore them, or prove that anything stayed
unchanged between two observations. "Equal before and after" is not a proof of
"never changed during".

The DSL target is the account withdrawal shape: a successful call must reduce
the balance by the amount, an insufficient-funds error must leave the balance
equal to the amount observed before the call, and a declared account identifier
must be unchanged in both outcomes.

## 2. Syntax

```lisp
(cl-spec:defspec-function withdraw!
  (:args (account account-spec)
         (amount positive-money))

  (:capture
    (balance-before (account-balance account))
    (id-before      (account-id account)))

  (:cases
    (:sufficient-funds
      (:when (<= amount balance-before))
      (:returns receipt-spec)
      (:state-post
        (= (account-balance account)
           (- balance-before amount))
        (eql (account-id account) id-before)))

    (:insufficient-funds
      (:when (> amount balance-before))
      (:signals (type insufficient-funds))
      (:state-post
        (= (account-balance account)
           balance-before)
        (eql (account-id account) id-before)))))
```

Grammar:

```text
CLAUSE    := (:args ...) | (:args-generator NAME) | (:pre FORM ...)
           | (:capture (NAME FORM) ...)
           | (:returns SPEC) | (:signals SPEC) | (:post FORM ...)
           | (:post-values (NAME ...) FORM ...)
           | (:state-post FORM ...) | (:cases CASE ...)
CASE      := (KEYWORD [DOCSTRING] (:when FORM) OUTCOME)
OUTCOME   := (:returns SPEC) [(:post ...) | (:post-values ...)] [(:state-post ...)]
           | (:signals SPEC) [(:state-post ...)]
```

`:capture` and `:state-post` are new clause heads. They were previously refused
as unknown clauses, so no existing contract changes meaning.

### 2.1 `:capture`

- At most one `:capture`, top-level only, omitted when unused.
- Takes one or more exact two-element `(NAME FORM)` bindings.
- `NAME` is a bindable symbol: non-constant, non-keyword, not a lambda-list
  keyword (its name does not start with `&`), and unique among the bindings.
- `NAME` must not collide with an argument variable, a supplied-p variable, an
  explicit `:post-values` name, or `RESULT` (the symbol the contract's own
  package resolves `RESULT` to).
- A `FORM` may refer to the arguments and to capture names declared *before*
  it, and must not refer to the return-value symbol `RESULT` or to a capture
  name declared *after* it. These are targeted refusals, not a free-variable
  analyzer: a symbol that is shadowed lexically inside `FORM` is still counted.
- No per-case `:capture`, no nested capture, no anonymous automatic capture.

Capture is not a target argument: it never changes the argument schema, the
generator, or the number, order or identity of the actual arguments passed to
the target.

### 2.2 `:state-post`

- One clause at one position, taking one or more ordinary Lisp forms.
- Case-less contract: top-level. Case-carrying contract: inside each case.
- A case-carrying contract may not also carry a top-level `:state-post`; there
  is no common state-post inheritance, override or composition in this version.
- Allowed on `:returns` cases and on `:signals` cases alike, and on case-less
  ordinary-return and expected-error contracts.
- Usable without `:capture` to check state only after the call.
- An empty clause `(:state-post)` is refused: the rule is judged by clause
  occurrence, so an empty written clause is still a clause.

`:state-post` is a new, independent clause. It does not relax the existing
`:signals` / `:post` / `:post-values` exclusivity, and it does not change the
multiple-value rules of `:returns` / `:post` / `:post-values`.

### 2.3 Variable scope

| Position | Sees |
|---|---|
| common `:pre` | arguments (unchanged; runs before capture) |
| `:capture` form *i* | arguments and capture names 0..i-1 |
| case `:when` | arguments and all completed capture values |
| `:post` / `:post-values` | return bindings, arguments and capture values |
| `:state-post` | arguments and capture values |

The first version binds no implicit `RESULT`, condition, or raw outcome inside
`:state-post`. A relation between the return value and post-state is written in
the existing `:post` (or checked separately), not in `:state-post`.

Optional, keyword and rest arguments and suppliedness keep the existing
`call-layout` meaning, and the target's default forms are never evaluated for
capture or for case selection.

Compilation, name resolution and macroexpansion reuse the existing mechanism.
No runtime `eval`, dynamic interning, or string substitution creates a binding,
and no general free-variable analyzer is added.

## 3. Evaluation and value semantics

One ordinary trial evaluates in this order:

1. Argument-schema validation and binding.
2. Common `:pre`. A refusal returns `:rejected`; capture, guards, the target
   and state-post all run zero times.
3. `:capture`, once per trial, each form once, in declaration order.
4. Case selection (exclusive) when the contract declares `:cases`.
5. The target, exactly once, producing one raw outcome.
6. The existing `:returns` / `:signals` / `:post` / `:post-values`
   classification of that outcome.
7. Only when step 6 was `:passed`, the applicable `:state-post`.
8. Final classification and evidence for the trial.

A case-less contract omits step 4 and uses the top-level outcome and
state-post.

Capture semantics:

- Forms run in declaration order; a later form sees earlier capture values,
  i.e. `let*` visibility. Each compiled binding is an ordinary lambda over the
  arguments plus the previously computed capture values, so nothing is
  interpreted at check time.
- Exactly one primary value per form is bound. Multiple values are not
  collected implicitly; an author who needs them collects them into a list.
- A captured `NIL` is a value, distinct from "not yet evaluated".
- The captured values belong to one trial. They are never carried into the next
  trial or another run.
- Capture is not re-evaluated to build a report or explanation.

`:state-post` semantics:

- Forms run in declaration order, each once. Non-`NIL` holds, `NIL` does not.
- The first non-holding form or the first form that signals stops the
  evaluation. Later forms are not run merely to enrich the diagnosis.
- A successful outcome whose state-post forms all hold makes the trial
  `:passed`.
- Input schema, capture and case guards are not re-evaluated after the call, so
  a target that changed its inputs as intended is not re-rejected by the
  pre-call schema.

### 3.1 No automatic deep copy

A capture variable holds the value the form returned. It is not a copy of the
object, and `(:capture (before account))` does not preserve the account's
pre-call contents. An author who wants a pre-call representation must read a
value out (a number, an identifier) or explicitly build an independent
representation, for example `copy-seq` over the part that matters.

Independence is the author's contract. cl-spec does not validate aliasing,
ownership or independence, and this version adds no snapshot machinery, no
implicit deep copy of capture values, no graph walker for input sharing, no
before/after comparison of a validator, and no detector that guesses whether a
value is independent. The existing evidence snapshot used to freeze arguments
and outcomes for the trial record is a separate responsibility and is
unchanged; its coverage is not extended into a general object-freezing
guarantee.

## 4. Failure classification and priority

| Where it happened | status / reason | failure phase | target calls |
|---|---|---|---|
| capture form signals | `:error` / `:contract-error` | `:capture` | 0 |
| case selection fails | existing classification | `:case-selection` | 0 |
| existing outcome contract fails | existing classification | existing (NIL) | 1 |
| state-post form returns `NIL` | `:failed` / `:state-postcondition` | `:state-post` | 1 |
| state-post form signals | `:error` / `:contract-error` | `:state-post` | 1 |

A condition signalled by capture or state-post is never accepted as the
target's expected error. A `SPEC-VIOLATION` there is a contract-evaluation
error at that position, not a common-`:pre` rejection.

### 4.1 Normal return and expected error

A normal return that satisfies the outcome contract, and an error that
satisfies a `:signals` requirement, both proceed to state-post. This is how
"the right error was signalled but the balance was still changed" is detected.

### 4.2 When the outcome contract fails first

A return-spec violation, postcondition violation, missing condition, condition
mismatch, unexpected target error, or an evaluator-side error keeps the existing
failure as the primary result and does not run state-post. The state evidence
records `:not-evaluated` with the reason (`:outcome-failed`,
`:capture-failed`, `:case-selection-failed`). An unrun check is never reported
as `:passed`.

This is a deliberate first-version limit: it is not a `finally` contract that
always runs state-post after every abnormal exit, it does not list outcome and
state failures together, and a failure found first is not overwritten by a
later diagnostic error. It covers ordinary returns and errors caught by the
existing `invoke-target-once`; it does not promise that state is inspected after
`throw`, an external abort, process exit, timeout or crash.

### 4.3 Phase and target invocation are not the same fact

A non-`NIL` phase does not mean the target did not run:

- `:capture` is a pre-target phase; `:state-post` is a post-target phase.
- A `:state-post` failure keeps the case in `:called`, keeps the raw outcome,
  and is not classified as `:not-a-target-failure`.
- The phase is recorded where the framework performed the step, never inferred
  from the condition's class, and selecting a case is not by itself evidence
  that the target ran.

### 4.4 Expected error and state violation are separate

When an expected error satisfies its spec but state-post does not hold, the
final result is `:failed` / `:state-postcondition`, and the raw outcome still
holds the error the target actually signalled. The classification-side
condition field and the target-outcome condition are not confused. An expected
error that was signalled does not by itself make the trial `:passed`.

When state-post itself signals, both the target outcome and the verifier-side
condition are retained.

## 5. Evidence, conditions and failure identity

### 5.1 Conditions

- `capture-error` (`cl-spec-error`): `function`, `binding` (name), `index`
  (zero-based binding position), `captured` (the ordered `(NAME . VALUE)`
  alist completed before the failure), and `original-condition`. Accessors and
  `capture-error-data` (structured explanation) are public.
- `state-post-error` (`cl-spec-error`): `function`, `case` (name or `NIL`),
  `index` (zero-based form position), `form` (the source form), and
  `original-condition`. Accessors and `state-post-error-data` are public.
- `unsupported-stateful-operation` (`cl-spec-error`): `operation` and
  `function`. Signalled before generation, capture or the target whenever a past
  result stands in for a run: `check-function` with a result as `:seed`, and
  `run-property` / `replay-property` with a result as their seed, so the
  function-check adapter cannot be replayed through any of those entry points.

The `NIL` state-post failure is a plain `:failed` outcome and carries no
condition object.

### 5.2 Failure identity

```text
capture error        (:capture BINDING-INDEX :contract-error CONDITION-TYPE)
case-less state NIL  (:state-postcondition FORM-INDEX)
case state NIL       (:case CASE-NAME :state-postcondition FORM-INDEX)
case-less state err  (:state-post FORM-INDEX :contract-error CONDITION-TYPE)
case state err       (:case CASE-NAME :state-post FORM-INDEX :contract-error CONDITION-TYPE)
```

A state-post violation is a failure kind separate from `:return-spec` and
`:postcondition`. The form position is part of the identity, and the case name
too when the contract has cases. Concrete values and variable error messages
are never part of an identity. The existing `:case` wrapper comparison is
reused; the artifact validator is not relaxed to accept arbitrary signatures.
Capture errors happen before selection, so they carry no case name.

### 5.3 Trial state evidence

A trial produced by a contract that declares `:capture` or `:state-post` carries
a state-evidence plist on its observation (new
`trial-observation-state`, projected into `result-data` under `:state`):

```text
(:capture (:status :not-evaluated | :completed | :error
           :declared (NAME ...)
           :values ((NAME . VALUE) ...)          ; only completed bindings
           :error (:binding NAME :index I :condition-type T))
 :state-post (:status :not-evaluated | :passed | :violation | :error
             :reason REASON                        ; when :not-evaluated
             :case NAME | NIL
             :index I :form FORM                   ; when violation or error
             :condition-type T))                   ; when error
```

- `:capture` is present only when the contract declares `:capture`; its
  `:values` is an ordered `((NAME . VALUE) ...)` alist over the bindings that
  completed, so a caller reads a value with `assoc` rather than reconstructing
  the pairing from `:declared`. A capture that failed halfway never shows later
  bindings as obtained, and a captured `NIL` is a `(NAME . NIL)` entry, not an
  absence.
- `:state-post` is present when the contract declares a clause: the selected
  case's, or, before a case is selected, the top-level clause or any case's. When
  no case was selected its `:case` is `NIL` and its `:reason` is
  `:capture-failed` or `:case-selection-failed`, so "no state-post declared" and
  "declared but stopped before selection" stay distinct.
- `:reason` for `:not-evaluated` is one of `:precondition-rejected`,
  `:capture-failed`, `:case-selection-failed`, `:outcome-failed`.
- A contract that declares neither clause has no state evidence at all
  (`trial-observation-state` is `NIL`, and `result-data` omits `:state`), so a
  featureless run's evidence is unchanged.

Values are projected through the existing evidence snapshot: a cons or array is
reported as its copy, and an atom whose representation is self-contained
(number, character, symbol) as itself. An object the snapshot returns by
identity -- a CLOS instance, structure, hash table, function and the like -- is
reported as `(:unavailable :reason :opaque-value :type TYPE)`, an explicit
unprojectable placeholder, because the snapshot does not preserve its contents
and a live reference would read like frozen evidence. The evaluation path still
passes the original value to later capture forms, guards and predicates; this is
a report projection, not a deep copy or a new snapshot. A projection failure
never discards the target outcome or an already-determined failure.

No automatic expected/actual extraction, no generic diagnostic DSL and no
all-field diff is added. No giant log of every successful trial object is kept;
successful-run counts remain visible through the existing trial and case
counters.

### 5.4 Case report

The per-case report gains one counter:

```text
(:selection :exclusive :unit :normal-trials
 :declared-cases (NAME ...)
 :cases ((:name NAME :documentation S
          :called N :passed N :failed N :error N) ...)
 :case-selection-errors N
 :capture-errors N
 :never-called (NAME ...))
```

- A capture failure increments no case's `:called` and is not a
  `:case-selection-error`; it increments `:capture-errors`.
- A state-post violation increments the calling case's `:called` and `:failed`;
  a state-post evaluation error increments its `:called` and `:error`.
- A trial is counted once, from its final classification, at the existing
  counting hook, never once at outcome time and again at state-post time.
- Precondition refusals contribute nothing.
- Because capture failures (and case-selection errors) call no target,
  `trials - rejected` is not claimed to equal target calls or case-selection
  arrivals; the meanings of generated, rejected and target-called counts are
  unchanged.

## 6. Data model, introspection and digest

Function Spec slots:

- `capture-bindings`: ordered `(NAME FORM)` pairs, or `NIL`.
- `capture-functions`: the aligned compiled functions, or `NIL`.
- `state-postconditions`, `state-postcondition-function`: the case-less clause.

Function Case slots:

- `state-postconditions`, `state-postcondition-function`.

The declaration is structured, not hidden in metadata. Per-trial capture values
live in the trial's state evidence, never in a slot of the registered
definition. `function-spec-data` exposes the declaration without running any
capture form, guard, state-post or target and without projecting a closure:

- contract: `:capture ((:name NAME :form FORM) ...)` and `:state-post (FORM ...)`
  only when declared;
- case: `:state-post (FORM ...)` only when declared.

`definition-description` includes capture names, order and source, state-post
forms, and the case association, so changing any of them changes the digest.
A definition that uses neither clause keeps its existing digest bytes,
failure signatures, multi-value rules, case rules, expected-error rules and
multi-value/post semantics. Capture values obtained at runtime never enter a
declaration digest. A programmatic definition without source follows the
existing digest-completeness policy; the digest does not freeze external
readers or database state.

Validation is enforced for the DSL, for programmatic construction, for
reinitialization and for registry registration alike:

- capture names are unique, bindable, and collide with no argument, supplied-p
  variable, post-value name or `RESULT`;
- capture forms and capture functions are present together and aligned in
  count and order, and a capture-name list change requires new forms and
  functions;
- state-post forms and the compiled state-post function are present together
  and change together at both the contract level and per case;
- a refused reinitialization rolls back the participating slots and keeps the
  previous definition.

No proof that arbitrary source and its closure are semantically equivalent is
attempted.

## 7. Shrinking, replay and artifacts

The feature observes state; it never restores it. Observing a value is not the
same as being able to re-run from the same state.

### 7.1 Ordinary trials

Existing `check-function` runs are allowed. An author who needs independent
trials builds a fresh target object or initial state through the existing
generator machinery for each trial. cl-spec neither detects, verifies nor
restores that. Reusing one mutable object means the next trial starts from the
updated state, and that is not described as an independent same-condition
trial. Capture re-reads per trial; re-reading is not a reset.

### 7.2 Automatic shrinking

Automatic shrinking is disabled for a contract that declares `:capture` or
`:state-post`, even for a pure use. The policy is not inferred from generated
types or from a previous mutation-detection verdict, and a custom shrinker does
not bypass it.

- The target is not called again with the same mutable object after a failure.
- The already-captured failure evidence is retained.
- The shrink report carries the explicit `:termination
  :state-restoration-unavailable`.
- The reason is that no contract for rebuilding the same initial state exists,
  not that the target was never called. A failure that never reached the
  target (a capture or case-selection error) keeps the existing
  `:not-a-target-failure` reason, which is accurate for it.
- Capability reporting matches: such a contract reports `:shrinking :none`
  rather than claiming an available shrinker, and a failing result's selected
  shrink report says `:state-restoration-unavailable`.

Featureless Function Specs and Properties keep their existing shrinking,
including custom shrinkers. Generator construction for ordinary specs is
unchanged.

### 7.3 Replay

Automatic replay of a past result is unsupported in this version for a
state-observing contract:

- `check-function` with an earlier result as `:seed` is refused before the
  target is called, with `unsupported-stateful-operation` (`:operation
  :replay`).
- `run-property` with a `property-result` as `:seed`, and `replay-property`
  with one, are refused the same way before the integer seed is extracted, so the
  function-check adapter cannot be replayed through those entry points either.
  Because `replay-property` would otherwise convert the result to an integer
  seed and lose the fact that it is a replay, its check runs on the result while
  it is still a result. An integer seed is not a replay and is not refused.
- `recheck-counterexample` refuses a state-observing resolved definition with
  its existing `:unsupported` outcome and reason
  `:stateful-contract-unsupported`, before the target is called.

A *new* run with an integer seed is allowed. An integer seed reproduces a
random stream; it does not restore external state or a mutable object's initial
contents, and the new run's initial state is the author's responsibility.

No fixture, reset hook or state-policy option is added.

### 7.4 Counterexample artifacts

Persisting a state-observing contract's result to artifact v1, and direct
recheck from such an artifact, are unsupported:

- `make-counterexample-artifact` refuses with its existing
  `invalid-counterexample-artifact` condition, reason
  `:stateful-contract-unsupported`.
- Whether the contract is state-observing is read from the definition metadata
  captured in the result before execution, not re-resolved from the current
  registry, so registering a different definition under the same name does not
  change the answer.
- `result-data` still provides diagnostics. Capturing values is not a
  reproducible artifact.
- Existing artifacts, their loading, and rechecks of featureless contracts are
  unchanged.

No generic object codec or state-restoration adapter is added. This is a
first-version scope limit, not a claim that state constraints are inherently
unshrinkable or unreplayable; an explicit state-construction/restoration
protocol can be added later.

## 8. Definition integrity, digest and unsupported paths

- `install`/`refresh` of runtime instrumentation refuse a state-observing
  contract before changing an fdefinition or an existing wrapper, with the
  existing unsupported-target condition and reason
  `:state-constraints-unsupported`. `definition-instrumentation-capability`
  reports `:unavailable` for it, so capability and refusal agree; no partial
  argument-only wrapper is built. Case-less, featureless instrumentation is
  unchanged.
- Backend result validation, observation, function-check-result and result-data
  carry the new observation, phase, signature and state failure consistently.
  The shared evaluator is used; the check-it side does not reimplement case or
  state-post judgement.
- A backend that does not observe state does not fabricate a pass or a known
  zero. Input generation budgets, rejection counts and termination reasons are
  unchanged; capture and state-post errors never become generation rejections
  or exhaustion.

## 9. Non-goals

This version does not add: automatic deep copy or snapshot of arbitrary
objects; CLOS/hash-table traversal; graph walkers for input sharing;
mutation detection or rollback; before/after validator comparison; state
restoration, fixtures or reset protocols; state-machine PBT; concurrency,
atomicity or crash-atomicity guarantees; guarantees that no external I/O
occurred; per-case `:capture`; common state-post inheritance; an implicit
`RESULT`/condition/outcome binding inside state-post; shrinking, replay or
artifact support for state-observing contracts; a generic diagnostic DSL;
all-field diffs; a solver; or new MCP tools.

Capture forms, case guards, post predicates, state-post predicates and readers
are contractually non-destructive: they must not modify the inputs or anything
reachable from them. The target's intended state change is allowed. cl-spec
neither detects nor restores a violation, and this feature does not solve
reproduction or reset of stateful targets.
