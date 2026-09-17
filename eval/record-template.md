# Comparison run record

One record per `(task, condition, model)` run. `record-template.json` is the
machine-readable shape; this file explains the fields and the rules that are easy
to get wrong.

## Rules

- **Record unmeasured values as `null`, never as `0`.** A trial count nobody read
  is not zero trials; a token count the runner did not report is not zero tokens.
- **Do not generalise from a pilot.** A handful of runs is not evidence that a
  condition improves development efficiency or quality. If no comparison was run,
  the result section says `not-run`.
- **Distinguish outcome kinds.** `success`, `failure`, `incomplete` and
  `environment_error` are four different results. A load failure, a missing
  dependency, a timeout or an exception in another test is not a repair failure
  and not a successful repair.
- **Record integrity separately from outcome.** A run that passes because it
  weakened a self-specification or edited a fixed file is not a successful
  repair.
- **State the unverified scope.** What was not exercised is part of the record.

## Fields

| Field | Meaning |
|---|---|
| `task_id` | Task directory name. |
| `core_baseline_revision` | Core commit the snapshot was taken from (the task manifest's `core_baseline_commit`). |
| `assets_revision` | Commit carrying the fixed self-specifications and this harness (the checkout's `HEAD`). |
| `faulty_revision` | Revision/hash of the faulty copy handed to the agent. |
| `condition` | `A` (docs plus conventional tests) or `B` (A plus the fixed self-specs). |
| `model.identifier/settings/provider` | Exact model and configuration. |
| `fixed_artifacts.files` | Path and SHA-256 of every file the candidate may not change. Hashes, not just a declaration digest. |
| `budget` | Wall clock, tool calls and tokens allowed. `null` when not fixed. |
| `execution.commands` | Exact commands run. |
| `execution.self_spec_targets_run` | How many self-spec targets were selected and executed. |
| `execution.contracts_run` / `property_trials_run` / `inner_cases_run` | What actually ran. |
| `execution.acceptance_result` | `pass`, `fail`, `not-run` or `environment-error`. |
| `outcome` | `success`, `failure`, `incomplete`, `environment-error` or `not-run`. |
| `agent_effort` | Repairs, tool calls, elapsed time and tokens, when the runner reports them. |
| `integrity` | Whether self-specs were weakened or fixed files changed, and which. |
| `unmeasured` | Measurements the run could not obtain. |
| `unverified_scope` | Behaviour the run did not exercise. |
| `comparison_status` | `not-run` unless the same task, fault, model, settings and budget were run under both A and B. |

## Procedure

1. Build the work copy for the condition:

   ```sh
   eval/make-workcopy.sh registry-stale-index B /tmp/task-registry-B
   ```

   The copy has no `.git` directory; the fault is applied by exact replacement
   and the manifest with the fixed-file hashes is written next to the copy.

2. Run the agent in that copy only. Do not run it in the checkout.

3. Judge with the evaluator-owned acceptance check (never with a test the agent
   could edit):

   ```sh
   eval/run-acceptance.sh registry-stale-index /tmp/task-registry-B
   ```

4. Fill one record from `record-template.json`, then remove the work copy.

5. To compare conditions, repeat steps 1-4 with `A` and `B` for the same task,
   model, settings and budget. The two runs must not share a process, a Lisp
   image or a work copy.
