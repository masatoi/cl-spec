# Structured generation self-specifications

> **For agentic workers:** Use superpowers:executing-plans to implement this plan.

**Goal:** Extend executable generation and retained-counterexample laws to homogeneous
maps, keyed fields, tagged unions and AND composition (specification §68.1).

**Architecture:** Keep bounded, deterministic fixture domains in a separate inferred
subsystem. Every law iteration visits every fixture. Recheck retained structured
inputs through core CHECK-CALL; preserve the existing artifact law for serializable
inputs. Do not extend the artifact codec or backend semantics.

**Tech Stack:** Common Lisp, ASDF package-inferred systems, Rove, check-it.
**Spec:** The accepted improvement 1 in this conversation; specification §68.1.

## Constraints and review focus

- Core and the specification bundle must not acquire a check-it dependency.
- EQ keys use symbols; EQUAL/EQUALP fixtures exercise string equivalence.
- Empty maps and unshrinkable values must not be counted as successful shrinks.
- Nonempty shrink fixtures must actually retain shrunk evidence in acceptance tests.
- Tagged branches are exercised explicitly, not left to random branch selection.
- Budget exhaustion is a measured failure of generation, never unsatisfiability.
- Hash-table values use direct rechecks; the artifact codec does not support them.
- Existing registration/discovery/execution lists must stay in agreement.

## Task 1: Extend the executable laws

- [x] Add failing Rove coverage and behavioral checks to self-specs-test.
- [x] Add self-generation-fixtures.lisp with finite structured generation domains,
      contract construction and retained-evidence checks.
- [x] Extend the generation corpus and retained-counterexample law in specs.lisp.
- [x] Add a bounded generation law for deterministic collision/filter exhaustion.
- [x] Run targeted suites and inspect failures.

## Task 2: Verify and document

- [x] Document the finite coverage and direct-versus-artifact recheck distinction.
- [x] Run the full suite and compile checks; inspect warnings and the final diff.
- [x] Review the completed changes and address correctness findings.

Execution: authorized by the user's implementation request; work in the current
clean checkout. No push or merge is part of this change.

## Execution record

- Initial coverage/registration tests failed before the corpus and laws were added.
- Added 25 structured domains, three executable laws, and independent boundary
  and negative-evidence tests. Existing artifact law remains intact.
- Ruling: string MEMBER keys stay in generation checks; direct rechecks use STRING
  because cons/array snapshots lose EQL string identity. Documented and tested.
- Review found a false positive in the reduction acceptance test. A saved-original
  negative test failed, then passed with an optional REQUIRE-REDUCTION check using
  EQUALP, including hash-table contents. Seed 1 demonstrates actual reductions;
  the general validity law permits already-minimal generated inputs.
- Review also tightened EQL vs EQUALP (forced keys 1 and 1.0) and sample counts.
- Full suite and final verification results are reported with the delivered change.
- Forced compilation succeeded. Mallet reports only two pre-existing needless-let*
  warnings in unchanged portions of specs.lisp.
