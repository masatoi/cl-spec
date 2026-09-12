# Verification evidence

Implement the user's requested evidence corrections on branch verification-evidence.

## Execution contract

A shared core execution module records each evaluated input with its observed status,
failure signature, reason, explanation and condition. Property observations distinguish a
false predicate from a signalled error, and errors by condition type. Function contracts
supply their existing return-spec/post-form/target/contract identities through a property
subclass and the same trial evaluation protocol. The initial trial and each shrink attempt
evaluate user code once; classification never calls the target again. Return validation uses
EXPLAIN-DATA once, avoiding a second evaluation of SATISFIES predicates.

The check-it backend rejects shrink attempts whose identity differs from the original
failure. Only observations made while shrinking can supply a reported shrunk value; an
unobserved backend return value is not evidence. A shrink report means an observed reduction,
not a proof of global minimality. Zero-argument failures need no shrinking.

Capture generated conses and arrays before user execution. Invoke user code on the actual
generated objects to preserve EQ semantics. Stop shrinking if a trial mutates argument
storage, since its generator caches can no longer be trusted. Arbitrary CLOS objects and
external state are not checkpointed.
Ordinary shrinking still executes the target, so stateful targets must not be described as
replayed or pure. Keep the original observation alongside the selected shrink observation.

## Backend and result protocol

RUN-GENERATED-TEST requires a nonnegative integer :trials option and returns a plist with
explicit :status and :trials. Missing/invalid counts signal a backend protocol error rather
than becoming zero-trial success. Completed trial counts cannot exceed the requested budget.
Failed/error outcomes carry :failure observation, optionally :shrunk-failure, and
:shrunk-outcome (:used, :none, :different-failure). :rejected counts only generated trials
refused by function preconditions. A shared around method validates returned evidence.
Public property results expose original and shrunk observations and shrink disposition.
Function-check results retain their existing accessors, populated from the selected
observation, not a classification rerun.

## Entity discrimination

Add :entity-kind to spec-data, property-data and function-spec-data with values :spec,
:property and :function-spec. Preserve existing :kind values as node/author classification
and the legacy function-spec marker. Property-result-entity-kind distinguishes :property
from :function-spec results. This is additive for introspection consumers.

## Validation

Test identity transitions (false/error, different error types, same-type conditions with
different reports), observed condition/input agreement, zero-argument side effects,
return-predicate evaluation counts, mutable argument snapshots, precondition accounting,
seeded replay, malformed backend replies and discriminator collisions. Update prior tests
that assumed a final incompatible candidate discards all earlier valid reductions: the new
shrinker may now find a smaller candidate that still has the original failure identity.
Core loading must continue to avoid check-it. Use Rove, forced compile and mallet.
