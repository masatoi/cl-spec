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

## #14 compatibility decisions

- Neutral call-layout/bound-call descriptors separate raw arguments, predicate
  values, named bindings and suppliedness. Required positional syntax remains
  the only syntax in this checkpoint. Derived adapters read current contract
  slots; no second authoritative cache is stored.
- The existing argument-schema API still returns the same tuple, preserving
  generator annotation and complete declaration digest bytes. Return-schema
  projects the legacy primary value, including NIL for zero values.
- Target invocation captures one tagged outcome and all returned values. Existing
  six evaluate-trial return values stay unchanged; an optional seventh carries
  the target outcome. Legacy specializations remain valid.
- Trial evidence adds frozen :outcome data: :returned/:values or
  :signaled/:condition-type/:condition-report. :value stays the primary value.
  Snapshot target values before contract predicates can change them.
- Instrumentation shares binding and primary-return projection, preserves
  multiple-value-call delivery, and does not catch/re-signal target errors,
  retaining active restart contexts.
- Result schema v1 is additive. Artifact v1 keeps its concrete call arguments
  and failure identity; diagnostic returned objects need not be persistable.
  Old artifacts and six-value evaluators remain readable/executable.

## #14 validation checkpoint

Complete: 467 Rove tests; clean-process full suite; changed-file Mallet; forced
core compilation; diff checks. Tests compare legacy digest, classifications,
pre/post order, fresh derived schemas, full-value snapshots, zero values versus
one NIL, error identity and active target restarts under instrumentation.

## #15 decisions and validation

Syntax `(NAME SPEC [SUPPLIED-P])` after &optional; omitted predicate value NIL,
false suppliedness, no target-default evaluation. Provided NIL is validated.
Raw arguments remain evidence; named projection uses binding protocol.
Built-in generation chooses an optional prefix, shrinking removes its suffix.
Shared internal call spec carries declaration metadata; required-only digest
bytes remain stable. Self-spec find-spec exercises optional registry behavior.
486 Rove tests pass at integration checkpoint, including review regression for
captured precondition specs and new failure-shape key classification.

#15 final verification: clean-process 49 suites, changed-file Mallet, forced core
compilation and diff checks passed.

## #16 decisions and validation

Explicit `((:KEY VARIABLE) SPEC [SUPPLIED-P])`, first duplicate wins, raw order
preserved, reserved :allow-other-keys uses its first value. Declaration
&allow-other-keys is terminal. Keyword tail is finite/even/keyword-only.
Optional positions are consumed greedily. Generated keys are declared keys only.
505 tests pass, including empty-key capability and new self-spec coverage.
The mixed optional/key compatibility fixture intentionally triggers Mallet's
mixed-optional-and-key rule; lint this single file with that rule disabled.
Other changed files use the normal preset.

#16 final verification: clean-process 53 suites, scoped Mallet, forced core
compilation and diff check passed.
