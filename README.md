# cl-spec

An executable semantic IR and property framework for Common Lisp programs,
designed for both humans and LLM coding agents.

**Status: MVP vertical slice.** Normalization, validation, structured explain,
spec introspection, the check-it generator backend, `defproperty` and the
property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `function-spec-data`) for
required and optional positional arguments and either one return value or a required error outcome,
including custom generators
for whole argument sets. Custom generators are
implemented for functions of no arguments. Runtime instrumentation supports input,
output and postcondition scopes through the optional `cl-spec/instrument` system.
The `describe-*` printers remain stubs. The cl-mcp adapter lives in cl-mcp, not here.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, structured explain, introspection, DSL | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/specs` | executable specifications of cl-spec's own APIs and semantic laws | none |
| `cl-spec/tests` | test suite | `rove` |

`cl-spec` never loads `check-it`. Load `cl-spec/check-it` to install a generator
backend into `cl-spec:*generator-backend*`.

## Usage

```lisp
(asdf:load-system :cl-spec)
(asdf:load-system :cl-spec/check-it)
```

## cl-spec's own executable specifications

Load the optional specification bundle to register contracts for thirteen public
functions and seven semantic Properties. The definitions live in
[`specs.lisp`](specs.lisp), independently of Rove, and are discoverable through
the same structured APIs used by cl-mcp:

```lisp
(asdf:load-system "cl-spec/specs")
(cl-spec:function-spec-data 'cl-spec:validate)
(cl-spec:properties-for 'cl-spec:validp)

(asdf:load-system "cl-spec/check-it")
(cl-spec:check-function 'cl-spec:validate :trials 100 :seed 42)
(mapcar (lambda (name)
          (cl-spec:result-data (cl-spec:run-property name :profile :normal :seed 42)))
        (cl-spec/specs:property-names))
```

Loading this bundle registers definitions in the current registry; it does not
instrument functions. After clearing or replacing the registry, call
`cl-spec/specs:register-specifications` to reinstall them. Normal `cl-spec` loads
do not load the bundle. Generation is needed only to execute the checks.

The contracts cover normal operation of `validp`, `validate`, `explain-data`,
`compile-validator`, `compile-explainer`, `spec-data`, `semantic-data`, and
`custom-generator-shrinker`, using
their required arguments and default keyword options. A required-error contract
covers `normalize-spec-form` on a finite malformed-DSL corpus. A Property checks
the relation between `validate`'s refusal and `explain-data`; each function name
currently has one registered function contract. Generators exercise a finite scalar/composite
DSL subset; this is not exhaustive API coverage. Custom generators preserve
original counterexamples; whole-argument generators can supply a shrinker. See specification
§68.1 for the coverage and remaining work.

### Persisting and directly rechecking a counterexample

```lisp
(let* ((artifact (cl-spec:make-counterexample-artifact result))
       (wire (cl-spec:serialize-counterexample-artifact artifact))
       (saved (cl-spec:deserialize-counterexample-artifact wire)))
  ;; After repairing the target implementation:
  (cl-spec:recheck-counterexample saved :state-policy :stateless))
```

The default `:selection :selected` prefers an accepted shrunk observation;
`:original` and `:shrunk` explicitly select either saved input. Recheck checks a
complete matching declaration digest, validates arguments and preconditions,
then invokes the current property/function once, without generation or shrinking.
Its `:status` distinguishes `:same-failure`, `:different-failure`, `:passed`,
`:definition-missing`, `:definition-mismatch`, `:incomparable-definition`,
`:input-invalid`, `:precondition-rejected`, `:unsupported` and `:contract-error`.

`:state-policy :stateless` asserts that external state needs no restoration;
without it execution is refused. Recorded or newly detected input mutation is
unsupported. Arbitrary external state is neither detected nor restored.
`result-data` captures digest omissions/exclusions, `:options` and `:provenance`
before execution. Provenance's `:collection-states` plist distinguishes `:known`,
`:unknown` (collection attempted but unavailable), and `:not-collected`. An omitted
target revision retains its legacy `:unknown` value with collection state
`:not-collected`; optional
`:target-revision` in runner options records a caller-supplied implementation
label, independent of the declaration digest. A recheck accepts its own optional
`:target-revision` label.

Artifact version 1 uses a bounded `AV1` format without the Lisp reader or symbol
interning. It supports existing package symbols, characters, integers, ratios,
finite single/double floats, simple strings, cons trees and simple general
vectors. Float type and signed zero are preserved. Sharing, cycles, opaque
objects, other arrays and absent packages/symbols are explicitly refused with
`invalid-counterexample-artifact`. Defaults limit each value to 10,000 nodes,
nesting depth 128 and 1,000,000 wire characters, with additional scalar storage
limits. A flat list consumes the node budget rather than one depth level per
cons cell; traversal and parsing use bounded iterative work lists.
Nonfinite floats are refused through the same artifact condition as other
unsupported evidence. Unsupported or excessive optional `:options`, `:provenance`
and `:capabilities` metadata is replaced with `(:unavailable t :reason REASON)`;
`:metadata-omissions` records the affected fields and reasons. These omissions
never change saved arguments, failure identity or declaration digest. If combined
optional metadata exceeds the artifact budget, it is omitted and evidence encoding
is retried. `:invalid-selection` and `:missing-shrunk-evidence` identify selection
errors directly.

Artifact v1 also preserves `:digest-omissions` and `:digest-exclusions`. The data
reader reports `:not-collected` for these fields when absent from older v1 artifacts;
absence does not mean a known empty omission list. The wire version remains unchanged.

Load the defining packages before deserialization. Artifacts are evidence records,
not authenticated data or a mechanism for restoring application state.

## Required error contracts

`:signals` requires an error escaping the target to satisfy an existing spec:

```lisp
(defun checked-integer (value)
  (cl-spec:validate (cl-spec:normalize-spec-form 'integer) value))

(cl-spec:defspec-function checked-integer
  (:args (value string))
  (:signals (type cl-spec:spec-violation)))

(cl-spec:check-function 'checked-integer :trials 50 :seed 42) ; => passed
```

Use `(and (type my-error) (satisfies my-error-details-p))` to check condition
slots, or reference a named spec. Custom condition class names require explicit
`type` or `instance-of`; a bare user symbol names a registered spec.

Normal return produces `:failed / :missing-condition`; an error that does not
match produces `:error / :condition-spec`, retaining its condition object and
structured explanation. Status distinguishes normal return from an error outcome;
use `failure-reason` to distinguish a contract mismatch from `:contract-error`.
Preconditions still gate invocation. Warnings and
non-error signals retain their ordinary behavior and do not satisfy the contract.
Internally handled errors do not satisfy it either. `program-error` and
`undefined-function`, including subclasses, always remain `:error / :condition`;
even an explicit spec accepting these classes cannot certify a broken invocation.
Predicate errors follow
the existing explainer rules; they cannot become expected target errors.

`:signals` takes one non-NIL spec and cannot coexist with `:returns` or `:post`.
`function-spec-signal-spec` returns normalized IR, and `function-spec-data`
includes its `:signals` projection. Declaration digests include the expected
condition spec and named dependencies. Shrinking preserves mismatch class and
spec-derived failure shape, and cannot cross between missing and mismatching errors.

Runtime instrumentation of `:signals` contracts is unavailable.
`instrument-function` refuses them with `unsupported-instrumentation-target`
and reason `:expected-condition-contract`, before changing the function.
This applies even to input-only or empty scopes. If an already instrumented
function's contract is changed to `:signals`, explicitly call `uninstrument-function`:
contract edits do not refresh captured checks, and a refused reinstall leaves
the existing wrapper intact.

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

## Structured plist specifications

Declare required and optional fields, with unknown keys allowed by default:

```lisp
(cl-spec:defspec user-record
  (plist
    (:required (:id integer))
    (:optional (:nickname (nullable string)))
    (:closed t)))

(cl-spec:validp 'user-record '(:id 1 :nickname nil)) ; => T
(cl-spec:validp 'user-record '(:nickname nil))       ; => NIL
(cl-spec:explain-data 'user-record '(:id "bad"))
;; The field error has :PATH (:ID).
(cl-spec:sample 'user-record :count 10 :seed 42)
```

Plists must be finite proper lists of keyword/value pairs with unique keys.
Missing fields differ from fields whose value is NIL. Order does not matter.
Use `:closed t` to reject unknown keys; the default is NIL. Empty `(plist)`
accepts any structurally valid keyword plist. Clauses and declared keys must
not repeat.

Field errors identify their key in `:path`. Structural errors use
`:not-a-plist`, `:duplicate-key`, `:missing-key`, and `:unknown-key`.
Introspection exposes `:closed` and ordered `:fields` descriptors with
`:key`, `:required`, and `:child-index` pointing into `:children`.
Declaration digests include field keys, presence requirements and child specs.

The check-it backend generates required fields and randomly includes optional
fields. It generates no unknown keys, even for open specs. Shrinking can remove
optional fields and shrink values while retaining required keys. Every child
must have a generator, including optional fields; custom generators still have
no automatic value shrink strategy.

Cross-field constraints use ordinary `and` / `satisfies`. Their automatic
generation retains the existing AND limitations below. Field metadata is
independent of storage format; alist and hash-table DSLs are not implemented yet.

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

Use the run's random state, as above, for seeded replay. Without an explicit
shrinker, custom argument tuples retain their original observation.
The CLOS equivalent is `:argument-generator`; `function-spec-data` includes
`:argument-generator` and the derived tuple `:argument-schema`.

Function checks record the target outcome separately from the contract verdict.
`trial-observation-outcome` and each `result-data` failure expose either
`(:kind :returned :values (...))` or
`(:kind :signaled :condition-type ... :condition-report ...)`. Returned conses and
arrays are captured before contract predicates can change them. The existing
`:value` remains the primary value; zero values and one `NIL` stay distinct in
`:outcome`. Older six-value evaluator extensions report `:not-collected`.
Artifact v1 still persists concrete arguments and failure identity, so opaque
returned objects do not prevent direct rechecking.

### Optional positional arguments

```lisp
(defun optional-value (&optional (value 42)) value)
(cl-spec:defspec-function optional-value
  (:args &optional (value (nullable integer) supplied))
  (:returns (nullable integer))
  (:post (if supplied (eql result value) (= result 42))))
```

After `&optional`, each declaration is `(NAME SPEC)` or `(NAME SPEC SUPPLIED-P)`.
Contract predicates receive `NIL` for an omitted value and false suppliedness;
explicit `NIL` has true suppliedness and must satisfy its spec. The target's
default forms run only in the actual call. There are no contract default forms.
Multiple optional parameters are positional: supplying a later one also supplies
every preceding one. Required parameters precede the single `&optional` marker.

The generator chooses an optional prefix, and shrinking can remove its suffix.
Saved evidence retains the raw call list, while named counterexamples include
contract values and declared suppliedness flags. Function introspection adds
`:kind :optional` and `:supplied-p` to optional entries. `defproperty` bindings
remain required pairs; `&key` and `&rest` are introduced in subsequent changes.

### Shrinking correlated arguments

A leading `:shrink` clause receives the current argument list and returns a proper
list of candidate argument lists, in preference order:

```lisp
(cl-spec:defgenerator interval-arguments ()
  (:shrink (arguments)
    (unless (equal arguments '(0 2 1))
      (list '(0 2 1))))
  (list 10000 20000 15001))
```

Use it through `(:args-generator interval-arguments)`. The runner checks each
candidate against the argument schema, then the precondition, then calls the
target. It accepts only a changed input with the original failure identity and
restarts from that input. It does not independently shrink fields. Visited inputs
are skipped, and the original observation is retained throughout.

For custom whole-argument shrinking, `check-function` and `run-property` accept
`:options '(:shrink-budget 100)`; the
default is 100 and the supported range is 0–100000. Candidate batches must be
finite proper lists within the remaining budget. An oversized batch stops the
search before invoking its candidates. Duplicates and rejected candidates consume
budget. `property-result-shrink-report` and `result-data` expose `:candidates`,
`:budget`, and `:termination`, separately from generated `:trials`; artifacts retain
this report. Built-in shrinking and older backends/artifacts use `:not-collected` when they
do not collect this report.

Malformed candidate lists, shrinker errors, and detected cons/array mutation stop
the search while preserving previous evidence. User shrinker code must terminate;
cl-spec does not interrupt arbitrary code or restore external state. Deterministic
candidate order is needed for replay, and the result is not a global minimum.
The CLOS equivalent is `:shrinker`, read by `custom-generator-shrinker`; changing
it on a source-backed generator requires matching source and draw-function updates.
The source declaration participates in the definition digest. Nested custom value
generators currently retain their no-op shrink behavior.

## Runtime instrumentation

Load the optional system, then select the checks to enforce at call sites:

```lisp
(asdf:load-system :cl-spec/instrument)

(defun positive-step (x) (1+ x))
(cl-spec:defspec-function positive-step
  (:args (x integer))
  (:pre (plusp x))
  (:returns integer)
  (:post (> result x)))

(cl-spec/instrument:instrument-function
 'positive-step :scopes '(:input :output :post))
(positive-step 1) ; => 2
;; (positive-step 0) signals an input/precondition violation before running the target.

(cl-spec/instrument:instrumented-function-p 'positive-step) ; => T
(cl-spec/instrument:uninstrument-function 'positive-step)   ; => T
```

All three scopes are enabled by default. `:input` checks arity, argument specs and
`:pre`; `:output` checks the primary return value; `:post` checks postconditions.
Checks use no generator. Violations are `cl-spec/instrument:instrumentation-violation`
conditions, a subtype of `cl-spec:spec-violation`, with function, scope and reason
readers in the instrumentation package. Existing spec-violation readers expose
structured paths and errors. The target executes once; all its return values and
conditions pass through when checks succeed. A `spec-violation` from `:pre` is an input refusal, as in `check-function`;
other precondition errors and all postcondition errors propagate. Argument and return
specs retain the ordinary validation/explanation behavior.

Use `:registry` to select a registry; the earlier positional registry argument
also works; NIL selects the current default registry. Reinstall to refresh captured
contracts or change scopes. Named spec
references resolve in the selected registry on each call. Postconditions see the
arguments after any target mutations, as in `check-function`.

Uninstrumenting restores the original only if the current definition is still
the installed wrapper. A later redefinition or `fmakunbound` is preserved. `instrumented-function-p` also drops detached
installation entries; that boolean query or uninstrumenting releases that state.
`instrumentation-status` preserves it so repeated diagnostic queries remain useful.
Only ordinary symbol-named functions outside `COMMON-LISP` are supported; macros,
special operators and generic functions are refused. Captured function objects,
lexical calls and inlined calls bypass the wrapper. Undefined targets signal
`unbound-target`; unsupported definitions signal `unsupported-instrumentation-target`
with name and reason readers. Both belong to `cl-spec-error`.

`(cl-spec/instrument:instrumentation-status 'positive-step)` returns a record
with `:status` (`:not-installed`, `:current`, `:stale`, `:indeterminate`),
`:reasons`, installed/current declaration digests and `:scopes`. It also returns
`:installed-digest-omissions`, `:current-digest-omissions` and `:digest-exclusions`.
Installed details are snapshots; current omissions come from the current query.
`:not-collected` means no corresponding inspection was performed. It does not call
the target, refresh the wrapper or discard installation evidence. Use `:registry`
when comparing against a registry other than the current default.

`(cl-spec/instrument:refresh-instrumentation 'positive-step)` explicitly refreshes
an active installation, using its stored registry and scopes unless overridden.
It compiles the new checks and captures metadata before replacing the wrapper;
a refusal preserves the old installation. Detached or absent installations are
refused, and an external redefinition is never overwritten by refresh.

Status compares captured declarations and predicate identities separately from
registered dependencies. Reinitialization, replacement, removal and a new compiled
pre/post predicate are detected. Named spec references continue resolving dynamically:
a dependency-only digest change is reported as `:dependency-status :changed`
without declaring the captured checks stale. When the local declaration also
changes, dependency comparison is indeterminate because the full digest includes
both. Incomplete digests yield
`:indeterminate` unless a known difference already establishes staleness. No
extra digest computation is added to ordinary function calls. Status cannot
prove that a closure's captured state or external application state is unchanged.
`:signals` remains unsupported for installation/refresh; after such an edit,
status detects the stale contract and explicit uninstrumentation remains required.

The argument contract describes the whole call, not just a prefix of the target's
lambda list. For example, `(:args (a integer))` admits exactly one argument even if
the target accepts optional extras. Optional contracts preserve omission; rest/key semantics remain deferred.

Violation specs are the actual argument/return IR, an argument tuple for arity, or
a predicate spec for pre/post. Precondition values are the argument list; postcondition
values are `(primary-value . arguments)`. Error records use the usual `:actual`,
`:expected`, and explainer `:kind` vocabulary.

Serialize installation/removal
with function redefinition in concurrent applications.

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
classification. `schema-info` describes the versioned Lisp protocol. All three
definition readers include `:schema-version 1`, `:record-kind :definition`,
`:definition-digest`, `:definition-digest-complete`, `:definition-digest-covers`,
`:digest-omissions`, `:digest-exclusions` and `:capabilities` on the root record. Nested specs remain ordinary IR projections.
Consumers should ignore unknown keys and explicitly handle
unsupported versions. `result-data` returns the same metadata with
`:record-kind :result`, captured before execution, plus trials, budget and the
original/selected failure evidence. Results also expose `property-result-entity-kind`.

The digest tracks stored declarations and their registered spec/generator
dependencies, including whole-argument generators. It excludes target/helper
implementations, captured/external state, source locations and backend settings.
It is a bounded, non-cryptographic change detector; it does not prove that a run
is reproducible. Missing dependencies, opaque values or exceeded limits produce
NIL with `:definition-digest-complete NIL`, never a trusted partial digest.
`definition-digest` returns `(values digest complete-p omissions)`; existing digest
bytes and the first two values retain their meaning. Each omission is
`(:kind KIND :path PATH :target SYMBOL-OR-NIL :reason REASON)`. Kinds are
`:unresolved-reference`, `:opaque-definition`, `:missing-source`, `:opaque-value`,
`:uninterned-symbol` and `:resource-limit`. Stable traversal paths identify the
first occurrence; independent omissions are collected within the traversal limits.
`:digest-exclusions` lists the intentional scope exclusions above and does not make
an otherwise complete digest incomplete.

Capabilities describe the currently installed backend: generator construction
may be `:available`, `:unavailable` or `:unknown`; shrinking can additionally be
`:none` when disabled, when the root custom generator has no shrinker, or when
all tuple elements lack a shrink strategy. Empty plists and plists containing only
required constant/custom fields also have no shrink strategy; optional field
removal is a strategy even when field values cannot shrink.
Legacy non-plist constants retain the backend's coarse `:available` shrinking
report; the plist-specific check excludes constant children from its strategy.
Construction availability does not promise a valid draw or an accepted reduction.
No trials, targets or custom generator bodies run during built-in introspection.
Runs reuse capabilities captured from the actual compiled generator; older
backends that omit this report produce `:unknown` capabilities in results.
Instrumentation is `:available` for supported function targets after loading
`cl-spec/instrument`, independently of the generator backend. This denotes support,
not active wrapping; use `cl-spec/instrument:instrumented-function-p` for active state.
See specification §38.1 for the full contract.

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

### Programmatic definition invariants

`property`, `function-spec` and `custom-generator` validate construction,
reinitialization and class-update initialization. Arguments normalize to IR;
names, bindings, trial budgets, callable predicates, source and metadata shapes
are checked even without a DSL macro. Properties require a compiled function;
custom evaluator subclasses specialize `cl-spec/src/property:validate-property-executable`.
Direct closures without source are supported, with incomplete declaration digests.
Body/function updates and source-bearing generator source/function updates must
supply both halves together. Function pre/post forms and predicates also change
together. These checks enforce representation consistency, not equivalence
between arbitrary supplied code and source text.

Registry writes call `validate-definition` before replacing definitions or
changing reverse indexes. Refused updates restore participating slot bindings,
including previously unbound slots. Subclasses extend
`definition-validation-slots` with an `append` method, and specialize
`validate-definition` (calling the next method) for their own invariants.
Successful changes to a registered property's targets/tags require explicit
re-registration to update indexes. Arbitrary destructive mutation inside slot
values and raw `slot-value` writes are outside automatic update validation;
registration validates again. The generic registry protocol still permits opaque
backend values through the default validation method.

After loading `cl-spec/instrument`, call
`cl-spec/specs:register-instrumentation-specifications` to register the optional
status API shape contract. The normal self-spec bundle does not load instrumentation.
