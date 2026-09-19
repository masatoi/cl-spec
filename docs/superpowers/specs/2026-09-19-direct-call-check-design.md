# Direct concrete invocation checking for Function Specs

Status: **design record; implemented on this branch.**
Date: **2026-09-19**.
Baseline: `main` at `03785e1` (PR #32 merged).
Normative contract: the "Direct concrete invocation" addendum in
`docs/cl-spec-specification-v0.2-draft.md`.
Runnable tour: the `check-call` example in `README.md`.

## 1. Purpose

A registered Function Spec is today only checkable through `check-function`,
which generates inputs. Before a generator exists -- and in ordinary REPL or
fixture-driven Common Lisp work -- a caller already holds the concrete objects
and wants to ask whether *this* invocation satisfies the contract. The new API
checks one caller-supplied raw argument list against a registered Function Spec
with no generator, property trial loop, shrinking or replay.

The intended progression is:

```text
REPL fixture -> one concrete contract check -> generated checking when needed
```

The one-shot classification must be the same classification generated checking
performs for the same invocation. That is achieved by putting the new API on top
of the existing single-trial path rather than beside it.

## 2. Public API

```lisp
(cl-spec:check-call function-designator arguments &key registry)
```

* `function-designator` is a symbol or a `function-spec` object; resolution uses
  `resolve-function-spec`, so an unregistered name signals
  `unknown-function-spec`.
* `arguments` is the explicit raw argument list exactly as it would be passed to
  `apply` on the target; it follows the contract's declared call layout,
  including `&optional`, `&key`, `&allow-other-keys` and `&rest`.
* `registry` is the explicit registry, defaulting to `cl-spec:*registry*`, in the
  same style as `check-function` and `run-property`.

**Naming decision.** `check-call` was chosen over `check-function-once`. It
reads as "check this call", it is short enough for REPL use, and together with
its result class `call-check-result` and projection `call-check-data` it forms a
family that is clearly distinct from the generated `check-function` /
`function-check-result` / `result-data` family. `check-function-once` describes
the implementation (one trial) rather than the meaning (one concrete call), and
"once" would become misleading if the operation is ever reused internally.

## 3. Result representation

```lisp
(defclass call-check-result ()
  (name arguments observation source-form definition))
```

* `name` -- the checked function/contract symbol.
* `arguments` -- a snapshot of the caller-supplied raw argument list.
* `observation` -- the `trial-observation` the shared path recorded.
* `source-form` -- the contract's source form, snapshotted before the call.
* `definition` -- the version 1 declaration metadata envelope (digest,
  completeness, omissions, exclusions, capabilities, state constraints)
  captured before the call with `definition-metadata`.

A dedicated class is used rather than a `property-result`: a one-shot check has
no seed, no trial budget, no profile, no shrinking and no generation report, and
filling those `property-result` slots would publish fabricated values. The
observation is reused as-is, so status, reason, signature, explanation,
condition, outcome, values, case and state evidence keep their existing
meaning and shape. `call-check-data` projects the result with the existing
version 1 envelope (`:schema-version 1`, `:record-kind :result`,
`:entity-kind :function-spec`) and the existing `observation-data` shape under
`:observation`; no second schema vocabulary is introduced.

A passing result is returned, not only a failure: it carries the outcome, the
selected case, the state evidence and the declaration metadata.

## 4. Reused internal path

`check-call` resolves the contract, validates the raw arguments against the
contract's own argument schema, builds the same `function-check-property`
adapter `check-function` builds, and calls `observe-trial` once. All of the
following come from that one call and are not reimplemented:

* call binding (`bind-call-arguments` through `evaluate-trial`),
* the common `:pre` (`precondition-refuses-p`),
* `:capture` (`run-captures`),
* exclusive `:cases` selection (`function-case-select`),
* the single target invocation (`invoke-target-once`),
* `:returns` / `:signals` / `:post` / `:post-values` classification
  (`classify-target-outcome`),
* `:state-post` (`classify-state-post`),
* evidence construction and validation (`observe-trial`),
* failure identity (`failure-signature`, `case-selection-signature`).

No second evaluator, classifier, case selector or evidence builder exists.

## 5. Argument admission, rejection and errors

The raw argument list is checked with `explain-data` against a
`call-arguments-spec` built on the contract's own call layout before
`observe-trial` runs. This is the same presence-aware validator the generated
path uses, so an argument outside the declared schema is refused exactly as a
generated value would be. It covers shape (arity, malformed keyword tails,
unknown keys, and a non-list, vector, dotted or circular argument list) and every
present argument's declared spec; an omitted `&optional` is not validated.

Whether the call itself was malformed is answered by
`call-layout-shape-error`, not by the error kind: the same `:wrong-length`,
`:unknown-key` and `:not-a-sequence` datums are produced both by a malformed
call and by a value that misses a composite argument spec. A layout refusal is
`:shape`; a call the layout accepts whose value fails a declared spec is
`:argument-spec`. Every refusal carries standard EXPLAIN-DATA datums, so a
non-list or vector refusal supports the same `:kind` / `:path` / `:actual` /
`:expected` reads as an argument-spec refusal.

The boundary between "you called it wrong" and "the contract refused it" is:

| Situation | Signal or result |
|---|---|
| unknown Function Spec | signal `unknown-function-spec` |
| target not fbound | signal `unbound-target` |
| raw arguments invalid (shape or argument spec) | signal `invalid-call-arguments` |
| `:pre` refuses the admitted input | result with `:status :rejected` |
| ordinary contract-side error (`:capture`, case selection, classifier) | result with `:status :error` |
| target condition the contract did not expect | result with `:status :error`, reason `:condition` |
| declared-outcome violation (returns, signals, post, state-post) | result with `:status :failed` |
| invocation satisfies the contract | result with `:status :passed` |
| `undefined-function` / `program-error` in `:pre`, `:post` or a spec predicate | propagates, as in `check-function` |
| `undefined-function` / `program-error` in `:capture`, a case guard or `:state-post` | result with `:status :error` and that clause's phase |
| target signals `undefined-function` / `program-error` | result with `:status :error`, reason `:condition` |

`invalid-call-arguments` is a new `cl-spec-error` carrying `:function`,
`:arguments`, a `:reason` (`:shape` or `:argument-spec`) and the structured
`:errors` from `explain-data`. It is signalled rather than returned because a
malformed or inadmissible call is API misuse, not a finding about the target.
Precondition refusal is deliberately *not* a signal: it uses
`precondition-refuses-p`, including its treatment of `spec-violation`, and is a
structured result. How `undefined-function` and `program-error` surface is the
shared evaluator's decision, not a new policy: the clauses that observe errors
explicitly (`:capture`, case selection, `:state-post`) turn them into their own
structured contract errors, the clauses the evaluator does not intercept
(`:pre`, `:post`, spec predicates) let them propagate so a mistyped or
mis-called predicate is never published as a counterexample, and a target that
signals one is an ordinary `:error` / `:condition` target observation.

## 6. Target call count

The target is called zero times when the raw argument shape is invalid, when an
argument spec fails, when `:pre` refuses the input, when `:capture` signals,
when named-case selection fails, and in every contract-side error before the
invocation. It is called exactly once -- by `invoke-target-once` -- once the
input reaches the invocation. Rendering, projecting or introspecting the result
never calls the target again.

## 7. Limits

`check-call` performs no generation, shrinking or replay, creates no seed and
claims no replayability. It may observe one stateful invocation because the
caller explicitly supplies the fresh state, but it does not make that state
restorable, reproducible or persistable, and it changes none of the existing
stateful-contract restrictions. It works with only the core system loaded; it
does not require the check-it backend.
