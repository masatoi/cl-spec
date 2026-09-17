# Task: replacement registration leaves stale reverse-index entries

## Reported behaviour

Re-registering a property under a name it already has must replace the stored
definition and retract the reverse-index entries the previous definition
declared. After the replacement, a target or tag that only the old definition
used must no longer answer with that name.

In this checkout the replacement leaves the old target and tag entries behind,
so `properties-for` and `properties-with-tag` still report a property that no
longer declares them.

## Required change

Make the property registration path retract the previous definition's index keys
before the new ones are indexed. Keep every other behaviour: a fresh name joins
the names and every declared index; a refused index argument changes nothing;
an index entry shared with another property stays.

## Where

Only `src/registry.lisp`.

## How you will be judged

The public registry API is exercised directly with an explicit before/after
expectation, and the self-specification bundle (when present) is run over the
same invariant. Do not change tests or specifications to make the report go
away.
