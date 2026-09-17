# Working with the executable self-specifications

`cl-spec/specs` is an optional bundle of executable contracts and semantic laws
about cl-spec's own public API. This guide shows how to load it in a fresh image,
keep it away from the registry under test, find the contract and properties that
describe a symbol, run one check or all of them, and read the structured result.
It also points at the fault-injection and repair-comparison procedure in
`eval/README.md`.

Everything named here exists in the current implementation; the `describe-*`
printers are still stubs and no convenience API is invented for this guide.

## 1. Load the bundle in a fresh image

The core system never loads the bundle, check-it or Rove. Load the generator
backend first (it is what executes generated checks), then the bundle:

```lisp
(asdf:load-system "cl-spec/check-it")   ; installs the generator backend
(asdf:load-system "cl-spec/specs")      ; registers the self-specifications
```

Loading `cl-spec/specs` registers the bundle in the currently bound
`cl-spec:*registry*` and runs nothing. If you clear the registry or bind a fresh
one, register again:

```lisp
(cl-spec/specs:register-specifications)
```

Re-running it replaces the bundle's entries by name; it does not duplicate a
name or an index entry. Loading the core `cl-spec` system alone does not pull in
the bundle, check-it or Rove.

## 2. Keep the bundle's registry separate from the registry under test

A contract that exercises a registry-mutating API must not share its registry
with the definitions being checked. Bind a fresh registry, register the bundle
there, and pass the registry under test explicitly where the API takes one:

```lisp
(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
  (cl-spec/specs:register-specifications)
  (cl-spec:check-function 'cl-spec:validate :trials 50 :seed 42))
```

`cl-spec/registry-register-property`'s self-contract goes one step further: its
generator builds a fresh target registry for every draw, pre-registers a sentinel
property, and the `:capture`/`:state-post` forms read only the public readers.
The target API changes that per-trial registry, never `cl-spec:*registry*`.
Introspection and state observation are read-only; they never prepare or restore
state.

## 3. Find the contract and properties for a symbol

```lisp
(cl-spec:find-function-spec 'cl-spec:validate)   ; the contract, or two values
(cl-spec:properties-for 'cl-spec:validate)       ; sorted property names
(cl-spec:function-spec-data 'cl-spec:validate)   ; declaration projection
(cl-spec:property-data 'cl-spec/specs::validate-cases-classify-admitted-and-refused)
```

`cl-spec:function-spec-data` returns a v1 envelope plus the contract's clauses.
A case-carrying contract adds `:case-selection :exclusive` and an ordered
`:cases`; a contract that declares `:capture` adds an ordered `:capture` of
`(:name NAME :form FORM)`; a contract or case that declares `:state-post` adds
its forms. A contract that declares none of these omits the keys, so a consumer
sees no fabricated clause. Producing the projection runs no guard, capture,
state-post or target.

`cl-spec/specs:contract-names` and `cl-spec/specs:property-names` are the
bundle's declared execution set. In a fresh registry that just ran
`register-specifications`, each list is exactly the corresponding registry
listing (`cl-spec:list-function-specs`, `cl-spec:list-properties`), with no
duplicates.

## 4. Run one check or all of them

Individual contract (generated trials):

```lisp
(cl-spec:check-function 'cl-spec:validate :trials 50 :seed 42)
```

Individual property:

```lisp
(cl-spec:run-property 'cl-spec/specs::sample-reports-its-generation-request :seed 42)
```

Bulk, over the bundle's declared set:

```lisp
(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
  (cl-spec/specs:register-specifications)
  (dolist (name (cl-spec/specs:contract-names))
    (format t "~A ~A~%" name
            (cl-spec:property-result-status
             (cl-spec:check-function name :trials 50 :seed 42))))
  (dolist (name (cl-spec/specs:property-names))
    (format t "~A ~A~%" name
            (cl-spec:property-result-status
             (cl-spec:run-property name :seed 42)))))
```

A property's trial count comes from its own `:trials` table under the selected
profile (`:normal` by default), not from a shared constant. Read
`(cl-spec:property-trials (cl-spec:find-property name))` for the declared budget
and compare the run's `cl-spec:property-result-trials` against it. `:skipped`,
`:pending`, generation exhaustion and an all-rejected run are not passes.

The Rove suites `cl-spec/tests/self-specs-test`,
`cl-spec/tests/self-properties-test` and
`cl-spec/tests/self-api-contracts-test` run the bundle through the normal test
path; `tests/self-api-contracts-test.lisp` adds the concrete boundary and
negative-data expectations.

## 5. Read a run

For a contract run:

```lisp
(let ((result (cl-spec:check-function 'cl-spec:registry-register-property
                                      :trials 20 :seed 42)))
  (cl-spec:property-result-status result)                 ; :passed :failed :error ...
  (cl-spec:function-check-result-case-report result)      ; per-case counts
  (cl-spec:property-result-failure-phase result)          ; :case-selection :capture :state-post ...
  (cl-spec:property-result-failure-reason result)
  (getf (cl-spec:result-data result) :failure))           ; structured observation
```

- The case report lists the declared cases in order, the target calls, passed
  and failed counts, `:case-selection-errors`, `:capture-errors` and
  `:never-called`. A backend that did not report leaves the report
  `:not-collected`, which is different from measured zeros.
- `:failure-phase` says where the trial stopped: `:case-selection` before the
  target, `:capture` before the target, `:state-post` after a passed outcome.
- `:failure :state` carries `:capture` (`:status`, `:declared`, `:values` as a
  `(NAME . VALUE)` alist, optional `:error`) and `:state-post` (`:status`,
  `:reason`, `:case`, `:index`, `:form`, `:condition-type`). A captured NIL is
  an entry such as `(NAME . NIL)`; a binding whose form never ran is absent from
  `:values` but still listed in `:declared`.
- A capture value that is or contains an opaque object is projected as
  `(:unavailable :reason :opaque-value :type TYPE)` rather than as frozen
  evidence. Capture observes a value and does not copy or restore it.

## 6. What the state-observing self-contracts do not do

`cl-spec:registry-register-property`'s contract is a sequential-execution
contract. It does not claim atomicity under concurrency, and it does not claim
rollback from an arbitrary backend error. Like every `:capture`/`:state-post`
contract in this version it is **not** shrunk (its shrink report says
`:state-restoration-unavailable`), a past result cannot be replayed onto it
(`unsupported-stateful-operation`), and it cannot be saved as a counterexample
artifact (`invalid-counterexample-artifact` with a stateful reason). Case-carrying
contracts refuse runtime instrumentation. Do not work around these limits to run
a self-specification.

## 7. Finite corpus, public domain and unverified scope

The `validate` contract draws admitted/refused inputs from a small finite
`*validate-corpus*` and the boundary test passes an explicit sequence through
`*scripted-validate-inputs*`. That corpus is a sample that reaches both named
cases; it is not the whole DSL and not the whole value domain the public API
accepts. The registry write contract goes further and **declares** its input
domain as exactly the finite scenario set `registration-scenario` produces,
through `registration-scenario-targets-p` and `registration-scenario-tags-p` in
its `:args`: its state-post names those scenarios' fixed target and tag symbols,
so a valid index list outside the scenarios is outside the contract, not a
counterexample to it. When a check passes, it says the sampled inputs passed; it
does not say the whole domain was verified. The small-domain oracle in
`tests/self-api-contracts-test.lisp` states verdicts by hand from `integerp`,
`stringp`, `eql` and `member` so that `validp` and `validate` are not their own
authority.

## 8. Fault detection and repair comparison

`eval/run-detection.sh` applies one limited fault at a time to a throwaway
source snapshot, runs the fixed self-specification and an evaluator-owned
acceptance check in fresh processes, and requires the correct baseline to pass
and the faulty copy to fail both. It never modifies the checkout and never uses
git to restore anything. The three tasks, their allowed paths, the fixed-file
hashes and the fresh-process procedure are documented in `eval/README.md`;
`eval/run-acceptance.sh` judges a candidate work copy.

The comparison between an agent that may use the fixed self-specifications
(condition B) and one that may not (condition A) is **prepared but not run**.
No model was invoked, so no efficiency or quality improvement is reported. The
record shape in `eval/record-template.json` records unmeasured values as
`null`, never `0`, and marks `comparison_status` `not-run` until both conditions
have actually been executed. One comparison limitation is already known:
condition A must also drop `api-docs.lisp` and the instrumentation-status
integration test because they import the bundle, so the two conditions differ by
more than self-spec availability; `eval/README.md` records this explicitly.

## 9. Spec → API → property → test → eval task

| Self-specification | Public API | Related property | Test | Eval task |
|---|---|---|---|---|
| `:conforming`/`:refused` cases | `validate` | `validate-cases-classify-admitted-and-refused`, `validation-preserves-values-or-explains-refusal` | `self-specs-test`, `self-api-contracts-test` | — |
| `:capture`/`:state-post` registration contract | `registry-register-property` | `registration-replacement-preserves-unrelated-indexes` | `self-specs-test`, `self-api-contracts-test` | `registry-stale-index` |
| Function Spec projection | `function-spec-data` | `function-spec-projection-retains-declared-state` | `self-specs-test`, `self-api-contracts-test` | `function-spec-capture-drop` |
| Result projection | `result-data` | `result-projection-retains-state-evidence` | `self-specs-test`, `self-api-contracts-test` | `result-state-evidence-drop` |

What is not covered by the bundle today: every keyword-option combination, custom
registry or backend implementations, a malformed `defspec` form itself, the whole
shrink-candidate search, and the `describe-*` printers.
