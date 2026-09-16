# State observation walkthrough

This guide runs cl-spec's explicit pre-observation (`:capture`) and post-run
state constraints (`:state-post`) end to end on a tiny account model. The source
of truth is the executable file
[`examples/stateful-withdraw.lisp`](../../examples/stateful-withdraw.lisp); every
excerpt here is a call into that file, and the normal test suite runs the same
entry points in `tests/stateful-withdraw-example-test.lisp`, so a change that
breaks this walkthrough fails `rove cl-spec.asd`.

For the normative contract see §17.3 in the
[specification](../cl-spec-specification-v0.2-draft.md); the design record is
[`docs/superpowers/specs/2026-09-17-function-spec-state-observation-design.md`](../superpowers/specs/2026-09-17-function-spec-state-observation-design.md).

## Running it from a fresh image

Loading `cl-spec` alone does not load this example or the generator backend. Ask
for the example system explicitly: it is an ASDF package-inferred subsystem whose
`defpackage` declares the check-it generator backend, so this one form also
installs the backend the checker needs.

```lisp
(asdf:load-system "cl-spec/examples/stateful-withdraw")

(defparameter *registry*
  (cl-spec/examples/stateful-withdraw:make-example-registry))
(cl-spec/examples/stateful-withdraw:register-example! *registry*)
```

`make-example-registry` returns a fresh registry and `register-example!` is the
only function that registers anything, so loading the example file neither draws
a value nor changes `cl-spec:*registry*`. Every demo below takes the registry
explicitly for the same reason.

## The model

One operation, two required behaviours inside the region its common `:PRE`
admits, with the state observed before the call:

```lisp
(cl-spec:defspec-function withdraw!
  (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
  (:args-generator scripted-accounts)
  (:capture
    (balance-before (account-balance account))
    (id-before (account-id account)))
  (:cases
    (:sufficient-funds
      (:when (<= amount balance-before))
      (:returns (satisfies listp))
      (:state-post (= (account-balance account) (- balance-before amount))
                   (eql (account-id account) id-before)))
    (:insufficient-funds
      (:when (> amount balance-before))
      (:signals (type insufficient-funds))
      (:state-post (= (account-balance account) balance-before)
                   (eql (account-id account) id-before)))))
```

`withdraw-account` is a small structure whose balance and identifier are
integers, and `insufficient-funds` is an ordinary `error` subtype defined by the
example. `:capture` runs after the common `:PRE` admits an input and before case
selection; each `:state-post` runs only after that case's outcome contract
passed. A case cannot declare its own arguments, precondition, `:capture` or
nested `:cases`.

## Evaluation order

One ordinary trial proceeds in this order:

1. Argument-schema validation and binding.
2. The common `:PRE`. A refusal is a `:REJECTED` trial; nothing else runs.
3. `:CAPTURE`, each binding once, in declaration order.
4. Exclusive case selection, when the contract declares `:CASES`.
5. The target is called exactly once, producing one raw outcome.
6. The existing `:RETURNS` / `:SIGNALS` / `:POST` / `:POST-VALUES`
   classification of that outcome.
7. Only when step 6 was `:PASSED`, the selected case's `:STATE-POST`.
8. Final classification and evidence.

The capture bindings are `let*`-like: a later form sees the arguments and the
capture values declared before it. Only the primary value is bound, so a
captured `NIL` is a value rather than an absence. Capture is not a target
argument: the argument schema, the generator and the actual call are unchanged.

## 1. A correct update and a correct refusal

The example drives its inputs with a scripted generator whose every draw builds
a **fresh** account, so a trial never starts from the object an earlier trial
mutated:

```lisp
(cl-spec/examples/stateful-withdraw:demo-successful-withdrawal *registry*)
;; => (:STATUS :PASSED :FAILURE-PHASE NIL :TARGET-CALLS 2 :FAILURE-REASON NIL
;;     :SIGNATURE NIL :STATE NIL :SHRINK-TERMINATION NIL
;;     :CASES ((:NAME :SUFFICIENT-FUNDS ... :CALLED 1 :PASSED 1 :FAILED 0 :ERROR 0)
;;             (:NAME :INSUFFICIENT-FUNDS ... :CALLED 1 :PASSED 1 :FAILED 0 :ERROR 0))
;;     :CAPTURE-ERRORS 0 :NEVER-CALLED NIL)
```

The first input fits and the second does not. A trial whose expected error was
signalled exactly as required proceeds to state-post and, when the balance was
left alone, counts as a `:PASSED` trial of its case.

## 2. A target that forgets the update

`withdraw-without-recording!` answers the right receipt but leaves the balance
alone. The outcome contract passes; the state relation does not:

```lisp
(cl-spec/examples/stateful-withdraw:demo-missing-update *registry*)
;; => (:STATUS :FAILED :FAILURE-PHASE :STATE-POST :TARGET-CALLS 1
;;     :FAILURE-REASON :STATE-POSTCONDITION
;;     :SIGNATURE (:CASE :SUFFICIENT-FUNDS :STATE-POSTCONDITION 0)
;;     :STATE (:CAPTURE (:STATUS :COMPLETED :DECLARED (BALANCE-BEFORE ID-BEFORE)
;;                       :VALUES ((BALANCE-BEFORE . 30) (ID-BEFORE . 7)) :ERROR NIL)
;;             :STATE-POST (:STATUS :VIOLATION :REASON NIL :CASE :SUFFICIENT-FUNDS
;;                         :INDEX 0 :FORM (= (ACCOUNT-BALANCE ACCOUNT) ...)
;;                         :CONDITION-TYPE NIL))
;;     :SHRINK-TERMINATION :STATE-RESTORATION-UNAVAILABLE ...)
```

The result carries the failing form's zero-based position in the failure
identity, the values that completed before it, and the writing of the form. The
phase is `:STATE-POST`, which is a **post-target** phase: the target was called,
so the case report counts the call and the selected case keeps the failure.

## 3. The right error after a partial update

`withdraw-then-refuse!` changes the balance and then signals the expected error.

```lisp
(cl-spec/examples/stateful-withdraw:demo-refusal-that-mutated *registry*)
;; => (:STATUS :FAILED :FAILURE-PHASE :STATE-POST :TARGET-CALLS 1
;;     :FAILURE-REASON :STATE-POSTCONDITION
;;     :SIGNATURE (:CASE :INSUFFICIENT-FUNDS :STATE-POSTCONDITION 0) ...)
```

The raw outcome still holds the `INSUFFICIENT-FUNDS` condition the target
signalled, but the final result is `:FAILED`, not `:PASSED`: signalling the
required error does not excuse the state change. The calling case is counted as
`:FAILED`, not `:PASSED`, and the expected-error condition is retained in the
trial's outcome evidence.

## 4. An unrelated declared value changing

`withdraw-renumbered!` withdraws correctly but also changes the identifier.

```lisp
(cl-spec/examples/stateful-withdraw:demo-renumbered-account *registry*)
;; => (:STATUS :FAILED :FAILURE-PHASE :STATE-POST
;;     :SIGNATURE (:CASE :SUFFICIENT-FUNDS :STATE-POSTCONDITION 1) ...)
```

Only **declared** observations are checked. The contract opted into observing
`(account-id account)`, so changing it is a violation; a field the author did not
declare is not automatically required to be unchanged, and this feature does not
claim otherwise.

## 5. A violation and a verification error are different

`withdraw-asserted!` uses a state-post form that calls a helper which signals
`balance-verification-failed`:

```lisp
(cl-spec/examples/stateful-withdraw:demo-verification-error *registry*)
;; => (:STATUS :ERROR :FAILURE-PHASE :STATE-POST
;;     :FAILURE-REASON :CONTRACT-ERROR
;;     :STATE (:STATE-POST (:STATUS :ERROR :INDEX 0
;;                         :CONDITION-TYPE BALANCE-VERIFICATION-FAILED ...)) ...)
```

A predicate that returns `NIL` is a `:STATE-POSTCONDITION` violation
(`:FAILED`). A form that signals is a `:CONTRACT-ERROR` (`:ERROR`) carrying the
original condition and the failing position. Neither is ever accepted as the
target's expected error: a condition raised by contract-side code at a capture
or state-post position is classified by that position, not by its type.

## 6. What the first version does not do

```lisp
(cl-spec/examples/stateful-withdraw:demo-limits *registry*)
;; => (:SHRINK-TERMINATION :STATE-RESTORATION-UNAVAILABLE
;;     :STATE-CONSTRAINTS :PRESENT
;;     :ARTIFACT :STATEFUL-CONTRACT-UNSUPPORTED
;;     :REPLAY :STATE-RESTORATION-UNAVAILABLE)
```

A contract that declares `:CAPTURE` or `:STATE-POST` observes state but never
restores it, so this version does not:

- shrink it — no candidate is re-run against the same mutable object, and the
  shrink report says `:STATE-RESTORATION-UNAVAILABLE`. The reason is the missing
  restoration contract, **not** that the target was never called (a capture or
  case-selection failure keeps `:NOT-A-TARGET-FAILURE`, which is accurate for
  it).
- replay a past result — `check-function` with a result as `:SEED` is refused
  with `unsupported-stateful-operation` before the target is called. The
  function-check adapter cannot be replayed through the property runner either:
  `run-property` with a `property-result` as `:SEED`, and `replay-property` with
  one, are refused the same way before the result is turned into an integer seed,
  so generation, capture and the target all run zero extra times.
  `recheck-counterexample` refuses a state-observing resolved definition with
  `:STATEFUL-CONTRACT-UNSUPPORTED`.
- persist a counterexample artifact — `make-counterexample-artifact` refuses
  with `:STATEFUL-CONTRACT-UNSUPPORTED`, read from the declaration captured in
  the result rather than from the current registry.
- instrument the function — install and refresh refuse with
  `:STATE-CONSTRAINTS-UNSUPPORTED` before replacing the fdefinition.

A **new** run with an integer seed is allowed. The seed reproduces a random
stream; it does not restore external state or a mutable object's initial
contents, so the author supplies the fresh initial state. This is a scope limit,
not a claim that state constraints are inherently unreproducible: a future
explicit state-construction protocol can lift it.

## Evidence

A trial of a state-observing contract records state evidence on its
observation (`trial-observation-state`), projected into `result-data` under
`:state`:

```text
(:capture (:status :not-evaluated | :completed | :error
           :declared (NAME ...)
           :values ((NAME . VALUE) ...)          ; only completed bindings
           :error (:binding NAME :index I :condition-type T))
 :state-post (:status :not-evaluated | :passed | :violation | :error
             :reason REASON                      ; when :not-evaluated
             :case NAME | NIL
             :index I :form FORM                 ; when violation or error
             :condition-type T))                 ; when error
```

`:reason` for a `:NOT-EVALUATED` state-post is one of `:PRECONDITION-REJECTED`,
`:CAPTURE-FAILED`, `:CASE-SELECTION-FAILED`, `:OUTCOME-FAILED`. `:values` is an
ordered `((NAME . VALUE) ...)` alist, so a value is read with `assoc`, and a
`(NAME . NIL)` entry means the capture returned `NIL` rather than that it did not
run. A capture that failed halfway never shows a later binding as obtained.

`:state-post` appears when the contract declares a clause — the selected case's,
or, before a case is selected, the top-level clause or any case's. When no case
was selected its `:case` is `NIL` and its `:reason` is `:CAPTURE-FAILED` or
`:CASE-SELECTION-FAILED`, so "no state-post declared" and "declared but stopped
before selection" stay distinct. A contract that declares neither clause records
no state evidence at all, so a featureless run's projection is unchanged.

Capture values are projected through the existing evidence snapshot: a cons or
array as its copy, a self-contained atom as itself. An object the snapshot returns
by identity — a CLOS instance, structure, hash table, function — is reported as
`(:unavailable :reason :opaque-value :type TYPE)`, an explicit unprojectable
placeholder, because a live reference would read like frozen evidence. The
evaluation path still passes the original value to later capture forms, guards and
predicates; this is a report projection, not a deep copy. Nothing is re-executed
to build this data, and the state-post violation's `:kind`/`:case`/`:index`/`:form`
explanation is readable from `trial-observation-explanation`,
`property-result-explanation`, `function-check-result-explanation` and
`result-data`'s `:failure` alike.

## Failure identities

| Where it happened | status / reason | failure phase | identity |
|---|---|---|---|
| capture form signals | `:error` / `:contract-error` | `:capture` | `(:capture I :contract-error TYPE)` |
| case selection fails | existing | `:case-selection` | existing |
| outcome contract fails | existing | existing (`NIL`) | existing |
| state-post returns `NIL` | `:failed` / `:state-postcondition` | `:state-post` | `(:state-postcondition I)`, or `(:case NAME :state-postcondition I)` |
| state-post signals | `:error` / `:contract-error` | `:state-post` | `(:state-post I :contract-error TYPE)`, or case-wrapped |

A state-post violation is a failure kind separate from `:RETURN-SPEC` and
`:POSTCONDITION`. Concrete values and variable error messages never enter an
identity.

## Reading the report

`FUNCTION-CHECK-RESULT-CASE-REPORT` and `RESULT-DATA`'s `:CASE-REPORT` return
the case report with one added counter:

```text
(:selection :exclusive :unit :normal-trials
 :declared-cases (NAME ...)
 :cases ((:name NAME :documentation S
          :called N :passed N :failed N :error N) ...)
 :case-selection-errors N
 :capture-errors N
 :never-called (NAME ...))
```

A capture failure increases no case's `:CALLED` and is not a case-selection
error; it counts in `:CAPTURE-ERRORS`. A state-post violation increases the
calling case's `:CALLED` and `:FAILED`; a state-post evaluation error increases
its `:CALLED` and `:ERROR`. Each trial is counted once, from its final
classification. Because capture and selection errors call no target,
`TRIALS - REJECTED` is not claimed to equal target calls.

## What this version does and does not do

| Area | Behaviour | Main limit |
|---|---|---|
| `:capture` | ordered `(NAME FORM)` bindings, `let*` visibility, one primary value | top-level only; no per-case or nested capture; no automatic deep copy |
| `:state-post` | one clause, case-less or per case, after a passed outcome | no common inheritance, no `:SIGNALS` + `:POST` relaxation |
| Target calls | once per trial; capture and selection failures call it zero times | no `:FINALLY`-style state check after every abnormal exit |
| Detects | declared observations changing, expected error after mutation, unrelated declared value changing | not all undeclared fields, not atomicity, concurrency, crash safety or absent I/O |
| Evidence | capture progress, state-post status and position, raw outcome | reuses the existing snapshot; an opaque value is reported as an explicit unprojectable placeholder, not frozen |
| Shrinking | disabled, `:STATE-RESTORATION-UNAVAILABLE` | not restored, so no candidate is re-run |
| Replay | result-as-seed refused; integer seed starts a new run | initial state is the author's responsibility |
| Artifact | refused with `:STATEFUL-CONTRACT-UNSUPPORTED` | no object codec or restoration adapter |
| Instrumentation | refused with `:STATE-CONSTRAINTS-UNSUPPORTED` | featureless instrumentation unchanged |

Guarantee boundaries:

- Capture forms, guards, post predicates, state-post predicates and readers must
  not modify their input or anything reachable from them. The target's intended
  state change is allowed. cl-spec neither detects nor restores a violation.
- A capture variable holds the value the form returned. `(:capture (before
  account))` does **not** preserve the account's earlier contents; an author who
  needs a pre-call representation reads a value out or copies the part that
  matters.
- Equal before and after is not a proof that nothing changed during the call.
  Intermediate states, concurrent execution, crash atomicity and absent external
  notifications or I/O are not guaranteed.
- `:CAPTURE` and `:STATE-POST` are new syntax; a contract without them keeps its
  syntax, meaning, failure signatures, projection and digest bytes. The existing
  `:SIGNALS` / `:POST` exclusivity and the multiple-value rules are unchanged.
- Not in this version: automatic deep copy or snapshotting of arbitrary objects,
  CLOS/hash-table traversal, mutation detection, rollback, fixtures or reset
  protocols, state-machine PBT, concurrency, a generic diagnostic DSL, and new
  MCP tools.

## Where to read more

- [`README.md`](../../README.md) — entry point, short examples and limits.
- [`docs/cl-spec-specification-v0.2-draft.md`](../cl-spec-specification-v0.2-draft.md)
  — §17, §17.1, §17.2 and §17.3.
- [`docs/api/cl-spec.md`](../api/cl-spec.md) — generated from public docstrings.
- [`examples/stateful-withdraw.lisp`](../../examples/stateful-withdraw.lisp) —
  the code these excerpts call.
