#!/bin/sh
# Run the evaluator-owned acceptance check for a task against a work copy.
#
# usage: run-acceptance.sh TASK WORKDIR
#
# The acceptance check is independent of specs.lisp and of the task description:
# it states the expected public behaviour directly.  Exit 0 means accepted.

set -eu

eval_dir=$(cd "$(dirname "$0")" && pwd)
task=$1
work=$2

case "$task" in
  registry-stale-index) script=acceptance-registry.lisp ;;
  function-spec-capture-drop) script=acceptance-capture.lisp ;;
  result-state-evidence-drop) script=acceptance-state.lisp ;;
  *) echo "unknown task: $task" >&2; exit 2 ;;
esac

CL_SOURCE_REGISTRY="$work//" CL_SPEC_ROOT="$work" \
  ros run -- --non-interactive --load "$eval_dir/$script"
