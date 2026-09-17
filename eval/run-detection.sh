#!/bin/sh
# Fault-injection detection check.
#
# For each task this builds a disposable snapshot, runs the correct baseline and
# the faulty copy in separate fresh Lisp processes, and requires:
#   correct baseline: the self-spec target passes and the acceptance check passes
#   faulty copy:      the self-spec target fails and the acceptance check fails
#
# It never touches the user's tree: every copy lives under the system temporary
# directory and is removed on exit.  It does not use git and never resets.

set -u

eval_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$eval_dir/.." && pwd)
snapshot=$(mktemp -d "${TMPDIR:-/tmp}/cl-spec-snapshot.XXXXXX")
work_dirs=""
failures=0

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
    CL_SPEC_ROOT="$PREPARED" CL_SPEC_TASK_DIR="$eval_dir/tasks/$task" \
      ros run -- --non-interactive --load "$eval_dir/apply-faults.lisp" >/dev/null 2>&1 || {
        echo "FAULT-APPLY-FAILED $task" >&2
        return 2
      }
  fi
  return 0
}

run_detect() {
  # run_detect WORK EXPECT KIND NAME SCENARIO
  work=$1
  expect=$2
  kind=$3
  name=$4
  scenario=${5:-}
  CL_SOURCE_REGISTRY="$work//" \
  CL_SPEC_ROOT="$work" \
  CL_SPEC_DETECT_KIND="$kind" \
  CL_SPEC_DETECT_NAME="$name" \
  CL_SPEC_DETECT_EXPECT="$expect" \
  CL_SPEC_DETECT_SCENARIO="$scenario" \
  CL_SPEC_DETECT_TRIALS=20 \
    ros run -- --non-interactive --load "$eval_dir/detect.lisp"
  return $?
}

run_acceptance() {
  # run_acceptance WORK SCRIPT
  work=$1
  script=$2
  CL_SOURCE_REGISTRY="$work//" CL_SPEC_ROOT="$work" \
    ros run -- --non-interactive --load "$eval_dir/$script"
  return $?
}

check() {
  # check EXPECTED ACTUAL LABEL
  if [ "$2" -eq "$1" ]; then
    echo "OK   $3"
  else
    echo "BAD  $3 (expected exit $1, got $2)"
    failures=$((failures + 1))
  fi
}

run_task() {
  task=$1
  kind=$2
  name=$3
  scenario=$4
  script=$5

  prepare "$task" baseline
  baseline=$PREPARED
  prepare "$task" faulty
  faulty=$PREPARED

  echo "== $task (baseline $baseline) =="
  run_detect "$baseline" pass "$kind" "$name" "$scenario"
  check 0 $? "$task baseline self-spec passes"
  run_acceptance "$baseline" "$script"
  check 0 $? "$task baseline acceptance passes"

  echo "== $task (faulty $faulty) =="
  run_detect "$faulty" fail "$kind" "$name" "$scenario"
  check 0 $? "$task faulty self-spec detects the fault"
  run_acceptance "$faulty" "$script"
  check 1 $? "$task faulty acceptance fails"
}

run_task registry-stale-index \
  contract cl-spec:registry-register-property replace acceptance-registry.lisp
run_task registry-stale-index \
  property cl-spec/specs::registration-replacement-preserves-unrelated-indexes "" \
  acceptance-registry.lisp
run_task function-spec-capture-drop \
  property cl-spec/specs::function-spec-projection-retains-declared-state "" \
  acceptance-capture.lisp
run_task result-state-evidence-drop \
  property cl-spec/specs::result-projection-retains-state-evidence "" \
  acceptance-state.lisp

echo
if [ "$failures" -eq 0 ]; then
  echo "DETECTION-OK (all cases matched)"
  exit 0
fi
echo "DETECTION-FAILED ($failures case(s) did not match)"
exit 1
