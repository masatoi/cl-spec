# P0 verification design

User-authorized order: issue #9, then #10, then #12. Base f38936e includes open PR #8;
work stays on p0-verification without changing its branch or merging it.

## #9: counterexamples

Public APIs: make-counterexample-artifact(result &key selection),
counterexample-artifact-data(artifact), serialize-counterexample-artifact(artifact),
deserialize-counterexample-artifact(string), recheck-counterexample(artifact &key
registry state-policy target-revision). Selection is :selected (default), :original
or :shrunk; selecting an absent observation is refused. Data uses artifact-version 1,
record-kind :counterexample, kind/name, captured declaration metadata, original and
accepted shrunk input/signature/status/reason/mutation evidence, actual selection,
seed/profile/budget/options and captured execution provenance.

Immutable artifact payloads are validated bounded serialized data. Supported values
are scalar numbers/characters/existing package symbols and a documented subset of
simple strings/vectors/conses. Cycles, shared mutable values and opaque values are
explicitly unsupported in version 1. Parsing never invokes the Lisp reader or interns
symbols. No condition report/preview is used to reconstruct execution values.

Recheck resolves the current declaration and checks complete matching digest before
input admission, precondition and one target invocation. There is no generation or
backend dependency. It distinguishes :definition-missing, :definition-mismatch,
:incomparable-definition, :input-invalid, :precondition-rejected, :same-failure,
:different-failure, :passed, :unsupported and :contract-error. Existing seed replay is
unchanged. State-policy defaults to :unconfirmed; the caller must explicitly assert
:stateless to execute. Known input mutation refuses execution, newly observed input
mutation returns unsupported. This does not detect/restore arbitrary external state.
Target revisions are optional caller-supplied provenance labels; unknown is explicit.

## #10: construction

Use shared validation and rollback hooks with an explicit list of participating slots
for extension classes. Validate property declarations at construction, reinitialization
and registration, keeping DSL and legitimate direct construction compatible.
Compiled closures without source remain permitted but do not acquire a complete digest.
Do not claim sandboxing, raw slot-value interception, or arbitrary subclass rollback.
Apply extension hooks to function-spec's existing rollback path as well.
Registration validates before changing storage/indexes. Invalid updates restore slots;
registered index changes require explicit re-registration, as in the current lifecycle.

## #12: stale instrumentation

Installation stores a snapshot of captured declaration description (without resolving
named spec dependencies), captured function/predicate identities, full dependency digest,
and the registry/contract identity. Status reports :not-installed, :current, :stale,
or :indeterminate with reasons. Named dependencies remain dynamically resolved;
dependency drift is reported separately rather than labelled stale captured checks.
No per-call digest work. Explicit refresh requires an existing installation and builds
the replacement before swapping fdefinition. Failed refresh preserves the wrapper.
External redefinition is never overwritten. No global registry generation/cache required.
