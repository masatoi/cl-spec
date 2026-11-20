#!/bin/sh
# Create a source snapshot of the working tree with no version-control history.
#
# usage: make-snapshot.sh DEST
#
# The snapshot is what a fresh process compiles from, so a candidate cannot
# recover the correct implementation with git checkout.  Build output and the
# evaluator's own eval/ directory are excluded.

set -eu

src=$(cd "$(dirname "$0")/.." && pwd)
dest=$1

mkdir -p "$dest"
archive=$(mktemp "${TMPDIR:-/tmp}/cl-spec-source.XXXXXX")
trap 'rm -f "$archive"' EXIT
trap 'exit 1' HUP INT TERM

# POSIX pipelines only report the extractor's status. Finish the archive before
# extracting so a source read failure cannot deliver a partial snapshot.
tar cf "$archive" --exclude=.git --exclude=eval --exclude='*.fasl' --exclude='*.lx64fsl' \
    -C "$src" .
tar xf "$archive" -C "$dest"

echo "SNAPSHOT-CREATED $dest"
