# Changelog

## v1.0.0

The first stable release adopts the published 1.x compatibility policy for
public APIs, structured data, counterexamples, and seed replay.
[Compatibility policy](docs/compatibility.md)

- The ASDF system versions and generated-run provenance report `1.0.0`.
- Counterexample artifact loading rejects function-case signatures on property records.
  [Issue #95](https://github.com/masatoi/cl-spec/issues/95)

## v1.0.0-rc.2

- `run-property`, `run-properties`, `replay-property`, `check-function` and
  `check-function-with-examples` report invalid explicit generation and shrink
  budgets in `:options` as `cl-spec:invalid-argument`, with the public caller
  and option name.
- The API reference explains how capture failures affect case counts, how to
  pass a registry, and which recheck policies return a verdict or signal an
  argument error.
- The README case and direct-check examples now include their setup. The
  fixture guide shows a saved failure through serialization and recheck.
  The tutorials and structured-data walkthrough use verified output examples.

## v1.0.0-rc.1

This candidate defines the public API and data compatibility rules for the
1.x series. The Git tag identifies the candidate. Its ASDF and run-provenance
version is `0.1.0`. [Compatibility policy](docs/compatibility.md)

- Case guards can read an unrelated package's `RESULT` variable when the first
  parameter comes from Common Lisp or an imported package. Guard references to
  the contract's return bindings are still refused. [Issue #132](https://github.com/masatoi/cl-spec/issues/132)
- Artifact loading checks that a saved symbol resolves to its recorded home
  package. The regression suite also reads and rechecks v1 and v2 artifacts
  written by an earlier revision.
- The README documents installation and Linux CI coverage. The API reference
  identifies the check-it backend package and describes output checks for
  fixed multiple return values.
