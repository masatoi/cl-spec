#!/bin/sh
# Build an agent work copy for one repair task and comparison condition.
#
# usage: make-workcopy.sh TASK CONDITION DEST
#   TASK      registry-stale-index | function-spec-capture-drop | result-state-evidence-drop
#   CONDITION A | B
#   DEST      a path that must not exist yet
#
# The copy has no version-control history and no eval/ directory, so the correct
# implementation cannot be recovered with git checkout and the evaluator's
# acceptance files are not visible.  Condition A removes the fixed
# self-specification bundle and its tests, so "self-spec available" is a real
# difference between A and B; condition B keeps them.  A manifest with the fixed
# file list and hashes is written next to -- not inside -- the work copy.

set -eu

eval_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$eval_dir/.." && pwd)
task=$1
condition=$2
dest=$3

if [ -e "$dest" ]; then
  echo "destination already exists: $dest" >&2
  exit 2
fi

"$eval_dir/make-snapshot.sh" "$dest" >/dev/null
CL_SPEC_ROOT="$dest" CL_SPEC_TASK_DIR="$eval_dir/tasks/$task" \
  ros run -- --non-interactive --load "$eval_dir/apply-faults.lisp" >/dev/null

if [ "$condition" = "A" ]; then
  # The API-docs generator and the instrumentation-status integration suite
  # both import CL-SPEC/SPECS, so they go with the bundle; their imports must
  # then leave tests.lisp too.
  rm -f "$dest/specs.lisp" \
        "$dest/self-spec-fixtures.lisp" \
        "$dest/api-docs.lisp" \
        "$dest/tests/self-specs-test.lisp" \
        "$dest/tests/self-properties-test.lisp" \
        "$dest/tests/self-api-contracts-test.lisp" \
        "$dest/tests/api-docs-test.lisp" \
        "$dest/tests/instrument-status-integration-test.lisp" \
        "$dest/docs/guides/self-specification-guide.md"
  grep -v -e 'self-specs-test' -e 'self-properties-test' -e 'self-api-contracts-test' \
    -e 'api-docs-test' -e 'instrument-status-integration-test' \
    "$dest/tests.lisp" > "$dest/tests.lisp.filtered"
  mv "$dest/tests.lisp.filtered" "$dest/tests.lisp"
fi

cp "$eval_dir/tasks/$task/task.md" "$dest/TASK.md"

# Files the work copy must still contain at judgement time.  Condition A removes
# the self-specification bundle on purpose, so only tests.lisp is required there;
# condition B delivers the bundle and the files that import it.
required_files=""
if [ "$condition" = "B" ]; then
  required_files="specs.lisp self-spec-fixtures.lisp api-docs.lisp
    tests/self-specs-test.lisp tests/self-properties-test.lisp
    tests/self-api-contracts-test.lisp tests/api-docs-test.lisp
    tests/instrument-status-integration-test.lisp"
fi

manifest="$dest.manifest.txt"
{
  echo "task_id=$task"
  echo "condition=$condition"
  # The core baseline and the self-spec/eval assets are different revisions: the
  # task's manifest names the core commit the snapshot came from, while HEAD is
  # the commit that carries the fixed self-specifications and this harness.
  echo "core_baseline_revision=$(sed -n 's/.*"core_baseline_commit": "\([^"]*\)".*/\1/p' \
        "$eval_dir/tasks/$task/manifest.json")"
  echo "assets_revision=$(cd "$root" && git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "work_copy=$dest"
  echo "fixed_files:"
  for f in specs.lisp self-spec-fixtures.lisp api-docs.lisp \
           tests/self-specs-test.lisp tests/self-properties-test.lisp \
           tests/self-api-contracts-test.lisp tests/api-docs-test.lisp \
           tests/instrument-status-integration-test.lisp \
           eval/acceptance-registry.lisp eval/acceptance-capture.lisp \
           eval/acceptance-state.lisp eval/tasks; do
    if [ -d "$root/$f" ]; then
      printf '  %s %s/\n' \
        "$(find "$root/$f" -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1)" \
        "$f"
    elif [ -f "$root/$f" ]; then
      printf '  %s %s\n' "$(sha256sum "$root/$f" | cut -d' ' -f1)" "$f"
    fi
  done
  # The allowed-change set, copied from the task manifest for the record.
  echo "allowed_change_paths:"
  sed -n 's/.*"allowed_change_paths": \[\([^]]*\)\].*/  \1/p' \
    "$eval_dir/tasks/$task/manifest.json"
  # The required set is a human-readable summary; the whole-copy baseline below
  # is what check-integrity.sh checks.
  echo "required_files:"
  for f in tests.lisp $required_files; do
    if [ -f "$dest/$f" ]; then
      printf '  %s %s\n' "$(sha256sum "$dest/$f" | cut -d' ' -f1)" "$f"
    else
      printf '  MISSING %s\n' "$f"
    fi
  done
} > "$manifest"

# Baseline every delivered file so check-integrity.sh can detect a change,
# deletion or addition anywhere outside the task's allowed paths.  It is written
# after every delivery step, so condition A's filtered tests.lisp is baselined as
# delivered and its intentionally removed bundle files are simply absent.
baseline="$dest.baseline.txt"
(cd "$dest" && find . -type f | sed 's|^\./||' | sort) | while read -r path; do
  printf '%s %s\n' "$(sha256sum "$dest/$path" | cut -d' ' -f1)" "$path"
done > "$baseline"

echo "WORKCOPY-CREATED $dest"
echo "MANIFEST $manifest"
echo "BASELINE $baseline"
