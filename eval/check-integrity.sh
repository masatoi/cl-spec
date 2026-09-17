#!/bin/sh
# Verify that a candidate changed only the paths a task allows.
#
# usage: check-integrity.sh TASK WORKDIR
#
# make-workcopy.sh baselines every delivered non-directory entry
# (WORKDIR.baseline.txt) and records the task's allowed_change_paths.  This
# script requires every delivered entry outside those paths to be present and
# unchanged and rejects an entry added outside them, so the whole work copy is
# covered rather than a fixed subset.  A symlink is an entry: it is compared by
# its target and is never followed, so a link added outside the allowed paths is
# a violation and `find -L` is deliberately not used.  It judges integrity only;
# run run-acceptance.sh separately for correctness.  Exit 0 clean, 1 violation,
# 2 missing manifest or baseline.
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
TAB=$(printf '\t')

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

# entry_kind_value PATH -> prints "KIND<TAB>VALUE" for a regular file, symlink or
# any other non-directory entry, or nothing when the entry is absent.
entry_kind_value() {
  target="$work/$1"
  if [ -L "$target" ]; then
    printf 'L\t%s\n' "$(readlink "$target")"
  elif [ -f "$target" ]; then
    printf 'F\t%s\n' "$(sha256sum "$target" | cut -d' ' -f1)"
  elif [ -e "$target" ]; then
    printf 'X\t-\n'
  fi
}

violations=0
checked=0

# Delivered entries that were modified, retyped or deleted outside allowed paths.
while IFS="$TAB" read -r kind value path; do
  [ -n "$path" ] || continue
  ignored_p "$path" && continue
  path_allowed_p "$path" && continue
  current=$(entry_kind_value "$path")
  if [ -z "$current" ]; then
    echo "INTEGRITY-VIOLATION $path (delivered entry was deleted)"
    violations=$((violations + 1))
    continue
  fi
  checked=$((checked + 1))
  if [ "$kind$TAB$value" != "$current" ]; then
    echo "INTEGRITY-VIOLATION $path (delivered entry was modified)"
    violations=$((violations + 1))
  fi
done < "$baseline"

# Entries that appeared after delivery, outside the allowed paths.  The listing
# covers every non-directory entry, so a new symlink is reported like a new file.
baseline_paths=$(mktemp)
current_paths=$(mktemp)
cut -f3 "$baseline" | sort > "$baseline_paths"
(cd "$work" && find . ! -type d | sed 's|^\./||' | sort) > "$current_paths"
while read -r path; do
  [ -n "$path" ] || continue
  ignored_p "$path" && continue
  path_allowed_p "$path" && continue
  echo "INTEGRITY-VIOLATION $path (entry was added outside the allowed paths)"
  violations=$((violations + 1))
done <<EOF
$(comm -13 "$baseline_paths" "$current_paths")
EOF
rm -f "$baseline_paths" "$current_paths"

echo "INTEGRITY-CHECKED task=$task files=$checked violations=$violations"
[ "$violations" -eq 0 ]
