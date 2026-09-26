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
- [ ] Write Rove tests for fresh contexts, cleanup after setup errors and outward throws,
      recipe codec refusal, mutation, and simultaneous evaluation/cleanup errors.
- [ ] Run the new suite and observe missing behavior.
- [ ] Implement definition validation/rollback and bounded recipe lifecycle.
- [ ] Run the suite; commit this independent core foundation.

## Task 2: Function DSL and direct fixture API

Files: src/dsl.lisp, src/function-spec.lisp, src/execution.lisp, src/schema.lisp,
main.lisp, tests/fixture-function-test.lisp, tests.lisp.
Interfaces: :fixture clause; check-fixture, fixture-check-data; recipe adapter.
- [ ] Test declarations and fresh account checks, state-post identity, partial setup,
      cleanup errors, invalid call construction, direct check-call isolation.
- [ ] Observe failures, then implement parsing, slot validation, common evaluation,
      introspection/digest, and schema-v2 direct observations.
- [ ] Run new suites and existing DSL/function/call/self API suites; commit.

## Task 3: Generated trials, shrinking and replay

Files: src/backends/check-it.lisp, src/generator.lisp, src/property-runner.lisp,
src/function-spec.lisp, tests/fixture-generation-test.lisp, tests.lisp.
Interfaces: backend lifecycle capability, recipe input schema, run-error evidence,
normal/custom recipe shrinking and strict fixture replay identity.
- [ ] Test fresh objects per candidate, same-case state failure preservation,
      recipe mutation refusal, cleanup failure stopping shrinking, zero/all-rejected runs,
      unsupported backend refusal and changed replay definitions.
- [ ] Observe failures; lift recipe generators/shrinkers and add lifecycle-aware eligibility.
- [ ] Extend result validation/projection without changing legacy results.
- [ ] Run integration and full suites; commit.

## Task 4: Artifact v2 and generator-free rechecks

Files: src/counterexample.lisp, tests/fixture-counterexample-test.lisp, tests.lisp.
Interfaces: artifact-version 2, :input-kind :fixture-recipe, :state-policy :fixture.
- [ ] Test roundtrip, target repair with same recipe, definition mismatch refusal,
      no generator draws, unsafe lifecycle refusal and v1 regression.
- [ ] Observe failures; implement direct/run result factories and bounded record validation.
- [ ] Run artifact and full suites; commit.

## Task 5: Self contracts, guide and final verification

Files: specs.lisp, self-spec-fixtures.lisp, tests/self-api-contracts-test.lisp,
README.md, docs/guides, example and mirrored tests.
- [ ] Add executable self contracts and a deterministic fixture withdrawal example.
- [ ] Document supported operations and deferred supervision/external restoration.
- [ ] Run full Rove suite, forced ASDF compilation, and lint if available.
- [ ] Review final branch, fix meaningful findings with regression tests.

## Execution ledger

- Baseline: cl-mcp run-tests cl-spec/tests → 880 passed, 0 failed.
- Ruling: work in the existing checkout on feature/reproducible-stateful-contracts,
  matching the user's branch request; no additional worktree is required.
- Ruling: the user explicitly requested implementation after reading the design,
  so execute inline without an additional design/plan approval round.
