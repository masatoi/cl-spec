# Input coverage

Coverage records what was tried, independently of whether execution passed.
It is opt-in and does not change `:passed` or evidence policy version 1.

```lisp
(ql:quickload :cl-spec/check-it)
(cl-spec:defproperty record-roundtrip
    ((payload (plist (:required (:n (range integer 1 3)))
                     (:optional (:memo integer)))))
  (:trials (:normal 7))
  (listp payload))

(cl-spec:coverage-schema (cl-spec:find-property 'record-roundtrip))
(let ((result (cl-spec:run-property 'record-roundtrip :seed 7
                :options '(:coverage (:mode :exercise)))))
  (cl-spec:coverage-data result))
```

Use `(:mode :observe)` to retain the ordinary generator's seeded input stream.
Use `(:mode :exercise)` to attempt supported buckets once in schema order, then
resume ordinary generation. This is a bounded plan, not a combinatorial solver.
The trial budget remains authoritative; unattempted entries stay `:pending`.
An `:attempted` entry does not claim that its bucket reached the target.

The initial provider discovers plist optional-key presence, open-plist extra-key
presence, and directly declared finite integer range lower/upper/interior buckets.
Integer endpoints are rounded inward. Singleton ranges hit both lower and upper;
ranges with no interior integers declare the interior bucket inapplicable.
Nested plists and finite references are followed. Absent parents and omitted
arguments are inapplicable, distinct from a present key whose value is NIL.
Unsupported composites, recursive references and discovery limits are reported
under `:unexpanded`; discovery is then `:partial`.

Each dimension has a structural `:id`, argument/field path, kind and buckets.
Reports save the starting definition digest, schema, capabilities, options and
per-stage counters. Reading `coverage-data` returns a copy without executing code
or consulting the current registry. Result projections and `evidence-summary`
include the same `:coverage` record.

| Stage | Meaning |
| --- | --- |
| `:generated` | The ordinary root draw was observed. |
| `:domain-valid` | Existing domain validation actually accepted the input. |
| `:pre-admitted` | Existing precondition checking admitted it. |
| `:target-observed` | The target returned or signalled an observed condition. |
| `:checked` | Final trial classification was passed or failed. |

Coverage never adds validation/predicate calls. Where domain validation is not
performed, its stage is `:not-collected`, not a numeric zero. Stage records with
`:collected` distinguish `:observed-trials`, `:unknown-trials`,
`:not-applicable-trials` and bucket counts. Buckets need not be mutually exclusive.
Shrink candidates do not contribute. Values are classified before target code can
mutate them; the collector keeps counters and bucket names, not input graphs.

`check-call` and `check-fixture` accept `:coverage '(:mode :observe)` directly and
report `:single-call` scope. Exercise is refused because these APIs do not generate.
Fixture reports describe reconstructed call arguments, never recipe fields;
their generated stage is inapplicable and checked counts wait for cleanup.
Fixture recipes and custom generator output are not rewritten for targeting.
Plist fields beneath optional or keyword arguments are observable but their
targeting is unsupported (`:argument-supply-not-targeted`): this provider does not
force the outer argument to be supplied.
`:input-unavailable` counts trials without observable input; the bounded
`:input-unavailable-reasons` counters distinguish recipe validation, setup, argument binding and
unknown reasons.

Exercise's extra-key pool defaults to `(:coverage-extra :probe-extra)`. Override
it with `:extra-keys`, a unique list of at most 64 keywords. The first key absent
from declared fields is added with NIL value. An exhausted pool is unsupported,
not a retry loop. Ordinary observe-mode generation never adds extra keys.
Capabilities describe generation and targeting separately from observed hits.

Options are closed: `:mode`, exercise-only `:extra-keys`, `:dimension-limit`
(default 1024, maximum 65536), and `:depth-limit` (default 32, maximum 256).
Discovery stops when dimensions exceed the limit or omitted-path metadata reaches
that limit. The last omission identifies the truncation point, not every omitted
path. Invalid options signal `invalid-coverage-options`.

Disabled and older result objects explicitly report missing measurement. A backend
must opt into `:coverage-v1` for generation-stage observation and exercise.
Legacy backends retain core checkpoints when they use `observe-trial` and report
ordinary trials with `note-trial-outcome`; unreported trials produce a partial
collection, and unmeasured stages remain unknown. Shrink observations without an
ordinary-trial report never contribute. Legacy backends refuse exercise.
Participating backends must open/close one run-owned collector
and account for exactly the ordinary trial count, or signal `invalid-backend-result`.

The internal extension protocol separates `definition-coverage-schema` and
`observe-coverage-dimension` from `backend-coverage-capabilities` and targeting.
Providers must emit bounded, copyable protocol data and never call application
predicates/readers. Future providers can use the same stages and saved-report shape.
This release does not measure argument supply, tagged branches, collection lengths
or combinations, and it introduces no coverage sufficiency policy. Measured plist
dimensions remain partial evidence, never a correctness proof.
