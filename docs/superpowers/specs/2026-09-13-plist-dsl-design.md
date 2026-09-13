# Plist field specifications

Approved design from the implementation discussion, 2026-09-13.

Add `(plist (:required (:key spec) ...) (:optional (:key spec) ...) (:closed nil))`.
Clauses are optional and unique; unknown clauses, malformed pairs, non-keyword keys,
repeated field keys across either clause, and non-boolean closed flags are refused.
Empty `(plist)` admits any finite keyword plist with unique keys. Unknown fields are
allowed by default; closed specifications reject them. NIL values remain distinct
from absent fields. Input ordering is immaterial. Improper, cyclic, odd-length,
non-keyword-key and duplicate-key inputs are rejected before child predicates run.

A representation-independent field definition stores a key, child IR, and required
flag. A field-spec base holds ordered fields and a closed flag. The concrete
plist-spec enforces keyword keys, uniqueness, finite field lists and boolean
closed flags at initialization and reinitialization, before changing instance state. No alist/hash-table implementation or public
representation-conversion API is introduced. Field metadata and child IR remain
separate so future representations can choose their own key equality semantics.

The explainer emits key paths, missing/duplicate/unknown-key and malformed-structure
errors. A field path also contributes to failure identity so shrinking cannot move
a return-value failure between distinct fields with the same value spec. Ordinary
collection element indices must remain absent from that identity.

Introspection publishes ordered field descriptors with key, required flag, and child
index plus the closed flag. Declaration digests include these fields and traverse
child dependencies, including programmatically constructed nodes.

The check-it backend generates required fields, randomly includes optional fields,
and generates no unknown fields. Shrinking can omit optional fields and shrink
values without removing required keys. Unsupported child generators report existing
generator-unavailable behavior. Cross-field predicates remain ordinary AND/SATISFIES;
no general constraint solver or new AND generation policy is introduced.

Migrate the self-specification envelope shape checks to this DSL, leaving only
cross-field semantic predicates in Lisp. Existing finite-domain guarantees remain.

Expected condition contracts are a separate subsequent implementation unit; this
unit delivers plist validation, explanation, introspection, generation and shrinking.
