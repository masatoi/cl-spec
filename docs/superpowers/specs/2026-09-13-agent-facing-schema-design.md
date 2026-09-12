# Agent-facing schema version 1

The user approved stabilizing definition and result records before instrumentation.
Keep :entity-kind (:spec/:property/:function-spec) and all legacy :kind meanings.
Add :schema-version 1, :record-kind (:definition/:result), :definition-digest,
:definition-digest-complete, :definition-digest-covers, and :capabilities.
Required keys are present even when NIL. Optional unknown keys are ignored by
consumers; incompatible meanings or required-key removals require a new version.
The Lisp schema version is independent of the MCP JSON envelope version.
After review, only root records carry the full envelope. Nested IR projections
retain :entity-kind without repeating dependency walks and generator compilation.

Digest a canonical, bounded representation of the declaration and its reachable
IR, registered reference specs, and registered custom generator definitions.
Do not hash capabilities, source locations, backend availability, or timing.
Use tagged FNV-1a 64-bit as a non-cryptographic change detector, with explicit
completeness. Missing references, missing stored executable source, opaque values,
or budget exhaustion produce NIL/incomplete, never a trusted partial digest.
Target implementation, helper function implementations and captured/external state
are outside coverage. Results capture this metadata before generation, so later
registry updates cannot relabel earlier evidence. Raw CLOS predicates without
stored source remain executable but cannot claim a complete definition digest.

Use shared generic declaration descriptions, specialized for function-spec in its
own file to avoid dependency cycles. Backend capability probes may compile a
schema but must never draw values or run target/predicate functions. Unknown
backends default to unknown. Custom whole-argument generators advertise generation
available and automatic shrinking none; missing backend/generator is explicit.
During a run, the backend reports capabilities captured from its actual compiled
generator; the runner does not compile a second generator solely for metadata.
Expose schema-info and result-data, while preserving existing result readers.

cl-mcp already has a legacy digest and JSON schema version. Prefer core metadata
when available and retain a fallback for older cl-spec. Carry core schema facts as
an additive nested object through describe/check JSON responses. Exercise actual
adapter API discovery, digest matching, and JSON response construction in contract
tests. The cl-mcp checkout contains unrelated staged work; preserve it and limit
adapter edits to the relevant source/tests.

Tests cover deterministic digests across printer settings, changed reference and
generator definitions, missing/opaque/cyclic data, frozen result metadata, namespace
collisions, capabilities without executing user code, no-backend behavior, legacy
adapter fallback, and real JSON handoff. Core must not depend on check-it or cl-mcp.
