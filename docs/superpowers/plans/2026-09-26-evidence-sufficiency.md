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
- [x] Write/run failing Rove tests for summary, three requirement kinds, insufficient/unknown precedence, inapplicable-only, malformed policies, deterministic defensive copies.
- [x] Implement bounded policy validation and pure projections; run the unit suite.

## Task 2: Normal-trial reporting and generated results
Files: src/trial-report.lisp, src/execution.lisp, src/generator.lisp,
src/backends/check-it.lisp, src/property-runner.lisp, src/function-spec.lisp,
tests/evidence-run-test.lisp, tests.lisp.
Interfaces: backend-trial-reporting opt-in; runner-owned begin/note/end report; saved trial report and declared-case snapshot.
- [x] Write/run failing tests for passed/failed/rejected/error counts, zero runs, shrink exclusion, fixture cleanup errors, unsupported backend, duplicate/wrong-run/incomplete reports.
- [x] Implement context and consistency checks; make check-it report completion via an after method; integrate snapshot fields and function result copying.
- [x] Run affected suites and all legacy suites.

## Task 3: Direct APIs, public export and discovery
Files: src/function-spec.lisp, main.lisp, src/schema.lisp,
tests/evidence-direct-test.lisp, tests/schema-test.lisp, tests.lisp.
Interfaces: evidence-facts methods for call-check-result and fixture-check-result; :evidence in data projections; schema-info evidence extension.
- [x] Test direct success/error/pre-refusal, case declarations, registry changes, signals, copy safety and core-only operation.
- [x] Implement direct case snapshots and projections; export public APIs and document discovery.
- [x] Run direct and schema suites plus the full suite.

## Task 4: Self contracts, documentation and verification
Files: specs.lisp, self-spec-fixtures.lisp, tests/self-specs-test.lisp,
README.md, AGENTS.md, docs/guides/evidence-sufficiency.md, docs/api,
docs/cl-spec-specification-v0.2-draft.md.
- [x] Add self contracts for public evidence APIs and malformed-policy scenarios.
- [x] Add guide and executable examples showing passed-but-insufficient and unmeasured evidence.
- [x] Run full suite, clean-process Rove, forced compilation, lint and API doc generation.
- [x] Independent read-only review; reproduce/fix meaningful findings, update ledger, commit locally.

## Execution ledger

- Branch: feature/evidence-sufficiency, based on merged main 0a5698c.
- Baseline: 919 tests passed. Current full REPL suite: 947 passed, 0 failed.
- Clean `rove cl-spec.asd`: all 87 suites passed (the Rove CLI counts suites).
- Fresh core-only worker: guide examples returned passed/insufficient and unknown;
  check-it package absent.
- Forced core compile: no compiler warnings beyond image redefinitions; one existing
  unreachable-code note in artifact-values.
- New evidence modules/tests: mallet clean. Broader changed files: three existing
  needless-let* warnings in specs/check-it; clean Rove has existing fixture-test
  ignored-loop-variable style warnings.
- Generated API reference updated.
- Independent review found two Important issues, both fixed with RED→GREEN
  regression tests: contradictory status/failure reports and retention of full
  ordinary observations. No Critical/Minor findings or deferred fixes.
- Reporting now uses an observation-owned private token; successful observations
  can be collected during the run (SBCL weak-pointer regression, including a
  temporary restoration of the retention bug proving the test fails).
- Final clean Rove: 87 suites passed. Final forced compile: no new warnings.
  All new modules/tests and execution.lisp lint clean. API docs regenerated.
- No push or merge; implementation stays on the requested branch.

### Review scope decisions

- Runtime checks were performed by the parent, independently of the read-only
  reviewer; the green results cover the current branch, not future edits.
- Memory verification proves collection of completed observations, not an
  application-specific heap limit; workload-dependent allocation costs remain.
- Portability follows Common Lisp in production code; runtime verification was
  on SBCL. No new concurrency guarantee is made; other hosts need their own checks.
- Extension methods remain trusted arbitrary Lisp. The report protocol checks
  ordinary misuse and is not a sandbox against internal mutation.
- Unchanged subsystems received full regression tests rather than exhaustive
  new review; unrelated latent defects remain possible.

### Implementation rulings

- Keep the requested feature branch in this checkout to preserve the REPL root;
  concurrent unrelated edits would need separation.
- Isolate ordinary-trial reporting in `src/trial-report.lisp` to avoid dependency
  cycles; this adds one internal module.
- The exact shipped check-it class opts in automatically. A subclass overriding
  execution must opt in explicitly; otherwise its checked counts remain unknown.
- Close check-it reporting through an `:after` method inside the runner's
  `:around` boundary; future method-order changes must preserve this ordering.
