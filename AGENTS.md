# Repository Guidelines

@prompts/repl-driven-development.md
@prompts/common-lisp-expert.md

**Current status: MVP vertical slice.** Normalization, validation, structured
explain, spec introspection, the check-it generator backend, `defproperty` and
the property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `function-spec-data`) in
their §73.1 D1 range: required/optional positional and keyword arguments, with either one return value
or a required error outcome via `:signals`. Expected-error contracts are not
supported by runtime instrumentation.
Custom generators (`defgenerator`, no-argument bodies), whole-argument generators,
and scoped runtime instrumentation (`:input`, `:output`, `:post`) are implemented.
Field-aware keyword plist specs support required/optional keys, closed records,
structured errors, introspection and check-it generation/shrinking. Field metadata
is separated from storage representation in `src/field-spec.lisp`.
The `describe-*` printers remain stubs. The cl-mcp adapter lives in cl-mcp, not here.

## Project Structure & Module Organization

`src/` holds the implementation, one responsibility per file, under ASDF
`package-inferred-system`: the package name equals the file path, so
`src/ir.lisp` defines `cl-spec/src/ir`. Dependencies are inferred from
`:import-from`, so adding a source file needs no `.asd` edit. `main.lisp`
re-exports the public API under the nickname `cl-spec` and contains no logic.
Tests mirror the sources in `tests/` as `*-test.lisp` and **must** be listed in
`tests.lisp` — an unlisted suite never runs.

Four systems sit beside the core: `cl-spec/check-it` (generation and
shrinking), `cl-spec/instrument` (runtime contract wrappers), `cl-spec/specs`
(executable self-specifications) and `cl-spec/tests`.
The core system must never load `check-it` or cl-mcp.

## Build, Test, and Development Commands

Develop through cl-mcp's REPL tools; run individual suites with `run-tests` so
tests execute inside the agent without shelling out. `rove cl-spec.asd` runs
the full suite in a clean process and is the fallback when the image is stale.

## Coding Style & Naming Conventions

Google Common Lisp Style Guide: 2-space indent, ≤100 columns, blank line
between top-level forms. Each `*.lisp` starts with `;;;; <path>`, then
`defpackage`, then `(in-package ...)`. Use `(:use #:cl)` and nothing else;
import every other symbol explicitly. Lower-case lisp-case, `-p` predicates,
`+constants+`, `*specials*`. Public functions, macros and classes require
docstrings — stubs included. Avoid runtime `eval` and dynamic interning.

## Testing Guidelines

Write Rove tests before implementations. Name suites after the unit under test.
Remaining stubs are tested by asserting they signal `not-implemented` with the
right operator; replace those assertions with behavioural tests as each module
is implemented. Executable public API contracts and semantic laws (specification
§68.1) live in `specs.lisp`, loaded through `cl-spec/specs` and checked by
`tests/self-specs-test.lisp`. Extend these when adding covered APIs.
`tests/self-properties-test.lisp` additionally checks generation and replay
through `run-property` itself.

## Commit & Pull Request Guidelines

Commits are imperative and scoped (`module: action`). PRs describe the
capability change, list the commands run (`rove cl-spec.asd`, `mallet ...`,
`(asdf:compile-system :cl-spec :force :all)`) and link the specification
section they implement.

## Security & Configuration Notes

`cl-spec/instrument` rewrites fdefinitions; it is a separate system so that
production images can load cl-spec without that capability. Property bodies and
generators run arbitrary user code — treat a registry populated from untrusted
input as untrusted code (specification §45, §49).


## Verification protocol additions

Counterexample artifacts and direct stateless rechecks live in `src/counterexample.lisp`;
`src/utils/artifact-values.lisp` owns the bounded, reader-free wire codec.
`src/definition-validation.lisp` supplies object validation and explicit extension-slot
rollback hooks. Property/function/generator construction and registry writes use them.
Instrumentation status and explicit refresh remain in the separate `cl-spec/instrument`
system. Optional status self-contract registration is exposed by
`cl-spec/specs:register-instrumentation-specifications` after that system is loaded.
