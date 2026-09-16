# Function Spec cases walkthrough

This guide runs cl-spec's named per-condition Function Spec cases end to end on a
small pure model. The source of truth is the executable file
[`examples/function-spec-cases.lisp`](../../examples/function-spec-cases.lisp);
every excerpt here is a call into that file, and the normal test suite runs the
same entry points in `tests/function-spec-cases-example-test.lisp`, so a change
that breaks this walkthrough fails `rove cl-spec.asd`.

For the normative contract see §17.2 and the case-selection implementation
addendum in the [specification](../cl-spec-specification-v0.2-draft.md); the
design record is
[`docs/superpowers/specs/2026-09-16-function-spec-cases-design.md`](../superpowers/specs/2026-09-16-function-spec-cases-design.md).

## Running it from a fresh image

Loading `cl-spec` alone does not load this example or the generator backend. Ask
for the example system explicitly: it is an ASDF package-inferred subsystem whose
`defpackage` declares the check-it generator backend, so this one form also
installs the backend the checker needs.

```lisp
(asdf:load-system "cl-spec/examples/function-spec-cases")

(defparameter *registry*
  (cl-spec/examples/function-spec-cases:make-example-registry))
(cl-spec/examples/function-spec-cases:register-example! *registry*)
```

`make-example-registry` returns a fresh registry and `register-example!` is the
only function that registers anything, so loading the example file neither draws
a value nor changes `cl-spec:*registry*`. Every demo below takes the registry
explicitly for the same reason.

## The model

One function, two required behaviours inside the region its common `:PRE`
admits:

```lisp
(cl-spec:defspec-function remaining-balance
  "Require the remainder when the balance suffices, and the named error when it does not."
  (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
  (:args-generator scripted-arguments)
  (:cases
    (:sufficient-funds
      "The amount fits: return the remaining balance."
      (:when (<= amount balance))
      (:returns (range integer 0 *))
      (:post (= result (- balance amount))))
    (:insufficient-funds
      "The amount does not fit: signal the named error."
      (:when (> amount balance))
      (:signals (type insufficient-funds)))))
```

`insufficient-funds` is an ordinary `error` subtype defined by the example. The
common `:args`, `:args-generator` and `:pre` stay on the contract; each case
carries only its condition and its required outcome. A case cannot declare its
own arguments or precondition, nest `:cases`, or use `:else` or a priority.

### Selection is exclusive

After the argument schema and the common `:PRE` admit an input, **every** case's
`:when` runs in declaration order and exactly one must be true. Evaluation does
not stop at the first true guard, because a later guard error would then be
hidden. `:when t` is an ordinary always-true form, not an implicit `:else`, and
`:when nil` is an ordinary never-true one.

Zero matches, several matches, and a guard that signals are contract-side
**case-selection errors**. The target is not called at all, and the result is
`:ERROR` / `:CONTRACT-ERROR` with `:FAILURE-PHASE :CASE-SELECTION` and a
structured explanation. A `SPEC-VIOLATION` from a guard is a selection error too;
only the common `:PRE` treats that as a refusal.

## 1. One contract, a return case and an expected-error case

The example drives its inputs with a scripted argument generator
(`:args-generator scripted-arguments`), so both cases are exercised
deterministically instead of hoping a seed samples them:

```lisp
(cl-spec/examples/function-spec-cases:demo-both-outcomes *registry*)
;; => (:STATUS :PASSED :FAILURE-PHASE NIL :TARGET-CALLS 2 :CASE NIL :FAILURE-REASON NIL
;;     :SIGNATURE NIL :SELECTION-ERROR NIL
;;     :CASES ((:NAME :SUFFICIENT-FUNDS ... :CALLED 1 :PASSED 1 :FAILED 0 :ERROR 0)
;;             (:NAME :INSUFFICIENT-FUNDS ... :CALLED 1 :PASSED 1 :FAILED 0 :ERROR 0))
;;     :NEVER-CALLED NIL :CASE-SELECTION-ERRORS 0)
```

A trial whose expected error was signalled exactly as required counts as a
`:PASSED` trial of its case, and `:TARGET-CALLS` is 2: each admitted trial called
the target once.

## 2. A wrong implementation, attributed to its case

The example's `broken-remaining-balance` answers `0` instead of signalling.

```lisp
(cl-spec/examples/function-spec-cases:demo-wrong-implementation *registry*)
;; => (:STATUS :FAILED :FAILURE-PHASE NIL :TARGET-CALLS 1
;;     :CASE :INSUFFICIENT-FUNDS :FAILURE-REASON :MISSING-CONDITION
;;     :SIGNATURE (:CASE :INSUFFICIENT-FUNDS :MISSING-CONDITION)
;;     :SELECTION-ERROR NIL ... :NEVER-CALLED (:SUFFICIENT-FUNDS))
```

The failure is a **target bug**, so it is reported as one: status `:FAILED`, no
`:FAILURE-PHASE`, and a counterexample from the trial that was actually called.
The case name is part of the failure identity, so shrinking, replay and a saved
counterexample artifact all stay inside `:insufficient-funds`; a reduction that
crossed into another case is not accepted as this failure's reduction.

## 3. Duplicate and missing conditions are contract bugs

Two other contracts in the example have conditions that are not exclusive.

```lisp
(cl-spec/examples/function-spec-cases:demo-selection-errors *registry*)
;; => (:AMBIGUOUS (:STATUS :ERROR :FAILURE-PHASE :CASE-SELECTION :TARGET-CALLS 0
;;                 :CASE NIL :FAILURE-REASON :CONTRACT-ERROR
;;                 :SIGNATURE (:CASE-SELECTION :AMBIGUOUS-CASE)
;;                 :SELECTION-ERROR :AMBIGUOUS-CASE ... :CASE-SELECTION-ERRORS 1)
;;     :MISSING   (:STATUS :ERROR :FAILURE-PHASE :CASE-SELECTION :TARGET-CALLS 0
;;                 :CASE NIL :FAILURE-REASON :CONTRACT-ERROR
;;                 :SIGNATURE (:CASE-SELECTION :NO-MATCHING-CASE)
;;                 :SELECTION-ERROR :NO-MATCHING-CASE ... :CASE-SELECTION-ERRORS 1))
```

Both runs called the target **zero** times, counted no case, and are **not**
precondition rejections (`PROPERTY-RESULT-REJECTED` stays 0). The structured
explanation names the error and, for the ambiguous case, the case names that
matched; a guard error also carries the offending case and the original
condition. These runs are never shrunk and never persisted as target
counterexamples (`make-counterexample-artifact` refuses with
`:CASE-SELECTION-FAILURE`).

The three kinds are, in the explanation's `:CASE-ERROR` and in the signature:

| Kind | Meaning | Signature |
|---|---|---|
| `:NO-MATCHING-CASE` | no guard is true | `(:case-selection :no-matching-case)` |
| `:AMBIGUOUS-CASE` | two or more guards are true | `(:case-selection :ambiguous-case)` |
| `:CASE-GUARD-ERROR` | a guard signalled | `(:case-selection :case-guard-error NAME)` |

`:FAILURE-PHASE` is the phase the classifier recorded where selection failed; it
is never inferred from a condition's class. A target that signals the public
`case-selection-error` condition under any contract is therefore an ordinary
target failure whose evidence may be shrunk and persisted, not a selection error.

A solver is not consulted: exclusivity and coverage are checked for the inputs
that were actually generated, not proved for every input.

## 4. A passing status with unchecked cases

```lisp
(cl-spec/examples/function-spec-cases:demo-unchecked-cases *registry*)
;; => (:STATUS :PASSED ... :TARGET-CALLS 1
;;     :CASES (..., (:NAME :INSUFFICIENT-FUNDS ... :CALLED 0 ...))
;;     :NEVER-CALLED (:INSUFFICIENT-FUNDS) :CASE-SELECTION-ERRORS 0)
```

`:PASSED` means no violation was observed in the trials that ran. It does not
mean every case ran. `:NEVER-CALLED` lists the declared cases no trial reached,
and a case reached once is still not proof of exhaustive coverage of that case.
This version adds no per-case minimum trial count and does not fail a run for
coverage; to reach a rare case, hand the contract a controlled
`:args-generator` (as the example does) or generate the inputs explicitly.

## Reading the report

`FUNCTION-CHECK-RESULT-CASE-REPORT` and `RESULT-DATA`'s `:CASE-REPORT` return:

```text
(:selection :exclusive :unit :normal-trials
 :declared-cases (NAME ...)
 :cases ((:name NAME :documentation S
          :called N :passed N :failed N :error N) ...)
 :case-selection-errors N
 :never-called (NAME ...))
```

The counters cover ordinary generation trials only. Shrinking invocations are
not trials, a precondition refusal belongs to no case, and a case-selection error
increases no case's `:called`. A contract error raised while classifying a
selected case — a case postcondition that signals, say — is counted as that
case's `:error` and keeps the case in its evidence and identity, because the
target was called for it. Because a selection error calls no target,
`TRIALS - REJECTED` is the number of trials that reached selection, not the
number of target calls. The counters belong to one run and are snapshotted onto
its result. A participating backend opens the report before its first draw, so a
run with zero trials, or one whose first draw exhausted the generation budget,
reports known zeros (the exhaustion itself under `:FAILURE-PHASE :GENERATION`);
a result built by hand, and one whose backend never opened reporting, answers
`:NOT-COLLECTED`.

## What this version does and does not do

| Area | Behaviour | Main limit |
|---|---|---|
| `:cases` | one clause, one or more named cases, exclusive selection | no per-case `:args`/`:pre`, no nesting, no `:else`, no priority |
| Case outcome | `:returns` (+ `:post`/`:post-values`) or `:signals` | a `:signals` case cannot carry postconditions in this version |
| Common `:pre` | still bounds the region; a refusal is a rejection | guards run only inside the admitted region |
| Selection errors | `:error` / `:contract-error` / `:failure-phase :case-selection` | not shrunk; never a target counterexample |
| Report | per-case calls and outcomes, selection errors, never-called | no automatic per-case trial minimum or coverage failure |
| Failure identity | `(:case NAME . existing-signature)` | a case-less signature is unchanged |
| Introspection | `function-spec-data` `:cases` + `:case-selection :exclusive` | producing it runs neither guard nor target |
| Digest | covers names, order, guards, outcomes, post bindings, dependencies | does not identify arbitrary argument- or state-dependent code |
| Instrumentation | `:unavailable`; install/refresh refuse with `:named-cases-unsupported` | no case-aware wrapper in this version |

Guarantee boundaries:

- Case guards, like validation predicates and readers, must not modify their
  input or anything reachable from it. cl-spec neither detects nor restores a
  violation. This does not forbid a target's intended state change, but this
  feature does not solve reproduction or reset of stateful targets.
- Case selection is evaluated once per admitted trial. A guard call has no
  timeout and no purity check, and reproducibility assumes guards and generators
  are deterministic in the same effective environment.
- `:CASES` is new syntax; a contract without it keeps its syntax, meaning,
  failure signatures, projection and digest.
- Not in this version: `:capture`/`old`, postconditions over the state after an
  expected error, fixture/reset protocols, state-machine PBT, concurrency, CLOS
  method contract composition, mutation detection, a general constraint solver,
  and case selection through `tagged-by` (which selects a data spec by a value's
  tag, a different feature).

## Where to read more

- [`README.md`](../../README.md) — entry point, short examples and limits.
- [`docs/cl-spec-specification-v0.2-draft.md`](../cl-spec-specification-v0.2-draft.md)
  — §17, §17.1, §17.2, §18, §19 and the case-selection implementation addendum.
- [`docs/api/cl-spec.md`](../api/cl-spec.md) — generated from public docstrings.
- [`examples/function-spec-cases.lisp`](../../examples/function-spec-cases.lisp)
  — the code these excerpts call.
