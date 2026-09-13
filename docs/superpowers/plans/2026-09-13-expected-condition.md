# Expected-condition Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Check required error outcomes through `(:signals SPEC)`.

**Architecture:** Extend existing function-spec declarations and trial classification. Reuse Semantic IR, explain-data, observation identity and schema dependency traversal.

**Tech Stack:** ANSI Common Lisp, ASDF package-inferred systems, Rove, check-it.

**Spec:** [Approved design](../specs/2026-09-13-expected-condition-design.md)

## Global Constraints

- Core dependencies remain free of check-it and cl-mcp.
- Use structural cl-mcp edits, no runtime eval or interning.
- Tests must be listed in tests.lisp.

## Task 1: Declaration and execution

Files: src/dsl.lisp, src/function-spec.lisp, main.lisp,
tests/signals-test.lisp, tests.lisp.

- [x] Add a test registering `(defspec-function raise-error (:signals (type simple-error)))`; confirm current macro rejects it.
- [x] Add grammar tests rejecting empty, NIL, duplicate, returns/post combinations; add direct class normalization and rollback assertions.
- [x] Add signal-spec slot/reader and normalize it under shared-initialize; include it in rollback slots.
- [x] Parse exactly one spec in :signals and emit `:signal-spec (normalize-spec-form 'SPEC)`.
- [x] Classify matching errors as passed, returns as :missing-condition, mismatches as :condition-spec. Extend failure-signature with separate outcome classes.
- [x] Test preconditions, ordinary warnings, unexpected errors, predicate-error explanations and check-function shrinking.

## Task 2: Projection and instrumentation boundary

Files: src/introspection.lisp, src/function-spec.lisp, src/instrument.lisp,
tests/signals-test.lisp.

- [x] Assert `(getf (function-spec-data name) :signals)` projects normalized IR and changing only the expected condition changes declaration digest.
- [x] Add the signal node to definition-description dependencies and :signals to introspection.
- [x] Assert instrument-function refuses signals contracts without changing fdefinition; report capability :unavailable and refuse installation before mutation.

## Task 3: Self-specs and validation

Files: specs.lisp, tests/self-specs-test.lisp, README.md, AGENTS.md, CLAUDE.md,
docs/cl-spec-specification-v0.2-draft.md.

- [x] Add a normalize-spec-form contract over malformed DSL forms requiring invalid-spec-form with a nonempty reason; include its name in contract-names. Fix the dotted-spine normalization bug demonstrated by this contract.
- [x] Update executable self-spec expectations and run seeded contract checks.
- [x] Document required-error semantics, failure reasons, DSL example and instrumentation boundary.
- [x] Run focused suites and full `run-tests` for cl-spec/tests, clean `rove -r dot cl-spec.asd`, cold `(asdf:compile-system :cl-spec :force :all)`, mallet on changed Lisp files, and git diff --check.
- [x] Review final diff and commit the complete change.

## Verification

- Red: initial signals tests failed for unsupported clause and missing signal-spec initarg.
- Red: projection/dependency tests detected missing :signals metadata and unchanged digests.
- Red: instrumentation test detected silent installation.
- Red: the new executable self-contract found (tuple . integer) raising TYPE-ERROR;
  four malformed-spine regression assertions failed before the finite-list guard.
- Green: cl-mcp run-tests, cl-spec/tests: 330 passed, 0 failed.
- Green: rove -r dot cl-spec.asd: exit 0, 26 suites completed. Existing dependency
  warnings and 9 fixture style warnings remain; no new undefined-variable warnings.
- Green: cold (asdf:compile-system :cl-spec :force :all), with assertions that
  neither check-it nor cl-mcp was loaded: exit 0.
- Green: mallet on all changed Lisp files and git diff --check.
- Independent read-only code review: no actionable findings.

## PR #8 review follow-up

- Fixed: broad :signals specs accepted target PROGRAM-ERROR/UNDEFINED-FUNCTION.
  These classes and their subclasses now retain :error/:condition before expected
  spec matching, even if explicitly named in the expected spec. Contract predicate
  authoring errors still propagate through the existing outer handler.
- Fixed: AND/OR/NULLABLE expected descriptors now include child descriptors.
- Simplified: one unsupported-contract-reason helper serves instrumentation
  capability and installation checks.
- Removed: normalize-plist's redundant outer finite-list-p check. Its sole caller
  has already checked the same spine; clause and entry validation remains.
- Retained: :failed means normal-return violation, :error means error outcome.
  failure-reason distinguishes :condition-spec from :contract-error. Changing
  statuses would alter the approved observation protocol.
- Retained: captured wrappers require explicit refresh/removal. A refused refresh
  preserves an existing wrapper; changing to unsupported signals requires
  uninstrument-function. A new test demonstrates this lifecycle.
- Retained: signals instrumentation is unavailable for all scopes, including
  input-only and NIL. Tests now cover these scopes explicitly.
- Rejected complexity claim: finite-list-p walks only CDR spines, not nested
  elements. The added traversal is aggregate linear in ordinary tree-shaped DSL
  conses, not a full subtree scan at each depth.

Red/green evidence: focused tests initially failed 23 assertions for programming
errors and composite descriptors. Final suite: 333 passed, 0 failed. Clean-process
Rove: exit 0, 26 suites completed (existing dependency/fixture warnings only).
Cold forced core compilation and dependency-isolation assertions: exit 0, no
warnings. Mallet on all PR Lisp files and git diff --check passed.
Independent review of final code changes: no actionable regressions.
