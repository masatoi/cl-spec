# P1 verification implementation

Base: main 35c374e (PR #22 merged), branch p1-verification.
User-authorized order: #11, #13, #14, #15, #16, #17, #18.
P2 #19/#20 are outside this task. Commit each issue after targeted/full validation.

- [ ] #11: digest omissions/exclusions and explicit provenance collection states;
  preserve information in results/artifacts/instrumentation. Additive schema v1.
- [ ] #13: finite, budgeted correlated shrink candidates, custom generator DSL,
  capabilities, failure-preserving acceptance, artifact integration.
- [ ] #14: argument binding / return schema / observed outcome IR, retaining existing
  public readers and required positional/primary-return behavior.
- [ ] #15: optional arguments with explicit presence, without evaluating target defaults.
- [ ] #16: keyword calls preserving original argument order and CL binding semantics.
- [ ] #17: rest calls preserving raw tail, bounded generation and shrinking.
- [ ] #18: explicit fixed multiple-value contracts, keeping old primary-only contracts.

Each checkpoint: tests first, suite registration, executable self-specs, README/spec
decisions, review, full run-tests, clean-process rove, changed-file mallet, forced core
compile. No main merges or publishing new PR unless requested.

#11 decisions:
- definition-digest gains a third value: stable structured omissions. Existing first
  two values and complete-definition digest bytes remain unchanged.
- definition metadata adds :digest-omissions and :digest-exclusions. Exclusions never
  make an otherwise complete declaration incomplete.
- Reason entries identify :kind, :path, :target and :reason. Dependency and child
  traversal is bounded/cycle-safe, deterministic, and collects independent failures.
- Result metadata remains captured before execution. Artifact v1 accepts additive
  digest fields and keeps old artifacts readable; missing old detail is explicit.
- Provenance retains existing scalar labels and adds collection-state information:
  :known, :unknown (attempted but unavailable), :not-collected (not requested).
- No target/helper code is invoked to obtain provenance.

## #13 protocol decisions

- Extend `defgenerator` with an optional leading `(:shrink (value) body...)`
  clause after its optional docstring. Existing no-argument draw bodies retain
  their meaning. CLOS instances accept `:shrinker` (function or NIL); the whole
  source form describes both draw and shrink code.
- Shrinkers receive a copied current value and return a finite proper list of
  candidate values, in preference order. Whole-argument generators receive and
  return whole argument lists. No independent field shrinking is added.
- Check candidates against the argument schema before preconditions and target.
  Accept only changed, nonmutating candidates with the original failure identity.
  Restart enumeration from each accepted candidate; remember all visited inputs.
- A default 100-candidate budget, configurable with `:shrink-budget`, counts
  examined candidates including duplicates and domain rejections. Validate the
  budget before drawing. Bound candidate-list inspection and detect cycles.
- Preserve original evidence on malformed output, shrinker error, or mutation.
  Report candidate count and termination reason separately from generated trials.
  Arbitrary user shrinker code must itself terminate; no wall-clock interruption
  or external-state restoration is promised. Deterministic candidate order is
  the user's responsibility for replay.

## #11 validation checkpoint

Complete: 426 Rove tests; clean-process 37 suites; Mallet changed Lisp files;
forced core compilation and git diff check passed. Existing digest golden values
are stable, old artifacts recheck successfully, resource-limit diagnostics use
lazy array traversal. Review corrections cover old captured metadata and bounded
pending scanner allocation.

## #13 validation checkpoint

Complete: 444 Rove tests, clean-process full suite, changed-file Mallet, forced
core compilation and diff checks passed. Accepted custom shrinks persist and
directly recheck without another draw. Regression checks cover malformed DSL,
CLOS rollback, finite whole-call list validation, candidates rejected by domain,
preconditions and failure identity, duplicates, mutation, errors and budgets.
Reports are additive optional artifact v1 metadata. Built-in shrinking does not
claim the custom search budget/report.
