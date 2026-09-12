# Runtime Instrumentation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enforce function contracts at runtime with independent input/output/post scopes.
**Architecture:** An opt-in ANSI fdefinition wrapper, compiled explainers, structured violations,
and a core capability query specialized by the wrapper module.
**Tech Stack:** Common Lisp, ASDF package-inferred systems, Rove, cl-mcp REPL.
**Spec:** ../specs/2026-09-13-runtime-instrumentation-design.md and specification §20.

## Global Constraints

- Core must not load check-it, cl-mcp or the instrumentation module.
- Required positional arguments; primary return value checked, all values preserved.
- Existing optional positional registry call remains supported.
- No runtime eval, dynamic interning, or implementation-specific advice.

## Task 1: Scoped wrappers and lifecycle

Files: src/instrument.lisp, tests/instrument-test.lisp (already included in tests.lisp).
- [x] Replace table/stub assertions with behavioral tests: `(instrument-function 'target)`
  then `(funcall (fdefinition 'target) "bad")` must signal spec-violation before target calls.
- [x] Run the suite and confirm the not-implemented failure.
- [x] Implement compiled input and return explainers, pre/post predicates, and
  `(multiple-value-call ... (apply original arguments))` to preserve target values.
- [x] Add scope-isolation and lifecycle regressions. Save original and wrapper in an entry;
  `(eq (fdefinition name) wrapper)` gates restoration and active-state reporting.
- [x] Run the suite for argument arity, source predicate errors, post index, mutation,
  returned values, redefinition and invalid installation requests.

## Task 2: Capability integration and documentation

Files: src/schema.lisp, src/instrument.lisp, tests/instrument-test.lisp, README.md,
docs/cl-spec-specification-v0.2-draft.md.
- [x] Add a failing metadata test with a bound ordinary function and registered contract.
- [x] Add `(defgeneric definition-instrumentation-capability (definition))`, default
  unavailable; specialize function-spec in the optional module and call it from metadata.
- [x] Document the public module API, scopes, conditions and lifecycle limits in §20.
- [x] Run all tests, clean rove, lint changed Lisp, force core compile in isolation;
  verify core alone never loads instrumentation or generation backend.
- [x] Review changes and resolve correctness findings before reporting completion.

Commits and publication are left to the user's next instruction.

## Verification and review

- cl-mcp run-tests cl-spec/tests: 269 passed, 0 failed (17 instrumentation tests).
- Clean `rove cl-spec.asd`: all 22 suite groups passed, exit 0.
- `mallet` over the five changed Lisp files: no problems.
- Forced core compile: passed; CHECK-IT, CL-MCP and instrumentation packages absent.
- Forced instrument-system compile and README-style demo: passed; CHECK-IT and CL-MCP absent.
- `git diff --check`: clean.
- Independent review identified an ambiguous predicate-error guarantee. Documentation now
  distinguishes pre/post errors (propagate) from spec predicates (existing explainer semantics);
  added input/output predicate-error tests. Additional lifecycle and condition-reader tests pass.
- Existing clean-run warnings from Quicklisp/check-it and the intentional invalid DSL test remain.
