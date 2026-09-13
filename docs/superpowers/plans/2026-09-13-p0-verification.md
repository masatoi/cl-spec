# P0 verification implementation plan

Approved task scope: issues #9, #10, #12, executed in order.
Design: ../specs/2026-09-13-p0-verification-design.md.

- [ ] #9a Bounded value codec: src/utils/artifact-values.lisp and focused tests.
  Encode/decode supported scalar/list/vector values; reject unsupported graphs and
  malicious/unbounded wire input. Agent owns codec, root integrates its public functions.
- [ ] #9b Artifact and direct recheck: src/counterexample.lisp, result provenance,
  function adapter factory, public exports, tests/counterexample-test.lisp.
  Start with failing maker/recheck tests; integrate codec, validate schema, prove no
  generator calls and exactly one target call, status distinctions and unchanged evidence.
- [ ] #9c Review and validate: core/full tests, clean Rove, mallet, force compile,
  self-specs/docs. Commit issue #9 before issue #10 implementation.
- [ ] #10 Shared invariant validation/rollback hooks; property and registry integration;
  function-spec extension hooks; CLOS/DSL/registration table tests and subclass rollback.
  Review, docs/self-specs and validation; commit before issue #12.
- [ ] #12 Installation snapshot/status/refresh, dynamic dependency distinction,
  lifecycle tests, review, docs/self-specs and validation; separate commit.

Decision: version-1 codec rejects shared/circular mutable values rather than losing
their semantics. Recheck needs an explicit stateless assertion; fixture support is
outside the issue. Cost: callers with these inputs require a later codec/fixture extension.
Decision: current working checkout uses a new feature branch; PR #8 remains untouched.
Baseline: 333 tests pass.
