# AND generation composability: a bounded filter over a generatable source

Status: **historical design record.** This is the original proposal. It was
superseded by `2026-09-15-and-generation-composability-design-revised.md`, and
the feature is implemented in `main`. The normative contract is §73.5's
bounded-AND addendum in `docs/cl-spec-specification-v0.2-draft.md`, and the
runnable tour is `docs/guides/structured-data-walkthrough.md`. Read this document
as a record of the discussion, not as the current usage guide.

## 1. Current behavior

This spec validates today but has no generator:

```lisp
(cl-spec:defspec period
  (and
    (plist (:required (:start integer) (:end integer)))
    (satisfies ordered-period-p)))
```

`generator-for`/`sample` signal `generator-unavailable: "an AND needs a type or
range conjunct to generate from"`. Verified on `a193739`: `validp` answers
`T`/`NIL` correctly, `backend-capabilities` answers
`(:generation :unavailable :shrinking :unavailable)`, and `sample` signals.
The mechanism:

- `spec-generator ((spec and-spec) context)` — `src/backends/check-it-generators.lisp:1003`.
- `fold-and-children` (`:957`) folds only `TYPE-SPEC`, `RANGE-SPEC`, a resolved
  `REFERENCE-SPEC`, and a nested `AND-SPEC` into `base-type/minimum/maximum`;
  every other conjunct is pushed onto `leftovers` (in reverse order — `:1000`).
- No `base-type` → `generator-unavailable` (`:1013-1016`).
- A `base` with `leftovers` is wrapped in check-it's `guard-generator`
  (`:1024-1027`), whose `generate` re-enters itself with **no depth limit**
  (`check-it/src/generators.lisp:367-371`).

Two distinct gaps:

- **G1, source**: a generatable structured spec (`plist`/`alist`/`hash-table`/
  `tuple`/`list-of`/`vector-of`/`tagged-by`/`member`/`or`/`nullable`) cannot be
  the generation source. Only numbers can.
- **G2, boundedness/reporting**: the leftover conjuncts go through an unbounded
  guard, and nothing reports how many draws were rejected.

## 2. What the spec already fixes

Any solution has to fit these, quoted with the line in
`docs/cl-spec-specification-v0.2-draft.md`:

| § | Text (abridged) | Consequence |
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

## 3. The tension, and the scope of the change

§9.2 says to express inter-field constraints with `and`/`satisfies`, but the AND
generator refuses exactly those specs; the only generation route is a whole-AND
`(:generator NAME)`. The request is to close that gap *before* adding new syntax.

Resolution: this is a **scoped revision**, not a solver.

- Exactly **one** conjunct is the source, chosen by a fixed documented policy.
- **No** constraint propagation, no product/intersection of two structured
  sources, no search over orderings or rewrites.
- A **finite** attempt budget with a reported termination reason.
- The failure report **explicitly disclaims** unsatisfiability: it is "this
  strategy did not produce a value", never "this spec admits nothing".

The words "一般化は導入しない" (§9.2) and "無制限に…は採用しない" (§73.4) are
what the amendments in §7 must rewrite: bounded filtering is not the unlimited
redraw §73.4 bans, but it is broader than §9.2's current wording allows.

## 4. Design

### 4.1 Source selection (explicit policy)

For `(and C1 … Cn)`, after flattening nested `AND`s and resolving reference
aliases, in declaration order:

1. **P0** A custom generator named on the AND node wins (existing
   `spec-generator :around`, `:356`).
2. **P1** Fold numeric narrowing as today. If a `base-type` results, the
   numeric generator is the source. This preserves
   `(and integer (range 1 100) (satisfies oddp))` and
   `(and my-range (satisfies oddp))` narrowing.
3. **P2** Otherwise the source is the **first conjunct, in declaration order,
   that compiles to a generator**. Candidates are the kinds with a
   `spec-generator` method: `member`, `or`, `nullable`, `tuple`, `list-of`,
   `vector-of`, `plist`, `alist`, `hash-table`, `tagged-by`, and references
   resolving to any of these. A candidate that signals `generator-unavailable`
   is skipped and its reason remembered.
4. **P3** If none compiles, signal `generator-unavailable` naming the AND and
   each candidate's reason.
5. **P4** A conjunct carrying its own custom generator stays refused (§73.4,
   open question Q3).
6. The filter predicate is the **whole-AND validator**, so every conjunct —
   including the source's own constraints — is enforced.

`leftovers` must be collected in declaration order; today `push` reverses it
(`:1000`), which is harmless only because nothing reads the order.

### 4.2 Bounded filter

Replace `guard-generator` in the AND path with a cl-spec
`bounded-filter-generator` (in `src/backends/check-it-generators.lisp`):

- Slots: `sub-generator`, `filter`, `budget`, and counters `attempts`,
  `rejections`.
- `generate`: draw up to `budget` times; return the first value the filter
  accepts, counting each rejection; on exhaustion signal
  `generation-budget-exhausted` (§4.4) carrying the report.
- `shrink` / `regenerate` / `generator-shrink-strategy-p`: delegate to the
  sub-generator, mirroring check-it's `guard-generator`
  (`check-it/src/shrink.lisp:254`, `regenerate.lisp:52`), but a value the filter
  rejects must never surface as a counterexample.

### 4.3 Budget scope

Two choices, with a real statistical difference. For acceptance probability `p`,
`T` trials, and per-value budget `B`, the run succeeds with probability
`(1-(1-p)^B)^T`; a per-run total budget instead needs a negative-binomial number
of attempts, which concentrates around `T/p`.

- **Per value** (current guard semantics): simple, but at `p=0.05`,
  `B=100`, `T=100` a valid spec fails ~45% of runs.
- **Per run** (recommended): attempts are shared across the whole generation
  request, so low acceptance costs more attempts instead of failing. This is
  also what §48/§72.4 anticipate when they require the whole-run budget and the
  trial budget to be distinguished.

Recommendation: scope the budget to **one generation request**
(`run-generated-test` = one request; `sample` = one request for all its values),
with a per-value cap as a secondary guard. Pin it in
`with-generation-environment` (`src/backends/check-it.lisp:102`) so generation
stays a function of (spec, seed, backend) (§15). **Q1.**

### 4.4 Failure condition and the required distinction

- `generator-unavailable` — **no strategy** (static, authoring-time).
- `generation-budget-exhausted` — **a strategy ran and spent its budget**
  (dynamic). Its report and message must say that the budget, not
  satisfiability, was the limit.

Recommended shape: `generation-budget-exhausted` **inherits
`generator-unavailable`** (slots `spec`, `reason`, plus `attempts`,
`rejections`, `budget`). Existing `(handler-case … (generator-unavailable …))`
sites keep working; a caller that must distinguish handles the subclass. The
alternative — a `:cause` slot on `generator-unavailable` — is lighter but leaves
the distinction as data rather than type. **Q2.**

### 4.5 Reporting

Per §72.1 the result must carry the generation rejection count separately from
the precondition rejection count.

- New `generation-report-p` in `src/generator.lisp`, mirroring `shrink-report-p`
  (`:115-125`): `(:attempts N :rejections N :budget B :termination KEYWORD)`
  with `:termination ∈ {:completed, :budget-exhausted}`, validated in
  `validate-backend-outcome`.
- Backend outcome gains `:generation-report`; `property-result` gains a slot and
  a `property-result-generation-report` reader, defaulting to `:not-collected`
  exactly like `:shrink-report` (`src/property-runner.lisp:57`); `result-data`
  gains the key.
- `:rejected` (preconditions) and the report's `:rejections` stay distinct.
- `sample` returns the report as a **second value** — non-breaking, since the
  primary value is unchanged.
- Capability stays `:available` = construction success (§38.1); the filter does
  not change what `backend-capabilities` may claim.

### 4.6 Reproducibility

The filter draws from the run's seeded state, so a given (spec, seed, backend)
still determines the value sequence. The recorded attempt/rejection counts make
a replay's cost observable, and are part of why §15 keeps holding.

## 5. Non-goals

- No constraint solver, propagation, or automatic field-level narrowing.
- No product/intersection of two structured sources.
- No dependent/argument-reference DSL; `:args-generator` is untouched and
  remains the escape hatch for correlated arguments. This design *reduces* how
  often it must be hand-written, it does not replace it.
- Custom-generator output is still not re-validated (§11).
- **Nested field predicates** (`plist (:optional (:x (satisfies p)))`) stay
  refused at compile time. That is a field-level composability gap, distinct
  from the AND-level one, and is not addressed here.

## 6. Test plan

- The `period` example samples; every value satisfies the whole spec; the same
  seed replays identically.
- `and-folds-its-constraints-into-one-generator` and
  `and-folds-through-references-and-nested-ands` keep passing.
- No source (`(and (satisfies oddp) (satisfies plusp))`) still signals
  `generator-unavailable`.
- A generatable but unsatisfiable filter (`(and (member 1) (satisfies evenp))`)
  signals `generation-budget-exhausted` with attempts/rejections/budget, and its
  report says the budget was exhausted, not that the spec is empty; a
  `handler-case` for `generator-unavailable` still catches it.
- A satisfiable low-acceptance spec still succeeds within the recommended budget.
- Shrinking through the filter yields only spec-valid values and preserves
  failure identity.
- The generation report appears on a passing run, a failing run, and `sample`.
- Capability: constructed → `:available`, absent source → `:unavailable`.
- Cold `(asdf:compile-system :cl-spec :force :all)` and the full suite.

## 7. Specification amendments (proposed text)

- **§9.2 `:809-810`** — replace 「制約solverやAND生成の一般化は導入しない」 with:
  「制約solverは導入しない。ANDは生成可能な連言を1つ選んで生成元とし、残りの連言を
  有限予算のfilterで課す。予算切れは充足不能の判定ではなく、この生成戦略で値を
  得られなかったこととして理由と件数を報告する。」
- **§9.3 `:871`** — add the same sentence.
- **§73.4 `:4246`** — qualify: 「無制限の再生成は採用しない。ANDは有限予算の
  filterまでとし、上限に達したら`generation-budget-exhausted`で件数を報告する。」
- **§10 `:1002-1017`** — add "AND with at least one generatable conjunct".
- **§14 `:1240-1259`** — add the `:generation-report` key and its validation.
- **§38.1 `:2546-2559`** — add `:generation-report` to `result-data`.
- **§0.2 `:75`** — update the AND generation row.
- **§73.5** — record the item, budget default, and acceptance criteria.

## 8. Staging

1. **Slice 1 — mechanism**: source selection (§4.1), bounded filter (§4.2),
   budget (§4.3), condition (§4.4), tests. Amends §9.2/§9.3/§73.4/§10.
2. **Slice 2 — reporting**: generation report through outcome, result,
   `result-data`, `sample`; amends §14/§38.1/§72.1.
3. **Slice 3 — follow-ups**: option-recorded budget and a whole-run cap once the
   §48/§72.4 budget API is settled; possibly allowing a conjunct's own custom
   generator as source (Q3).

## 9. Open questions for the maintainer

- **Q1** Budget scope (per request vs per value) and the default (100, matching
  the only existing precedent, vs a larger value that makes ≥1% acceptance
  reliable).
- **Q2** `generation-budget-exhausted` as a subclass of `generator-unavailable`,
  or a `:cause` slot on `generator-unavailable`?
- **Q3** Keep §73.4's refusal of a conjunct's own custom generator, or let a
  reference to a spec that owns a `(:generator NAME)` (e.g. an `object-of`) be
  the source? The latter needs a §73.4 amendment and is the natural way to
  generate an `object-of` inside an AND.
- **Q4** Is the generation report part of the first PR, or a follow-on?
- **Q5** `sample` returning the report as a second value — acceptable, or a
  separate accessor?
