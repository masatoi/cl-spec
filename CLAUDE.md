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
their expanded §73.1 D1 range: required/optional positional, keyword and rest arguments,
primary or fixed multiple return values, and explicit `:post-values` bindings,
or a required error outcome via `:signals`. A function spec may instead declare
named `:cases`, each with one `:when` condition and one required `:returns` or
`:signals` outcome; selection is exclusive over the inputs the common `:pre`
admits, zero matches / several matches / a signalling guard are contract-side
`:case-selection` errors that call no target, per-case calls and never-called
cases are reported, the selected case name joins the failure identity, and
case-carrying contracts refuse instrumentation. Expected-error contracts are not
supported by runtime instrumentation.
Custom generators (`defgenerator`, no-argument bodies), whole-argument generators,
and scoped runtime instrumentation (`:input`, `:output`, `:post`) are implemented.
Field-aware keyword plist specs support required/optional keys, closed records,
structured errors, introspection and check-it generation/shrinking. Field metadata
is separated from storage representation in `src/field-spec.lisp`. Alist and
hash-table field specs share that base through a `:test` clause that fixes key
comparison, presence-versus-NIL and alist duplicate-key semantics. Struct and
CLOS field specs (`object-of`) observe instances through explicit readers; they
validate and introspect but need a custom generator to construct values. Tagged
unions (`tagged-by`) dispatch on an explicit tag reader, validate only the
matching branch, name it in errors, and let `sample :branch` target one branch.
AND generation selects one source by a fixed policy — a unique custom conjunct,
numeric folding, or the first ordinarily constructible conjunct — and enforces
the remaining conjuncts through a request-shared bounded filter whose attempts,
rejections and exhaustion are reported. Exhausting the finite budget signals
`generation-budget-exhausted` and is never a claim that the spec is
unsatisfiable. Validation predicates and readers are contractually
non-destructive — they must not modify their input or anything reachable from it
— and cl-spec neither detects nor restores a violation. The `describe-*` printers
remain stubs. The cl-mcp adapter lives
in cl-mcp, not here.

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
| `cl-spec/examples/structured-data` | executable structured-data integration example (inferred subsystem) | `check-it` |
| `cl-spec/examples/function-spec-cases` | executable named per-condition Function Spec example (inferred subsystem) | `check-it` |

The core system must never load `check-it`. The generator backend is injected
at load time into `cl-spec:*generator-backend*` by `cl-spec/check-it`.

`cl-spec/examples/structured-data` is not declared in `cl-spec.asd`: ASDF derives
it from `examples/structured-data.lisp`, and the bare
`:import-from #:cl-spec/src/backends/check-it` in its `defpackage` is what makes
loading the example install the generator backend.

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


## Verification protocol additions

Counterexample artifacts and direct stateless rechecks live in `src/counterexample.lisp`;
`src/utils/artifact-values.lisp` owns the bounded, reader-free wire codec.
`src/definition-validation.lisp` supplies object validation and explicit extension-slot
rollback hooks. Property/function/generator construction and registry writes use them.
Instrumentation status and explicit refresh remain in the separate `cl-spec/instrument`
system. Optional status self-contract registration is exposed by
`cl-spec/specs:register-instrumentation-specifications` after that system is loaded.
