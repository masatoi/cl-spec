# Reproducible stateful function checks

A function contract can declare an explicit `:fixture` to reconstruct its initial
state for every trial and shrink candidate. The runner generates and persists a
**recipe**, not the mutable object the target receives.

With `:isolation :fresh`, setup constructs fixture-owned state for each call.
With `:isolation :around`, a caller-supplied wrapper establishes an extent for
the entire trial, such as a transaction or a dynamically scoped mock.

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
(asdf:load-system "cl-spec")

(defun increment-cell! (cell)
  (incf (car cell)))

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

The target increments the integer stored in the cell and returns its new value.
The five clauses shown here are required for both isolation modes and appear
once each. `:version` is a positive integer. Change it when helper changes
alter the meaning of state construction or isolation.

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

## Wrap a trial in a transaction

Choose `(:isolation :around)` and add one wrapper clause. Its body receives
a zero-argument function and calls it synchronously exactly once.

```lisp
(:around (trial)
  (with-rolled-back-transaction ()
    (funcall trial)))
```

Here `with-rolled-back-transaction` is supplied by the application. The trial
function runs setup, the same call checks as `check-call`, evidence capture and
cleanup while the transaction is active. The wrapper's return values are
ignored. Both generation and shrinking use this lifecycle for each recipe
that passes recipe validation. An error, an outward transfer of control, or a
missing or repeated trial call aborts the run with an `:around` lifecycle error.
A repeated call cannot rerun setup or the target.

The executable example uses `unwind-protect` to roll back withdrawals from
one shared ledger. Each trial checks that it started at 100.

```lisp
(cl-spec/examples/reproducible-withdraw:demo-rollback *example-registry*)
;; => (:STATUS :PASSED :TRIALS 2 :BALANCE 100)
```

The fixture lifecycle records `:isolation`. For `:around`, it also records
the wrapper status. The declaration digest includes the isolation and wrapper
source. Setup, cleanup and the wrapper are captured for the whole run.

## Three execution modes

| Operation | Input | Generation | Fixture ownership |
|---|---|---|---|
| `check-call` | Actual raw argument list | None | Caller; no fixture hooks |
| `check-fixture` | One recipe | None | One setup/evaluation/cleanup |
| `check-function` | Generated recipes | check-it | Fresh lifecycle per trial/candidate |

```lisp
(let ((data (cl-spec:fixture-check-data
             (cl-spec:check-fixture 'increment-cell! 7))))
  (list (getf data :status) (getf (getf data :lifecycle) :state)))
;; => (:PASSED :RELEASED)
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
failed or the wrapper aborted. With either isolation, a transfer to a caller's
exit (for example, a timeout handler, restart or catch) proceeds after
applicable cleanup. If the wrapper resumes after an incomplete trial and
returns, the check records `:fixture-around-nonlocal-exit`. An error escaping
the wrapper or a missing or repeated thunk call also records a lifecycle error.

A process kill or crash can bypass Lisp cleanup entirely. This core feature
cannot return a record from a dead process; host supervision remains separate.
The application's wrapper owns any database or external rollback guarantee.

## Save and recheck a counterexample

For this example, redefine the target to return the expected integer while
leaving the cell untouched. Its `:state-post` now fails on every recipe.
Load the check-it backend to generate the initial failure.

```lisp
(asdf:load-system "cl-spec/check-it")

(defun increment-cell! (cell)
  (1+ (car cell)))

(let* ((result (cl-spec:check-function 'increment-cell! :trials 100 :seed 42))
       (artifact (cl-spec:make-counterexample-artifact result))
       (wire (cl-spec:serialize-counterexample-artifact artifact))
       (restored (cl-spec:deserialize-counterexample-artifact wire))
       (recheck (cl-spec:recheck-counterexample restored :state-policy :fixture)))
  (list (cl-spec:property-result-status result) (getf recheck :status)))
;; => (:FAILED :SAME-FAILURE)
```

Artifact creation requires a failure: a result in which no trial failed is
refused with `invalid-counterexample-artifact` and the reason
`:not-failure-evidence`.
Direct `fixture-check-result` objects are accepted too. Fixture artifacts use
version 2, while ordinary artifacts retain version 1 and the same AV1 wire codec.

Recheck validates the saved record, requires a complete matching declaration
digest and fixture version, then reconstructs one recipe without generator
draws or shrinking. Results distinguish `:same-failure`, `:different-failure`,
`:passed`, `:precondition-rejected`, `:contract-error`, `:fixture-error`, and the
definition checks `:definition-missing`, `:definition-mismatch` and
`:incomparable-definition`. A fixture recheck runs with `:state-policy :fixture`.
After the definition checks pass, the default `:unconfirmed` and `:stateless`
return `:status :unsupported` with `:detail :state-unconfirmed` and run nothing.
An unknown policy signals `invalid-argument` before the hooks run.

The target implementation may change so a repair can be checked. Changing the
contract or fixture is not silently accepted as the same experiment.
Incomplete/failed lifecycle runs and opaque recipes cannot be persisted.
Reading an artifact never runs its hooks.

Passing a prior result as `check-function :seed` still means **regenerating a
run**, not directly replaying the selected counterexample. Fixture replay checks
declaration identity, options, profile and trial budget before setup. A mismatch
signals `unsupported-stateful-operation` with a reason that names the cause:
`:definition-mismatch` for a changed declaration, including adding, changing or
removing a fixture, `:incomparable-definition` for an incomplete declaration
digest, and `:run-options-mismatch` for different options, profile or trial
budget. Omitting `:options` reuses the saved options. Supplying `:options nil`
requests an empty option list. Options containing conses and arrays are compared
against their saved snapshot. Use an integer seed for a deliberately different new run.

## Compatibility

Contracts with capture/state-post but no fixture keep their existing shrinking,
replay and artifact restrictions. Existing stateless artifact v1 and result v1
behavior is unchanged. Runtime instrumentation refuses fixture contracts,
including input-only instrumentation.

See the [design](../superpowers/specs/2026-09-26-reproducible-stateful-contracts-design.md)
for the protocol rationale and the staged plan for external state and supervision.
