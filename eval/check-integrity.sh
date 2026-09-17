#!/bin/sh
# Verify that a candidate changed only the files a task allows.
#
# usage: check-integrity.sh TASK WORKDIR
#
# make-workcopy.sh baselines every delivered file (WORKDIR.baseline.txt) and
# records the task's allowed_change_paths.  This script requires every delivered
# file outside those paths to be present and unchanged and rejects a file added
# outside them, so the whole work copy is covered rather than a fixed subset.  It
# judges integrity only; run run-acceptance.sh separately for correctness.
# Exit 0 clean, 1 violation, 2 missing manifest or baseline.
#
# Build output (ASDF fasls and similar) and the evaluator's TASK.md are ignored;
# everything else a candidate leaves behind must have been delivered.

set -u

eval_dir=$(cd "$(dirname "$0")" && pwd)
task=$1
work=$2
manifest="$work.manifest.txt"
baseline="$work.baseline.txt"
task_manifest="$eval_dir/tasks/$task/manifest.json"

if [ ! -f "$manifest" ]; then
  echo "INTEGRITY-UNKNOWN no manifest at $manifest; build the copy with make-workcopy.sh"
  exit 2
fi
if [ ! -f "$baseline" ]; then
  echo "INTEGRITY-UNKNOWN no baseline at $baseline; build the copy with make-workcopy.sh"
  exit 2
fi
if [ ! -f "$task_manifest" ]; then
  echo "INTEGRITY-UNKNOWN no task manifest at $task_manifest"
  exit 2
fi

# allowed is a newline-separated list; a path ending in / covers a directory.
allowed=$(tr -d '\n' < "$task_manifest" \
  | sed -n 's/.*"allowed_change_paths": \[\([^]]*\)\].*/\1/p' \
  | tr ',' '\n' | tr -d ' "')

path_allowed_p() {
  candidate=$1
  for allowed_path in $allowed; do
    case "$allowed_path" in
      */) case "$candidate" in "$allowed_path"*) return 0 ;; esac ;;
      *) [ "$candidate" = "$allowed_path" ] && return 0 ;;
    esac
  done
  return 1
}

ignored_p() {
  case "$1" in
    TASK.md|.git/*|*.fasl|*.lx64fsl|*.o|*.so|*.log|*.tmp|*~|*.orig|*.rej) return 0 ;;
  esac
  return 1
}

violations=0
checked=0

# Delivered files that were modified or deleted outside the allowed paths.
while read -r hash path; do
  [ -n "$path" ] || continue
  ignored_p "$path" && continue
  path_allowed_p "$path" && continue
  target="$work/$path"
  if [ ! -f "$target" ]; then
    echo "INTEGRITY-VIOLATION $path (delivered file was deleted)"
    violations=$((violations + 1))
    continue
  fi
  checked=$((checked + 1))
  actual=$(sha256sum "$target" | cut -d' ' -f1)
  if [ "$actual" != "$hash" ]; then
    echo "INTEGRITY-VIOLATION $path (delivered file was modified)"
    violations=$((violations + 1))
  fi
done < "$baseline"

# Files that appeared after delivery, outside the allowed paths.
baseline_paths=$(mktemp)
current_paths=$(mktemp)
cut -d' ' -f2- "$baseline" | sort > "$baseline_paths"
(cd "$work" && find . -type f | sed 's|^\./||' | sort) > "$current_paths"
while read -r path; do
  [ -n "$path" ] || continue
  ignored_p "$path" && continue
  path_allowed_p "$path" && continue
  echo "INTEGRITY-VIOLATION $path (file was added outside the allowed paths)"
  violations=$((violations + 1))
done <<EOF
$(comm -13 "$baseline_paths" "$current_paths")
EOF
rm -f "$baseline_paths" "$current_paths"

echo "INTEGRITY-CHECKED task=$task files=$checked violations=$violations"
[ "$violations" -eq 0 ]
