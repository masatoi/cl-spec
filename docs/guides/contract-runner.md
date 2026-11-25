# Contract suites in CI

Load a generation backend such as `cl-spec/check-it` and register the contracts
and properties to check. Then run a selection with `cl-spec:check-contracts`.

```lisp
(asdf:load-system "cl-spec/check-it")

(cl-spec:check-contracts
  :names '((:function-spec ledger:withdraw)
           (:property ledger:withdraw-preserves-balance))
  :seeds '(42 2026)
  :trials 100
  :examples '((ledger:withdraw (100 100) :sufficient-funds)))
```

Each `:names` item may include the definition kind as above. A bare symbol runs
both kinds when both are registered under it. Use `:package "LEDGER"` for names
whose home package is `LEDGER`, or `:tag :ci` for properties with that tag.
An unknown package name produces an `:unknown-package` problem.
Omit the selector to run every registered Function Spec and property. Pass
`:registry` to choose a registry.

The suite runs each target once per `:seeds` item. A nonnegative integer selects
a fixed seed. A `:fresh` item draws a seed per target from a newly randomized
state and preserves the caller's `*random-state*`. The default is `(:fresh)`.
`:trials` sets the Function Spec budget. A property uses its own
budget, with the usual backend default when the normal budget is absent. An
explicit non-`nil` `:profile` requires that the property declare that profile.
`:options` goes to both generated runners.

Examples are `(NAME RAW-ARGUMENTS [EXPECTED-CASE])` rows. Each runs once after
generation via `check-call`. The raw arguments are supplied by the caller.
An expected case must match the observed case.

## Reading the verdict

Check the report's `:status` for `:passed` or `:failed`. A passing suite
selects at least one generated target and one seed. Every generated run must
pass, with at least one measured checked trial and at least one checked trial
for each declared case. Every supplied example must pass. Missing measurements,
unregistered targets and escaped errors produce failures.

Pass a version-one evidence policy in `:policy` to
add requirements or raise the minimum checked counts. This suite also requires
the full requested trial budget to finish. [Evidence policies](evidence-sufficiency.md)

```lisp
(cl-spec:check-contracts
  :package "LEDGER"
  :seeds '(42)
  :policy '(:policy-version 1
            :requirements ((:kind :requested-trials-completed))))
```

Generated rows in `:entries` are in seed order, then target order. Each row
records the target `:kind` and `:name`, its decimal-string `:seed`, its
execution `:status` and its CI `:verdict`. When available, `:result` is the
saved `result-data` plist and `:assessment` shows the checked evidence and
any gaps. Rows in `:examples` carry the direct observation under `:result`
when available. `:problems` identifies failures at the suite or row level.

Call `cl-spec:judge-contract-result` on a saved generated result to get the
verdict, evidence assessment and problems as three values. It uses the suite's
default policy when called with one argument. An explicit second argument
selects the full evidence policy for that result.

To rerun a generated check, parse the row's `:seed` with `parse-integer`. Pass
the resulting integer and the saved settings from `:result` to
`check-function` or `run-property`. Compare `:definition-digest` with the
current definition when checking that the declarations match.
[Replay and compatibility](../compatibility.md#saved-counterexamples-and-replay)

## Rove

Add `cl-spec/rove` to the ASDF dependencies of your test suite. Use
`deftest-contract` with a Rove test name followed by a literal target and
runner keywords.

```lisp
(cl-spec/rove:deftest-contract checked-withdraw (:function-spec ledger:withdraw)
  :seeds '(42)
  :trials 100)
```

Rove reports the seed. Its failure description includes the saved
counterexample, definition digest and example conditions when available.
The literal target supplies the selection. Adding `:names`, `:package` or
`:tag` signals an error during macroexpansion.
