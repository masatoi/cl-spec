# Required expected-condition contracts

Approved scope: `(:signals SPEC)` requires the target to signal an error satisfying SPEC.
Normal return fails; `:returns` and nonempty or empty `:post` clauses cannot coexist
with `:signals`. There is at most one signals clause and it takes one non-NIL spec.
SPEC uses the existing normalized DSL; user condition classes use `(type CLASS)`
or `(instance-of CLASS)`, and condition slots use named `satisfies` predicates.
Warnings and non-error signals retain their ordinary Common Lisp behavior and do
not satisfy this contract. Only errors escaping the target invocation are checked.

The function-spec stores normalized `signal-spec`, exposed by
`function-spec-signal-spec`. Constructor and reinitialization enforce exclusivity,
normalize the designator, and roll back rejected changes. Introspection adds
`:signals` as a spec-data projection and declaration digests include that node and
its registered dependencies.

Preconditions still gate invocation. Expected errors pass without failure evidence.
Normal return yields `:failed / :missing-condition`; a mismatching error yields
`:error / :condition-spec` with the original condition and explain-data. Existing
contracts without signals keep `:error / :condition`. Identity separates missing
conditions from mismatches; mismatches compare condition class plus spec-derived
explanation shape, never condition reports or input values. Errors in contract
resolution remain outside target classification. Predicate errors follow existing
explainer semantics and appear as predicate-error diagnostics, not successful matches.

Runtime instrumentation of these contracts is explicitly unavailable: installing
one signals unsupported-instrumentation-target before mutating any fdefinition.
Supporting runtime signals checks while preserving condition/restart behavior is
outside this change. Core dependencies remain free of check-it and cl-mcp.

Tests cover grammar, direct CLOS construction/reinitialization, success, normal
return, mismatch, preconditions, warnings, predicate errors, declaration digest,
shrinking and rejected instrumentation. The self-spec bundle gains an executable normalize-spec-form contract over a
finite malformed-DSL corpus, requiring invalid-spec-form and a nonempty reason.
The existing validate contract and its relational Property remain intact.
The corpus exposed an existing dotted-spine bug; normalize-compound now checks
finite proper list structure before dispatching to list operations.
