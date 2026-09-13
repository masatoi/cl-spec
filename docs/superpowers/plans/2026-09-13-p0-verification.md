# P0 verification implementation plan

Approved task scope: issues #9, #10, #12, executed in order.
Design: ../specs/2026-09-13-p0-verification-design.md.

- [x] #9a Bounded value codec: src/utils/artifact-values.lisp and focused tests.
  Encode/decode supported scalar/list/vector values; reject unsupported graphs and
  malicious/unbounded wire input. Agent owns codec, root integrates its public functions.
- [x] #9b Artifact and direct recheck: src/counterexample.lisp, result provenance,
  function adapter factory, public exports, tests/counterexample-test.lisp.
  Start with failing maker/recheck tests; integrate codec, validate schema, prove no
  generator calls and exactly one target call, status distinctions and unchanged evidence.
- [x] #9c Review and validate: core/full tests, clean Rove, mallet, force compile,
  self-specs/docs. Commit issue #9 before issue #10 implementation.
- [x] #10 Shared invariant validation/rollback hooks; property and registry integration;
  function-spec extension hooks; CLOS/DSL/registration table tests and subclass rollback.
  Review, docs/self-specs and validation; commit before issue #12.
- [x] #12 Installation snapshot/status/refresh, dynamic dependency distinction,
  lifecycle tests, review, docs/self-specs and validation; separate commit.

Decision: version-1 codec rejects shared/circular mutable values rather than losing
their semantics. Recheck needs an explicit stateless assertion; fixture support is
outside the issue. Cost: callers with these inputs require a later codec/fixture extension.
Decision: current working checkout uses a new feature branch; PR #8 remains untouched.
Baseline: 333 tests pass.

## Completed checkpoints

- #9: `9b2fc1c`; 355 Rove tests, 30 clean-process suites; core compilation and changed-file mallet passed.
- #10: 371 Rove tests, 33 clean-process suites; shared object validation, registration gate and rollback integrated. Core compilation passed.

- #10 committed as `5375f94`.
- #12: 388 Rove tests / 35 clean-process suites passed. Status/refresh integration,
  named dependencies, opaque closures, compile/deletion refusal and optional
  executable status self-contract covered. Core compilation and isolated loading
  passed (neither check-it nor instrumentation loaded by core/self-spec bundle).
- Detection cost sample: SBCL 2.5.8.roswell, one integer argument and integer
  return, 100 warmup queries then 1,000 status queries: 0.028 seconds total
  (~28 microseconds/query). This is a local measurement, not a performance
  guarantee; cost grows with declaration/dependency graphs. Wrapper calls perform
  no status/digest work. A local declaration change reports dependency comparison
  as indeterminate, since the full digest cannot isolate that change's contribution.


## PR #22 review follow-up

- Codec: typed nonfinite rejection; logical list depth; iterative bounded work.
- Artifact: optional metadata omissions (including aggregate limits), early selection
  diagnostics, shared finite-list predicate, one normal-path wire encoding.
- Recheck: dispatch through the whole-argument schema generic; generator annotations
  still do not execute a generator during validation.
- Instrumentation: honor description completeness, share graph traversal with digest,
  avoid destructive reversal of literal reason lists; golden digests preserved.
- Registry: keep independent index-key validation and report truthful TYPE-ERROR data.
- Provenance: remove runtime ASDF import; test release-version consistency.
- Function checks: reuse the adapter's existing captured source form.
- Style: wrap the overlong public export line in specs.lisp.

Review validation: 405 tests passed, 35 clean-process suites passed; changed-file
mallet and forced core compilation passed. Standalone core loading confirms no
ASDF runtime module dependency and no check-it/instrumentation load.
