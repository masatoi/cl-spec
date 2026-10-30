# Result and Trial Refactoring Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` for these two changes.

**Goal:** Preserve the existing checking API while eliminating copied run-result
fields and positional trial classifications inside function-spec checking.

**Architecture:** Capture common run-result initargs once, then construct the
requested result class with `make-instance`. A one-use constructor is consumed
before user code runs, so nested executions select their own result classes.
Represent function-trial classifications with named internal fields; the
existing `evaluate-trial` generic continues to return its established multiple
values at the boundary.

**Tech stack:** Common Lisp, ASDF package-inferred systems, Rove, cl-mcp.

**Spec:** `docs/cl-spec-specification-v0.2-draft.md` §§13–19, `AGENTS.md`, and
the guides for evidence sufficiency, coverage, and reproducible stateful contracts.

## Global Constraints

- Do not change public result classes, readers, schemas, artifact versions, or
  the `evaluate-trial` multiple-value protocol.
- Do not add a check-it dependency to the core system.
- Capture, case selection, target invocation, postconditions, and fixture cleanup
  retain their order and execute the same number of times.
- Keep missing measurements distinct from measured zero; preserve the original
  counterexample separately when a fixture cleanup failure aborts a run.
- Use the existing Rove suites and add behavior-level regression tests only for
  uncovered compatibility concerns.

## Review Focus

- A function result preserves trial, coverage, run error, provenance, and case
  evidence, including a failure during fixture cleanup, and uses its normal
  CLOS initialization protocol.
- The selected shrunk failure and its explanation remain consistent across both
  property-result and function-result readers.
- A legacy `evaluate-trial` specialization returning six values remains usable.
- Nested property and function runs retain their own result classes.
- Result initialization observes the enclosing coverage and case contexts, not
  the completed inner run's contexts.
- Capture, case-selection, and state-post failures retain their recorded phases.
- A signalling target remains distinguishable from a signalling contract guard.

## Task 1: Preserve run-result state during function-result construction

**Files:** `src/property-runner.lisp`, `src/function-spec.lisp`, and the
function, evidence, fixture, coverage, and schema test suites.

1. Run the existing tests for selected failure evidence, case counts, fixture
   cleanup failures, and metadata as a baseline.
2. Capture the common initargs once in the property runner and construct either
   result class directly. A function result must retain normal `make-instance`
   hooks, the property name and budget, and the selected failure explanation.
   Consume its one-run constructor before execution and verify nested calls.
3. Run the same tests and the full `cl-spec/tests` suite with cl-mcp.

## Task 2: Name the internal function-trial classification fields

**Files:** `src/function-spec.lisp`, `tests/verification-evidence-test.lisp`.

1. Add and run a behavioral regression for a property extension whose
   `evaluate-trial` method returns only the established six values.
2. Add a private classification structure with fields for status, reason,
   signature, explanation, condition, value, outcome, selected case, failure
   phase, and state evidence. Convert it to the existing ten values only at the
   function-check-property `evaluate-trial` boundary.
3. Return named classifications from target-outcome and state-post
   classification and from each function-trial branch; preserve all error
   handling, snapshots, signatures, and evaluation order.
4. Run the compatibility test, direct/generated checks, cases, observations,
   fixture, coverage, evidence, and full `cl-spec/tests` suites with cl-mcp.
