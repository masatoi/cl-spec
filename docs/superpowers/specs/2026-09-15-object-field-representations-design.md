# Struct and CLOS object field specifications

Approved design from the implementation discussion, 2026-09-15.

Add `(object-of CLASS (:required (READER SPEC) ...) (:optional (READER SPEC) ...))`
for structure and CLOS instances. CLASS is a non-NIL symbol naming a class or
structure type, resolved with `find-class` when a value is checked so a forward
reference stays legal. Each entry names a one-argument reader as a symbol (or,
programmatically, a function object); the reader is the field key, so error paths
and `:field-path` carry the reader name.

Only `:required` and `:optional` clauses are accepted. `:closed` is refused
because a reader observes declared fields only and cannot enumerate undeclared
slots without MOP; `:test` is refused because there is no key to compare.
Programmatic construction refuses `:closed-p t` for the same reason.

The value is first checked against CLASS; a non-instance is `:not-an-instance`
and no reader runs. Then each field is read. A reader that returns NIL is a
present field with value NIL. A reader that signals `unbound-slot` marks the
field absent: `:unbound-slot` when required, no error when optional. Any other
condition becomes `:reader-errored` with `:condition-type` and
`:condition-report`, except `undefined-function` (a misspelled reader) and
`program-error` (wrong reader arity), which are authoring mistakes and propagate.
This is the same rule `predicate-spec` applies to a signalling predicate.

The IR reuses `field-spec` and `field-definition` unchanged; `object-spec` adds
only `class-name` and reports `:object`. Validation checks the class name, that
each field key is a reader designator, and that readers are unique, and it runs
before initialization or reinitialization changes a slot. Field metadata stays
separate from storage, so a future object representation can choose different
observation rules.

`spec-data` reports `:class-name`, `:closed` (always NIL) and `:fields`.
`definition-constraints` prepends `:class`, so the digest covers the class as
well as reader names, requiredness and child specs. The expected descriptor is
`:kind :object`, `:class`, `:fields`.

Readers observe but do not construct, so the check-it backend reports
`generator-unavailable` for an `object-of` spec and `backend-capabilities`
answers `:generation :unavailable`. A definition may attach `(:generator NAME)`,
which the existing custom-generator path honors; that is the only construction
route today, because only the author knows the constructor and its initargs.
Shrinking follows the same custom generator's shrinker.

## Not in this change

No MOP-driven slot enumeration or initarg inference. No `:closed` semantics for
objects, no constructor/builder clause turning a field plist into an instance,
and no `defspec-generic` or integrated generic-function inspection. Those remain
future work under specification section 23.
