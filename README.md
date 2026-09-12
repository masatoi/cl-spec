# cl-spec

An executable semantic IR and property framework for Common Lisp programs,
designed for both humans and LLM coding agents.

**Status: MVP vertical slice.** Normalization, validation, structured explain,
spec introspection, the check-it generator backend, `defproperty` and the
property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `function-spec-data`) for
required positional arguments and one return value, including custom generators
for whole argument sets. Custom generators are
implemented for functions of no arguments. The `describe-*` printers and
instrumentation are still stubs that signal `not-implemented`. The cl-mcp adapter
lives in cl-mcp, not here.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, structured explain, introspection, DSL | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/tests` | test suite | `rove` |

`cl-spec` never loads `check-it`. Load `cl-spec/check-it` to install a generator
backend into `cl-spec:*generator-backend*`.

## Usage

```lisp
(asdf:load-system :cl-spec)
(asdf:load-system :cl-spec/check-it)
```

## Example

The vertical slice from specification §67, working end to end:

```lisp
(cl-spec:defspec positive-integer
  (and integer (range 1 *)))

(cl-spec:find-spec 'positive-integer)
(cl-spec:spec-data 'positive-integer)
(cl-spec:validp 'positive-integer 10)          ; => T
(cl-spec:explain-data 'positive-integer -1)    ; => (:VALID NIL :ERRORS (...))
(cl-spec:sample 'positive-integer)             ; => (3 17 1 42 ...)

(cl-spec:defproperty addition-preserves-order
    ((x positive-integer)
     (y positive-integer))
  (:about +)
  (:kind :monotonicity)
  (> (+ x y) x))

(cl-spec:properties-for '+)
(cl-spec:run-property 'addition-preserves-order)
```

## Generate related arguments together

Use `:args-generator` when independently generated arguments would mostly be
rejected by `:pre`. A registered generator returns the whole positional argument
list in one draw:

```lisp
(defun bounded-value (low high value)
  (declare (ignore low high))
  value)

(cl-spec:defgenerator bounded-arguments ()
  (let* ((low (random 10))
         (high (+ low 1 (random 10)))
         (value (+ low (random (1+ (- high low))))))
    (list low high value)))

(cl-spec:defspec-function bounded-value
  (:args (low (range integer 0 20))
         (high (range integer 0 20))
         (value (range integer 0 20)))
  (:args-generator bounded-arguments)
  (:pre (< low high) (<= low value high))
  (:returns integer))

(let ((result (cl-spec:check-function 'bounded-value :trials 100 :seed 42)))
  (list :generated (cl-spec:property-result-trials result)
        :rejected (cl-spec:function-check-result-rejected result)))
;; => (:GENERATED 100 :REJECTED 0) — all 100 draws checked the function.
```

In the regression example, independent generation checked 20 of 100 draws;
the coordinated generator checked all 100. Each custom draw must be a proper
list of the declared arity and satisfy every argument spec before `:pre` or the
target runs. Invalid output signals `invalid-generated-arguments`, without retries.
`:pre` still rejects valid tuples that fail its additional constraints.

Use the run's random state, as above, for seeded replay. Custom argument tuples
have no automatic shrink strategy; failures retain their original observation.
The CLOS equivalent is `:argument-generator`; `function-spec-data` includes
`:argument-generator` and the derived tuple `:argument-schema`.

## Verification evidence

Property and function checks record each failing invocation with its input,
failure identity, condition and explanation. Shrinking accepts only observations
with the original failure identity: a false result cannot shrink into an error,
and an error cannot shrink into another condition type. Within each function
contract clause, return-spec failure shapes and post-form positions must match;
the existing rule still permits crossings between return-spec and postcondition
failures with known identities. Unknown post-form identities cannot match.
Classification never calls the target again; shrinking itself executes candidates
only after checking their argument specs.

```lisp
(cl-spec:defproperty under-five ((value (range integer 0 10)))
  (< value 5))

(let ((result (cl-spec:run-property 'under-five :seed 42)))
  (list (cl-spec:property-result-shrunk-outcome result)
        (cl-spec:trial-observation-arguments
         (cl-spec:property-result-failure-evidence result))
        (cl-spec:trial-observation-arguments
         (cl-spec:property-result-shrunk-evidence result))))
;; => (:USED (6) (5))
```

A shrunk result is an observed reduction, not a guarantee of global minimality.
If none is accepted, the original observation remains available. Conses and
arrays are copied for evidence while the target receives the actual generated
objects. Detected argument mutation or a shrinker error stops the search while
preserving any earlier accepted observation. Arbitrary object state and external
state are not checkpointed. Copies and comparisons use iterative graph traversal,
and invocation provenance does not retain all trial observations.

Some check-it shrink callbacks expose internal representations, such as character
lists for strings. These are rejected when they do not satisfy the argument spec;
the original counterexample remains available if no valid reduction was observed.

Introspection records have `:entity-kind` (`:spec`, `:property`, or
`:function-spec`); existing `:kind` fields retain their node or author
classification. Results expose `property-result-entity-kind`.

Backend implementers must supply explicit nonnegative `:trials` counts and
observations for failures. Missing counts or contradictory evidence signal
`invalid-backend-result`; see specification §14 for the outcome protocol.

## Testing

```bash
rove cl-spec.asd
```

## Known limitations

`cl-spec/check-it` cannot generate values for every spec it can validate and
explain:

- `(not ...)`, a bare `(satisfies ...)`, `(instance-of ...)`, and a spec that
  refers back to itself (directly, or through `list-of`/`vector-of`/`tuple`)
  have no generator; `sample`/`generator-for` signal `generator-unavailable`.
  Validation and `explain` still work on these.
- `(and ...)` needs at least one `(type ...)` or `(range ...)` conjunct to
  generate from; an `and` of predicates alone (e.g. `(and (satisfies oddp)
  (satisfies plusp))`) signals `generator-unavailable`.
- A predicate that an `and` cannot fold into its base generator falls back to
  a guard that retries by recursing with no depth limit. A guard over a
  predicate that is rarely or never true (an unsatisfiable `satisfies`, for
  example) can exhaust the stack instead of signalling.
- A counterexample over `(range real ...)`, or any other real valued
  argument, does not shrink: check-it's shrinker treats reals as a
  non-discrete search space and returns them unchanged.
- Replaying a property run from an integer seed requires SBCL; other
  implementations signal `unsupported-seed`.

## Documentation

- `docs/cl-spec-specification-v0.2-draft.md` — the specification
- `docs/superpowers/specs/` — design documents

## License

MIT
