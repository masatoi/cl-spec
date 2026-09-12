# Function argument-set generators

The approved scope is a function-level custom generator for required positional
arguments and one return value. Keep existing `(variable spec)` declarations.

`defspec-function` accepts one `(:args-generator NAME)` clause. NAME identifies an
existing no-argument `defgenerator` in the run's registry, resolved when checking
so forward definitions and registry isolation work. Each draw returns one proper
list containing the entire argument set in declaration order, including NIL for
zero arguments. It must have the correct length and satisfy every argument spec.
Invalid output signals `invalid-generated-arguments` before the target or :pre runs;
it is not a target counterexample. Generator errors propagate without retry loops.
Valid output still passes through :pre, counted as a rejection when refused.

The CLOS API adds `:argument-generator` and `function-spec-argument-generator`.
`function-spec-argument-schema` derives a tuple-spec from the current normalized
argument specs and generator name, so reinitialization cannot stale a stored schema.
`property-argument-schema` supplies the equivalent backend-facing generic; the
function-check adapter specializes it. The check-it backend compiles this whole
schema using the existing tuple and custom generator paths. It validates custom
draws without compiling independent element generators, supporting specs for which
only the full argument generator is available.

The run's existing seeded random state applies to custom draws. A custom generator
must use that state and avoid uncontrolled external state for replay to hold.
The existing custom-value-generator has no shrink strategy: keep the original
failure, report :none, and never construct independent shrinkers for custom tuples.
Existing independent generation and safe shrinking remain unchanged.

Introspection adds :argument-generator and :argument-schema to function-spec-data;
the latter is ordinary spec-data for the derived tuple, including its generator.
No solver, dependent DSL, arbitrary generator expressions, custom shrink API,
lambda-list expansion, instrumentation, or schema-version project is included.

Validation: compare independent and coordinated low/high/value generation for 100
draws; ensure the custom generator yields 100 admitted calls and zero rejections.
Test seeded sequences/replay, invalid lengths/types/cycles, zero arguments, :pre
rejection, named spec resolution, missing generators, CLOS reinitialization,
introspection, retained failure evidence, core loading, and existing regressions.
