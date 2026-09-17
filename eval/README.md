# Fault injection and repair-comparison tasks

This directory prepares three small repair tasks and the checks that decide
whether an implementation is correct. It is an evaluator's area: the task
descriptions, the faulty edits and the acceptance checks must not be visible to
the agent being measured (see "Leakage" below).

Nothing here is part of the library. No file in `eval/` is loaded by `cl-spec`,
`cl-spec/specs` or the test suite, and running an evaluation never patches the
checkout, never runs `git reset` and never rewrites history.

## Tasks

| Task | Fault | Allowed path | Self-spec that must fail | Acceptance |
|---|---|---|---|---|
| `registry-stale-index` | Re-registration keeps the previous definition's target/tag index entries | `src/registry.lisp` | `cl-spec:registry-register-property` (with a forced `:replace` scenario), `registration-replacement-preserves-unrelated-indexes` | `acceptance-registry.lisp` |
| `function-spec-capture-drop` | `function-spec-data` drops a contract's declared `:capture` bindings | `src/introspection.lisp` | `function-spec-projection-retains-declared-state` | `acceptance-capture.lisp` |
| `result-state-evidence-drop` | `result-data` drops the observed `:state` evidence | `src/property-runner.lisp` | `result-projection-retains-state-evidence` | `acceptance-state.lisp` |

Each task directory holds `task.md` (the requirement handed to the agent),
`faults.sexp` (one exact, single-occurrence replacement) and `manifest.json`
(baseline commit, targets, allowed and fixed paths).

## Detection check

```sh
eval/run-detection.sh
```

For every task and every target it builds a disposable source snapshot, runs the
correct baseline and the faulty copy in separate fresh Lisp processes, and
requires all four of:

1. baseline self-spec target reports `status=:passed`,
2. baseline acceptance prints `ACCEPTANCE-RESULT <task> PASS` and exits 0,
3. faulty self-spec target reports the task's expected `status`, `reason` and
   `phase` (recorded as `expected_fault_status`/`_reason`/`_phase` in the task's
   `manifest.json`),
4. faulty acceptance prints `ACCEPTANCE-RESULT <task> FAIL` and exits 1.

The driver compares the record fields, not just the exit code: a load failure, a
missing dependency, an unrelated exception or a record that does not match the
expectation is a harness failure, never a detection. Each process runs under
`timeout` (`PROCESS_TIMEOUT`, default 900s) and a timeout is reported as its own
failure. The script exits `0` only when every case matched, and removes every
temporary copy on exit.

Individual runs:

```sh
CL_SOURCE_REGISTRY="$work//" CL_SPEC_ROOT="$work" \
  CL_SPEC_DETECT_KIND=property \
  CL_SPEC_DETECT_NAME=CL-SPEC/SPECS::RESULT-PROJECTION-RETAINS-STATE-EVIDENCE \
  CL_SPEC_DETECT_EXPECT=fail \
  ros run -- --non-interactive --load eval/detect.lisp
```

`CL_SOURCE_REGISTRY` is required: without it ASDF resolves `cl-spec` to the
checkout, not to the snapshot, and the fault is invisible.

## Repair work copy

```sh
eval/make-workcopy.sh registry-stale-index B /tmp/task-registry-B
eval/check-integrity.sh registry-stale-index /tmp/task-registry-B
eval/run-acceptance.sh registry-stale-index /tmp/task-registry-B
```

`make-workcopy.sh` copies a snapshot, applies the fault with exact replacements,
writes `TASK.md` and a manifest of fixed-file hashes *next to* the copy, and
refuses to overwrite an existing destination. It creates no `.git` directory, so
the correct implementation cannot be recovered with `git checkout`.

- Condition `A` additionally removes `specs.lisp`, `self-spec-fixtures.lisp`,
  the three self-spec test files, the self-spec guide and the corresponding
  `tests.lisp` imports. The agent sees the normal documentation and the
  conventional tests only.
- Condition `B` keeps them. Condition B is A plus the fixed self-specifications.

The acceptance checks under `eval/acceptance-*.lisp` are independent of
`specs.lisp`: they call the public API and state the expected result directly, so
a candidate cannot pass by weakening a self-specification or by editing a test.
They load `cl-spec/check-it` but not `cl-spec/specs`, so they run in both
conditions.

`check-integrity.sh` compares the fixed files still present in a work copy
against the manifest hashes. A candidate that changed a fixed file is an
integrity violation even when acceptance passes; record the result as a rule
violation, not as a successful repair.

### Unresolved comparison asymmetry

Condition A also has to drop `api-docs.lisp`, `tests/api-docs-test.lisp` and
`tests/instrument-status-integration-test.lisp`, because those files import
`cl-spec/specs` and would not load once the bundle is removed. A/B results would
therefore mix the effect of the self-specifications with the absence of the
docs generator and one integration test. That is a real limitation of the
prepared comparison, not something this work resolved; it is recorded here so no
result is read as a clean "self-spec on/off" effect. Before using the numbers,
either define a shared conventional test set or state exactly what differs.

Condition A's conventional `registry-test` already detects the registry fault.
That is expected and is not a flaw: the question the comparison asks is not
"does only B find the bug", but whether exploring and running the fixed
self-specifications and reading their structured diagnosis makes a repair faster
or more accurate. Do not weaken A's tests to manufacture a difference.

## Leakage

Keep the agent's work copy free of this directory, of the correct source and of
the acceptance checks. The correct implementation is whatever the working tree
held when the snapshot was taken; do not hand the agent a repository whose fault
is an uncommitted change it can undo with `git checkout`. Fix the external
search and repository access allowed to both conditions before comparing them.

## Recording

Copy `record-template.json` for each run and read `record-template.md` for the
field meanings and the rules. Record the core baseline revision and the revision
that carries the self-specifications and this harness separately: the task
manifest's `core_baseline_commit` is the core commit the snapshot came from,
while `assets_revision` is the checkout's `HEAD`, which is what
`make-workcopy.sh` writes into the manifest next to each work copy. The
comparison between conditions A and B is **prepared but not run**: no model was
invoked for this work, and `comparison_status` stays `not-run` until the same
task, fault, model, settings and budget have actually been run under both
conditions. Do not record an unmeasured value as `0`, and do not generalise a
pilot into a general claim about development efficiency or quality.
