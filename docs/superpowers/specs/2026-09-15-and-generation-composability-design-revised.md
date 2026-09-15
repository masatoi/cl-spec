# AND generation composability: a bounded filter over a generatable source

Status: **revised design proposal; not an implementation report.**
Revision date: **2026-09-16**.
Supersedes the original `2026-09-15-and-generation-composability-design.md`.

This revision incorporates the original proposal, its review, and the subsequent
recommendations for the five maintainer questions. It preserves the original
§1–§9 organization. §9 now records decisions rather than reopening those questions.
The specification amendments in §7 must accompany the implementation.

**Evidence boundary.** The observations on commit `a193739`, source locations,
and excerpts from `docs/cl-spec-specification-v0.2-draft.md` below are carried
forward from the original proposal. They have not been independently reverified
for this rewrite and are not claims about the current `main` branch. Line numbers
are historical navigation aids; implementation must locate the corresponding
sections by heading and function name. No tests were executed for this revision.

**Decision boundary.** §9.1 records the five recommendations already made in the
discussion. §9.2 identifies additional contract proposals introduced here to make
the design implementable, including exact option/report names, runner outcome
mapping, and shrink-time accounting. These are explicit draft choices, not claims
that those interfaces already exist or were previously approved.

## 1. Current behavior

The original proposal reports that this spec validates but has no generator on
`a193739`:

```lisp
(cl-spec:defspec period
  (and
    (plist (:required (:start integer) (:end integer)))
    (satisfies ordered-period-p)))
```

`generator-for`/`sample` signal `generator-unavailable` with the reason
`"an AND needs a type or range conjunct to generate from"`. The proposal reports
that `validp` answers `T`/`NIL` correctly and `backend-capabilities` returns
`(:generation :unavailable :shrinking :unavailable)` for this example.
The reported mechanism is:

- `spec-generator ((spec and-spec) context)` lives in
  `src/backends/check-it-generators.lisp` (original location `:1003`).
- `fold-and-children` (`:957`) handles `TYPE-SPEC`, `RANGE-SPEC`, resolved
  references, and nested ANDs through `base-type/minimum/maximum`; other
  conjuncts become `leftovers`. `push` currently reverses their order (`:1000`).
- With no `base-type`, construction signals `generator-unavailable`
  (`:1013–1016`). Structured generation is therefore not an available source
  for the example above.
- A base with remaining constraints uses check-it's `guard-generator`
  (`:1024–1027`), whose `generate` recursively retries without a depth limit
  (`check-it/src/generators.lisp:367–371`).

The change addresses three related gaps:

- **G1 — source composability:** an otherwise generatable structured or finite
  spec cannot serve as the AND source through the existing base-type route.
- **G2 — boundedness and reporting:** remaining constraints use an unbounded
  guard, and generation rejection counts are not exposed.
- **G3 — explicit-source reuse:** a spec with its own `(:generator NAME)` cannot
  currently be reused as an AND source under §73.4, even when it is the only
  custom source. This blocks a natural route for an `object-of`-style spec.

The source-kind inventory in the original proposal includes `plist`, `alist`,
`hash-table`, `tuple`, `list-of`, `vector-of`, `tagged-by`, `member`, `or`, and
`nullable`. This design uses whatever generator support exists at the
implementation baseline; it does not implement an otherwise missing spec kind.

## 2. What the spec already fixes

The following abridged excerpts and locations are preserved from the original
proposal. The right-hand column describes the **old** contract, not the revised
policy. In particular, the blanket custom-conjunct refusal will be amended.

| § | Text (abridged) | Consequence at the original baseline |
|---|---|---|
| §9.2 `:809-810` | 「フィールド間制約は既存の`and`・`satisfies`で表現する。制約solverやAND生成の一般化は導入しない」 | The spec tells authors to use `and`/`satisfies` **and** forbids generalizing AND generation. This is the conflict to resolve. |
| §9.3 `:871` | 「フィールド間制約はplistと同じく既存の`and`・`satisfies`で表現する」 | Same for alist/hash-table. |
| §73.4 `:4243-4246` | 連言のcustom generatorは「直接指定・別名参照・入れ子のANDのいずれでも…`generator-unavailable`」「生成方法を指定する場合はAND全体に`(:generator NAME)`」「制約が満たされるまで**無制限に**生成し直す方式は採用しない」 | Conjunct custom generators stay refused; only *unbounded* redraw is banned; the whole-AND generator is the sanctioned route. |
| §73.5 `:4566-4568` | 「rest generatorから最大100候補callを生成し、全引数schemaで交差条件を検査する。上限まで適合しなければ`generator-unavailable`とする」 | A **bounded search is already accepted practice**, reports `generator-unavailable`, and its limit is 100. |
| §19 `:1574-1592` | 「ランダム生成 → 99.999% reject → 1件だけvalid」を避け、「可能ならgenerator側に制約を反映する」 | A filter is a fallback, not the preferred design; high rejection is a smell to report. |
| §72.1 `:3955` | 「要求した試行予算、実際に評価した件数、**生成・前提条件による棄却件数**」 | Generation-rejection counts are **already required** to be reported; the result has no field for them. |
| §38.1 `:2521-2543` | `:available`は「generatorの構築を試み、成功」であり「生成成功や契約を満たすdrawの存在を保証するqueryではない」 | Capability must not be upgraded to promise a valid draw. |
| §47 `:2847-2857` | 目標taxonomyに`:generator-error`・`:precondition-exhausted` | A generation-exhaustion cause is anticipated, though not a current status. |
| §9 `:690-691` | 空の有限domainは「列挙不能」と区別する | Evidence that the framework distinguishes empty/unsatisfiable from strategy failure. |

The revision must preserve three boundaries: capability availability means
construction success, exhaustion does not prove unsatisfiability, and generation
rejections must not be confused with precondition rejections. The existing
100-candidate rest-call search is a precedent for bounded search, not a reason to
reuse 100 as a request-wide default with a different counting unit.

## 3. The tension, and the scope of the change

§9.2/§9.3 direct authors to express cross-field constraints with `and` and
`satisfies`, while the existing AND source policy prevents natural generation of
those specs. Requiring a whole-AND custom generator also duplicates existing
construction logic when a named spec already has a suitable custom generator.

Resolution: this is a **scoped revision, not a solver**.

- Build **one generation source** using a documented deterministic policy.
  Existing numeric folding may combine numeric constraints to construct that
  source; otherwise select one conjunct. Do not combine two structured sources.
- Prefer one explicitly configured custom source when there is exactly one
  competing custom-source conjunct. Refuse ambiguous custom-source choices.
- Apply the whole-AND validator through a bounded filter when filtering is
  needed. Share a finite candidate budget across the generation request.
- Report work, generated root values, termination, and exhaustion phase without
  claiming that exhausted search proves the spec admits no values.

No constraint propagation, search over source orderings, dependent-argument DSL,
or automatic switch to another source after poor acceptance is introduced.
The generation mechanism, applied budget, condition, runner integration, and
reporting are one first-PR delivery, although they may be separate commits.

## 4. Design

### 4.1 Source selection (explicit policy)

Source selection happens at construction time. It must not draw values, execute
custom generator bodies, or run the target or filter predicates.

#### Candidate discovery and custom-generator boundaries

For `(and C1 ... Cn)`, inspect candidates in declaration order:

1. Check the outer AND's own generator annotation before inspecting its children.
2. Resolve reference aliases and flatten **unannotated** nested ANDs left to
   right. Keep diagnostic paths into the original declaration.
3. Stop expansion at a node with its own custom generator. That node is an
   indivisible source candidate; do not flatten away its annotation or replace
   its chosen generator with an underlying definition's generator.
4. Do not descend into a collection's fields or elements merely to discover
   competing AND sources. Their generators belong to construction of that
   collection candidate, not to independent alternatives for the outer AND.
5. Preserve existing unresolved-reference and cycle diagnostics. Resolution must
   not loop, and this change does not add recursive generation support.

A custom annotation on an alias takes precedence at that alias boundary under
the existing override rule. A nested annotated spec's internal construction is
not an additional competing outer-AND source. Conversely, two custom-bearing
candidate occurrences are competing sources even when they name the same
registered generator; this revision does not silently coalesce duplicates.

The source policy is:

| Priority | Condition | Action |
|---|---|---|
| **P0 — explicit whole-AND override** | The outer AND itself names a custom generator. | Use the existing override semantics. Do not add a new filter to that override merely because its definition is an AND. |
| **P1 — unique custom conjunct** | Exactly one discovered conjunct carries a custom generator, directly or through an alias. | Use that conjunct as the source, ahead of numeric folding and ordinary declaration-order selection. Apply the whole-AND filter. |
| **P1 refusal — competing custom conjuncts** | More than one discovered conjunct carries a custom generator. | Signal `generator-unavailable` with an ambiguity reason and candidate paths. Require a whole-AND override to choose explicitly. |
| **P2 — numeric fast path** | There is no custom-source candidate, and supported numeric folding constructs a generator. | Preserve existing numeric narrowing and use the folded generator. Use the bounded filter for constraints not discharged by the fold. |
| **P3 — ordinary conjunct source** | No custom source exists and the numeric fast path is inapplicable. | Select the first conjunct, in declaration order, for which ordinary generator construction succeeds. Apply the whole-AND filter. |
| **P4 — no source** | No eligible source can be constructed. | Signal `generator-unavailable` with the AND and ordered candidate refusal reasons. |

Discover all competing custom annotations **before** choosing an ordinary source.
An early success from the first ordinary candidate must not conceal a custom
annotation appearing later in the declaration.

#### Numeric fast path and construction refusals

Numeric folding remains a fast path, not a requirement imposed on all ANDs.
The existence of a `base-type` slot value alone does not establish a usable
numeric generator. Preserve supported numeric type/range narrowing through
aliases and unannotated nested ANDs. A nonnumeric type must not prevent a
structured source from being considered. For example:

```lisp
(and (type list) (list-of integer))
```

may use the `list-of` generator and validate against both conjuncts. Do not force
it through an unavailable generator for `(type list)`.

A documented, construction-time lack of generation support may lead to P3 or
skip an ordinary P3 candidate. Malformed declarations, arbitrary extension
errors, and invalid references must not be silently treated as optional
unsupported strategies. Preserve existing explicitly diagnosed empty numeric
ranges rather than retrying them with another source. Runtime budget exhaustion
is never a source-probing result; probing must not execute a draw. Construction
success is tracked separately from the truth value or representation of its
result: a supported constant source, including NIL, is not a no-source refusal.

Failure to construct the explicitly selected P1 custom source is an error, not
permission to ignore the annotation and choose another generator. Once a source
has been selected, neither rejection rate nor exhaustion causes reselection.

When a numeric fold completely handles the AND with no residual checks, the
existing unfiltered path may remain. Every new fallback filter checks the
**whole AND**, including the selected source's own constraints.

#### Custom-source reuse

For a registered `account` spec with its own custom generator, this becomes a
supported composition when no other competing custom source exists:

```lisp
(cl-spec:defspec funded-account
  (and account
       (satisfies sufficiently-funded-p)))
```

Candidates come from `account`'s declared generator and must pass the entire
`funded-account` validator. A rejected candidate consumes the same request budget
as any other filtered candidate. A propagated error in the generator is not a
rejection and must not be hidden by retrying.

This is an **outer AND validation boundary**. It does not globally change the
legacy semantics of a custom generator used alone or as P0. Rejection sampling
also changes the accepted distribution; there is no promise to preserve the
unfiltered source distribution or to cover all values admitted by the AND.

### 4.2 Bounded filter

Replace `guard-generator` in the affected AND paths with a cl-spec
`bounded-filter-generator`. The original likely integration point is
`src/backends/check-it-generators.lisp`.

The wrapper keeps construction-time state: its sub-generator, compiled
whole-AND validator, source/spec identity, and diagnostic path. **Request budgets
and counters do not belong to reusable compiled-generator state.** They live in
the request context described in §4.3. Existing cached generated values may stay
on generator objects under the backend's existing rules.

Conceptual normal-generation algorithm:

```text
loop:
    reserve one candidate unit from the active request and phase
        if no unit remains, signal the request-owned exhaustion condition
    candidate := draw once from the selected sub-generator
    if the whole-AND validator returns true:
        cache and return candidate
    record one filter rejection for the active phase
```

Reservation occurs immediately before calling the sub-generator. Rejection
increments only after that call returns a candidate and the validator returns
false. A propagated error is not converted to false, and no blanket handler
around the loop retries it. Existing validator/predicate error semantics remain
unchanged; this mechanism does not redefine errors that a validator already
handles internally.

The last permitted candidate may succeed. Reaching a used count equal to the
budget does not itself fail the accepted draw: exhaustion is signaled only when
another candidate reservation is required. There is no extra draw after budget
exhaustion and no random-state consumption merely to report it.

Every draw returned by this wrapper satisfies the whole-AND validator, **provided
the validator's predicates and readers honor the non-destructiveness contract in
§4.8**: a candidate is returned only after the validator returned true, and this
wrapper neither detects nor repairs a predicate that changed its input. This
claim is local to the new wrapper, not a stronger guarantee for every existing
custom-generator entry point. Shared mutable compiled generators are not made
thread-safe by moving counters into a request context.

### 4.3 Budget scope, default, counting, and lifetime

#### Request and default

**Decision:** the budget is shared across one generation request, not reset for
each requested value. One `sample` call is one request for all of its values;
one `run-generated-test` invocation is one request. No independent per-value cap
is introduced in the first PR.

Let `N` be the planned number of normal, root-level values or argument tuples to
be generated. For `sample`, this is its requested count. For the runner, it is
the existing generation/trial-loop bound established before execution, not a new
target of `N` accepted preconditions or `N` successful target invocations.
The default candidate budget is:

```text
B = 1,000 × N
```

Thus a request for ten root values has one budget of 10,000 candidate units.
One difficult value may use more than 1,000 units if the shared budget remains.
The request stops when its existing stopping rule is met; unused budget is not
spent. Preconditions do not replenish this budget or change `N` after the run
starts. Existing `:trials`, `:rejected`, zero-trial, and early-failure semantics
must not be redefined by this calculation.

The coefficient 1,000 is an initial engineering default, **not an empirically
validated optimum or a completion guarantee**. For a single filter with
independent, constant 1% acceptance, the expected cost per accepted value is 100
candidates and 1,000 candidates all failing has probability `0.99^1000`, about
0.0043%. Shared budgets absorb variability across requested values. Nested
filters and nonstationary or stateful generators do not follow this simple
probability model. An impossible filter will consume more work with a larger
budget; callers need an explicit smaller override when appropriate.

For comparison, independent per-value caps succeed for `N` values with
probability `(1 - (1 - p)^b)^N` under that same independence assumption. A small
per-value cap would reintroduce the failure mode that sharing is intended to
avoid, even when the request has spare budget.

#### Candidate unit and nested filters

One budget unit is **one call by a bounded AND filter to its selected source to
request a fresh candidate**. It is not one accepted root value, one target call,
or every backend generator invocation.

All structural descendant and sibling bounded filters in a request share the
same context. An outer filter reserves a unit before entering its source; a
nested filter reserves its own units. The outer reservation is not refunded if
a nested draw fails. Therefore a root value can cost several units even when
its outermost check accepts on its first try.

Only a false validation result for a fresh candidate following that filter's
own reservation increases generation-report `rejections`. Pure shrink-candidate
validation failures do not increase this counter. Totals sum the accounted
filter invocations across phases. In particular:

```text
0 <= rejections <= attempts <= budget
```

but **`attempts - rejections` is not the number of generated root values**.
A root value is counted separately, only when its top-level generator returns
normally. For a function check this can be a whole raw argument tuple, including
one subsequently rejected by its precondition.

A fully folded numeric generator or a source with no bounded AND filter uses
zero candidate units for this mechanism. The report must name its counting
scope; it is not a complete CPU-cost or all-generator-draw measurement.
Other existing rejection loops, including the rest-call search, retain their
separate limits unless separately amended. This is not a new global budget for
all backend work.

#### Lifetime and phases

Create a fresh context at each public generation-request boundary, using the
existing `with-generation-environment` boundary where appropriate. Restore the
previous context on unwind. Compilation and introspection consume no budget.
A public single-value drawing entry point without an active context uses an
implicit request with `N = 1`; internal backend methods do not silently create
fresh budgets on retry or recursive descent.

Sequential requests using the same compiled generator get fresh budgets and
counters. Structural generator composition inherits the active request. An
explicit nested public `sample` or test-runner call starts a separate request;
its work inside user code is not recursively controlled by the outer budget.
Request identity distinguishes an inner request's exhaustion from the outer
request's own depletion. Counters alone do not guarantee reproducibility of
arbitrary stateful custom generators.

**Additional contract proposal:** the same context remains active during
shrink-time regeneration in that runner request. Fresh candidates requested by
bounded filters during shrinking consume the remaining shared budget; the budget
is not reset after the first target failure. Counters distinguish `:generation`
and `:shrinking` phases. Normal shrink proposals that request no fresh draw do
not consume generation units and remain subject to existing shrink limits.
See §4.7 for preserving failure evidence when this shared budget is exhausted.

#### Options and recorded settings

**Additional API proposal:** expose the total override as `:generation-budget`:

```lisp
;; Proposed sample API extension.
(cl-spec:sample 'period :count 10 :seed 42 :generation-budget 5000)

;; Proposed runner option, using the existing runner-options convention.
(cl-spec:run-property 'period-law
                     :seed 42
                     :options '(:generation-budget 5000))
```

`check-function` forwards the same option through its existing options route.
Validate an explicit override as a nonnegative integer before execution. Omitted
means compute the default; explicit zero is not an omission. Zero forbids any
new bounded-filter source call, but need not forbid a draw that uses no such
filter. If an existing entry point permits `N = 0`, its default budget is zero
and it requests no roots; its existing success/status semantics remain intact.

Record before execution the effective budget, `:request` scope,
`:bounded-filter-source-call` unit, planned `N`, whether the budget was defaulted
or explicit, and source-policy identifier `:and-single-source-v1`. Store these
in the existing options/provenance machinery and expose the applicable fields
in the report. Record the default coefficient when defaulting. Do not rely on
remembering only that the caller omitted an option: defaults may change later.

Finite candidate count is **not** a wall-clock timeout. One generator or predicate
call may block, loop, allocate without bound, or change external state. This
change adds neither interruption nor state rollback.

### 4.4 Failure condition and execution boundaries

**Decision:** introduce `generation-budget-exhausted` as a subclass of
`generator-unavailable`.

The parent remains the existing broad family for an unavailable or uncompleted
generation operation. Do not redefine it as exclusively static: the original
§73.5 precedent already uses it after dynamic candidate search. The subclass
identifies the specific case where a request-owned finite budget was exhausted.
An ordinary no-source construction failure still uses `generator-unavailable`
without this subclass.

Retain the inherited `spec` and `reason`, and expose an immutable snapshot of the
request's generation report. Provide readers for attempts, rejections, budget,
exhaustion phase, and the exhausting filter's declaration path, derived from that
snapshot rather than independently mutable duplicate slots. Internally retain
request ownership so the runner can distinguish its own depletion from an
unrelated condition of the same type. The live context/token is not wire metadata.

The diagnostic must say, in substance:

> The selected generation strategy exhausted its candidate budget. No claim is
> made that the specification is unsatisfiable.

It identifies the filter that attempted the denied reservation. That path marks
where the shared budget ran out, not proof that this one filter consumed all work.
An independently proven empty numeric interval may retain its existing distinct
construction diagnosis; budget exhaustion never constitutes that proof.

Existing callers catching `generator-unavailable` still catch this subclass.
Callers needing the distinction handle `generation-budget-exhausted` first.
A report/wire reason may be derived from the condition type; do not add a mutable
`:cause` that can contradict it.

#### Normal generation versus target execution

Catch the request-owned budget condition around generator execution, **not**
around the entire trial including the target, preconditions, and postconditions.
A target that signals the same condition class retains its existing target
outcome semantics. A custom source that raises an unrelated/inner-request
condition does not establish that the current request spent its own budget.
Do not silently retry arbitrary custom-source errors.

For `sample`, owned exhaustion signals the condition with its partial progress
report. Do not return a shorter list as normal success. Partial root values need
not be retained in the condition; the generated count is available. Previously
performed generator side effects are not rolled back.

**Additional runner-protocol proposal:** when the current request exhausts during
normal input generation, return a generation-infrastructure error result with:

```lisp
(:status :error
 :failure-reason :generation-budget-exhausted
 :failure-phase :generation
 :condition <the-condition>
 :generation-report <snapshot>)
```

This is a proposed outcome shape, not executable Lisp or a claim that the current
validator accepts it. Extend `validate-backend-outcome` and result readers for
this explicit branch. Preserve all already-collected trial/precondition counts
under their existing definitions, but supply **no target failure observation,
no counterexample, and no fabricated failed invocation**. A partial successful
prefix is not a passed run. Attempting to create a counterexample artifact from
this generation-only result must be refused under the artifact API's explicit
unsupported/no-evidence path.

The exception to target-evidence requirements must be narrow: a validated,
request-owned normal-generation exhaustion with coherent report and counts.
Do not relax evidence requirements for ordinary target `:failed`/`:error` results
or allow contradictory target evidence on the generation-only branch. Existing
handling of other generator errors is retained; such errors are not mislabeled
as budget exhaustion. Shrink-phase depletion follows §4.7 instead.

### 4.5 Reporting and `sample` multiple values

**Decision:** reporting ships in the first PR. `:rejected` continues to mean the
existing precondition rejection count, not filter rejection count.

**Additional report-schema proposal:** use the following ordinary Lisp data.
This example is a ten-root `sample` with one filter and no shrinking:

```lisp
(:scope :request
 :unit :bounded-filter-source-call
 :budget 10000
 :requested-values 10
 :generated-values 10
 :attempts 18
 :rejections 8
 :phases (:generation (:attempts 18 :rejections 8)
          :shrinking (:attempts 0 :rejections 0))
 :termination :completed
 :exhaustion-phase nil
 :exhausted-at nil)
```

| Field | Contract |
|---|---|
| `:scope`, `:unit` | Explicitly identify the request-wide, bounded-filter source-call accounting described in §4.3. |
| `:budget` | Effective nonnegative total budget for both phases. |
| `:requested-values` | Planned normal-generation root count `N`, fixed before execution. It is not an assurance that every planned root will be requested. |
| `:generated-values` | Roots returned normally during the normal-generation phase. Shrink candidates/regeneration and nested intermediate values do not increase it. |
| `:attempts`, `:rejections` | Aggregate candidate reservations and false-filter results in both phases. |
| `:phases` | Separate generation/shrinking counters whose sums equal the aggregate counters. This prevents shrink work from being presented as initial-input generation cost. |
| `:termination` | `:completed`, `:budget-exhausted`, or `:interrupted`, with the meanings below. |
| `:exhaustion-phase` | `:generation` or `:shrinking` for owned budget exhaustion; otherwise NIL. |
| `:exhausted-at` | Stable declaration path of the denied filter reservation; otherwise NIL. No live generator, closure, or opaque context. |

`:completed` means this generator subsystem ended without owned exhaustion or a
propagated generation error. It does **not** mean the whole test passed, all `N`
roots were generated, or the underlying spec has broad coverage. A runner that
stops after a target counterexample can have `:completed` generation and
`:generated-values < :requested-values`.

`:budget-exhausted` identifies the owned exhaustion and its phase. During
shrinking it may accompany a valid, retained target counterexample. `:interrupted`
is an additional proposal for a generator/source error that aborts generation
or shrink-time regeneration without depleting this budget. It must not be used
as a synonym for false-filter rejection, or overwrite a more specific owned
exhaustion already recorded. Target failures by themselves do not make the
generation report `:interrupted`.

Add `generation-report-p` in `src/generator.lisp` and validate the shape and
relationships in `validate-backend-outcome`: nonnegative counts, roots within
`N`, phase sums, rejection bounds, total attempts within budget, and coherent
exhaustion fields. Owned exhaustion requires `attempts = budget`, because it is
reported when a further reservation is denied. Completed reports may also have
`attempts = budget` if the final permitted candidate sufficed.

Backend outcomes gain `:generation-report`; `property-result` gains
`property-result-generation-report`; `result-data` exposes the snapshot and the
explicit failure-phase distinction where applicable. Reports are immutable
snapshots, not references to live counters. Keep old extension/backend/record
absence as `:not-collected`, never a fabricated zero-work report. A collecting
backend with no bounded filter returns known zero filter counts and its actual
root count. Report omissions in older saved data remain unknown/not collected.
Follow the existing result/artifact metadata and versioning rules; a new optional
report does not license weakening argument or failure-evidence validation.

**Decision:** successful `sample` returns:

```lisp
(values samples generation-report)
```

Both requested values and report belong to that invocation; no global
"last-sample-report" accessor is needed. Primary-value-only callers retain their
observed value. Callers using `multiple-value-list`, `multiple-value-call`, or
exact fixed-value contracts can observe this API extension. Update documentation,
any return declarations, and self-specifications accordingly; do not call it
unconditionally non-breaking. On exhaustion, obtain the same report schema from
the condition rather than from normal return values.

Capability semantics remain unchanged: `:available` means construction succeeded.
It promises neither a valid draw within this budget nor an accepted shrink.
Probing must not invoke generators/predicates/targets or allocate a draw request.
A constructed but impossible finite filter can therefore be `:available`.

### 4.6 Reproducibility

Selection, candidate order, counting, and stopping must be deterministic given
the same effective configuration. All ordinary random draws use the request's
existing seeded state. Budget reservation and reporting make no extra random
calls. Rejected values consume the random work actually performed and are not
replayed or redrawn merely to classify the result.

A replay depends on the same declarations and registered dependencies, seed,
backend/version, source-policy version, requested count, effective budget, other
relevant runner settings, and deterministic generator/validator behavior.
Shrinking additionally depends on the target's failure behavior. Captured state,
external I/O, time, and implementation changes are not made reproducible by a
seed or declaration digest. Claims limited to `(spec, seed, backend)` are too
strong once configuration and custom code can vary.

Record applied settings before execution, including defaulted values (§4.3).
The same request settings should reproduce accepted roots, attempts/rejections,
exhaustion phase/path, and retained shrink observations when those determinism
conditions hold. Changing the budget is intentionally allowed to change whether
the request completes and how far shrinking proceeds.

### 4.7 Shrinking, regeneration, and evidence preservation

Implement explicit wrapper behavior for `shrink`, `regenerate`, and
`generator-shrink-strategy-p`; "delegate" alone is not a sufficient contract.
The original delegation points were `check-it/src/shrink.lisp:254` and
`regenerate.lisp:52`; verify current backend call conventions during implementation.

Before any candidate reaches the target evaluator, validate it against the whole
AND. A candidate rejected by this check must neither call the target nor replace
the selected cached/evidence value. Subsequent existing argument-schema and
precondition gates still apply; passing this filter is not permission to bypass
them. Only observed, spec-valid candidates satisfying the existing failure-
identity rules may replace counterexample evidence. Never adopt an unobserved
transformed value returned by a delegated shrinker.

Fresh source draws requested by a bounded filter during regeneration consume
shared request units and increment the shrinking-phase counters. Pure shrink
proposals consume no generation units; their rejection and termination remain
under the existing shrink protocol. No rejected shrink candidate is presented
as an initial-generation filter rejection.

When owned budget exhaustion occurs after a target failure has been observed:

1. Stop shrink/regeneration search without requesting another candidate.
2. Retain the original failure observation and any previously accepted reduced
   observation. Preserve the target's failure status and identity.
3. Record `:budget-exhausted` with `:exhaustion-phase :shrinking` in the generation
   report and expose the stop reason through shrink diagnostics as well.

**Additional shrink-report proposal:** extend the collecting shrink report's
termination vocabulary with `:generation-budget-exhausted` when this is the
reason it stops. Do not fabricate unrelated candidate metrics for older backends
that have not collected them; the generation report remains sufficient to expose
the phase and cause. Existing shrink-report validators and result projections
must be updated together if the new termination is emitted.

A shrink-time generator error follows the existing evidence-preserving error
policy, with generation counters retained, rather than erasing the original
counterexample. Capability may claim a shrink strategy only when the underlying
strategy is supported through these validation/evidence gates. Do not claim new
custom-value shrinking support merely because a custom generator is now eligible
as an AND source. Global minimality, restoration of arbitrary objects, and external
state rollback remain outside this change.

### 4.8 Validator non-destructiveness is an author contract

**Decision (maintainer, 2026-09-16).** A predicate or reader used for
specification validation MUST NOT modify the value it is handed, nor any mutable
object reachable from it. This covers, for example, destructive plist/alist
edits, hash-table entry writes, array or vector element writes, CLOS or structure
slot writes, and writes into a mutable object shared inside the input.

cl-spec neither detects a violation of this contract nor restores a modified
value. In particular the bounded wrapper adds no snapshot, deep copy, digest,
slot monitor, re-validation, mutation condition, or optional/debug mutation
check, and `generate`/`shrink`/`regenerate` do not compare the candidate before
and after validation. When the contract is violated, the admissibility of
generated values, any shrink result, and any reproducibility that depends on that
validation are not guaranteed, and no particular condition is promised.

The contract does not forbid:

- a generator constructing or initializing a fresh object;
- the target function making its intended state change;
- the runner or backend updating its own counters;
- an existing property body that deliberately tests stateful behaviour.

This is not a general side-effect ban or a purity requirement. Replay determinism
with respect to time, random state and external state keeps its existing
guarantees; non-destructiveness alone is not claimed to make a run reproducible.

Consequences:

- The bounded filter returns a candidate after the whole-AND validator returns
  true. "The returned candidate satisfies the whole AND" is conditional on the
  validator honoring this contract.
- Shrink and regeneration call the whole-AND validator before the target-facing
  callback and adopt only callback-observed values, but they do not inspect
  whether validation changed a candidate. A destructive predicate can therefore
  corrupt a candidate or the retained evidence; that is a contract violation, not
  a gap this PR is scoped to close.
- Reintroducing an input-mutation detector is a separate decision. It must not be
  justified solely by the fact that a destructive predicate currently goes
  undetected.

## 5. Non-goals

- No constraint solver, propagation, automatic cross-field narrowing, adaptive
  source switching, or product/intersection of two structured generators.
- No new dependent/argument-reference DSL. Existing `:args-generator` and custom
  whole-argument shrinking remain the explicit route for tightly correlated
  arguments. This design reduces some hand-written adapters; it does not replace
  that facility.
- No blanket revalidation change for standalone custom generators or P0. The new
  validation is the enclosing AND's whole-spec filter for selected conjunct sources.
- No generation strategy for a bare nested field predicate such as
  `(plist (:optional (:x (satisfies p))))` without an existing source/generator.
  An AND *inside* a field can use this mechanism if it has an eligible source,
  but a bare predicate has not acquired one.
- No general recursive generation, termination proof, wall-clock timeout,
  resource isolation, external-state restoration, or transactional rollback.
- No redesign of existing precondition rejection budgets, rest-call generation
  limits, custom generator semantics outside the scoped changes, or full backend
  cost accounting.

## 6. Test plan

Use controlled generator fixtures for exact acceptance/rejection sequences and
budget boundaries; do not make correctness depend on a probabilistic "rare but
possible" success. Keep seeded integration tests separate from deterministic
boundary tests. The following tests are first-PR acceptance requirements.

| Area | Required checks |
|---|---|
| **Basic composition** | The `period` example samples values satisfying the whole spec. Exercise supported structured/finite source kinds without claiming support for absent kinds. |
| **Numeric regression** | Existing `and-folds-its-constraints-into-one-generator` and reference/nested-AND folding tests remain valid. Preserve narrow numeric generation and established empty-range diagnostics. |
| **Nonnumeric fallback** | `(and (type list) (list-of integer))` reaches the structural source instead of failing solely because a base type has no generator. |
| **Ordered selection** | The first ordinarily constructible source wins after fast paths; ordered reasons remain stable. Known unsupported construction can be skipped; malformed definitions and arbitrary construction errors cannot. No probe performs a draw. A successfully constructed constant/NIL source is not mistaken for absence. |
| **No source** | `(and (satisfies oddp) (satisfies plusp))` still signals ordinary `generator-unavailable` without a budget-exhaustion claim. |
| **Unique custom source** | A custom-generated object/spec can be composed with another predicate. It wins even when an ordinary source appears earlier. Its candidates are filtered against the whole AND. |
| **Custom boundaries** | Test direct/alias/nested annotated specs, annotation-preserving flattening, later conflicting annotations, two occurrences naming the same generator, and field-level custom generators that are not competing outer sources. |
| **Custom errors and override** | An unavailable explicit custom source or a propagated draw error is not silently retried through another source. Whole-AND P0 remains the explicit ambiguity override with its legacy validation semantics. |
| **Impossible filter** | `(and (member 1) (satisfies evenp))` constructs but exhausts its finite budget. Verify condition inheritance, report ownership, counts, and the explicit non-unsatisfiability message. |
| **Last candidate / zero budget** | Acceptance on the last permitted reservation succeeds. A further reservation fails before a source call or RNG use. Explicit zero is not defaulted; no-filter and zero-count cases follow §4.3. |
| **Shared budget** | A difficult individual value can exceed 1,000 candidates while the request has spare budget. Sibling and nested filters share the limit; ancestor reservations are retained on child failure. Root and filter counters differ as specified. |
| **Request lifetime** | Sequential requests using a compiled generator receive fresh counters and budgets. Internal delegation never resets a budget. Nested public requests restore the outer context and do not misattribute exhaustion. |
| **Partial generation** | After a known number of completed roots, owned exhaustion preserves existing trial/precondition counts, returns the proposed generation-error branch, and creates no target failure observation or artifact. It never passes a partial run. |
| **Phase boundary** | The target or a pre/postcondition signaling the same condition type is not classified as request-owned input-generation exhaustion. Unrelated inner-request/source errors do not masquerade as outer budget depletion. |
| **Shrink safety** | Rejected shrink/regenerate candidates cause zero target calls. Only observed valid candidates with matching failure identity replace evidence. Delegated unobserved return values are not adopted. |
| **Shrink exhaustion** | Consume the remaining request budget during regeneration. Preserve original/accepted reduced failures, mark the shrinking phase and shrink termination, and never replace the target failure with a generation-only error. |
| **Reporting** | Validate reports for success, target failure, normal-generation exhaustion, shrink exhaustion, no-filter runs, and propagated generation interruption. Reject inconsistent phase sums, counts, and evidence branches. |
| **Compatibility** | Legacy backends/results retain `:not-collected`. `sample` keeps its primary list, adds its second value, and exposes report readers on failure. Test observable multiple-value changes and update affected self-specs. |
| **Replay and options** | The same deterministic configuration reproduces roots, work counts, and exhaustion. Record the effective default/override before execution; explicit zero and changed defaults are distinguishable. |
| **Capability / full regression** | Construction alone determines capability and runs no user code. Perform the cold compile and full existing suite, including outcome, evidence, schema, metadata/artifact, and self-specification tests. |

The original cold-compile gate is:

```lisp
(asdf:compile-system :cl-spec :force :all)
```

No test outcomes are asserted by this design document.

## 7. Specification amendments (proposed text)

Amend the main specification by **section meaning**, not by assuming that the
original line numbers are still current. Update the implementation, API docs,
and executable self-specifications with these contracts in the same first PR.

| Section | Required amendment |
|---|---|
| **§9.2 / §9.3** | Permit one-source bounded AND generation for cross-field constraints; preserve the prohibition on a solver and structured-source intersection. Replace the blanket "no AND generalization" wording. |
| **§73.4** | Replace blanket conjunct-custom-generator refusal with P0/unique-custom/ambiguous-custom rules. Preserve explicit overrides and prohibit unbounded retries. State annotation boundaries and whole-AND filtering of a selected custom source. |
| **§10** | Describe source selection and supported composability, including custom-source ambiguity and construction errors. Do not promise generation merely because some conjunct is generatable. |
| **§11** | Clarify that standalone/P0 custom generation retains its contract, but a selected custom conjunct is subject to its enclosing AND validator. Propagated generator errors are not filter rejections. |
| **§14** | Add report validation and the narrow generation-only error branch without target failure evidence. Specify normal-generation versus shrink exhaustion and preserve ordinary evidence requirements. |
| **§15** | State reproducibility assumptions including effective budgets, count, source policy, backend implementation, and deterministic user code; record defaults before execution. |
| **§38.1** | Add report and phase/reason projections to results while preserving construction-only capability semantics and `:not-collected` compatibility. |
| **§47 / §48** | Distinguish generation infrastructure errors, request-wide filter budget, and existing trial/time/shrink budgets. Update taxonomy for the chosen concrete outcome representation, not just a future target name. |
| **§72.1 / §72.4** | Define generation versus precondition counts, root counts, shared units, phases, partial progress, and recorded applied budget. |
| **§73.5** | Record this bounded-AND feature and acceptance criteria, without silently changing the separate 100-candidate rest-call policy. |
| **§0.2** | Update the AND generation status row and its limitations. |
| **Public API and report contracts** | Document the subclass/readers, proposed option key, report shape, sample's two-value return, and the shrink-report termination extension wherever these APIs are specified. |

Suggested replacement wording for §9.2/§9.3:

> 制約solverは導入しない。ANDは決定的な規則で生成元を一つ構築する。
> 既存の数値制約のfoldを維持し、それ以外は適格な連言一つを生成元とする。
> 必要な制約検査にはAND全体のvalidatorによる有限予算のfilterを用いる。
> 予算は一生成要求内のfilter間で共有し、候補数・棄却数・生成済みのルート値の
> 件数・終了理由を報告する。予算切れは、この生成戦略が適用予算内に値を
> 得られなかったことを示すものであり、仕様の充足不能を意味しない。

Suggested replacement wording for the custom-source portion of §73.4:

> AND自身に指定されたcustom generatorは従来どおり優先する。それがない場合、
> 生成元として競合する連言にcustom generatorの指定が一つだけあれば、その連言を
> 優先して生成元とし、得られた候補にAND全体のvalidatorを適用する。
> 複数の競合するcustom生成元がある場合は、暗黙に一つを選ばず
> `generator-unavailable`とする。選択を明示するにはAND全体へgeneratorを指定する。
> aliasや入れ子のANDを処理する際にcustom generatorの指定を失わせてはならない。
> collection内部のfield用generatorは、それだけで外側のANDの競合生成元とはしない。
> 無制限の再生成は採用しない。予算切れは`generation-budget-exhausted`とし、
> 件数・枯渇フェーズ・位置を報告する。

Suggested budget wording:

> 予算単位はbounded AND filterによる生成元への新規候補要求一回とする。
> 通常生成で予定するルート値の件数をNとし、明示指定がなければ総予算は
> 1,000×Nとする。値ごとに予算をリセットせず、独立した値単位上限も設けない。
> 入れ子・兄弟のfilterは同じ予算を消費する。縮小中の再生成にも残予算を使用し、
> フェーズ別に計数する。縮小で予算が尽きても、既存の失敗証拠を失わせない。
> この予算は候補要求数を制限するもので、任意の利用者コードの実行時間や
> 外部状態を制御するものではない。

## 8. Staging and first-PR acceptance

Slices are implementation/checkpoint boundaries, **not independently mergeable
feature contracts**. The first PR contains Slice 1, Slice 2, effective option
recording, and all cross-boundary tests.

### Slice 1 — source, budget, condition, safety

Implement ordered candidate discovery, custom annotation boundaries and priority,
numeric fast path/fallback, request context and default/override, bounded filter,
condition/readers, and shrink/regeneration validation gates. Define the report
schema alongside the mechanism so counters and lifetime are not redesigned later.
Add deterministic construction, budget-boundary, nested-context, and safety tests.

### Slice 2 — runner, sample, results, and evidence

Connect the context/report to backend outcomes, outcome validation, result
readers, `result-data`, proposed phase/error mapping, shrink diagnostics, and the
second `sample` value. Record effective options before execution. Preserve target
failure evidence across shrink exhaustion and keep legacy absence as
`:not-collected`. Update normative specification sections, API documentation,
and executable self-specifications. Run the full acceptance matrix in §6.

Do not merge the new bounded mechanism while request-wide budgeting, owned
exhaustion handling, applied option recording, or public reporting is missing.
A main-spec amendment without the corresponding executable behavior is not a
completed slice of the public feature.

### Follow-ups, not prerequisites

Detailed per-filter histograms/source diagnostics beyond the exhaustion path,
acceptance-rate warnings, empirical tuning of the default coefficient, optional
additional caps, broader cost accounting, and richer shrinking for custom values
may follow separately. Changing source-selection semantics, permitting multiple
custom sources, or introducing a solver requires a new design decision.

## 9. Decision record

### 9.1 Previously discussed maintainer questions — resolved policy

These replace the original Q1–Q5; none is left open in this revision's proposed
implementation policy.

| Original question | Decision | Reason |
|---|---|---|
| **Q1 — budget scope/default** | One shared generation-request budget; default `1,000 × N`; no independent per-value cap in the first PR; permit an explicit total override. | Avoid multiplicative accidental failure from per-value caps, allow cost variability across values, and choose a finite initial allowance rather than reuse an unrelated 100-candidate limit. The default is provisional engineering policy, not a measured guarantee. |
| **Q2 — condition shape** | `generation-budget-exhausted` subclasses `generator-unavailable`; derive reporting causes from its type. | Preserve broad existing handlers while allowing type-directed handling of budget depletion. Do not maintain contradictory class/cause state. |
| **Q3 — §73.4 relaxation** | Allow and prioritize a unique competing custom conjunct; refuse multiple custom candidates; retain whole-AND override. | Reuse natural object/spec construction without silently ignoring explicit generator choices or introducing multiple-source composition. This supersedes the earlier review preference to defer relaxation. |
| **Q4 — reporting delivery** | Include mechanism, report, runner integration, and effective option recording in the first PR. | Rejection cost, incomplete generation, and applied limits are observable semantics required to interpret the new behavior, not optional later telemetry. |
| **Q5 — sample return** | Return the report as a second value; expose it through the condition on exhaustion. | Associate diagnostics with their invocation while preserving the primary sample list. Explicitly document changes visible to multiple-value callers. |

### 9.2 Additional contract proposals made by this rewrite

The discussion required these points to be specified but did not previously
settle their exact representation. This revision proposes the following rather
than presenting them as pre-existing decisions or repository facts:

| Detail | Proposed resolution and location |
|---|---|
| **Concrete override spelling** | `sample` gets `:generation-budget`; runner entry points use the same key in their options; effective settings include scope/unit/source-policy metadata (§4.3). |
| **Shrink-time budget** | Share the request's remaining candidate budget across generation and shrink-time regeneration; split counters by phase and preserve existing failure evidence (§4.3, §4.7). |
| **Concrete generation-only outcome** | `:status :error`, `:failure-reason :generation-budget-exhausted`, `:failure-phase :generation`, condition/report, and no target failure observation; explicitly extend validator rules (§4.4). |
| **Report schema** | Add requested/generated root counts, phase totals, exhaustion path/phase, and `:interrupted` in addition to completed/exhausted termination (§4.5). |
| **Shrink termination diagnostic** | Add `:generation-budget-exhausted` to a collecting shrink report's termination vocabulary; do not invent uncollected metrics (§4.7). |
| **Reentrancy and duplicate annotations** | Nested public requests have separate ownership; structural composition shares context; competing annotated occurrences are not silently coalesced (§4.1, §4.3). |

These proposed interfaces must be checked against the implementation baseline
before coding. Any incompatibility should produce an explicit revision of the
corresponding contract and tests, not a silent fallback to the original open
questions, per-value retry budgets, or evidence-free target-error results.

### 9.3 Maintainer decision: validator non-destructiveness (2026-09-16)

The maintainer fixed the guarantee boundary for this PR: validation predicates
and readers must not modify their input or anything reachable from it, and
cl-spec does not detect or repair a violation (§4.8). The input-mutation
detection that an earlier round of review prompted in the AND wrapper is removed;
no replacement detection mechanism is added. This is a settled contract, not a
deferred item. "The candidate satisfies the whole AND" is stated subject to this
contract, and defensible shrink safety and report accuracy for conforming
predicates are unchanged.

The intended invariant across all of them is:

> **Select one source explicitly; bound the shared filtering work; distinguish
> inability to generate from a target counterexample; retain evidence; and report
> what actually happened without claiming more than was observed.**
