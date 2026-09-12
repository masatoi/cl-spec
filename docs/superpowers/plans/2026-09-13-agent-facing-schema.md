# Agent-facing schema implementation plan

**Goal:** Stabilize definition/result metadata and its actual cl-mcp handoff.
**Architecture:** Shared schema constants and bounded canonical digest; generic
definition descriptions avoid a function-spec/property-runner dependency cycle.
Backend capability methods and run-time metadata snapshots feed additive records.
**Tech stack:** ANSI Common Lisp, ASDF, Rove, check-it, cl-mcp adapter.
**Spec:** ../specs/2026-09-13-agent-facing-schema-design.md

- [x] Add core schema tests first: required keys/version, generator/reference digest
  changes, completeness, capability nonexecution and retained run metadata.
- [x] Implement schema-info, bounded canonical encoding and definition description
  generics; specialize Function Spec and expose definition-digest/metadata APIs.
- [x] Add backend generation/shrink capability query, definition envelopes and
  result metadata snapshots/result-data. Re-export public symbols.
- [x] Add cl-mcp adapter tests before edits. Prefer core digest, carry core schema
  metadata through describe/check response builders, preserve legacy fallback.
- [x] Run core/adapter contract suites, clean process tests, compile/lint, core-only
  dependency check, independent review. Document schema rules and digest coverage.

Validation completed 2026-09-13:

- REPL `run-tests`, system `cl-spec/tests`: 248 passed, 0 failed.
- `rove cl-spec.asd`: exit 0, all 22 suite groups passed (clean process).
- Adapter core/report/builders/integration suites: 23/48/29/7 passed; 0 failed.
  Integration tests used the actual cl-spec API, covering property and Function Spec.
- `mallet` on changed Lisp files in both repositories: no warnings.
- Clean SBCL with Quicklisp setup and the local ASD explicitly registered:
  `(asdf:compile-system :cl-spec :force :all)` succeeded; CHECK-IT and CL-MCP
  packages were absent after core load/compile. Plain SBCL initially lacked the
  source-registry setup; explicit ASD registration resolved that environment issue.
- `git diff --check` passed in both repositories.
- Independent review found two digest issues: user pretty-printer dispatch and
  unrepresented extension subclass slots. Both reproduced in regression tests and
  fixed. Existing compiler style warnings in older tests remain unrelated.

The cl-mcp adapter changes are in its separate checkout. Its pre-existing staged
random-spec sources and untracked coverage directory were preserved. Publish the
core and adapter changes as separate pull requests targeting their respective main branches.
