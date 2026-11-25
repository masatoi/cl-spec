# cl-spec 1.x compatibility

Published 1.x releases preserve the calling conventions and documented behavior
of the interfaces listed here. This includes supported DSL forms, argument and
return conventions, condition types and the meanings of documented data fields.
Minor releases may add operations, optional arguments and data fields. Fixes may
change behavior that contradicted the documented contract. The API reference
provides signatures and docstrings for the names listed here. [API reference](api/README.md)

## `cl-spec`

Load the `cl-spec` ASDF system for the core package. For generation and shrinking,
load the `cl-spec/check-it` ASDF system. It installs the bundled backend for use
through `cl-spec`. The backend's implementation package and exported class are
reserved for the implementation. [Generation and shrinking](../README.md#known-limitations)

| Operation | Supported entry points |
|---|---|
| Declarations | `defspec`, `defgenerator`, `defproperty`, `defspec-function`, `defstate-machine` and their documented DSL forms, including named cases, custom generators and shrinkers, capture and state-post clauses, and fresh fixtures |
| Validation and explanation | `normalize-spec-form`, `validp`, `validate`, `compile-validator`, `compile-explainer`, `explain-data`, `explain`, and dynamic binding of `*reference-depth-limit*` |
| Registry and name resolution | `hash-table-registry`, `make-hash-table-registry`, `*registry*`, `find-spec`, `find-generator`, `find-property`, `find-function-spec`, `list-specs`, `list-generators`, `list-properties`, `list-function-specs`, `register-spec`, `register-generator`, `register-property`, `register-function-spec`, `properties-for`, `properties-with-tag`, `clear-registry` |
| Definition introspection | `spec-data`, `property-data`, `function-spec-data`, `semantic-data`, `schema-info`, `definition-digest`, `definition-metadata`, `definition-description`, `source-location-file`, `source-location-package`, `spec-kind`, `spec-children`, `tagged-union-branch` |
| Sampling with the bundled backend | `sample`, `generator-for`, `current-generator-backend`, `*generator-backend*`, `backend-capabilities`, and `generate-value` on an opaque handle returned by `generator-for` for that backend |
| Direct checks | `check-call`, `call-check-data`, `check-fixture`, `fixture-check-data`, `check-state-machine` |
| Generated checks | `run-property`, `run-properties`, `replay-property`, `check-function`, `check-function-with-examples`, `result-data` |
| Contract suites | `check-contracts` |
| Saved evidence and coverage | `evidence-summary`, `assess-evidence`, `coverage-schema`, `coverage-data`, `format-check-summary` |
| Counterexamples | `counterexample-artifact`, `make-counterexample-artifact`, `counterexample-artifact-data`, `serialize-counterexample-artifact`, `deserialize-counterexample-artifact`, `recheck-counterexample`, `observation-failure-p`, `failure-identities-match-p` |

The supported declaration types are `spec`, `property`, `function-spec` and
`custom-generator`. The readers documented for those types apply to
definitions obtained through the public declaration and registry APIs,
including the argument schema and fixture readers. Use `property-call-arguments-p`
and `property-named-arguments` to inspect argument binding. Treat returned
declarations and embedded implementation objects as read-only. Constructor
initargs, writes to slots, the `validate-definition` and
`definition-validation-slots` extension hooks, and stored function
representations are reserved. [Core API reference](api/cl-spec.md)

The supported result and observation types are `property-result`,
`function-check-result`, `call-check-result`, `fixture-check-result`, and
`trial-observation`. The documented readers with those prefixes apply to
values returned by the public checks. `fixture-check-data` is the stable reader
for a direct fixture result. `check-state-machine` returns a `trial-observation`
directly. Read result classes through their readers and projections.
[Core API reference](api/cl-spec.md)

### Registry protocol

The supported extension protocol for a custom registry consists of the following
15 generic functions. It covers sequential callers, symbol identity, replacement
by name, sorted queries and the property reverse indexes.

- Specs use `registry-find-spec`, `registry-register-spec`, `registry-list-specs`.
- Generators use `registry-find-generator`, `registry-register-generator`, `registry-list-generators`.
- Properties use `registry-find-property`, `registry-register-property`, `registry-list-properties`, `registry-properties-for`, `registry-properties-with-tag`.
- Function specs use `registry-find-function-spec`, `registry-register-function-spec`, `registry-list-function-specs`.
- `registry-clear` clears the registry.

The explicit `:registry` selects where cl-spec resolves declarations and their
references. User callbacks see the caller's dynamic `*registry*`. A callback
that calls cl-spec with an omitted `:registry` uses that dynamic binding. The
built-in registry and the conformance suite cover sequential operation.
Synchronization and recovery inside custom registry methods belong to the
implementation of that registry. [Registry conformance guide](guides/self-specification-guide.md#7-check-your-own-registry-implementation)

### Conditions

The 1.x contract includes the following condition types and their documented
readers. Dispatch on condition types and documented structured reason codes.

- `cl-spec-error`, `spec-violation`, `validation-depth-exceeded`, `invalid-argument`.
- `unknown-spec`, `unknown-property`, `unknown-function-spec`, `unbound-target`.
- `invalid-spec-form`, `invalid-property-form`, `invalid-function-spec-form`, `invalid-generator-form`, `invalid-call-arguments`, `invalid-generated-arguments`.
- `no-generator-backend`, `generator-unavailable`, `generation-budget-exhausted`, `unsupported-seed`, `invalid-backend-result`.
- `case-selection-error`, `capture-error`, `state-post-error`, `unsupported-stateful-operation`, including the three `*-error-data` projections for case selection, capture and state postconditions.
- `invalid-counterexample-artifact`, `invalid-evidence-policy`, `invalid-coverage-options`, `unsupported-coverage-operation`.

The live request from `generation-budget-exhausted-request` is reserved. Use
`generation-budget-exhausted-report` and the documented budget and count readers.
Condition reports, human-readable reason strings and the formatting of `explain`
and `format-check-summary` may change. [Core API reference](api/cl-spec.md)

## Optional systems

- `cl-spec/rove` supports `deftest-contract` for Rove suites.
  [Rove API reference](api/cl-spec-rove.md)
- `cl-spec/instrument` supports `instrument-function`, `uninstrument-function`,
  `instrumented-function-p`, `instrumentation-status` and `refresh-instrumentation`.
  It supports `instrumentation-violation` and `unsupported-instrumentation-target`
  with their documented readers. Installations and function redefinitions require
  caller serialization. The installation table `*instrumented-functions*` is
  reserved. [Runtime instrumentation](../README.md#runtime-instrumentation)
- `cl-spec/specs` supports `register-specifications`,
  `register-instrumentation-specifications`, `contract-names`, `property-names`,
  `evidence-policy`, `registry-implementation-p`, `registry-conformance-names`
  and `check-registry-implementation`. The set of bundled contracts, laws and
  conformance checks can grow or be refined. The fixture variable
  `*registry-constructor*` is reserved. [Self-specification guide](guides/self-specification-guide.md)

`describe-spec`, `describe-property`, their stub condition and the
`*spec-primitives*` variable are reserved. Backend construction and
specialization, custom evaluator methods, observation constructors, reporting
hooks and other `cl-spec/src/...` implementation APIs can change during 1.x.
Read the documented capability and evidence projections to inspect the bundled
backend. The `cl-spec/examples/*` systems are teaching examples and may change.

## Machine-readable records

For each supported schema version, existing documented keys, meanings, status
codes and failure identity forms are stable. Consumers should ignore unfamiliar
keys in returned plists and handle unsupported versions explicitly. New optional
fields and status or reason codes can appear as capabilities grow. Treat unfamiliar
verdicts as unknown. Incompatible changes to documented keys, shapes, or meanings
require a new schema version. Use the producing API and its schema together when
dispatching. [Schema reference](api/cl-spec.md#schema-info)

| Producer | Record discriminator and interpretation |
|---|---|
| `spec-data`, `property-data`, `function-spec-data` | Version 1, `:record-kind :definition` and the appropriate `:entity-kind`. Use `:kind` for node or author classification. |
| `result-data` | `:record-kind :result`. Ordinary generated runs use version 1. Generated fixture runs use version 2 and `:input-kind :fixture-recipe`. They include a generated-trial budget and saved failure evidence. |
| `call-check-data` | Version 1, `:record-kind :result` and `:entity-kind :function-spec`, with `:arguments` and `:observation` for one direct invocation. A generated function check can share the same envelope, so retain the projection source. |
| `fixture-check-data` | Version 2, `:record-kind :fixture-check` and `:input-kind :fixture-recipe`, with recipe and lifecycle evidence. |
| `check-function-with-examples` | A combined report with `:examples` and `:generated`. Each fixed row retains its direct result under `:call` when one returned. Use `result-data` on the result under `:generated`. |
| `check-contracts` | Version 1, `:record-kind :contract-suite`, with a suite `:status`, generated `:entries` and direct `:examples`. Each generated entry records its decimal seed and the saved result when available. |
| `evidence-summary`, `assess-evidence`, `coverage-schema`, `coverage-data` | Separate protocols described by `schema-info`. The assessment policy input has its own version. |
| `recheck-counterexample` | `:record-kind :recheck`, version 1 for ordinary saved input and version 2 for a saved fixture recipe. |

An execution verdict reports what happened on the executed input. Evidence
assessment applies an explicit policy to recorded facts. `:collected` facts
can include a measured zero. Preserve `:not-collected`, `:not-applicable`,
`:unavailable`, and `:unknown` wherever the relevant protocol defines them.
For example, provenance distinguishes unavailable information after an attempted
collection (`:unknown`) from a collection that was never attempted
(`:not-collected`). Use availability tags before interpreting application values,
including a collected `NIL`. [Evidence sufficiency](guides/evidence-sufficiency.md)
[Input coverage](guides/coverage.md)

## Saved counterexamples and replay

A newer 1.x release can deserialize artifacts written by an earlier 1.x release
when their values are in the documented bounded value domain and the decoding
implementation can represent them. Use the artifact API to write and read AV1
records. The ordinary artifact format is version 1 and the fixture format is
version 2. Load the defining packages before decoding. A saved symbol requires
its exact recorded home package name and symbol name. An absent home package
or symbol signals `invalid-counterexample-artifact` with `:missing-package` or
`:missing-symbol`, respectively. Decoding uses no nickname substitution or
symbol interning. [Supported artifact values and limits](../README.md#persisting-and-directly-rechecking-a-counterexample)

`recheck-counterexample` checks the saved input against a complete, matching
declaration digest. It invokes the current definition once when validation and
the relevant execution checks admit that input. Recheck uses the saved input
without generation or shrinking. Ordinary artifacts require
`:state-policy :stateless` and refuse recorded or newly detected input mutation.
Fixture artifacts require `:state-policy :fixture` and a matching fixture
version, and rebuild state from the saved recipe. A declaration digest covers
declarations and registered dependencies. Application implementations, external
state and backend settings are separate from the digest. The digest also
captures sharing within a declaration. A compiler can coalesce literal objects,
so loading a compiled definition and evaluating the same source in a REPL can
produce different digests. A target repair may change the recheck verdict while
keeping the declaration identical.
[Artifact recheck](../README.md#persisting-and-directly-rechecking-a-counterexample)

Seed replay regenerates a trial sequence. Integer-seeded replay with the bundled
backend is supported on SBCL. Reproduce a run with the same Lisp implementation
and version, cl-spec and backend and dependency versions, declaration,
application and generator code, relevant state, and run options and budget.
Replay is scoped to those inputs. When a fixture run uses a prior result as
its seed, it checks the declaration, fixture version, profile, trial budget
and options before calling setup. Use a counterexample artifact to recheck a
specific saved input after a target change. [Replay and limitations](../README.md#known-limitations)

## Fresh fixture lifecycle

For `:isolation :fresh`, setup receives a copied recipe and a fresh context and
returns the raw argument list. The recipe must fit the artifact value domain.
`check-fixture` runs one lifecycle, and generated fixture checks start a fresh
lifecycle for every trial and shrink candidate. `check-call` always uses the
supplied call arguments and bypasses fixture hooks. In a fixture invocation,
state postconditions and contract evidence capture precede cleanup. Once setup
starts, cleanup is attempted once on Lisp unwind, including after partial
setup. Cleanup failure aborts the run or shrink search and retains the relevant
observation separately from the lifecycle error.

`:released` means cleanup completed. The fixture author is responsible for
creating fresh in-memory state, maintaining the fixture version when setup
semantics change, and handling partial setup during cleanup. External I/O,
asynchronous tasks, rollback, and recovery after a process crash are outside
the fixture lifecycle. Capture without a fresh fixture observes the caller's
state and provides no restoration. [Reproducible fixture contracts](guides/reproducible-stateful-contracts.md)
