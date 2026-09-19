# Repository Guidelines

@prompts/repl-driven-development.md
@prompts/common-lisp-expert.md

**Current status: MVP vertical slice.** Normalization, validation, structured
explain, spec introspection, the check-it generator backend, `defproperty` and
the property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `check-call`,
`function-spec-data`) in
their expanded §73.1 D1 range: required/optional positional, keyword and rest arguments,
primary or fixed multiple return values, and explicit `:post-values` bindings,
or a required error outcome via `:signals`. A function spec may instead declare
named `:cases`, each with one `:when` condition and one required `:returns` or
`:signals` outcome; selection is exclusive over the inputs the common `:pre`
admits, zero matches / several matches / a signalling guard are contract-side
`:case-selection` errors that call no target, per-case calls and never-called
cases are reported, the selected case name joins the failure identity, and
case-carrying contracts refuse instrumentation. Expected-error contracts are not
supported by runtime instrumentation. A function spec may also declare a
top-level `:capture` of ordered `(NAME FORM)` bindings observed before the call
and a `:state-post` (top-level for a case-less contract, or inside each case)
checked after a passed outcome; a capture variable is not a target argument, a
capture or state-post failure keeps the recorded phase and evidence rather than
inferring either from a condition's class, and such a state-observing contract
is not shrunk, replayed from a past result, persisted as a counterexample
artifact or instrumented in this version. Capture observes a value and does not
copy it, and this feature does not restore anything. A direct one-shot check
(`check-call`, `call-check-result`, `call-check-data`) validates one
caller-supplied raw argument list through the same single-trial path -- binding,
`:pre`, `:capture`, exclusive case selection, one target call, outcome and
`:state-post` classification -- with no generation, shrinking or replay, and it
works in the core system without check-it.
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

## Project Structure & Module Organization

`src/` holds the implementation, one responsibility per file, under ASDF
`package-inferred-system`: the package name equals the file path, so
`src/ir.lisp` defines `cl-spec/src/ir`. Dependencies are inferred from
`:import-from`, so adding a source file needs no `.asd` edit. `main.lisp`
re-exports the public API under the nickname `cl-spec` and contains no logic.
Tests mirror the sources in `tests/` as `*-test.lisp` and **must** be listed in
`tests.lisp` — an unlisted suite never runs.

Systems beside the core are `cl-spec/check-it` (generation and shrinking),
`cl-spec/instrument` (runtime contract wrappers), `cl-spec/specs` (executable
self-specifications), `cl-spec/tests`, `cl-spec/examples/structured-data`,
`cl-spec/examples/function-spec-cases` and
`cl-spec/examples/stateful-withdraw`.
The core system must never load `check-it` or cl-mcp.

`examples/structured-data.lisp` is the executable integration example for the
structured-data and AND-generation features; its guide is
`docs/guides/structured-data-walkthrough.md` and its suite is
`tests/examples-test.lisp`. It is an inferred subsystem of the package-inferred
primary, not a `cl-spec.asd` entry, and its only dependency beyond `cl-spec/main`
is the check-it generator backend, declared by the bare
`:import-from #:cl-spec/src/backends/check-it` in its `defpackage`. Loading the
example therefore installs the backend while the core system stays free of
check-it. Loading the example defines functions and one class only: spec
registration and each demo are explicit entry points that use a dedicated
registry, so loading it never draws a value, runs a demo or changes `*registry*`.

`examples/function-spec-cases.lisp` is the same shape of executable example for
named per-condition cases; its guide is
`docs/guides/function-spec-cases-walkthrough.md` and its suite is
`tests/function-spec-cases-example-test.lisp`. It registers its own generator and
contracts only in `register-example!`, and each `demo-*` runs a controlled input
sequence, so neither loading nor reading it depends on what a seed draws.

`examples/stateful-withdraw.lisp` is the same shape of executable example for
`:capture` and `:state-post`; its guide is
`docs/guides/state-observation-walkthrough.md` and its suite is
`tests/stateful-withdraw-example-test.lisp`. Its generator builds a fresh
account per draw from a scripted `(BALANCE ID AMOUNT)` triple, and its
`demo-limits` entry point reports the unsupported shrinking, replay and
artifact paths rather than hiding them.

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
§68.1) live in `specs.lisp` with fixtures in `self-spec-fixtures.lisp`, loaded
through `cl-spec/specs` and checked by `tests/self-specs-test.lisp`. Extend these
when adding covered APIs. `tests/self-properties-test.lisp` additionally checks
generation and replay through `run-property` itself.
`tests/self-api-contracts-test.lisp` keeps the declared contract/property lists,
the execution set and the registry listings in agreement, and checks the named
`validate` cases, the registry write scenarios and the projection negative data
with hand-written expectations. New test files must be listed in `tests.lisp`.
The fault-injection and repair-comparison tasks are separate from the suite and
live in `eval/`; they never run during a normal `cl-spec` load or test run.

## Commit & Pull Request Guidelines

Commits are imperative and scoped (`module: action`). PRs describe the
capability change, list the commands run (`rove cl-spec.asd`, `mallet ...`,
`(asdf:compile-system :cl-spec :force :all)`) and link the specification
section they implement.

## Security & Configuration Notes

`cl-spec/instrument` rewrites fdefinitions; it is a separate system so that
production images can load cl-spec without that capability. Property bodies and
generators run arbitrary user code — treat a registry populated from untrusted
input as untrusted code (specification §45, §49). Specification-validation
predicates and readers are held to the non-destructive contract: they must not
modify their input or anything reachable from it, and cl-spec neither detects nor
repairs a violation, so a generated value's admissibility, a shrink result, and
replay determinism are not guaranteed after one.


## Verification protocol additions

Counterexample artifacts and direct stateless rechecks live in `src/counterexample.lisp`;
`src/utils/artifact-values.lisp` owns the bounded, reader-free wire codec.
`src/definition-validation.lisp` supplies object validation and explicit extension-slot
rollback hooks. Property/function/generator construction and registry writes use them.
Instrumentation status and explicit refresh remain in the separate `cl-spec/instrument`
system. Optional status self-contract registration is exposed by
`cl-spec/specs:register-instrumentation-specifications` after that system is loaded.
