#!/bin/sh
# Fault-injection detection check.
#
# For each task and each target this builds a disposable snapshot, runs the
# correct baseline and the faulty copy in separate fresh Lisp processes, and
# requires, from the process output rather than from the exit code alone:
#
#   correct baseline  the expected DETECT-RESULT (status :passed) and an
#                     ACCEPTANCE-RESULT record that says PASS
#   faulty copy       a DETECT-RESULT whose status, reason and phase match the
#                     task's declared expectation, and an ACCEPTANCE-RESULT
#                     record that says FAIL
#
# A timeout, a missing record, an unhandled error or a record that does not
# match is a harness failure, never a detection.  It never touches the user's
# tree: every copy lives under the system temporary directory and is removed on
# exit.  It does not use git and never resets.

set -u

eval_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$eval_dir/.." && pwd)
snapshot=$(mktemp -d "${TMPDIR:-/tmp}/cl-spec-snapshot.XXXXXX")
work_dirs=""
failures=0
PROCESS_TIMEOUT=${PROCESS_TIMEOUT:-900}

cleanup() {
  rm -rf "$snapshot" $work_dirs
}
trap cleanup EXIT INT TERM

"$eval_dir/make-snapshot.sh" "$snapshot" >/dev/null

prepare() {
  # prepare TASK faulty|baseline -> sets PREPARED and records it for cleanup.
  # It runs in the current shell, not a command substitution, so the recorded
  # list survives to the cleanup trap.
  task=$1
  mode=$2
  PREPARED=$(mktemp -d "${TMPDIR:-/tmp}/cl-spec-work.XXXXXX")
  work_dirs="$work_dirs $PREPARED"
  cp -R "$snapshot"/. "$PREPARED"/
  if [ "$mode" = "faulty" ]; then
    timeout "$PROCESS_TIMEOUT" env \
      CL_SPEC_ROOT="$PREPARED" CL_SPEC_TASK_DIR="$eval_dir/tasks/$task" \
      ros run -- --non-interactive --load "$eval_dir/apply-faults.lisp" >/dev/null 2>&1 || {
        echo "FAULT-APPLY-FAILED $task" >&2
        return 2
      }
  fi
  return 0
}

run_detect() {
  # run_detect WORK EXPECT KIND NAME SCENARIO WANT_STATUS WANT_REASON WANT_PHASE OUTFILE
  work=$1
  expect=$2
  kind=$3
  name=$4
  scenario=${5:-}
  want_status=${6:-any}
  want_reason=${7:-any}
  want_phase=${8:-any}
  outfile=$9
  timeout "$PROCESS_TIMEOUT" env \
    CL_SOURCE_REGISTRY="$work//" \
    CL_SPEC_ROOT="$work" \
    CL_SPEC_DETECT_KIND="$kind" \
    CL_SPEC_DETECT_NAME="$name" \
    CL_SPEC_DETECT_EXPECT="$expect" \
    CL_SPEC_DETECT_SCENARIO="$scenario" \
    CL_SPEC_DETECT_TRIALS=20 \
    CL_SPEC_DETECT_EXPECT_STATUS="$want_status" \
    CL_SPEC_DETECT_EXPECT_REASON="$want_reason" \
    CL_SPEC_DETECT_EXPECT_PHASE="$want_phase" \
    ros run -- --non-interactive --load "$eval_dir/detect.lisp" >"$outfile" 2>&1
  return $?
}

run_acceptance() {
  # run_acceptance WORK SCRIPT OUTFILE
  work=$1
  script=$2
  outfile=$3
  timeout "$PROCESS_TIMEOUT" env \
    CL_SOURCE_REGISTRY="$work//" CL_SPEC_ROOT="$work" \
    ros run -- --non-interactive --load "$eval_dir/$script" >"$outfile" 2>&1
  return $?
}

check_detect() {
  # check_detect RC OUTFILE LABEL
  rc=$1
  outfile=$2
  label=$3
  cat "$outfile"
  if [ "$rc" -eq 124 ]; then
    echo "BAD  $label (timeout after ${PROCESS_TIMEOUT}s)"
    failures=$((failures + 1))
  elif ! grep -q "DETECT-RESULT .*matched=T" "$outfile"; then
    echo "BAD  $label (no matching DETECT-RESULT record; exit $rc)"
    failures=$((failures + 1))
  elif [ "$rc" -ne 0 ]; then
    echo "BAD  $label (record matched but exit was $rc)"
    failures=$((failures + 1))
  else
    echo "OK   $label"
  fi
}

check_acceptance() {
  # check_acceptance RC OUTFILE TASK VERDICT EXPECTED_RC LABEL
  rc=$1
  outfile=$2
  task=$3
  verdict=$4
  expected_rc=$5
  label=$6
  cat "$outfile"
  if [ "$rc" -eq 124 ]; then
    echo "BAD  $label (timeout after ${PROCESS_TIMEOUT}s)"
    failures=$((failures + 1))
  elif ! grep -q "ACCEPTANCE-RESULT $task $verdict" "$outfile"; then
    echo "BAD  $label (no ACCEPTANCE-RESULT $task $verdict record; exit $rc)"
    failures=$((failures + 1))
  elif [ "$rc" -ne "$expected_rc" ]; then
    echo "BAD  $label (record present but exit was $rc, expected $expected_rc)"
    failures=$((failures + 1))
  else
    echo "OK   $label"
  fi
}

run_task() {
  # run_task TASK KIND NAME SCENARIO SCRIPT FAULT_STATUS FAULT_REASON FAULT_PHASE
  # The expectation is passed per target because one task can have several
  # targets with different expected failures; each call matches the target's
  # entry under self_spec_targets in the task manifest.
  task=$1
  kind=$2
  name=$3
  scenario=$4
  script=$5
  fault_status=$6
  fault_reason=$7
  fault_phase=$8

  prepare "$task" baseline
  baseline=$PREPARED
  prepare "$task" faulty
  faulty=$PREPARED

  echo "== $task (baseline $baseline) =="
  run_detect "$baseline" pass "$kind" "$name" "$scenario" ":passed" any any \
    "$baseline/detect.out"
  check_detect $? "$baseline/detect.out" "$task baseline self-spec passes"
  run_acceptance "$baseline" "$script" "$baseline/acceptance.out"
  check_acceptance $? "$baseline/acceptance.out" "$task" PASS 0 \
    "$task baseline acceptance passes"

  echo "== $task (faulty $faulty) =="
  run_detect "$faulty" fail "$kind" "$name" "$scenario" \
    "$fault_status" "$fault_reason" "$fault_phase" "$faulty/detect.out"
  check_detect $? "$faulty/detect.out" "$task faulty self-spec detects the fault"
  run_acceptance "$faulty" "$script" "$faulty/acceptance.out"
  check_acceptance $? "$faulty/acceptance.out" "$task" FAIL 1 \
    "$task faulty acceptance fails"
}

run_task registry-stale-index \
  contract cl-spec:registry-register-property replace acceptance-registry.lisp \
  ":failed" ":state-postcondition" ":state-post"
run_task registry-stale-index \
  property cl-spec/specs::registration-replacement-preserves-unrelated-indexes "" \
  acceptance-registry.lisp ":failed" ":predicate-false" any
run_task function-spec-capture-drop \
  property cl-spec/specs::function-spec-projection-retains-declared-state "" \
  acceptance-capture.lisp ":failed" ":predicate-false" any
run_task result-state-evidence-drop \
  property cl-spec/specs::result-projection-retains-state-evidence "" \
  acceptance-state.lisp ":failed" ":predicate-false" any

echo
if [ "$failures" -eq 0 ]; then
  echo "DETECTION-OK (all cases matched)"
  exit 0
fi
echo "DETECTION-FAILED ($failures case(s) did not match)"
exit 1
