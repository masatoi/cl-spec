# Named per-condition Function Spec cases

Status: **design record; implemented on this branch.**
Date: **2026-09-16**.
Baseline: `d8b7cca` (PR #29 merged).
Normative contract: the "Named case selection for function specs" addendum and
§17.2 of `docs/cl-spec-specification-v0.2-draft.md`.
Runnable tour: `docs/guides/function-spec-cases-walkthrough.md` and
`examples/function-spec-cases.lisp`.

## 1. Purpose

One function often has, inside the input region its common `:pre` admits, more
than one required behaviour: a normal result when some input condition holds and
a specific expected error when another does. Today that means either two
contracts on one function (only the last registration is reachable by name) or a
single contract that checks only one behaviour.

This design adds one top-level `:cases` clause to `DEFSPEC-FUNCTION`. Each case
is a named input condition (`:when`) plus exactly one required outcome
(`:returns` or `:signals`). The common `:pre` still bounds the region; the case
conditions select the required behaviour inside it. A contract without `:cases`
keeps its syntax, meaning, digests and failure identities unchanged.

This is not `tagged-by`. `tagged-by` selects a *data spec* from a value's tag.
A case selects the *required outcome* of a function invocation from the input
bindings. They share no semantics; only ordinary helper machinery is reused.

## 2. Syntax

```lisp
(cl-spec:defspec-function remaining-balance
  "For an admitted amount, require a result or the named error."
  (:args (balance (range integer 0 1000))
         (amount (range integer 1 1000)))
  (:cases
    (:sufficient-funds
      "Return the balance that remains."
      (:when (<= amount balance))
      (:returns (range integer 0 *))
      (:post (= result (- balance amount))))
    (:insufficient-funds
      "Signal the named error."
      (:when (> amount balance))
      (:signals (type insufficient-funds)))))
```

Grammar:

```text
CASE      := (KEYWORD [DOCSTRING] (:when FORM) OUTCOME)
OUTCOME   := (:returns SPEC) [(:post FORM ...) | (:post-values (NAME ...) FORM ...)]
           | (:signals SPEC)
```

Rules, all refused before registration with `INVALID-FUNCTION-SPEC-FORM`:

- `:cases` appears at most once and contains at least one case.
- A case name is a keyword, unique within the contract.
- A case has one optional docstring directly after its name.
- A case has exactly one `:when` clause with exactly one form.
- A case has exactly one of `:returns` or `:signals`.
- A `:returns` case may add `:post` or `:post-values` with the existing
  exclusivity, arity and variable rules.
- A `:signals` case may not carry `:post` or `:post-values` in this version.
- No other clause is accepted inside a case. Unknown, duplicated and malformed
  clauses are refused at macroexpansion time.
- `:cases` cannot be combined with a top-level `:returns`, `:signals`, `:post` or
  `:post-values`. There is no inheritance or overriding of a common outcome.
- `:args`, `:args-generator` and `:pre` stay top-level and are shared by every
  case.
- A case may not declare its own `:args`, `:args-generator`, `:pre`, nested
  `:cases`, `:else` or priority. Ordering is declaration order only.
- `(:when t)` and `(:when nil)` are ordinary forms. `T` is **not** an `else`
  marker; there is no implicit fallback case.

The compiled guard, the compiled case postcondition and the normalized case
outcome are stored on the contract. A contract built through the class rather
than the macro is held to the same invariants (`validate-definition`), including
the rule that a compiled guard and its source form are present together.

## 3. Case selection

Selection is **exclusive**: exactly one case must match, not first-match.

One ordinary trial is processed in this order:

1. Existing argument-schema validation and binding (`bind-call-arguments`).
2. The common `:pre` predicate. A refusal returns `:rejected` exactly as today;
   no case condition and no target call happen.
3. Every case's `:when` is evaluated in declaration order, once per trial. The
   evaluation does not stop at the first true guard: every guard runs so that
   duplicates are observed.
4. If all guards evaluated normally, the match count decides:
   one match selects that case; zero is `:no-matching-case`; two or more is
   `:ambiguous-case`.
5. A guard that signals an error stops selection at that point with
   `:case-guard-error`. The condition is captured, and the remaining guards are
   not evaluated.
6. The target is invoked exactly once, only when a unique case was selected.
7. Only the selected case's outcome contract classifies the invocation.
8. The case name and the resulting evidence are recorded for the trial.

Additional rules:

- Guards see the same bindings `:pre` sees. Optional, keyword, rest and
  supplied-p variables keep their existing `call-layout` meaning; a case does not
  change how an omitted argument is handled, and the target's default forms are
  never evaluated for selection.
- Guards may not reference `RESULT` or the return-value bindings.
- Guards are not re-evaluated for diagnostics, after the call, or to look for a
  case that would have matched the value the target produced.
- `SPEC-VIOLATION` signalled by a guard is a `:case-guard-error`, not a
  precondition refusal. The existing rule that `:pre` treats `SPEC-VIOLATION` as
  a refusal is a property of `:pre` only.
- Case selection errors are contract-side errors, not target failures.

Data fixed for a case-selection error:

| Field | Value |
|---|---|
| status | `:error` |
| failure reason | `:contract-error` |
| failure phase | `:case-selection` |
| condition | a `CASE-SELECTION-ERROR` carrying the details below |
| signature | `(:case-selection KIND)` or `(:case-selection :case-guard-error NAME)` |
| explanation | `(:kind :case-selection-error :case-error KIND :function NAME :cases (...) :case NAME :condition-type T :condition-report S)` |

`KIND` is `:no-matching-case`, `:ambiguous-case` or `:case-guard-error`.
`:cases` lists the matched case names for `:ambiguous-case` (NIL otherwise).
`:case` and `:condition-type`/`:condition-report` describe the guard that
signalled for `:case-guard-error` (NIL otherwise). `CASE-SELECTION-ERROR`
exposes the same values through `case-selection-error-function`,
`case-selection-error-kind`, `case-selection-error-cases`,
`case-selection-error-case` and `case-selection-error-original-condition`.

A selection error never invokes the target, so it is neither a target
counterexample nor a precondition rejection. It is excluded from shrinking, from
per-case call counts and from generation accounting.

The phase is **recorded where the framework knows it**, not inferred later from
the condition's class. The classifier marks a trial `:case-selection` when
selection itself failed; every target observation carries NIL. A target that
signals the public `CASE-SELECTION-ERROR` condition under any contract is
therefore an ordinary target observation: it may be shrunk, and its evidence may
be persisted. Inferring the phase from the condition's class would have made a
target's own condition a selection error, which it is not.

## 4. Reuse of the outcome evaluator

After a case is selected, classification is the existing one, applied to the
selected case's outcome contract:

- primary `:returns` via `EXPLAIN-DATA`, with `:missing-condition`,
  `:condition-spec` and `:condition` for `:signals` cases;
- fixed multiple values and `:post-values`;
- `:post` failure identity from the existing post-form index protocol;
- `PROGRAM-ERROR` and `UNDEFINED-FUNCTION` stay reserved failures;
- warnings and non-error signals keep their ordinary behaviour.

No check is relaxed to make a case pass, and the target is invoked once per
trial. The implementation extracts the existing per-trial classification into
one internal function used by both the case-less and the case-carrying paths;
the classification rules exist in one place, not two.

A classification error raised **after** selection — a case postcondition or an
outcome-spec predicate that signals — is still a `:contract-error`, and it keeps
everything the trial produced: the selected case is recorded in the evidence, the
captured target outcome is kept, the failure identity is case-wrapped
(`(:case NAME :contract-error TYPE)`), and the run's case report counts the call
as that case's `:error` (so `:never-called` never names a case whose target
actually ran). Before selection — a binding or common-`:pre` error — there is no
case to name, and the case-less identity is unchanged.

The selected case and the compiled outcome are carried in a per-trial context.
The registered contract is never rewritten, and no per-trial outcome is
installed on a shared definition.

## 5. Failure identity, shrinking, replay and artifacts

- The selected case name is recorded in the trial evidence
  (`trial-observation-case`).
- A failure of a selected case wraps the existing signature:
  `(:case NAME . EXISTING-SIGNATURE)`. `FAILURE-IDENTITIES-MATCH-P` compares the
  case names first and then applies the existing comparison to the inner
  signature, so a return-value violation in one case never shrinks into the same
  violation in another case, while the existing clause-crossing and post-form
  rules are preserved inside a case.
- A case-less contract's signature is unchanged, byte for byte.
- Shrinking candidates still pass the argument schema, the common `:pre` and case
  selection. A candidate that selects no case, several cases, or whose guard
  errors is not adopted.
- Case-selection errors are not shrunk in this version.
- Replay (`check-function` with an earlier result as `:seed`,
  `replay-property`) reuses the recorded options and budget and re-selects cases
  from the replayed inputs; the case name is part of the failure identity.
- Persistable target failures are stored, restored and directly rechecked with
  the case name preserved. `valid-signature-p` explicitly understands the
  `:case` wrapper and requires the inner shape to be one of the existing shapes;
  it is not relaxed to accept arbitrary signatures, and evidence without a case
  name never matches a case-carrying failure.
- A case-selection error on a case-carrying contract is a `:contract-error`
  observation, so `make-counterexample-artifact` refuses to persist it as a
  target counterexample (`:invalid-record` from the existing validator) and
  `recheck-counterexample` reports `:contract-error` rather than
  `:same-failure`.

## 6. Per-case report

`CHECK-FUNCTION` results carry a machine-readable case report, exposed by the
public reader `FUNCTION-CHECK-RESULT-CASE-REPORT` and included in `result-data`
as `:case-report`.

```text
(:selection :exclusive
 :unit :normal-trials
 :declared-cases (NAME ...)                 ; declaration order
 :cases ((:name NAME :documentation S
          :called N :passed N :failed N :error N) ...)
 :case-selection-errors N
 :never-called (NAME ...))
```

- Counters are aggregated from the observations of ordinary generation trials
  only. Shrinking invocations do not contribute.
- A trial whose common `:pre` refused the input contributes to nothing: not to
  any case's `:called`, not to `:case-selection-errors`.
- `:called` counts trials in which the target was actually invoked for that case.
  `:passed`, `:failed` and `:error` sum to `:called`. A successful expected-error
  trial counts as `:passed`, and a contract error raised while classifying a
  selected case counts as that case's `:error` because the target was called.
- `:case-selection-errors` counts trials that stopped in case selection; those
  trials increase no case's `:called`.
- `:never-called` lists the declared cases with `:called` equal to zero. It is
  not a proof that a case is unreachable, and one reached trial is not evidence
  of exhaustive coverage of that case.
- The report is computed from the run's own counters. Nothing is re-executed to
  build it, and no condition or target is called for it.
- The counters belong to one run. They are never stored on the registered
  definition or in a global table; the result receives a snapshot.
- A result that did not go through a function-check run reports
  `:not-collected` rather than measured zeros, and so does a run whose backend
  reported no observation at all. Reaching the counting hook is what makes a
  report measured; a backend that never calls it leaves counters nothing filled,
  and reporting them as zeros would claim a measurement that never happened.

`PROPERTY-RESULT-TRIALS` and `PROPERTY-RESULT-REJECTED` keep their meaning.
Because a case-selection error calls no target, `trials - rejected` is not always
the number of target calls; the docstrings of `check-function` and
`function-check-result-rejected` are updated to say so, and the case report is
the place to read the call counts.

## 7. Data model, introspection and digest

- A case is a structured object with name, optional documentation, the guard
  source form and compiled predicate, the normalized outcome spec, the
  postcondition forms and compiled predicate, and the post-value variable list.
- Cases are stored on the single `FUNCTION-SPEC` registered under the function
  name. A case is not registered as a separate public function spec.
- `FUNCTION-SPEC-DATA` gains ordered `:cases` and `:case-selection :exclusive`.
  Each case projects its name, documentation, guard form, outcome kind, the
  normalized outcome spec as the existing `spec->data` projection, and its post
  forms and post-value names. Executable closures are never projected, and
  producing the data runs no target and no guard.
- `definition-description` reports the cases as child definitions, so the digest
  covers case names, their order, guard source, outcome spec, post forms and
  post-value bindings, and the registered spec/generator dependencies they name.
  Changing a case changes the digest. A case-less contract's digest bytes are
  unchanged.
- Programmatic construction, reinitialization and registry registration enforce
  the same invariants as the DSL: guard source and compiled predicate together,
  unique keyword names, at most one outcome, and refusal of case-level
  postconditions on `:signals`. A refused reinitialization rolls back the
  participating slots (existing `call-with-definition-rollback`).
- A case reinitialization must update a clause's forms and its compiled
  predicate together, exactly as the contract-level `:pre` and `:post` do:
  `:when-forms` with `:when-function`, and `:postconditions` with
  `:postcondition-function`. A `:post-value-variables` change additionally
  requires new post forms and a new compiled predicate, so the bindings cannot
  drift from the function that reads them.
- Inside a case, `:post` and `:post-values` are mutually exclusive, as they are
  at the contract level; `:post-values` additionally requires a fixed
  `(values ...)` return declaration and a post predicate. Clause order never
  decides which of two predicates survives.

## 8. Instrumentation

Runtime instrumentation of case-carrying contracts is unsupported in this
version. `definition-instrumentation-capability` reports `:unavailable`, and
install and refresh refuse before replacing the function with the explicit
reason `:named-cases-unsupported`. An existing wrapper is left untouched, and no
case-ignoring wrapper that checks only arguments is built. Case-less
instrumentation is unchanged.

## 9. Compatibility

- A `defspec-function` without `:cases` is unaffected: same accepted clauses,
  same meaning, same failure signatures, same digest, same artifacts.
- `:cases` is new syntax. It was previously refused as an unknown clause, so no
  existing contract changes meaning silently.
- `result-data` gains `:case-report`; existing keys keep their meaning.
- `property-result-explanation` additionally returns the explanation of a
  `:contract-error` observation when one is recorded, which is how the
  case-selection explanation becomes readable. Existing `:contract-error`
  observations carry no explanation, so their projection does not change.
- `FAILURE-IDENTITIES-MATCH-P` accepts the new `:case` wrapper and keeps its
  existing rules inside it.
- Artifacts written before this change keep loading; they never carry a case
  name, so they match only case-less failures of the unchanged digest.

## 10. Non-goals

This version does not add: per-case `:args`/`:args-generator`/`:pre`; nested
cases; `:else` or priority; per-case generators, retry loops or an even
scheduler; a `check-function` case-selection option; automatic case-reachability
or coverage proof; a solver for guard exclusivity or exhaustiveness; case-level
minimum trial counts or coverage-driven failure; shrinking of case-selection
errors; `:capture`/`old`; postconditions over state after an expected error;
fixtures or reset protocols; state-machine PBT; concurrency; CLOS method
contract composition; mutation detection, deep copy or rollback; a generic
constraint/diagnostic DSL; new MCP tools.

Case guards, like validation predicates and readers, must not modify their input
or anything reachable from it. cl-spec neither detects nor restores a violation.
This does not forbid a target's intended state change, but this feature does not
solve reproduction or reset of stateful targets. No timeout or purity check is
introduced for a single guard call. Reproducibility assumes that guards and
generators are deterministic in the same effective environment.

## 11. Review follow-ups (2026-09-16)

The first PR revision was reviewed, and two findings plus three consistency gaps
found alongside them are fixed here:

- A classification error raised after a case was selected used to lose the case:
  the trial evidence named no case, the signature was unwrapped, and the report
  counted nothing. The selected case is now carried through that path, so its
  name, the captured target outcome, the case-wrapped `:contract-error` identity
  and the per-case call count all survive. (review P1)
- The failure phase used to be inferred from the condition's class, so a target
  that signalled the public `CASE-SELECTION-ERROR` was misread as a selection
  error, its shrinking was suppressed and its artifact refused. The classifier
  now records the phase, and every target observation is NIL. (review P2)
- `:post` and `:post-values` were mutually exclusive at the contract level but
  not inside a case, so clause order silently decided which predicate survived.
- A `FUNCTION-CASE` reinitialization could change a compiled predicate without
  its source form (or the reverse), which the contract-level clauses already
  refuse.
- `check-function` reported measured-looking zeros when the backend never
  reported an observation; that now answers `:not-collected`.

No new feature, mutation detection or general state tracking was added for these.
