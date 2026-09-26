# Evidence Sufficiency Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, followed by one independent final review.

**Goal:** Separate observed execution results from explicit evidence requirements.
**Architecture:** Save normal-trial counts and declared cases at execution time. A pure evidence module projects saved facts and evaluates bounded version-one policies; it never re-executes user code or resolves the current registry.
**Tech Stack:** Common Lisp, ASDF package-inferred systems, Rove, check-it.
**Spec:** ../specs/2026-09-26-evidence-sufficiency-design.md

## Global constraints

- Existing status, generation/shrink behavior, seed and artifact identity remain unchanged.
- Core never loads check-it or cl-mcp.
- Unknown measurement is not zero. Checked means passed + failed, excluding rejected/error.
- No automatic policy. No cross-run aggregation or optional-field coverage in v1.
- Returned evidence is copied; mutable registry changes cannot change historical facts.
- Implementation is authorized by the user; use the requested feature branch in this checkout.

## Review focus

- A fixture shrink abort preserves ordinary trial counts and does not add a trial.
- Backend participation without a completed, coherent report must be refused.
- Direct checks capture all declared cases, not only the selected one.
- Unknown/inapplicable requirements cannot accidentally produce satisfied.
- Malformed/cyclic policies are rejected without executing data.

## Task 1: Pure evidence protocol and assessment
Files: src/evidence.lisp, tests/evidence-test.lisp, tests.lisp.
Interfaces: evidence-facts generic; evidence-summary(result); assess-evidence(result, policy); invalid-evidence-policy.
- [ ] Write/run failing Rove tests for summary, three requirement kinds, insufficient/unknown precedence, inapplicable-only, malformed policies, deterministic defensive copies.
- [ ] Implement bounded policy validation and pure projections; run the unit suite.

## Task 2: Normal-trial reporting and generated results
Files: src/trial-report.lisp, src/execution.lisp, src/generator.lisp,
src/backends/check-it.lisp, src/property-runner.lisp, src/function-spec.lisp,
tests/evidence-run-test.lisp, tests.lisp.
Interfaces: backend-trial-reporting opt-in; runner-owned begin/note/end report; saved trial report and declared-case snapshot.
- [ ] Write/run failing tests for passed/failed/rejected/error counts, zero runs, shrink exclusion, fixture cleanup errors, unsupported backend, duplicate/wrong-run/incomplete reports.
- [ ] Implement context and consistency checks; make check-it report completion via an around method; integrate snapshot fields and function result copying.
- [ ] Run affected suites and all legacy suites.

## Task 3: Direct APIs, public export and discovery
Files: src/function-spec.lisp, main.lisp, src/schema.lisp,
tests/evidence-direct-test.lisp, tests/schema-test.lisp, tests.lisp.
Interfaces: evidence-facts methods for call-check-result and fixture-check-result; :evidence in data projections; schema-info evidence extension.
- [ ] Test direct success/error/pre-refusal, case declarations, registry changes, signals, copy safety and core-only operation.
- [ ] Implement direct case snapshots and projections; export public APIs and document discovery.
- [ ] Run direct and schema suites plus the full suite.

## Task 4: Self contracts, documentation and verification
Files: specs.lisp, self-spec-fixtures.lisp, tests/self-specs-test.lisp,
README.md, AGENTS.md, docs/guides/evidence-sufficiency.md, docs/api,
docs/cl-spec-specification-v0.2-draft.md.
- [ ] Add self contracts for public evidence APIs and malformed-policy scenarios.
- [ ] Add guide and executable examples showing passed-but-insufficient and unmeasured evidence.
- [ ] Run full suite, clean-process Rove, forced compilation, lint and API doc generation.
- [ ] Independent read-only review; reproduce/fix meaningful findings, update ledger, commit locally.

## Execution ledger

- Branch: feature/evidence-sufficiency, based on merged main 0a5698c.
- Baseline previously verified: 919 tests passed; re-run before implementation.
