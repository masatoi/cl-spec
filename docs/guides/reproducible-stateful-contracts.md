# Reproducible stateful function checks

A function contract can declare an explicit `:fixture` to reconstruct its initial
state for every trial and shrink candidate. The runner generates and persists a
**recipe**, not the mutable object the target receives.

The first implementation supports `:isolation :fresh`: fixture-owned in-memory
state, built anew for each call. It does not restore a caller's existing object,
roll back a database, or supervise a killed worker.

## Run the executable example

```lisp
(asdf:load-system "cl-spec/examples/reproducible-withdraw")
(defparameter *example-registry*
  (cl-spec/examples/reproducible-withdraw:make-example-registry))
(cl-spec/examples/reproducible-withdraw:register-example! *example-registry*)
(cl-spec/examples/reproducible-withdraw:demo-recheck *example-registry*)
;; => (:STATUS :FAILED :SHRUNK-RECIPE (1 7 1)
;;     :ARTIFACT-VERSION 2 :RECHECK :SAME-FAILURE)
```

The recipe means initial balance, account ID and withdrawal amount. The
deliberately broken function returns a receipt but never updates the account.
Every candidate gets a fresh account structure. The accepted recipe retains the
same state-post failure, is serialized using the bounded reader-free codec, and
is reconstructed for one direct recheck.

Loading the example defines its functions and installs the check-it backend.
Registration and execution occur only through the explicit entry points.
The mirrored suite is `tests/reproducible-withdraw-example-test.lisp`.

## Declare a fixture

```lisp
(cl-spec:defspec-function increment-cell!
  (:args (cell (list-of integer)))
  (:fixture
    (:isolation :fresh)
    (:version 1)
    (:recipe (recipe integer))
    (:setup (context)
      (let ((cell (list recipe)))
        (setf (gethash :cell context) cell)
        (list cell)))
    (:cleanup (context)
      (declare (ignore recipe))
      (clrhash context)))
  (:capture (before (car cell)))
  (:returns integer)
  (:state-post (= (car cell) (1+ before))))
```

The application supplies `increment-cell!`. All five fixture clauses are
required and unique. `:version` is a positive integer; change it when helper
changes alter the meaning of state construction.

`:recipe` binds one name to a value matching its spec. Setup and cleanup each
receive that recipe and a context with their declared name. Context is a fresh
EQ hash table, never persisted. Setup returns the raw argument list passed to
the target. Cleanup's return value is ignored.

The recipe binding is local to the hooks. It is not an implicit target argument
or a binding in preconditions, cases, captures or postconditions.
`:args` continues to describe actual calls, including optional/key/rest arguments.
`:fixture` and `:args-generator` are exclusive; attach a custom generator to the
recipe spec instead. A direct custom recipe shrinker is supported.

A recipe must fit the existing AV1 bounded tree codec. Cycles, shared compound
values, uninterned symbols and opaque objects are refused before setup.
Setup receives a separate copy. It must not mutate that recipe, including by
passing a recipe subobject to a mutating target without copying it.

The fixture author promises that the recipe determines the meaningful initial
state. Capture is still observation, not automatic copying or rollback.
Clocks, ambient randomness, global objects and external services are not
checkpointed. Dependency implementations and closure state are excluded from
declaration digests, so fixture version discipline matters.

## Three execution modes

| Operation | Input | Generation | Fixture ownership |
|---|---|---|---|
| `check-call` | Actual raw argument list | None | Caller; no fixture hooks |
| `check-fixture` | One recipe | None | One setup/evaluation/cleanup |
| `check-function` | Generated recipes | check-it | Fresh lifecycle per trial/candidate |

```lisp
(cl-spec:fixture-check-data
  (cl-spec:check-fixture 'increment-cell! 7))
```

This core operation does not load a generator backend. The result has
`:schema-version 2`, `:record-kind :fixture-check`,
`:input-kind :fixture-recipe`, `:recipe`, `:status`, `:reason`,
`:lifecycle` and the inner contract's `:observation`.

The `:fixture-protocol` entry in `schema-info` publishes supported result and
artifact versions, isolation modes and lifecycle states.

Generated fixture results also use schema version 2. Their counterexample
accessors name the recipe variable; they do not claim it is the raw target call.
Diagnostic call arguments and values use availability records so an opaque
instance is not presented as frozen historical data.

## Cleanup and failure handling

Setup starts inside an `unwind-protect`. Once it starts, cleanup is attempted
once even after partial setup, a precondition refusal, capture/guard failure,
target error, or a state-post violation. Cleanup must handle an empty or
partially populated context.

Each run captures its setup and cleanup functions before generation. Redefining
the registered fixture during a trial does not change that run's later hooks;
a new run captures the new definition.

The existing target evaluator runs once. State-post runs before cleanup.
Evidence is captured before cleanup can alter disposable objects.

A cleanup error stops the run and any shrink search. Results retain the inner
contract observation and separately report the lifecycle failure; a passed
target outcome cannot turn a failed cleanup into a passed run.

Lifecycle `:state` is `:not-acquired`, `:released`, or `:unknown`.
`:released` means the declared cleanup completed, not that cl-spec inspected
all reachable state or verified a rollback. `:unknown` is used when cleanup
failed. Arbitrary outward control transfers propagate after cleanup; they do not
produce fabricated successful results. Cleanup itself must not escape outward.

A process kill or crash can bypass Lisp cleanup entirely. This core feature
cannot return a record from a dead process; host supervision remains separate.
Database isolation, asynchronous tasks and external I/O are outside `:fresh`.

## Save and recheck a counterexample

```lisp
(let* ((result (cl-spec:check-function 'increment-cell! :trials 100 :seed 42))
       (artifact (cl-spec:make-counterexample-artifact result)))
  (cl-spec:serialize-counterexample-artifact artifact))
```

Artifact creation requires a failure. Direct `fixture-check-result` objects
are accepted too. Fixture artifacts use version 2, while ordinary artifacts
retain version 1 and the same AV1 wire codec.

```lisp
(cl-spec:recheck-counterexample artifact :state-policy :fixture)
```

Recheck validates the saved record, requires a complete matching declaration
digest and fixture version, then reconstructs one recipe without generator
draws or shrinking. Results distinguish `:same-failure`, `:different-failure`,
`:passed`, `:precondition-rejected`, definition mismatches and fixture errors.

The target implementation may change so a repair can be checked. Changing the
contract or fixture is not silently accepted as the same experiment.
Incomplete/failed lifecycle runs and opaque recipes cannot be persisted.
Reading an artifact never runs its hooks.

Passing a prior result as `check-function :seed` still means **regenerating a
run**, not directly replaying the selected counterexample. Fixture replay checks
declaration identity, options, profile and trial budget before setup. Use an
integer seed for a deliberately different new run.

## Compatibility

Contracts with capture/state-post but no fixture keep their existing shrinking,
replay and artifact restrictions. Existing stateless artifact v1 and result v1
behavior is unchanged. Runtime instrumentation refuses fixture contracts,
including input-only instrumentation.

See the [design](../superpowers/specs/2026-09-26-reproducible-stateful-contracts-design.md)
for the protocol rationale and the staged plan for external state and supervision.
