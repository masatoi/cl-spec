---
trigger: always_on
description: "cl-spec project overview, cl-mcp development workflow, ASDF systems and package-inferred naming rules, testing/linting, and code style imported from CLAUDE.md (complements root AGENTS.md)."
---

# cl-spec Project Guidelines (from CLAUDE.md)

Root `AGENTS.md` is loaded automatically by Antigravity and holds the current
implementation status and verification/fixture/evidence/state-machine/coverage
protocols. This rule supplements it with the remaining project guidelines from
`CLAUDE.md`.

## Project Overview

cl-spec is an executable semantic IR and property framework for Common Lisp
programs, designed for both humans and LLM coding agents. It provides
machine-readable specifications, runtime contract checking, property-based
testing and structured introspection.

- Specification: `docs/cl-spec-specification-v0.2-draft.md`
- Design documents: `docs/superpowers/specs/`

## Development With cl-mcp

This project is developed with `cl-mcp`'s tools:

- **Lisp code operations** (search, read, edit, eval, test): use
  `clgrep-search`, `lisp-read-file`, `lisp-edit-form`, `lisp-patch-form`,
  `repl-eval`, `load-system`, `run-tests`, and `spec-*` tools per
  `prompts/repl-driven-development.md`.
- **Shell commands**: only for `git`, `rove`, `mallet`, and user-requested
  commands.
- `cl-spec` itself does **not** depend on `cl-mcp`. Never add `cl-mcp` to
  `:depends-on`.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, explain, introspection, DSL | none |
| `cl-spec/check-it` | Generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | Runtime function instrumentation | none |
| `cl-spec/specs` | Optional executable API contracts and semantic laws | none |
| `cl-spec/tests` | Test suite | `rove` |
| `cl-spec/examples/structured-data` | Executable structured-data integration example (inferred subsystem) | `check-it` |
| `cl-spec/examples/function-spec-cases` | Executable named per-condition Function Spec example (inferred subsystem) | `check-it` |
| `cl-spec/examples/stateful-withdraw` | Executable capture/state-post Function Spec example (inferred subsystem) | `check-it` |
| `cl-spec/examples/reproducible-withdraw` | Executable `:fixture` Function Spec example: fresh state per trial, shrinking and artifacts (inferred subsystem) | `check-it` |
| `cl-spec/examples/tutorial-cart` | Executable shopping-cart example behind the introductory tutorial (inferred subsystem) | `check-it` |
| `cl-spec/examples/withdraw-cancellation` | Executable state-machine property example (inferred subsystem) | `check-it` |

- The core system (`cl-spec`) must never load `check-it` or `cl-mcp`. The
  generator backend is injected at load time into `cl-spec:*generator-backend*`
  by `cl-spec/check-it`.
- The core does not load `cl-spec/specs`. Loading `cl-spec/specs` registers its
  contracts, generators and laws in the currently bound `cl-spec:*registry*`
  without instrumenting functions. Call `cl-spec/specs:register-specifications`
  to register again after clearing a registry or binding a fresh one. Executing
  the generated checks requires `cl-spec/check-it`.
- `self-spec-fixtures.lisp` (`cl-spec/self-spec-fixtures`) and
  `self-generation-fixtures.lisp` (`cl-spec/self-generation-fixtures`) register
  nothing at load time.
- The self-spec bundle's suites require every run to be `:satisfied` under
  `cl-spec/specs:evidence-policy`, not only `:passed`. Its registry contracts
  and laws build registries through `cl-spec/specs:*registry-constructor*`, so
  `cl-spec/specs:check-registry-implementation` runs them as a conformance suite
  for another `REGISTRY-*` implementation.

## Package Naming

ASDF `package-inferred-system`: the package name equals the file path.

| File | Package |
|---|---|
| `src/ir.lisp` | `cl-spec/src/ir` |
| `src/backends/check-it.lisp` | `cl-spec/src/backends/check-it` |
| `tests/ir-test.lisp` | `cl-spec/tests/ir-test` |
| `specs.lisp` | `cl-spec/specs` |
| `self-spec-fixtures.lisp` | `cl-spec/self-spec-fixtures` |
| `self-generation-fixtures.lisp` | `cl-spec/self-generation-fixtures` |
| `main.lisp` | `cl-spec/main`, nickname `cl-spec` |

- Adding a file requires no `.asd` change; dependencies are inferred from
  `:import-from`.
- New test files **must** be added to `tests.lisp`, otherwise they are never
  run.
- **Never reference the `cl-spec` nickname from inside `src/`**: ASDF reads it
  as a dependency on the root system and the dependency graph becomes circular.

## Testing & Linting

```bash
rove cl-spec.asd                                  # full suite
mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
```

Single suite from the REPL:

```lisp
(rove:run :cl-spec/tests/registry-test)
```

Before opening a PR, in a **fresh** Lisp process — not the REPL you have been
developing in, which already has `cl-spec` loaded — run
`(asdf:compile-system :cl-spec :force :all)` to surface warnings against a cold
fasl cache (`:force t` recompiles nothing in a `package-inferred-system` because
the work lives in per-file subsystems that only `:force :all` reaches).
Compiling in an image that already has `cl-spec` loaded redefines every generic
function and method, burying real warnings under
`REDEFINITION-WITH-DEFGENERIC/DEFMETHOD`. Then run the full suite, then
`mallet`. Lint is currently advisory: findings are tracked for a single batch
cleanup, so a `mallet` warning does not block a PR today.

## Code Style & Stubs

- Google Common Lisp Style Guide: 2-space indent, <=100 columns, blank line
  between top-level forms.
- Lower-case lisp-case: `my-function`, `*special*`, `+constant+`, `something-p`.
- Docstrings required on public functions, macros and classes — stubs included.
- Each file starts with `;;;; <path>`, then `defpackage`, then `(in-package ...)`.
- `(:use #:cl)` only; import everything else via `:import-from`.
- Stubs signal `(error 'not-implemented :operator '<name>)` and declare their
  arguments ignored.

## Implementation Order

Follow §70 of the specification. Steps 1-17 (Semantic IR through the function
checker) are done, including the vertical slice of §67, and step 18
(introspection) is done except for the `describe-*` printers. Step 19, runtime
instrumentation, and function-level custom argument-set generation are also
implemented. Extended argument contracts remain deferred.

## Repository Structure

```text
main.lisp                      Public API re-export (no logic)
specs.lisp                     Optional executable self-specification bundle
self-spec-fixtures.lisp        Fixtures, finite corpora and test-support specials for the bundle
self-generation-fixtures.lisp  Structured generation/shrinking corpus and helpers for the bundle
tests.lisp                     Aggregate test system and rove runner
src/                           Implementation, one responsibility per file
tests/                         Rove suites, mirrored naming (*-test.lisp)
docs/                          Specification and design documents
eval/                          Fault-injection and repair-comparison tasks (not loaded by the library)
prompts/                       System prompts for AI agents
```
