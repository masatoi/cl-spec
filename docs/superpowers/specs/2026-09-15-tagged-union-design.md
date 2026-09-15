# Tagged (dispatched) unions

Approved design from the implementation discussion, 2026-09-15.

Add `(tagged-by TAG-READER (NAME SPEC) ...)`. The tag reader is explicit: a
keyword reads the value's plist entry with `getf`, while any other symbol names a
one-argument reader resolved like an object field reader. Each branch NAME is a
non-NIL symbol that is both the label reported in diagnostics and the EQL tag
value the reader is matched against, so the name and the tag cannot drift apart.
Branch names are unique and at least one branch is required.

The union dispatches: it reads the tag, finds the branch whose name is EQL to it,
and validates the value against that branch's spec alone. Errors from that branch
carry `:branch NAME`; a tag matching no branch is `:no-branch` with
`:observed-tag` and `:known-tags`. This is the difference from `OR`, which
reports every alternative under `:no-branch-matched`; the tagged union narrows to
the selected branch and gives a machine-readable branch name. A signalling tag
reader is `:reader-errored` with the condition type, while `undefined-function`
and `program-error` propagate as authoring errors, matching `object-of`.

Branch specs describe the whole value. The union reads the tag but does not
inject it, so a `:closed` plist branch must declare its tag field. A branch spec
that omits the tag still validates correctly when the tag happens to be read from
elsewhere, but generation from it can produce a value the union rejects; that is
the same honest failure mode as a custom generator drawing outside its spec.

The IR is a new `src/tagged-union.lisp` with `branch-definition` (name, spec) and
`tagged-union-spec` (tag reader, ordered branches) under `:tagged-union`.
`spec-children` returns the branch specs, so digest dependency traversal and
`validate-definition-tree` reach them. `shared-initialize :around` validates the
tag reader, the nonempty branch list, branch names and uniqueness before any slot
changes.

`spec-data` reports `:tag-reader` and `:branches` as
`(:name NAME :child-index INDEX)`. `definition-constraints` carries the tag
reader and the branch-name order; the branch specs enter the digest as children.
The expected descriptor is `:kind :tagged-union`, `:tag-reader` and `:branches`
with per-branch names and child descriptors.

Generation builds an `or-generator` over the branch generators so every branch is
reachable. Branch targeting is explicit: `sample` gains `:branch NAME`, and the
public `tagged-union-branch` returns the branch spec for a designator. Together
they let a caller draw or inspect one alternative; an unknown branch names the
branches that exist.

Failure identity keeps `:branch`, `:branch-path` and `:known-tags` as spec-derived
keys and drops `:observed-tag` as value-derived. `:branch` names the innermost
union that produced the error and `:branch-path` accumulates every enclosing
branch name outermost first (like `:field-path`), so a nested union's selection
survives an outer union's tagging and the same violation in the same branch
compares equal while a different branch or an unmatched tag does not.

## Not in this change

No catch-all/else branch, no multiple tag values per branch, and no tag injection
into a generated or constructed branch value. Those can be added without changing
the dispatch semantics because the branch spec remains the complete value spec.
