# Coverage Protocol Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; one independent final review.

**Goal:** Record stage-specific input coverage, with generic protocols and a plist provider.
**Architecture:** Core schemas and immutable observations feed a bounded run-owned collector.
Backend targeting is distinct from observation. Results save copied reports; evidence v1 stays unchanged.
**Tech Stack:** Common Lisp, ASDF package-inferred systems, Rove, check-it.
**Spec:** ../specs/2026-09-27-coverage-protocol-design.md

## Global constraints
- No check-it/cl-mcp dependency in core; no runtime eval/dynamic intern.
- Disabled/observe preserve RNG stream; exercise explicitly changes generation.
- No extra validation/predicate calls for coverage. Shrinking never counts.
- Unknown, measured zero, and inapplicable differ; schema/report are saved snapshots.
- Limits: 1024 dimensions (max65536), depth32 (max256), at most64 extra keywords.
- Existing execution status, artifact format, policy v1 unchanged.

## Review focus
- Nested absent records and omitted arguments must not be classified as present NIL.
- Fixture inner observations must not double-count outer trials, including cleanup abort.
- Exercise must not mutate custom/composite generated data or bypass domain checks.
- Ordinary observation graphs must be collectable before the run completes.
- Report reads must not consult the registry or reexecute predicates/readers.

## Task 1: Schema and options
Files: src/coverage.lisp, src/coverage-plist.lisp, tests/coverage-test.lisp, tests.lisp.
Interfaces: coverage-schema, definition-coverage-schema, normalize-coverage-options,
coverage-bindings; plist schema dimensions and input bucket projection.
- [x] RED tests: optional NIL/value-position keyword, nested absent, finite integer bounds,
  open/closed keys, cyclic/malformed options, limits and unsupported composites.
- [x] Implement static schema/observer without executing user predicates.
- [x] Run tests; commit.

## Task 2: Collector and direct execution
Files: src/coverage-report.lisp, execution.lisp, function-spec.lisp,
tests/coverage-direct-test.lisp.
Interfaces: run-owned context, per-trial bucket snapshot and stage marks,
coverage-data generic, saved direct reports.
- [x] RED tests: direct success/pre-refusal/capture error/post error, mutations,
  fixture cleanup/setup failure, disabled/legacy, copy/registry independence.
- [x] Connect existing evaluation checkpoints; direct :coverage supports observe only.
- [x] Full suite; commit.

## Task 3: Generated execution and check-it exercise
Files: generator.lisp, property-runner.lisp, backends/check-it*.lisp,
tests/coverage-run-test.lisp.
Interfaces: backend-coverage-protocol/capabilities, plan iterator, bounded extra-key targeting.
- [x] RED tests: budget0/shortfall/pre-all-refused, seed stability observe vs disabled,
  replay, extra-key collisions/closed/custom generators, bounds and nested targeting.
- [x] Observe generated roots and confirmed stages only; finalize normal reports.
- [x] Integrate targeting into built-in plist generation, without altering custom outputs.
- [x] Full suite; commit.

## Task 4: Public discovery, evidence and documentation
Files: main.lisp, schema.lisp, evidence.lisp, specs.lisp, tests/self-specs-test.lisp,
README.md, AGENTS.md, docs/guides/coverage.md, docs/api.
- [x] Tests first for public self-contracts and discovery; implement exports and coverage scope.
- [x] Write runnable guide and regenerate API docs.
- [x] Full suite, fresh core-only load, clean rove, forced compile, changed-file lint.

## Task 5: Independent review
- [x] Fresh read-only independent reviewer against design and full branch.
- [x] Reproduce/fix significant findings with regression tests; final suite and local commit.

## Ledger
- Baseline 948 tests passed on merged evidence implementation.
- Ruling: User explicitly authorized implementation and final independent review.
  Execute inline without an additional plan-approval stop.
- Ruling: Retain current checkout/REPL root on feature/coverage-protocol, based on
  approved docs commit 8b53ab3; no extra worktree needed for this single implementation.

- Checkpoint: 970 tests passed in REPL, including public self-contracts.
- Clean `rove cl-spec.asd`, core-only load and forced compile succeeded.
- New coverage modules/tests lint clean; changed-file lint retains three pre-existing needless-let warnings.
- Guide example executed (7 trials, complete report); API reference regenerated.

- Independent review found malformed-generator error regression and duplicate bucket
  counting. Reproduced both with failing tests, fixed, and re-reviewed.
- Restored core-known legacy backend coverage with deferred per-observation frames
  committed only on ordinary-trial reporting; missing reporting stays partial.
- Follow-up review corrected inherited-backend domain availability and fixture
  recipe/setup/binding absence reasons. Reviewer confirmed no significant findings.
- Final fresh-worker suite: 979 tests passed.
