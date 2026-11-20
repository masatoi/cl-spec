# Shrink and reproduce a double cancellation

A bank account starts with 100. Withdrawing 10 brings the balance to 90.
The first cancellation refunds the withdrawal. Cancelling the same withdrawal
again should leave the balance at 100. The example's target credits the second
cancellation too. Its model derives the expected balance from the transaction
status. [Example implementation](../../examples/withdraw-cancellation.lisp)

```lisp
(asdf:load-system "cl-spec/examples/withdraw-cancellation")
(cl-spec/examples/withdraw-cancellation:demo-double-cancellation :seed 2)
```

On SBCL with the check-it backend, seed 2 fails on the first generated trial.

| Result | Observed value |
| --- | --- |
| Generated sequence | `(:balance :balance :balance :balance :withdraw :cancel :balance :cancel)` |
| Shrunk sequence | `(:withdraw :cancel :cancel)` |
| Divergence | `(:index 2 :command :cancel :expected 100 :actual 110)` |
| Failure signature | `(:state-machine :observation-mismatch :cancel)` |
| Serialized artifact recheck | `:same-failure` on the broken account, `:passed` after repair |

## Define a machine

`defstate-machine` registers a property in the current registry. A command can
be a keyword or a proper list beginning with a keyword. The following machine
checks a mutable accumulator against an integer model and generates command
arguments from the declared range.

```lisp
(cl-spec:defstate-machine accumulator
    (commands (or (member :reset) (tuple (member :add) (range integer 1 5)))
              :max-length 12)
  :model 0
  :target (list 0)
  :model-step (lambda (model command)
                (let ((next (if (eq command :reset) 0 (+ model (second command)))))
                  (values next next)))
  :target-step (lambda (cell command)
                 (if (eq command :reset) (setf (car cell) 0) (incf (car cell) (second command)))
                 (values cell (car cell)))
  :invariant (lambda (model cell) (= model (car cell))))

(cl-spec:run-property 'accumulator :seed 2)
(cl-spec:trial-observation-status
 (cl-spec:check-state-machine 'accumulator '((:add 3) :reset (:add 1))))
;; => :PASSED
```

Each execution evaluates `:model` and `:target` afresh. Constructors must supply
independent states, and callbacks must treat the commands as read-only. Steps
may mutate their own state. Each returns exactly two values, the next state and
an observation. `:compare` defaults to `equal` and takes the model and target
observations in that order. An optional `:invariant` checks both states initially
and after each pair of agreeing steps.

An optional `:enabled` predicate takes the current model and command. A false
result rejects the trace before either step executes that command. An already
executed prefix belongs to that trial alone. The generator draws command lists
from the declared spec, so a highly restrictive guard can reject many trials.
The runner reports the rejected count and returns `:skipped` when all trials
are rejected.

For an observed coverage dimension, `:pre-admitted` counts traces that admit
their first command or complete initialization with an empty command list.
`:target-observed` counts traces that enter a target step. Disabling a later
command retains both measurements for the executed prefix. The built-in plist
coverage provider reports a command-list binding as an unexpanded collection.

The checker stops at the first violation. A mismatch or false invariant gives
`:failed`. A signaling callback gives `:error`, and its signature includes the
phase, command name and condition type. The explanation identifies the zero-based
index and command. An initial invariant has `nil` for both. Shrinking preserves
the failure signature while allowing the command's index and payload to change.
The result holds the original trace and any accepted reduction.

## Reproduce the saved commands

```lisp
(let* ((registry (cl-spec:make-hash-table-registry))
       (name 'cl-spec/examples/withdraw-cancellation:withdrawal-history))
  (cl-spec/examples/withdraw-cancellation:register-example! registry)
  (let* ((run (cl-spec:run-property name :seed 2 :registry registry))
         (wire (cl-spec:serialize-counterexample-artifact
                (cl-spec:make-counterexample-artifact run))))
    (cl-spec:replay-property name run :registry registry)
    (let ((saved (cl-spec:deserialize-counterexample-artifact wire))
          (cl-spec:*generator-backend* nil))
      (list (cl-spec:trial-observation-signature
             (cl-spec:check-state-machine name '(:withdraw :cancel :cancel) :registry registry))
            (getf (cl-spec:recheck-counterexample saved :registry registry
                                                   :state-policy :stateless)
                  :status)))))
;; => ((:STATE-MACHINE :OBSERVATION-MISMATCH :CANCEL) :SAME-FAILURE)
```

`replay-property` regenerates the seeded run. `check-state-machine` validates
the supplied list and executes it once. Malformed command syntax signals
`invalid-argument`, and a trace outside the declared spec signals `spec-violation`
before initialization. The v1 artifact stores the concrete commands using the
existing bounded codec. Its `:stateless` recheck policy asserts that all state
needed to repeat the trace comes from the machine's initializers.

The example's `:repaired t` registration selects a target that refunds only a
withdrawn transaction. Rechecking the artifact with that registry returns
`:passed`. The same-seed generated run passes all 100 trials.
