# Reproducible Stateful Contracts Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline.

**Goal:** Rebuild fixture state for independent trials, shrinking and saved-recipe rechecks.
**Architecture:** An inline fixture describes a bounded recipe and setup/cleanup hooks.
A shared lifecycle wraps the existing function evaluator; generation sees recipe arguments.
**Tech Stack:** Common Lisp, package-inferred ASDF, Rove, check-it.
**Spec:** ../specs/2026-09-26-reproducible-stateful-contracts-design.md

## Global constraints

- Core never imports check-it or cl-mcp.
- Existing check-call operates on caller-owned raw arguments without fixture hooks.
- Existing non-fixture digests, v1 artifacts and result shapes remain compatible.
- Setup begins inside unwind-protect; cleanup runs once even on partial setup.
- Stateful contracts without fixtures retain their restrictions.
- Worker supervision and external-state restoration are later, separate work.

## Review focus

- Partial setup and simultaneous target/cleanup failures retain both evidence records.
- Recipe mutation is refused; target mutation of fresh call objects is allowed.
- Custom recipe shrinkers are lifted into the whole-argument path.
- Persisted recipes never include opaque live instances or executable closures.
- Definition changes and unsupported backends refuse before side effects.

## Task 1: Fixture definition and lifecycle

Files: src/fixture.lisp, src/fixture-execution.lisp, tests/fixture-test.lisp, tests.lisp.
Interfaces: fixture definition with recipe name/spec, isolation, version, hook forms/functions;
a callback lifecycle producing immutable recipe and phase records.
- [x] Write Rove tests for fresh contexts, cleanup after setup errors and outward throws,
      recipe codec refusal, mutation, and simultaneous evaluation/cleanup errors.
- [x] Run the new suite and observe missing behavior.
- [x] Implement definition validation/rollback and bounded recipe lifecycle.
- [x] Run the suite; include the core foundation in the implementation checkpoint.

## Task 2: Function DSL and direct fixture API

Files: src/dsl.lisp, src/function-spec.lisp, src/execution.lisp, src/schema.lisp,
main.lisp, tests/fixture-function-test.lisp, tests.lisp.
Interfaces: :fixture clause; check-fixture, fixture-check-data; recipe adapter.
- [x] Test declarations and fresh account checks, state-post identity, partial setup,
      cleanup errors, invalid call construction, direct check-call isolation.
- [x] Observe failures, then implement parsing, slot validation, common evaluation,
      introspection/digest, and schema-v2 direct observations.
- [x] Run new suites and existing DSL/function/call/self API suites; include in checkpoint.

## Task 3: Generated trials, shrinking and replay

Files: src/backends/check-it.lisp, src/generator.lisp, src/property-runner.lisp,
src/function-spec.lisp, tests/fixture-generation-test.lisp, tests.lisp.
Interfaces: backend lifecycle capability, recipe input schema, run-error evidence,
normal/custom recipe shrinking and strict fixture replay identity.
- [x] Test fresh objects per candidate, state failure preservation and custom recipe shrinking,
      recipe mutation refusal, cleanup failure stopping shrinking, zero-trial runs,
      changed replay options/budgets and run-level hook snapshots.
- [x] Observe failures; lift recipe generators/shrinkers and add lifecycle-aware eligibility.
- [x] Extend result validation/projection without changing legacy results.
- [x] Run integration and full suites; include in checkpoint.

## Task 4: Artifact v2 and generator-free rechecks

Files: src/counterexample.lisp, tests/fixture-counterexample-test.lisp, tests.lisp.
Interfaces: artifact-version 2, :input-kind :fixture-recipe, :state-policy :fixture.
- [x] Test roundtrip, target repair with same recipe, definition mismatch refusal,
      no generator draws, unsafe lifecycle refusal and v1 regression.
- [x] Observe failures; implement direct/run result factories and bounded record validation.
- [x] Run artifact and full suites; include in checkpoint.

## Task 5: Self contracts, guide and final verification

Files: specs.lisp, self-spec-fixtures.lisp, tests/self-api-contracts-test.lisp,
README.md, docs/guides, example and mirrored tests.
- [x] Add executable self contracts and a deterministic fixture withdrawal example.
- [x] Document supported operations and deferred supervision/external restoration.
- [x] Run full Rove suite, forced ASDF compilation, and lint if available.
- [x] Review final branch, fix meaningful findings with regression tests.

## Execution ledger

- Baseline: cl-mcp run-tests cl-spec/tests → 880 passed, 0 failed.
- Ruling: work in the existing checkout on feature/reproducible-stateful-contracts,
  matching the user's branch request; no additional worktree is required.
- Ruling: the user explicitly requested implementation after reading the design,
  so execute inline without an additional design/plan approval round.

- Implemented Tasks 1–4 and executable self contracts/example together in `b304040`.
  The tightly coupled adapter/result/artifact protocol was committed as one checkpoint,
  rather than the originally proposed commit per task.
- Independent read-only review found lifecycle phase/condition priority, run-level hook
  capture, replay-property forwarding and duplicate introspection keys. Each finding
  was reproduced by a failing regression test and fixed. Reused adapters now capture
  current hooks separately for each run before metadata/replay validation.
- Follow-up checks added fixture error case counts, truthful custom-shrinker capability,
  schema-info v2 discovery, recipe mutation tests, simultaneous setup/cleanup evidence,
  and strict optional metadata omission validation for artifact v2.
- Final cl-mcp `run-tests cl-spec/tests`: **919 passed, 0 failed**.
- Clean process `rove cl-spec.asd`: exit 0, **83 suites passed**.
- `(asdf:compile-system :cl-spec :force :all)`: returned T; loaded-image redefinition
  warnings only. Generated API docs refreshed; `git diff --check` passed.
- Advisory lint command: `mallet src tests/fixture-test.lisp tests/fixture-function-test.lisp tests/fixture-generation-test.lisp tests/fixture-counterexample-test.lisp examples/reproducible-withdraw.lisp --format line`.
  Exit 1 from 10 warnings: three in pre-existing production code and seven test
  `needless-let*` reports. Six test cases deliberately bind special `*mode*`
  before evaluation; another reads the setup counter after a run. No lint errors.
- Delivered scope remains fresh in-memory fixtures. Database rollback, process-kill
  supervision and runtime instrumentation for fixtures remain deferred.
