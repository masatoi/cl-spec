# Verification Evidence Implementation Plan

**Goal:** Report only observed counterexamples with preserved failure identity, without classification reruns.
**Architecture:** Shared trial observations feed the backend, property results and function-check results.
**Tech Stack:** ANSI Common Lisp, ASDF package-inferred systems, Rove, check-it.
**Spec:** ../specs/2026-09-12-verification-evidence-design.md

## Global constraints

Core must not depend on check-it. Use cl-mcp for Lisp edits and REPL tests.
Do not introduce runtime EVAL or interning into production. Preserve existing public readers.

## Tasks

- [x] Add tests/verification-evidence-test.lisp and list it in tests.lisp.
      Reproduce false-to-error shrinking, condition/input mismatch, extra zero-argument
      target calls, duplicate return predicate calls, missing :trials and :kind collisions.
- [x] Add src/execution.lisp: trial-observation with arguments/status/signature/reason/
      explanation/condition; EVALUATE-TRIAL (property arguments &key context);
      OBSERVE-TRIAL snapshots inputs; FAILURE-IDENTITIES-MATCH-P compares existing identity keys.
- [x] Change check-it RUN-GENERATED-TEST to OBSERVE-TRIAL each generated and shrink input.
      Reject identity changes in the callback and report only an accepted observation.
      Keep original evidence and count precondition rejections only in the trial loop.
- [x] Specify and validate backend :status/:trials/:failure/:shrunk-failure protocol.
      Add INVALID-BACKEND-RESULT condition; reject missing, noninteger, negative and
      over-budget counts and inconsistent evidence. Property results project evidence.
- [x] Replace function-check's boolean wrapper and reproduction pass with a specialized
      property evaluator. Classify the target's one return value with EXPLAIN-DATA once.
      Preserve postcondition tagging and structural error handling.
- [x] Add :entity-kind to introspection and a result discriminator reader; re-export APIs.
- [x] Run Rove, update old shrink-discard tests to assert preservation of failure identity,
      add nested/mutable/zero-budget/adversarial backend coverage, then force compile.
- [x] Update specification §§13–19 and §73.4 and verify lint/diff/core dependency boundary.

## Verification evidence

- The initial seven regression tests failed against b6d242d for the expected reasons.
- Full Rove suite: 212 tests passed; clean-process `rove cl-spec.asd` exited 0.
- Core-only load: CHECK-IT package absent, generator backend NIL.
- Forced core compile: no warnings other than definition reloading notices.
- Full mallet run: 10 pre-existing findings; no new lint findings.
- Independent review found sharing-mutation detection, observation provenance and
  malformed-list validation gaps. Regression tests reproduce these cases; fixes
  preserve graph sharing, bind evidence to its run/property and reject cyclic lists.
  Follow-up review confirmed sharing/provenance fixes and identified valid dotted
  MEMBER constants; signature validation now accepts them with regression coverage.

## PR review follow-up (2026-09-13)

- Reproduced domain violations for guarded integers, string internal representations
  and MEMBER constants; candidates now pass compiled argument validators before invocation.
- Reproduced stack exhaustion on long snapshots/return values; copying and graph
  comparison now use iterative work lists. The regression checks 100,000 elements.
- Reproduced lost evidence after a shrinker exception and unknown evaluator status
  reported as passing. Both paths now preserve the failure or reject invalid evaluation.
- Replaced the observation retention table with a per-run token and fixed comparison
  of copied array constants in failure signatures.
- Strengthened shrink-identity tests to require an actual accepted reduction, and
  captured adversarial backend evidence inside the run to test beyond provenance.
- Full REPL suite: 221 tests passed. Clean-process Rove exited 0; forced core compile
  had no warnings beyond definition reloading. Mallet has only 10 pre-existing warnings.
- Independent read-only review found no new blocking issue in these fixes.
