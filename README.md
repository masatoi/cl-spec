# cl-spec
[![CI](https://github.com/masatoi/cl-spec/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/masatoi/cl-spec/actions/workflows/ci.yml)
[![Lint](https://github.com/masatoi/cl-spec/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/masatoi/cl-spec/actions/workflows/lint.yml)
[![API docs](https://github.com/masatoi/cl-spec/actions/workflows/docs.yml/badge.svg?branch=main)](https://github.com/masatoi/cl-spec/actions/workflows/docs.yml)

An executable semantic IR and property framework for Common Lisp programs,
designed for both humans and LLM coding agents.

**Status: MVP vertical slice.** Normalization, validation, structured explain,
spec introspection, the check-it generator backend, `defproperty` and the
property runner with seed, replay and shrinking are implemented, as are
function specs (`defspec-function`, `check-function`, `check-call`,
`function-spec-data`) for
required/optional positional, keyword and rest arguments, primary or fixed multiple
return values, or a required error outcome,
named per-condition `:cases`, and explicit pre-observation (`:capture`) plus
post-run state constraints (`:state-post`),
including custom generators
for whole argument sets. `check-call` checks one caller-supplied invocation
through the same single-trial path, with no generation. Custom generators are
implemented for functions of no arguments. Runtime instrumentation supports input,
output and postcondition scopes through the optional `cl-spec/instrument` system;
a state-observing contract refuses instrumentation.
The `describe-*` printers remain stubs. The cl-mcp adapter lives in cl-mcp, not here.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, structured explain, introspection, DSL | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/specs` | executable specifications of cl-spec's own APIs and semantic laws | none |
| `cl-spec/tests` | test suite | `rove` |
| `cl-spec/examples/structured-data` | executable structured-data integration example | `check-it` |
| `cl-spec/examples/function-spec-cases` | executable named-case Function Spec example | `check-it` |
| `cl-spec/examples/stateful-withdraw` | executable capture/state-post Function Spec example | `check-it` |

`cl-spec` never loads `check-it`. Load `cl-spec/check-it` to install a generator
backend into `cl-spec:*generator-backend*`.

## Usage

```lisp
(asdf:load-system :cl-spec)
(asdf:load-system :cl-spec/check-it)
```

For a runnable tour of the structured-data and AND-generation features, see the
[structured-data walkthrough](docs/guides/structured-data-walkthrough.md). Its
system is an inferred subsystem of the package-inferred primary, and its own
`defpackage` declares the check-it backend, so loading it on its own is enough
to run every demo:

```lisp
(asdf:load-system "cl-spec/examples/structured-data")
```

## cl-spec's own executable specifications

Load the optional specification bundle to register contracts for twenty-eight
public functions and thirty-one semantic Properties. The definitions live in
[`specs.lisp`](specs.lisp) with fixtures in
[`self-spec-fixtures.lisp`](self-spec-fixtures.lisp), independently of Rove, and
are discoverable through the same structured APIs used by cl-mcp:

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
`compile-validator`, `compile-explainer`, `spec-data`, `semantic-data`,
`definition-digest`, `find-spec`, `custom-generator-shrinker`,
`trial-observation-outcome`, `schema-info`, `make-hash-table-registry`,
`function-spec-data`, `property-data`, `definition-description`, the
property/function argument-schema and raw-call projection APIs, `result-data`,
`observation-failure-p`, `make-counterexample-artifact` and
`recheck-counterexample`, using their required arguments and default or declared
keyword options. A required-error contract covers `normalize-spec-form` on a
finite malformed-DSL corpus, and malformed surface declarations are refused at
macroexpansion. Properties check the relations between validation and
explanation (structured, compiled and rendered), registry round trips and reverse
indexes, collection and plist semantics, runner seed replay, artifact round trips
and failure-identity reflexivity. Two laws run the generators themselves over a
small built-in spec corpus: every generated value must satisfy its own spec, and
every retained shrunk counterexample must be a schema-valid input that still
fails identically when rechecked. Loading `cl-spec/instrument` and calling
`cl-spec/specs:register-instrumentation-specifications` adds the optional
instrumentation contracts and two install/uninstall laws. Generators exercise a
finite scalar/composite DSL subset, including `MEMBER`, `VECTOR-OF` and `PLIST`;
this is not exhaustive API coverage. Custom generators preserve
original counterexamples; whole-argument generators can supply a shrinker. See
[the self-specification guide](docs/guides/self-specification-guide.md) for how
to isolate the bundle's registry, find a symbol's contract and laws, read
`:case-report`/`:capture`/`:state-post` evidence, and run the fault-injection
and repair-comparison tasks, and specification §68.1 for the coverage and
remaining work.

The bundle now also exercises the newer clauses on its own API: `validate`
declares named `:conforming` and `:refused` cases in one contract, a
`registry-register-property` contract captures the target registry's public
readers before a new, replacement or refused write and checks the after-state
with `:state-post`, and two laws keep the `function-spec-data` and `result-data`
projections faithful to the declared cases, captures and state evidence. Two more
laws cover `check-call`: one pins the passing, failing-return and
precondition-rejected classifications and the `call-check-data` envelope against
anonymous contracts, and one declares a named case with capture and state-post on
the counting fixture and checks both the passing and the violating one-shot
result. The self-spec suites compare each run against the property's declared
`:trials` budget instead of assuming a shared trial count.

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

## Named per-condition cases

`:cases` requires a different behaviour per input condition, instead of one
outcome for every admitted input. The common `:pre` still bounds the region; the
case conditions select the required behaviour inside it.

```lisp
(defun remaining-balance (balance amount)
  (if (<= amount balance)
      (- balance amount)
      (error 'insufficient-funds)))

(cl-spec:defspec-function remaining-balance
  (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
  (:cases
    (:sufficient-funds
      (:when (<= amount balance))
      (:returns (range integer 0 *))
      (:post (= result (- balance amount))))
    (:insufficient-funds
      (:when (> amount balance))
      (:signals (type insufficient-funds)))))

(cl-spec:check-function 'remaining-balance :trials 100 :seed 42)
```

Each case is a unique keyword name, an optional docstring, exactly one
`(:when FORM)` and exactly one of `(:returns SPEC)` or `(:signals SPEC)`; a
`:returns` case may add `:post` or `:post-values`, a `:signals` case may not in
this version. That refusal is judged by clause occurrence, so an empty `(:post)`
is refused too, and `:post`/`:post-values` are mutually exclusive inside a case
just as they are at the contract level. `:args`, `:args-generator` and the common
`:pre` stay top-level.
`:cases` cannot be combined with a top-level `:returns`, `:signals`, `:post`,
`:post-values` or `:state-post`; there is no inherited common outcome. A case
cannot declare its own arguments or precondition, nest `:cases`, or use `:else`
or a priority.

Selection is exclusive, not first-match: after the common `:pre` admits an input,
every guard runs in declaration order and exactly one must be true. `:when t` is
an ordinary always-true form, not an implicit `:else`. Zero matches, several
matches and a guard that signals are contract-side errors reported as `:error` /
`:contract-error` with `:failure-phase :case-selection`: the target is not
called, no case is counted, the run is not shrunk, and no target counterexample
is saved. A `spec-violation` from a guard is such an error; only the common
`:pre` treats that as a refusal. The phase is recorded by the classifier where
selection failed, never inferred from a condition's class, so a target that
signals the public `case-selection-error` itself stays an ordinary target failure
whose evidence may be shrunk and persisted.

`function-check-result-case-report` and `result-data`'s `:case-report` report the
declared cases, the calls and outcomes actually observed per case, the selection
errors, and the cases no trial reached:

```lisp
(:selection :exclusive :unit :normal-trials
 :declared-cases (:sufficient-funds :insufficient-funds)
 :cases ((:name :sufficient-funds ... :called 62 :passed 62 :failed 0 :error 0)
         (:name :insufficient-funds ... :called 38 :passed 38 :failed 0 :error 0))
 :case-selection-errors 0 :capture-errors 0 :never-called nil)
```

A successful expected-error trial counts as a pass for its case. `:passed` means
no violation was observed in the trials that ran, not that every case ran: read
`:never-called`. Counters cover ordinary trials only, so shrinking and
precondition refusals are not counted and `trials - rejected` counts trials that
reached selection rather than target calls. A contract error raised while
classifying a selected case is counted as that case's `:error` and keeps the case
in its evidence and identity, because the target was called. A participating
backend opens the report before its first draw, so zero trials and a first draw
that exhausts the generation budget report known zeros (the exhaustion itself
under `:failure-phase :generation`); a result that did not go through a
function-check run, and a backend that never opens reporting, answer
`:not-collected` instead. The selected case's name is
part of the failure identity (`(:case NAME . existing-signature)`), so shrinking,
replay and counterexample artifacts stay inside that case;
`function-spec-data` exposes ordered `:cases` with `:case-selection :exclusive`,
and the digest covers them.

Runtime instrumentation of a case-carrying contract is unavailable:
`instrument-function` refuses with `unsupported-instrumentation-target` and
reason `:named-cases-unsupported`, before changing the function.

For a runnable tour of both behaviours, the duplicate and missing conditions, and
an unchecked case, see the
[cases walkthrough](docs/guides/function-spec-cases-walkthrough.md).

## Checking one concrete invocation

`check-call` checks one caller-supplied argument list against a registered
Function Spec without generating, shrinking or replaying anything:

```lisp
(defun withdraw (account amount)
  (decf (account-balance account) amount)
  amount)

(cl-spec:defspec-function withdraw
  (:args (account (satisfies account-p)) (amount (range integer 1 200)))
  (:capture (balance-before (account-balance account)))
  (:returns integer)
  (:post (= result amount))
  (:state-post (= (account-balance account) (- balance-before amount))))

(cl-spec:check-call 'withdraw (list account 40))
;; => a CALL-CHECK-RESULT; (:status :passed) when the one call satisfies the contract

(let ((result (cl-spec:check-call 'withdraw (list account 40))))
  (cl-spec:call-check-result-status result)        ; :passed / :failed / :error / :rejected
  (cl-spec:call-check-result-failure-phase result) ; e.g. :state-post, or NIL
  (cl-spec:call-check-data result))                ; version 1 structured record
```

`check-call` takes a Function Spec designator (a name or the `function-spec`
object), the explicit raw argument list exactly as `apply` on the target would
receive it, and `:registry` (default `cl-spec:*registry*`). The list follows the
declared call layout, so required, `&optional`, explicit `&key`,
`&allow-other-keys` and `&rest` all bind as they do in generated checking, and
present values are validated against the declared argument specs before the
target is reached. The reason is decided by the call layout, not by the error
kind: `:shape` means the call itself was malformed, while `:argument-spec` means
the layout was fine but a value missed a declared spec (including a composite
spec's own arity, key or sequence errors). Unknown names signal
`unknown-function-spec`, a missing function signals `unbound-target`, and an
inadmissible call signals `invalid-call-arguments` with a `:reason` of `:shape`
or `:argument-spec` and standard EXPLAIN-DATA `:errors` (`:kind`, `:path`,
`:actual`, `:expected`) even for a non-list, vector, dotted or circular list.

A `:pre` refusal is not an error: it is a result whose status is `:rejected`,
using the same `precondition-refuses-p` semantics as generated checking. Beyond
the shared validation, `check-call` uses the same single-trial path as
`check-function` -- case selection, one target invocation, `:returns` /
`:signals` / `:post` / `:post-values` classification and `:state-post` -- so both
entry points classify the same invocation identically. The target is called
exactly once when the input reaches the invocation, and zero times when the
shape is invalid, a declared argument spec fails, `:pre` refuses the input,
`:capture` signals or case selection fails. Error handling is the shared
evaluator's, unchanged: `:capture`, case guards and `:state-post` observe every
error (including `undefined-function` and `program-error`) and report their own
structured contract errors (`capture-error`, `case-selection-error`,
`state-post-error`), while a broken `:pre`, `:post` or spec predicate lets those
conditions propagate to the caller rather than becoming a target finding. A
target that signals either is an ordinary `:error` / `:condition` observation.

The result is a `call-check-result`, not a `property-result`: there is no seed,
trial budget, profile, shrink report or generation report to report, and
`call-check-data` reuses only the version 1 schema envelope, the declaration
digest and the existing observation projection. A state-observing contract may
be checked once because the caller supplies the fresh state, but this does not
make that state restorable, reproducible or persistable, and it relaxes none of
the existing stateful restrictions. No generator backend is required: `check-call`
works with only the core `cl-spec` system loaded.

## State observation and post-run constraints

`:capture` observes values before the call; `:state-post` checks after the call
that state relates, as declared, to the inputs and the captured values. This is
state **observation**, not state restoration: it detects that a declared
observation changed and that a declared relation failed, and it does not freeze,
deep-copy, restore or prove anything stayed unchanged during the call.

```lisp
(defstruct (account (:constructor make-account (balance id))) balance id)

(cl-spec:defspec-function withdraw!
  (:args (account (satisfies account-p)) (amount (positive-money)))
  (:capture
    (balance-before (account-balance account))
    (id-before      (account-id account)))
  (:cases
    (:sufficient-funds
      (:when (<= amount balance-before))
      (:returns receipt-spec)
      (:state-post
        (= (account-balance account) (- balance-before amount))
        (eql (account-id account) id-before)))
    (:insufficient-funds
      (:when (> amount balance-before))
      (:signals (type insufficient-funds))
      (:state-post
        (= (account-balance account) balance-before)
        (eql (account-id account) id-before)))))
```

- `:capture` is top-level, at most once, and takes one or more exact
  `(NAME FORM)` bindings. Each form runs once in declaration order and sees the
  arguments and the earlier capture values; only the primary value is bound, and
  a captured `NIL` is a value rather than an absence. A capture variable is
  **not** a target argument: the argument schema, generator and actual call are
  unchanged. Capture observes a value, so `(:capture (before account))` does not
  preserve the account's earlier contents.
- `:state-post` is one clause with one or more forms, top-level for a case-less
  contract or inside each case (never both). It runs only after the outcome
  contract passed, treats `NIL` as a violation and a signalled error as a
  contract error, and binds no implicit `RESULT`, condition or raw outcome. Its
  failure identity is `(:state-postcondition INDEX)`, or
  `(:case NAME :state-postcondition INDEX)` inside a case.
- A capture failure calls no target and is `:error` / `:contract-error` with
  `:failure-phase :capture`. A state-post violation is `:failed` /
  `:state-postcondition`; a state-post form that signals is `:error` /
  `:contract-error` with `:failure-phase :state-post`. Both keep the raw target
  outcome and count the call against the selected case. A `:signals` case may
  carry `:state-post`; the existing `:signals` / `:post` exclusivity is
  unchanged.
- An outcome that failed first keeps its existing classification and leaves
  state-post `:not-evaluated` with a reason; an unrun check is never reported as
  passed.

The trial's state evidence is on `trial-observation-state` and in `result-data`
under `:state`; `function-spec-data` exposes the declaration under `:capture`
and `:state-post`; `definition-digest` covers names, order, source and the case
association. Captured values are an ordered `((name . value) ...)` alist, and a
value the evidence snapshot cannot preserve is reported as an explicit
`:opaque-value` placeholder rather than a live reference. `check-function` runs
such a contract, but this version does not
shrink it (`:shrink-report` says `:state-restoration-unavailable`), replay a past
result into it (`unsupported-stateful-operation`, through `check-function` or the
property runner's `run-property`/`replay-property`), save it as a counterexample
artifact (`:stateful-contract-unsupported`) or instrument it
(`:state-constraints-unsupported`); a new run with an integer seed is allowed and
the author supplies the fresh initial state. Observing equal before and after is
not a proof that nothing changed in between, and this feature does not claim
atomicity, concurrency safety, crash safety or the absence of external I/O.

For a runnable tour — a correct update, a forgotten update, a refusal after a
partial update, a changed identifier, a verification error and the first-version
limits — see the
[state observation walkthrough](docs/guides/state-observation-walkthrough.md).

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

Cross-field constraints use ordinary `and` / `satisfies`:
`(and (plist ...) (satisfies ordered-p))` validates and generates. Field metadata
is independent of storage format, and the same fields can be declared as an
`alist`, a `hash-table`, an `object-of`, or dispatched by a `tagged-by` union.
See the [structured-data walkthrough](docs/guides/structured-data-walkthrough.md)
and the AND rules under [Known limitations](#known-limitations).

## Collection length and uniqueness

`list-of` and `vector-of` accept length and uniqueness options:

```lisp
(cl-spec:defspec small-batch
  (list-of integer :min-length 1 :max-length 100))

(cl-spec:defspec distinct-ids
  (vector-of (range integer 0 1000) :min-length 2 :unique t))
```

`:min-length` defaults to 0, `:max-length` defaults to unbounded and accepts `*`
as the unbounded marker, and `:unique` defaults to NIL. `:unique` compares
elements with `EQL`. Length violations explain as `:too-short` / `:too-long`
with `:minimum-length` / `:maximum-length` and `:actual-length`; a repeat
explains as `:duplicate-element` at the later element's `:path`, with
`:first-index` naming the earlier occurrence.

The constraints reach generation and shrinking: lengths are drawn inside the
declared range, and a shrink never removes past `:min-length`. `:unique`
generation draws distinct elements from a finite element domain. A finite
integer `range` is sampled directly, so any width works and does not widen the
generated collection length; fractional endpoints admit the integers between
them, as validation reads them; `member`,
`boolean`/`null`, `nullable` and `or` domains are materialized and are limited to
1000 values, and a larger domain signals `generator-unavailable`. A `:unique`
element spec with no finite enumeration, or one whose custom generator owns its
distribution — including a custom generator nested inside a `nullable` or `or`
node — signals `generator-unavailable` rather than retrying collisions
forever. A collection whose `:max-length` is 0 generates
the empty collection without compiling its element spec, and so does a `:unique`
collection whose finite element domain is empty when `:min-length` is 0. Element-wise shrinking
replaces an element only with a value the element shrinker reported through the
shrink callback, so a value that passes the property or fails the element spec
never becomes part of the recorded counterexample.

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

### Fixed multiple return values

```lisp
(defun divide-with-remainder (numerator denominator)
  (floor numerator denominator))
(cl-spec:defspec-function divide-with-remainder
  (:args (numerator integer) (denominator (range integer 1 20)))
  (:returns (values integer integer))
  (:post-values (quotient remainder)
    (= numerator (+ (* quotient denominator) remainder))
    (<= 0 remainder (1- denominator))))
```

`(:returns (values SPEC...))` checks the exact count and each value in order.
`(:returns (values))` accepts zero values, while `(values null)` requires one NIL.
Ordinary `(:returns SPEC)` still checks only the primary value, treating zero
values as NIL. The `values` declaration is specific to Function Spec returns.

`:post-values` explicitly names every return and cannot coexist with `:post` or
`:signals`. It requires a fixed return declaration, a body, and distinct bindable
names that do not collide with arguments, suppliedness variables, or `RESULT`.
`RESULT` still means the primary value in either post clause. Existing `:post`
also works with a fixed return declaration. CLOS construction accepts
`:return-spec '(values ...)` and `:post-value-variables '(...)`; its compiled
post predicate receives the full value list before the bound arguments.
`function-spec-post-value-variables` returns `:primary` for an ordinary post.

Count failures distinguish `:missing-values` and `:extra-values`; per-value
errors retain their zero-based position in `:tuple-path`. Shrinking preserves
that position and does not cross a fixed return violation into a post violation.
Results retain primary `:value` and all frozen values in `:outcome`. Artifact v1
persists the new `:return-values` failure identity for direct recheck; it still
requires only the concrete inputs to be serializable. Definition/result schema
v1 gains the `:values` IR kind and explicit `:post-value-variables` metadata.

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
remain required pairs.

### Keyword arguments

```lisp
(cl-spec:defspec-function lookup-page
  (:args (query string) &key ((:limit limit) integer supplied))
  (:returns list)
  (:pre (or (not supplied) (plusp limit))))
```

Each keyword declaration explicitly pairs the external keyword with its variable:
`((:KEYWORD VARIABLE) SPEC [SUPPLIED-P])`. This supports aliases and requires no
runtime symbol interning. Omitted values bind `NIL`; suppliedness distinguishes
explicit `NIL`. Repeated call keys bind and validate their first value, as Common
Lisp does; later duplicate values are ignored. Argument order is passed unchanged
to the target and retained in artifacts.

The keyword tail must have an even length and keyword keys. Unknown keys are
refused unless the declaration ends in `&allow-other-keys` or the first call-side
`:allow-other-keys` value is true. That control keyword is reserved and cannot be
declared as a parameter. Optional parameters consume their positions before the
keyword tail: all optionals must be supplied to reach keyword arguments.
Generation includes declared key pairs; shrinking can remove whole pairs.

### Rest arguments

```lisp
(defun total (&rest items) (reduce #'+ items :initial-value 0))
(cl-spec:defspec-function total
  (:args &rest (items (list-of integer)))
  (:returns integer)
  (:post (= result (reduce #'+ items :initial-value 0))))
```

`&rest (NAME WHOLE-LIST-SPEC)` declares exactly one parameter without a suppliedness
flag. Its spec validates the entire remaining list, including the empty list;
use `(list-of integer)` for homogeneous elements or `(tuple integer string)`
for a fixed heterogeneous tail. Required and optional parameters consume their
positions first. Predicates receive the original remaining list, preserving its
objects and identity, and the rest binding is always present.

An `&key` section may follow the rest declaration. Both see the same tail,
including duplicate keys and control pairs: the whole-list rest spec and the
keyword rules must both hold. Without `&key`, generation uses the whole-list rest
spec's generator. With `&key`, an exact, unannotated `(list-of t)` rest spec uses
keyword generation, and a length-constrained universal one — `(list-of t
:min-length N [:max-length M])` — is filled with keyword pairs whose total length
stays inside those bounds; a minimum longer than the distinct keyword count reuses
declared keywords, which a raw call allows because the first occurrence binds, and
an empty `&key` section is filled with the standard `:allow-other-keys` control
pair rather than signalling that no keyword can be generated. A rest spec
registered under a name is classified like the same spec written inline —
reference chains are followed — while a name annotated with a custom generator
keeps that generator instead of the keyword shortcut. Every pair —
declared or control — is drawn through the backend's one generator protocol, so a
keyword whose value spec compiles to a constant receives that constant: `null`,
`(member nil)` and a reference to either generate `NIL`, never `T`.
Other rest specs use their own generator and try up to
100 candidate calls against the complete argument schema; exhaustion signals
`generator-unavailable`. Custom generator annotations do not bypass this check.
Rejected generated candidates never reach the target. Shrinking also checks both
constraints before execution, and removes a keyword pair — including the
`:allow-other-keys` control pair — only while the call still satisfies the whole
argument schema, so the advertised shrinking capability matches what shrinking
can actually propose. Raw calls must remain finite proper lists. Introspection marks the parameter `:kind :rest`; rest declaration changes
participate in the definition digest.

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
`:pre`; `:output` checks the primary or fixed multiple-value return contract; `:post` checks postconditions.
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
the target accepts optional extras. Optional contracts preserve omission; rest contracts validate the whole remaining list.

Violation specs are the actual argument/return IR, an argument tuple for arity, or
a predicate spec for pre/post. Precondition values are the argument list; postcondition
values are `(primary-value . arguments)` for `:post` and
`(returned-values-list . arguments)` for `:post-values`. With only `:post` scope
enabled, explicit value bindings use NIL for absent values and ignore extra values;
return count enforcement belongs to `:output`. Error records use the usual `:actual`,
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
- `(and ...)` generates from one source chosen by a fixed policy: the AND's own
  `(:generator NAME)`, else a unique conjunct carrying a custom generator, else
  the folded `(type ...)`/`(range ...)` base, else the first conjunct whose
  ordinary construction succeeds. An `and` of predicates alone (e.g.
  `(and (satisfies oddp) (satisfies plusp))`) signals `generator-unavailable`.
- A conjunct the source cannot discharge is enforced by a bounded filter that
  re-checks the whole `and`. One generation request shares a budget of
  `1000 × N` candidate reservations (`N` is the requested value or trial count;
  `sample ... :generation-budget` overrides it), and running out signals
  `generation-budget-exhausted` with the attempt, rejection and phase counts.
  That means this strategy did not find a value within its budget; it does not
  prove the spec is unsatisfiable.
- Validation predicates and readers must not modify the value they are given or
  anything reachable from it (plist/alist entries, hash-table entries,
  array/vector elements, CLOS or structure slots, or a mutable object shared
  inside the input). cl-spec neither detects nor restores a violation, so an
  admissibility, shrinking or replay guarantee that depends on such validation is
  void after one.
- A counterexample over `(range real ...)`, or any other real valued
  argument, does not shrink: check-it's shrinker treats reals as a
  non-discrete search space and returns them unchanged.
- Replaying a property run from an integer seed requires SBCL; other
  implementations signal `unsupported-seed`.

## Documentation

- [`docs/api/`](docs/api/README.md) — API reference for the public packages,
  generated from their docstrings
- [`docs/guides/structured-data-walkthrough.md`](docs/guides/structured-data-walkthrough.md)
  — runnable structured-data integration walkthrough
- [`docs/guides/function-spec-cases-walkthrough.md`](docs/guides/function-spec-cases-walkthrough.md)
  — runnable named per-condition Function Spec walkthrough
- [`docs/guides/state-observation-walkthrough.md`](docs/guides/state-observation-walkthrough.md)
  — runnable capture and post-run state constraint walkthrough
- [`docs/guides/self-specification-guide.md`](docs/guides/self-specification-guide.md)
  — loading, isolating, exploring and running the executable self-specifications,
  and the fault-injection and repair-comparison tasks in [`eval/`](eval/README.md)
- [`docs/cl-spec-specification-v0.2-draft.md`](docs/cl-spec-specification-v0.2-draft.md)
  — the specification
- [`docs/superpowers/specs/`](docs/superpowers/specs/) — design documents, including
  historical proposals; read them as records of when they were written, not as
  the current usage guide
- [`examples/structured-data.lisp`](examples/structured-data.lisp) and
  [`examples/function-spec-cases.lisp`](examples/function-spec-cases.lisp) — the
  executable examples the guides run
- [`examples/stateful-withdraw.lisp`](examples/stateful-withdraw.lisp) — the
  executable capture/state-post example the state observation guide runs

The API reference is regenerated and committed by CI after every push to
`main`. Regenerate it locally with:

```lisp
(asdf:load-system "cl-spec/api-docs")
(cl-spec/api-docs:generate-api-docs)
```

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
