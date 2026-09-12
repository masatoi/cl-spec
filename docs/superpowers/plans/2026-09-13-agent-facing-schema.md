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

## PR #4 review follow-up

| Finding | Disposition |
|---|---|
| Metadata for custom-generator | v1 supports spec/property/function-spec records only. Documented and changed unsupported objects to explicit TYPE-ERROR; generators remain digest dependencies. |
| Spec completeness / description | Included description. Built-in IR slots can describe constraints completely without an original source form. |
| Suppressed extension errors | Removed broad digest handler. Unsupported non-finite float encoding is handled locally; extension programming errors propagate. |
| Missing entity namespace | Named digest calls require a valid explicit entity kind. Missing registered definitions remain incomplete. |
| Instrumentation override | Retained: instrumentation belongs to the separate instrumentation system, not generator backends. |
| Missing blank lines | Fixed. |
| Custom generators inside argument tuples | Walk compiled tuple/mapped/guard generators; no shrink strategy when all elements lack one. |
| Function documentation digest | Included documentation, also property/generator documentation and property tags. |
| Duplicate budget slots | Removed function result's duplicate; existing reader delegates to shared slot. |
| TRIALS integer versus plist | Retained legacy types, explicitly discriminated by record-kind. |
| Double compilation per run | Backend reports capabilities from its actual compiled generator; no disposable metadata compilation. |
| Result-data defensive copies | Retained and tested: consumer mutation must not alter retained evidence. |
| Metadata per nested node | Full envelope only on public root records; nested IR retains entity-kind. Measured 18 top-level compile calls reduced to 1. |
| Public reader docstrings | Updated all three to describe the seven envelope keys and root/nested distinction. |

Verification: 257 core tests and 7 actual cl-mcp integration tests passed; changed
Lisp files pass mallet. Added regressions establish compilation counts of 1 for
both an 18-node introspection and a property run. Independent follow-up review
found post-run shrink-setting rereads and non-finite floats; both were reproduced
and fixed. Capabilities now preserve the setting captured before user code runs.
