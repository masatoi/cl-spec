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

# Keep the pristine files available for provenance and both comparison
# conditions. Only the faulted copy is handed to the repairer.
checkout_revision=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || echo unknown)
work=$(mktemp -d "${TMPDIR:-/tmp}/cl-spec-workcopy.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
pristine=$work/pristine
reference=$work/reference
mkdir -p "$reference"
"$eval_dir/make-snapshot.sh" "$pristine" >/dev/null
mkdir -p "$(dirname "$dest")"
mkdir "$dest"
cp -R "$pristine"/. "$dest"/
# The evaluation assets belong to the evidence and stay outside the delivery.
cp -R "$eval_dir" "$pristine/eval"
eval_dir=$pristine/eval

matches_pristine() {
  for path do
    git diff --no-index --no-ext-diff --quiet -- "$reference/$path" "$pristine/$path" ||
      return 1
  done
}

declared_revision=$(sed -n 's/.*"core_baseline_commit": "\([^"]*\)".*/\1/p' \
  "$eval_dir/tasks/$task/manifest.json")
core_revision=unknown
assets_revision=unknown
if [ "$checkout_revision" != unknown ] &&
   git -C "$root" archive --output="$work/reference.tar" "$checkout_revision" &&
   tar xf "$work/reference.tar" -C "$reference"; then
  if matches_pristine src main.lisp cl-spec.asd; then
    core_revision=$checkout_revision
    if git -C "$root" diff --quiet "$declared_revision" "$checkout_revision" \
         -- src main.lisp cl-spec.asd 2>/dev/null; then
      core_revision=$declared_revision
    fi
  fi
  if matches_pristine eval specs.lisp api-docs.lisp self-spec-fixtures.lisp \
       self-generation-fixtures.lisp tests.lisp tests; then
    assets_revision=$checkout_revision
  fi
fi

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
  echo "core_baseline_revision=$core_revision"
  echo "assets_revision=$assets_revision"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "work_copy=$dest"
  echo "fixed_files:"
  for f in specs.lisp self-spec-fixtures.lisp api-docs.lisp \
           tests/self-specs-test.lisp tests/self-properties-test.lisp \
           tests/self-api-contracts-test.lisp tests/api-docs-test.lisp \
           tests/instrument-status-integration-test.lisp \
           eval/acceptance-registry.lisp eval/acceptance-capture.lisp \
           eval/acceptance-state.lisp eval/tasks; do
    if [ -d "$pristine/$f" ]; then
      printf '  %s %s/\n' \
        "$(cd "$pristine" && find "$f" -type f -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)" \
        "$f"
    elif [ -f "$pristine/$f" ]; then
      printf '  %s %s\n' "$(sha256sum "$pristine/$f" | cut -d' ' -f1)" "$f"
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

# Baseline every delivered non-directory entry so check-integrity.sh can detect a
# change, deletion or addition anywhere outside the task's allowed paths.  A
# symlink is recorded as its target rather than followed, so a link added or
# repointed is an entry like any other.  The baseline is written after every
# delivery step, so condition A's filtered tests.lisp is baselined as delivered
# and its intentionally removed bundle files are simply absent.
baseline="$dest.baseline.txt"
(cd "$dest" && find . ! -type d | sed 's|^\./||' | sort) | while read -r path; do
  target="$dest/$path"
  if [ -L "$target" ]; then
    printf 'L\t%s\t%s\n' "$(readlink "$target")" "$path"
  elif [ -f "$target" ]; then
    printf 'F\t%s\t%s\n' "$(sha256sum "$target" | cut -d' ' -f1)" "$path"
  else
    printf 'X\t-\t%s\n' "$path"
  fi
done > "$baseline"

echo "WORKCOPY-CREATED $dest"
echo "MANIFEST $manifest"
echo "BASELINE $baseline"
