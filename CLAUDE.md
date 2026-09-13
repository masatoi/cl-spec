# CLAUDE.md

## Agent Guidelines

@prompts/repl-driven-development.md
@prompts/common-lisp-expert.md

## Project Overview

cl-spec is an executable semantic IR and property framework for Common Lisp
programs, designed for both humans and LLM coding agents. It provides
machine-readable specifications, runtime contract checking, property-based
testing and structured introspection.

The specification lives in `docs/cl-spec-specification-v0.2-draft.md`; design
documents live in `docs/superpowers/specs/`.

**Current status: MVP vertical slice.** Normalization, validation, structured
explain, spec introspection, the check-it generator backend, `defproperty` and
the property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `function-spec-data`) in
their §73.1 D1 range: required positional arguments and either one return value
or a required error outcome via `:signals`. Expected-error contracts are not
supported by runtime instrumentation.
Custom generators (`defgenerator`, no-argument bodies), whole-argument generators,
and scoped runtime instrumentation (`:input`, `:output`, `:post`) are implemented.
Field-aware keyword plist specs support required/optional keys, closed records,
structured errors, introspection and check-it generation/shrinking. Field metadata
is separated from storage representation in `src/field-spec.lisp`.
The `describe-*` printers remain stubs. The cl-mcp adapter lives in cl-mcp, not here.

## Development With cl-mcp

This project is developed with cl-mcp's tools:

- **Lisp code operations** (search, read, edit, eval): use `clgrep-search`,
  `lisp-read-file`, `lisp-edit-form`, `repl-eval`, `run-tests` per
  `prompts/repl-driven-development.md`
- **Shell commands**: only for `git`, `mallet` and user-requested commands
- cl-spec itself does **not** depend on cl-mcp. Never add it to `:depends-on`

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, explain, introspection, DSL | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/specs` | optional executable API contracts and semantic laws | none |
| `cl-spec/tests` | test suite | `rove` |

The core system must never load `check-it`. The generator backend is injected
at load time into `cl-spec:*generator-backend*` by `cl-spec/check-it`.

The core does not load `cl-spec/specs`. Loading that optional bundle registers its
contracts, generators and laws in the currently bound `cl-spec:*registry*` without
instrumenting functions. Call `cl-spec/specs:register-specifications` to register
again after clearing a registry or binding a fresh one. Executing the generated
checks requires `cl-spec/check-it`.

## Package Naming

ASDF `package-inferred-system`: the package name equals the file path.

| File | Package |
|---|---|
| `src/ir.lisp` | `cl-spec/src/ir` |
| `src/backends/check-it.lisp` | `cl-spec/src/backends/check-it` |
| `tests/ir-test.lisp` | `cl-spec/tests/ir-test` |
| `specs.lisp` | `cl-spec/specs` |
| `main.lisp` | `cl-spec/main`, nickname `cl-spec` |

Adding a file requires no `.asd` change; dependencies are inferred from
`:import-from`. New test files **must** be added to `tests.lisp`, otherwise
they are never run.

Never reference the `cl-spec` nickname from inside `src/`: ASDF reads it as a
dependency on the root system and the graph becomes circular.

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
developing in, which already has cl-spec loaded — run
`(asdf:compile-system :cl-spec :force :all)` to surface warnings against a
cold fasl cache (`:force t` recompiles nothing here — this is a
package-inferred system, so the work lives in the per-file subsystems that
only `:force :all` reaches). Compiling in an image that already has cl-spec
loaded redefines every generic function and method, and the resulting
REDEFINITION-WITH-DEFGENERIC/DEFMETHOD warnings bury a real one. Then run the
full suite, then mallet. Lint is currently advisory: findings are tracked for
a single batch cleanup, so a mallet warning does not block a PR today.

## Code Style

- Google Common Lisp Style Guide
- 2-space indent, <=100 columns
- Blank line between top-level forms
- Lower-case lisp-case: `my-function`, `*special*`, `+constant+`, `something-p`
- Docstrings required on public functions, macros and classes — stubs included
- Each file starts with `;;;; <path>`, then `defpackage`, then `(in-package ...)`
- `(:use #:cl)` only; take everything else through `:import-from`
- Stubs signal `(error 'not-implemented :operator '<name>)` and declare their
  arguments ignored

## Implementation Order

Follow §70 of the specification. Steps 1-17 (Semantic IR through the function
checker) are done, including the vertical slice of §67, and step 18
(introspection) is done except for the `describe-*` printers. Step 19, runtime
instrumentation, and function-level custom argument-set generation are also
implemented. Extended argument contracts remain deferred.

## Repository Structure

```
main.lisp         Public API re-export (no logic)
specs.lisp        Optional executable self-specification bundle
tests.lisp        Aggregate test system and rove runner
src/              Implementation, one responsibility per file
tests/            Rove suites, mirrored naming (*-test.lisp)
docs/             Specification and design documents
prompts/          System prompts for AI agents
```
