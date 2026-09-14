# Alist and hash-table field specifications

Approved design from the implementation discussion, 2026-09-15.

Add `(alist ...)` and `(hash-table ...)` alongside `(plist ...)`. All three take
the same `:required` / `:optional` / `:closed` clauses; `alist` and `hash-table`
additionally take one `(:test TEST)` clause. TEST is `EQ`, `EQL`, `EQUAL` or
`EQUALP`, written as a keyword or a plain symbol, and defaults to `EQL`. Clause
repetition, an unknown clause, a malformed `:closed` or `:test` value, a
malformed field entry, and duplicate declared keys are refused before an IR
object exists. `plist` refuses `:test` because it compares keywords with EQL.

Field entries are `(KEY SPEC)` where KEY is any object for the keyed
representations, not only a keyword. Declared keys must be unique under the
declared test; the key test is parsed before the duplicate check, so a `:test`
written after a field still decides that field.

The IR reuses `field-definition` (key, child IR, required flag) and `field-spec`
(ordered fields, closed flag) unchanged. A new `keyed-field-spec` base adds only
`key-test`. `alist-spec` and `hash-table-spec` are its concrete subclasses and
report `:alist` and `:hash-table` from `spec-kind`. Field metadata stays separate
from storage representation, so each representation owns its key comparison and
its value traversal.

## Value semantics

An alist is a finite proper list whose elements are conses. The key is the CAR
and the value is the CDR, exactly as `ASSOC` reads it, so `(KEY . NIL)` is a
present field with value NIL, distinct from an absent field. A non-cons element
is `:bad-association`; a non-list, improper or circular value is
`:not-an-alist`; two elements whose keys compare equal under the declared test
are `:duplicate-key` at the second occurrence.

A hash table's own test must match the declared test. A table with a different
test is `:wrong-key-test`, carrying the table's test as `:actual-test`, so the
comparison the spec declares is the comparison the value actually uses. Key
presence uses `GETHASH`'s second return value, which again separates a present
NIL value from an absent key. Unknown keys in a closed spec are `:unknown-key`;
they are reported sorted by printed key so an unordered `MAPHASH` walk is not
observable.

Structural failures are reported before any child predicate runs, so a
malformed value cannot trigger user code. Field paths carry the declared key,
and `:field-path` carries only declared keys, which lets Function Spec failure
identity distinguish a violation in one field from the same violation in
another. Unknown and duplicate input keys stay in `:path` and never enter
`:field-path`.

## Introspection and generation

`spec-data` adds `:test` for the keyed representations. `definition-constraints`
includes it in the digest, so alist versus hash-table and a changed test produce
different digests; the plist digest and `spec-data` are unchanged because plist
reports no test. The `definition-description-complete-p` class list gains
`field-spec`, `keyed-field-spec`, `alist-spec` and `hash-table-spec`.

The check-it backend generates required keys always and includes each optional
key independently. A `keyed-value-generator` base owns that policy and the
shrinker; subclasses only encode and decode the association list. The alist
encoding writes `(KEY . VALUE)` pairs, the hash-table encoding builds a table
with the declared test. Shrinking removes optional keys and reduces field values
while keeping required keys and the declared test, and only adopts a candidate
the property callback reports as valid and still failing.

## Not in this change

No MOP or structure/CLOS field inference: a future object representation should
observe fields through explicit readers first. No representation-conversion API:
a spec describes one representation and does not transform between them. No
keyed uniqueness for collections (`:unique` remains element EQL), no cross-field
constraints beyond `AND`/`SATISFIES`, and no tagged union; the tagged union
remains the next structured-data extension.
