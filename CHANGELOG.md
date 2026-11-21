# Changelog

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
