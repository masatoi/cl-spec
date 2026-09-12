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

## PR #5 review follow-up

| Finding | Disposition |
|---|---|
| Target optional/rest/key arity | Keep the whole-call required-argument contract. Extras are outside its declared domain, not inferred target arity. Documented and tested all three target lambda-list variants; extended argument contracts remain deferred. |
| PRE with VALIDATE | Reuse precondition-refuses-p; SPEC-VIOLATION becomes input refusal, other errors retain their original condition. Regression reproduced before fix. |
| Anonymous PROGRAM-ERROR | Undefined targets use existing unbound-target. Other unsupported definitions use unsupported-instrumentation-target, inheriting cl-spec-error and program-error, with name/reason readers. |
| Error plist vocabulary | Use error-datum with :actual, :expected and existing :wrong-length/:predicate-failed kinds. Dedicated condition scope/reason readers keep runtime classification separate. |
| Function name in spec slot | Carry actual argument/return IR, an arity tuple, or synthetic pre/post predicate specs whose input matches the reported value. Function name remains in its own reader. |
| Positional registry / NIL | Retain the declared positional API alongside keywords; NIL explicitly selects the default registry. Both forms tested. |
| Stale entries | State queries now remove stale entries as well as uninstrument. Document that callers must query/clean up after external redefinition; portable automatic redefinition notification is unavailable. |
| Named reference compilation | Retain dynamic resolution: replacing or reinitializing the same registered IR object must be visible on the next call. EQ-object caching would be stale; added in-place mutation regression. A versioned validation cache is separate work. |
| Unconditional result list | Input-only/no-output checks return directly from APPLY, preserving all values without the results-list round trip. |
| Path allocations | Capture reversed argument paths once when constructing the wrapper. |
| Proper list helper | Reuse existing cycle-safe proper-list-p; dotted/circular scope tests protect failed-installation atomicity. |
| Documentation / width | Added private helper/installation docstrings and fixed all >100-column lines in instrument source/tests. Removed an existing unused import in the touched explainer package. |
| Package nickname cycle | No cycle: declaring a nickname does not import its system. Fresh compile confirms src/instrument depends only on canonical src packages. Keep the user-facing alias; internal imports remain canonical. |
| Result fallback | Uncaptured metadata reports instrumentation :unknown, matching other unknown capabilities. |
| Agent instructions | Updated AGENTS.md and CLAUDE.md status and implementation order. |

Validation after follow-up:
- cl-mcp run-tests cl-spec/tests: **278 passed, 0 failed**, including 26 instrumentation tests.
- Clean rove cl-spec.asd: all 22 suite groups passed.
- Forced core-only and instrumentation-only compilation passed; no unexpected backend or MCP dependency.
- mallet over all five changed Lisp files: no problems; git diff --check clean.
- Independent review found no further correctness issues and separately verified synthesized spec/value evidence.
