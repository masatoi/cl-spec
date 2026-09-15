# Structured-data walkthrough

This guide runs cl-spec's current structured-data and AND-generation features
end to end on a small pure batch-processing model. The source of truth is the
executable file [`examples/structured-data.lisp`](../../examples/structured-data.lisp);
every excerpt here is a call into that file, and the normal test suite runs the
same entry points in `tests/examples-test.lisp`, so a change that breaks this
walkthrough fails `rove cl-spec.asd`.

For exact option names and return shapes, follow the links to the
[specification](../cl-spec-specification-v0.2-draft.md) and the
[API reference](../api/README.md) rather than treating this guide as normative.

## Running it from a fresh image

Loading `cl-spec` alone does not load this example or the generator backend. Ask
for the example system explicitly: it is an ASDF package-inferred subsystem whose
`defpackage` declares the check-it generator backend, so this one form also
installs the backend that `sample` and the property and contract demos need.

```lisp
(asdf:load-system "cl-spec/examples/structured-data")

(defparameter *registry*
  (cl-spec/examples/structured-data:make-example-registry))
(cl-spec/examples/structured-data:register-example! *registry*)
```

`make-example-registry` returns a fresh registry and `register-example!` is the
only function that registers anything, so loading the example file neither draws
a value nor changes `cl-spec:*registry*`. The examples below pass `*registry*`
explicitly for the same reason.

## The model

A *window* is a closed keyword plist with integer endpoints and an optional,
unique, length-bounded tag list. `ordered-window-p` adds the cross-field
constraint `:start <= :end`; it only reads its argument:

```lisp
(defspec window
  (and (plist (:required (:start integer) (:end integer))
              (:optional (:tags (list-of (member :a :b :c)
                                         :min-length 1 :max-length 3 :unique t)))
              (:closed t))
       (satisfies ordered-window-p)))

(defspec batch (list-of window :min-length 1 :max-length 3))
```

A *batch* is a bounded list of windows. `window-span` and `total-span` are pure
functions over them. `:unique` compares elements with `EQL`; here the domain is
the finite `member` set `(:a :b :c)`, which the generator can sample without
replacement. Uniqueness of a field's value is a different thing from uniqueness
of a record's identity, which this version does not declare.

## 1. Validate and explain

```lisp
(cl-spec/examples/structured-data:demo-validation *registry*)
;; => (:GOOD-VALID T :UNORDERED-VALID NIL ... :MISSING-VALID NIL ...)
```

`validp` returns a boolean. `explain-data` returns the structured reason. For a
window whose start is after its end, the `and` reports a failed conjunct:

```lisp
(:kind :conjunct-failed
 :conjuncts ((:expected <plist descriptor> :status :satisfied)
             (:expected (:satisfies ordered-window-p) :status :failed))
 :errors ((:kind :predicate-failed :predicate ordered-window-p ...)))
```

For a value that omits the required `:end` field, the failing conjunct reports
the field position (`:errors` elided):

```lisp
(:kind :conjunct-failed ...
 :errors ((:field-path (:end) :kind :missing-key :path (:end) ...)))
```

Other structural failures use `:type-failed`, `:unknown-key`,
`:not-a-plist`, `:duplicate-key`; see §9.2 and §22 of the specification. A field
whose value is `NIL` is present, and is distinct from an absent field.

## 2. Generate and read the report

```lisp
(multiple-value-bind (values report)
    (cl-spec:sample 'window :count 5 :seed 42 :registry *registry*)
  (values values report))
```

With this seed the five windows are

```lisp
((:start -4 :end 9 :tags (:a :b :c))
 (:start 1 :end 6 :tags (:a :b :c))
 (:start 4 :end 8)
 (:start -7 :end 3)
 (:start -2 :end 10))
```

and the report is

```lisp
(:scope :request :unit :bounded-filter-source-call :policy :and-single-source-v1
 :budget 5000 :budget-source :default :default-coefficient 1000
 :requested-values 5 :generated-values 5
 :attempts 13 :rejections 8
 :phases (:generation (:attempts 13 :rejections 8)
          :shrinking (:attempts 0 :rejections 0))
 :termination :completed :exhaustion-phase nil :exhausted-at nil)
```

Read it as: one request asked for five root values, produced five, and spent
thirteen bounded-filter candidate draws, eight of which the whole-AND validator
rejected. `:requested-values`/`:generated-values` are roots;
`:attempts`/`:rejections` are candidate reservations and filter rejections. They
are different counts. A rejection here is a filter rejection, not a precondition
rejection (`property-result-rejected` counts those).

A whole-AND filter exists only when the AND has a residual constraint; a plain
type or range request reports zero attempts. The budget is shared by every
bounded filter in the request and defaults to `1000 × N`; `:generation-budget`
overrides it, and an explicit `0` is not an omission. The budget bounds bounded
filter candidate requests, not arbitrary generator internals or wall-clock time.

### Capability is construction, not success

```lisp
(cl-spec:backend-capabilities (cl-spec:current-generator-backend)
                              (cl-spec:find-spec 'window *registry*)
                              :registry *registry*)
;; => (:GENERATION :AVAILABLE :SHRINKING :AVAILABLE)
```

`:available` means a generator could be constructed, without drawing a value. It
does not promise that a draw will succeed within the budget (§38.1).

## 3. Check a function contract

```lisp
(cl-spec/examples/structured-data:demo-check-function *registry*)
;; => (:STATUS :PASSED :FAILURE-REASON NIL :REPORT (... :TERMINATION :COMPLETED))
```

`defspec-function` declares the argument and return specs; `check-function`
generates arguments, calls the function once per generated trial, and classifies
the outcome from captured evidence. The conforming `window-span` passes.

## 4. State a property

```lisp
(cl-spec/examples/structured-data:demo-property *registry*)
;; => (:NON-NEGATIVE :PASSED :ADDITIVE :PASSED)
```

Two named properties are registered. `span-is-non-negative` checks a result
property of `window-span`; `total-span-is-additive` checks that
`(total-span (list a b))` equals `(+ (window-span a) (window-span b))` for two
generated windows. Both are relations with a real body, not `(constantly t)`.

## 5. Discover specs, contracts and properties

```lisp
(cl-spec/examples/structured-data:demo-discovery *registry*)
;; => (:SPEC-NAME WINDOW :SPEC-KIND :AND
;;     :CONTRACT-KIND :FUNCTION-SPEC
;;     :PROPERTIES (SPAN-IS-NON-NEGATIVE)
;;     :SEMANTIC (... :PROPERTIES-ABOUT (SPAN-IS-NON-NEGATIVE))
;;     :CAPABILITY (:GENERATION :AVAILABLE :SHRINKING :AVAILABLE))
```

`spec-data` returns the normalized declaration, `function-spec-data` the
contract's argument and return specs, and `properties-for` / `semantic-data`
the related property names. This is the in-image introspection API; it is not a
check of the cl-mcp adapter, which lives outside this repository (§38).

## 6. Replay a run

```lisp
(cl-spec/examples/structured-data:demo-replay *registry*)
;; => (:ORIGINAL-STATUS :FAILED :REPLAY-STATUS :FAILED
;;     :ORIGINAL-SEED 7 :REPLAY-SEED 7
;;     :ORIGINAL-COUNTEREXAMPLE (W (:START -7 :END 9))
;;     :REPLAY-COUNTEREXAMPLE (W (:START -7 :END 9)))
```

Passing the earlier result as the seed reuses its recorded seed, profile and
options. Reproduction holds for the same declarations, registry, seed, backend
and deterministic functions. It is not a promise about object identity, printed
representation, elapsed time, randomness outside the run, or external state; a
readable claim is limited to the recorded configuration (§15).

## Supplementary examples

### alist and hash-table

```lisp
(cl-spec/examples/structured-data:demo-keyed-representations)
;; => (:ALIST-PRESENT-NIL T :ALIST-MISSING NIL
;;     :HASH-PRESENT-NIL T :HASH-MISSING NIL ...)
```

Both forms declare a required nullable `:note`. A present key whose value is
`NIL` is valid; an absent key is a `:missing-key` failure. The alist fixes key
comparison with `(:test equal)` for its string keys; the hash table keeps its
declared test, and a table whose actual test differs is a structure error
(§9.3).

### object-of with a custom generator, reused inside AND

```lisp
(cl-spec/examples/structured-data:demo-object-source)
;; => (:ENDPOINTS ((3 9) (0 6) (3 5)) :ALL-ORDERED T :TERMINATION :COMPLETED)
```

`object-of` observes an instance through explicit readers; it does not infer
slots with the MOP and cannot construct an instance by itself, so
`window-object-spec` names a `defgenerator`. `ordered-window-object` is an AND
whose only custom-generator conjunct is that spec, so the AND uses it as the
source and filters its draws with the whole-AND validator (§9.4, §73.4).

### tagged-by and branch targeting

```lisp
(cl-spec/examples/structured-data:demo-tagged-union)
;; error branch draws: ((:KIND :ERROR :MESSAGE ...) ...)
;; (:KIND :OTHER) -> :NO-BRANCH, :OBSERVED-TAG :OTHER, :KNOWN-TAGS (:OK :ERROR)
;; (:KIND :OK :VALUE "bad") -> :TYPE-FAILED with :BRANCH :OK
```

A tag reader selects one branch, and only that branch is validated, so a failure
names the branch. `sample :branch :error` aims generation at one branch. This is
dispatch on a data tag; it is not a function's normal-versus-error contract
(§9.5).

### Bounded-exhaustion

```lisp
(cl-spec/examples/structured-data:demo-budget-exhaustion 6)
;; => (:OUTCOME :EXHAUSTED :ATTEMPTS 6 :BUDGET 6 :REJECTIONS 6
;;     :PHASE :GENERATION :PATH (0) ... :TERMINATION :BUDGET-EXHAUSTED)
```

`(and (member 1) (satisfies evenp))` cannot be satisfied, and a human can see
that by inspection. The run stops after the explicit six-candidate budget and
signals `generation-budget-exhausted`; the condition carries the same report.
Exhaustion says this strategy did not find a value within its budget. It is not
a proof of unsatisfiability and not a counterexample from target code (§73.5).

### Target contract violation

```lisp
(cl-spec/examples/structured-data:demo-target-violation)
;; => (:STATUS :FAILED :FAILURE-REASON :RETURN-SPEC
;;     :COUNTEREXAMPLE (W (:START -7 :END 9))
;;     :SHRUNK-COUNTEREXAMPLE (W (:START 0 :END 1)) :SHRUNK-OUTCOME :USED)
```

Here inputs were generated, the deliberately wrong function was called, and the
declared return spec failed: this is a target failure, distinct from generation
exhaustion. A shrunk reduction is reported when the shrinker observed one that
kept the failure identity; no particular minimum is promised, and shrinking can
find nothing.

## What this version does and does not do

| Area | Declare and validate | Generate | Shrink | Main limit |
|---|---|---|---|---|
| `plist` fields | required/optional/closed, key identity, presence vs `NIL` | yes | yes | every field spec needs a generator |
| `alist` / `hash-table` fields | `:test`, presence vs `NIL`, duplicate-key/alist and wrong-table-test errors | yes | yes | key comparison is the declared `:test` |
| `object-of` | explicit readers only | no automatic construction | via the named generator | needs `(:generator NAME)`; no MOP inference |
| `list-of` / `vector-of` | `:min-length`, `:max-length`, `:unique` (EQL) | yes | yes | `:unique` needs a finite element domain |
| `tagged-by` | one branch per tag, branch named in errors | all branches | yes | `sample :branch` targets one branch |
| `and` | full validation always | one selected source plus a bounded filter | yes | see the AND rules above |
| `defspec-function` | argument/return/post/signals contracts | yes | yes | `:signals` excludes a normal-return contract (§17) |
| Properties | `defproperty`, `run-property`, replay | yes | yes | custom generators have no automatic shrink |
| `describe-*` | — | — | — | stubs; not usable API |

Guarantee boundaries:

- Validation predicates and readers must not modify their input or anything
  reachable from it. cl-spec neither detects nor restores a violation, so an
  admissibility, shrinking or replay guarantee that depends on such validation is
  void after one. This does not forbid a target function's intended state change,
  a runner counter update, or a property body that tests stateful behaviour.
- Validating or generating a value is separate from persisting it. Counterexample
  artifacts support version-1 values and do not serialize arbitrary objects;
  opaqueness, cycles and shared state have documented limits (§57, README).
- `:signals` and normal-return contracts are exclusive in this version, and
  expected-error contracts are not supported by runtime instrumentation.
- `describe-spec` and `describe-property` are stubs and signal
  `not-implemented`; they are not usable API.

## Where to read more

- [`README.md`](../../README.md) — entry point, short examples and limits.
- [`docs/cl-spec-specification-v0.2-draft.md`](../cl-spec-specification-v0.2-draft.md)
  — the normative contract, especially §§9.2–9.5, §10, §11, §14, §15, §22,
  §38.1, §73.4 and the §73.5 bounded-AND addendum.
- [`docs/api/`](../api/README.md) — generated from public docstrings.
- [`examples/structured-data.lisp`](../../examples/structured-data.lisp) — the code
  these excerpts call.
