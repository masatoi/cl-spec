# Argument-set generator implementation plan

**Goal:** Generate valid dependent argument tuples directly for Function Specs.
**Architecture:** Derived tuple schemas delegate to the existing custom generator
backend. Validate draws before target execution; retain existing evidence protocol.
**Tech stack:** ANSI Common Lisp, ASDF, check-it, Rove, cl-mcp REPL.
**Spec:** ../specs/2026-09-13-argument-set-generator-design.md

## Constraints

- Required positional arguments and one return value; no runtime EVAL.
- Core does not load check-it. No unbounded generator retry loops.
- Use the run registry and random state. Invalid draws are generator errors.

## Tasks

- [x] Add tests/argument-generator-test.lisp and list it in tests.lisp. Reproduce
  missing DSL clause/API, and implement tests for 100 coordinated draws, seeded
  replay, invalid tuple shape/domain, :pre rejection and failure without shrinking.
- [x] Extend function-spec class, validation/rollback slot list and DSL parsing with
  `:argument-generator` / `(:args-generator NAME)`. Derive tuple schemas with
  `(make-instance 'tuple-spec :element-specs specs :generator name)` and export readers.
- [x] Add `property-argument-schema` generic with default tuple construction and a
  function-check adapter method returning `function-spec-argument-schema`.
- [x] Compile the whole schema in check-it; custom draw validation checks proper
  argument list length before invoking compiled element validators. Signal
  `invalid-generated-arguments` with generator, value and reason on invalid output.
- [x] Add function-spec-data fields and main re-exports. Test invalid CLOS updates
  leave the contract intact and derived schemas reflect successful updates.
- [x] Run individual and full Rove suites, clean-process Rove, forced compile and
  mallet. Verify core-only loading and independent-generation seed regressions.
- [x] Update specification and README with a runnable low/high/value example,
  reject/call counts, seed requirements, validation and shrink limitations.

## Verification evidence

- Initial two tests failed on missing CLOS initarg and unsupported DSL clause.
- Full REPL suite: 234 tests passed. Clean-process `rove cl-spec.asd`: exit 0.
- Forced core compilation: no warnings beyond definition-reloading notices.
- Core-only load: CHECK-IT package absent, backend NIL, new API exported.
- Mallet: 10 pre-existing warnings, no new findings; `git diff --check`: clean.
- Independent vs coordinated draws, seed 42: 100/80/20 vs 100/0/100
  generated/rejected/checked. README example executed with 100 generated, 0 rejected.
- Independent review found a nested circular-list validator hang. A new test timed
  out before the fix; the collection proper-list check now detects cycles and the
  generator output is rejected before target execution.
- Validation mutation and generator errors have regression tests. No custom shrink
  strategy is inferred; failing custom tuples preserve the original evidence.
