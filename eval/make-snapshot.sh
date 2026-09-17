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
(cd "$src" && tar cf - \
    --exclude=.git \
    --exclude=eval \
    --exclude='*.fasl' \
    --exclude='*.lx64fsl' \
    .) | (cd "$dest" && tar xf -)

echo "SNAPSHOT-CREATED $dest"
