---
name: comprehensive-test
description: Test cl-spec from multiple perspectives using parallel agents with cl-mcp tools. Each agent adopts a different role (user, spec compliance, agent ergonomics, generation/shrinking, error handling, etc.) to find issues that single-perspective testing misses. Use for pre-release validation or quality audits of cl-spec or one of its subsystems.
allowed-tools: Agent, Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, mcp__cl-mcp__fs-set-project-root, mcp__cl-mcp__repl-eval, mcp__cl-mcp__load-system, mcp__cl-mcp__run-tests, mcp__cl-mcp__clgrep-search, mcp__cl-mcp__lisp-read-file, mcp__cl-mcp__code-find, mcp__cl-mcp__code-describe, mcp__cl-mcp__code-find-references, mcp__cl-mcp__clhs-lookup, mcp__cl-mcp__lisp-check-parens, mcp__cl-mcp__inspect-object, mcp__cl-mcp__fs-list-directory, mcp__cl-mcp__fs-read-file, mcp__cl-mcp__spec-list, mcp__cl-mcp__spec-symbol, mcp__cl-mcp__spec-describe, mcp__cl-mcp__spec-check
---

# Comprehensive Test (cl-spec / cl-mcp)

Test cl-spec from multiple perspectives using parallel agents, then aggregate and
evaluate findings. Ported from cl-mcp's `comprehensive-test` skill and adapted to
cl-spec's systems, documented scope and self-specification bundle.

## Arguments

`$ARGUMENTS` should contain:
- What to test (the whole library, a subsystem, a feature or an API)
- Optionally, specific areas of concern

Examples:
- `/comprehensive-test full`
- `/comprehensive-test function specs with :cases`
- `/comprehensive-test hash-table-of / alist-of generation and shrinking`
- `/comprehensive-test instrumentation`
- `/comprehensive-test counterexample artifacts`

## Severity Criteria

All testers and the coordinator MUST use these definitions consistently:

| Severity | Definition | Examples |
|----------|------------|----------|
| **Critical** | Crashes, wrong verdicts, data loss, spec violations that break core guarantees | A failing contract reported `:passed`; a replay seed that does not reproduce; a shrunk counterexample that no longer fails; the core system loading `check-it`; validation mutating its input |
| **Major** | Incorrect behavior, missing validation, unhelpful errors, undocumented deviation from the specification | Malformed spec accepted at definition time; explain path pointing at the wrong field; budget exhaustion reported as unsatisfiable; error with no structured data |
| **Minor** | Style issues, naming inconsistency, documentation gaps, non-idiomatic patterns | Missing docstring on an export; inconsistent keyword naming between `*-data` functions; README example drifting from behavior |

### Out of scope (documented, not defects)

Do NOT report these as bugs. Report them only if the docs claim otherwise or the
behavior differs from what CLAUDE.md / the specification says:

- `describe-*` printers are stubs signalling `not-implemented`
- Extended argument contracts (§73.1 beyond the D1 range) are deferred
- Expected-error contracts, case-carrying contracts and state-observing
  (`:capture` / `:state-post`) contracts refuse runtime instrumentation
- State-observing contracts are not shrunk, replayed from a past result or
  persisted as counterexample artifacts; capture observes and does not copy or
  restore
- Struct / CLOS field specs (`object-of`) need a custom generator to construct values
- `generation-budget-exhausted` is a finite-budget outcome, never a claim of
  unsatisfiability
- cl-spec does not detect or restore destructive validation predicates/readers
  (they are contractually non-destructive)
- mallet findings are advisory (tracked for a batch cleanup); report only lint
  that hides a real bug
- The cl-mcp adapter lives in cl-mcp, not here

## Instructions

### 1. Analyze the Product

Before spawning testers, build a **context brief** to share with all testers:

1. **Set project root**: `fs-set-project-root` with the cl-spec working directory.
2. **Know the systems** (from CLAUDE.md; re-check `cl-spec.asd` if it changed):

   | System | Purpose |
   |---|---|
   | `cl-spec` | IR, registry, validation, explain, introspection, DSL (never loads `check-it`) |
   | `cl-spec/check-it` | generator backend, property execution, shrinking |
   | `cl-spec/instrument` | runtime function instrumentation |
   | `cl-spec/specs` | optional self-specification bundle (contracts + laws) |
   | `cl-spec/tests` | rove suite |
   | `cl-spec/examples/*` | inferred example subsystems (structured-data, function-spec-cases, stateful-withdraw, tutorial-cart) |

3. **Load**: `load-system` `cl-spec/check-it`, then `cl-spec/instrument` and
   `cl-spec/specs` as the scope needs.
4. **Read structure**: `lisp-read-file` (collapsed) on `main.lisp` for the public
   API, and on the `src/` files relevant to `$ARGUMENTS`. The specification is
   `docs/cl-spec-specification-v0.2-draft.md`; API references are under `docs/api/`;
   guides under `docs/guides/`; design docs under `docs/superpowers/specs/`.
5. **Baseline tests**: `run-tests` with `{"system": "cl-spec/tests"}`. Record
   pass/fail/pending counts. A `NO TESTS RAN` summary is not a pass.
6. **Baseline contracts**: `spec-list` to see registered contracts and laws; for
   the area under test, `spec-check` a few relevant ones (note seed and trials).
   The self-spec bundle requires `:satisfied` evidence under
   `cl-spec/specs:evidence-policy`, not only `:passed` — record both.
7. **Identify key areas**: `clgrep-search` for the code under test.

**Clean-process fallback** (not the dev REPL):
```bash
rove cl-spec.asd
```

**Compile the context brief** (pass this to every tester):
```
Scope: {what $ARGUMENTS asked for}
Systems loaded: {list}
Test baseline: {N passed, N failed, N pending for cl-spec/tests}
Contract baseline: {spec-check runs: name, seed, status, assessment}
Source modules: {relevant src/ files with brief purpose}
Public API: {key exported symbols from main.lisp for this scope}
Relevant docs: {spec sections, docs/api, docs/guides pages}
Known gaps: {failing tests, out-of-scope items above that touch this scope}
```

### 2. Determine Perspectives

Select 3-5 perspectives that fit the scope. Not all apply to every run.

**Perspective pool:**

| Perspective | When to use | Focus area | Example probe |
|-------------|-------------|------------|---------------|
| **End User** | Always | Public API works as documented in README, tutorial and `docs/api/`; errors are helpful | Follow the tutorial / a guide step by step via `repl-eval`; does every snippet behave as written? |
| **Spec Compliance** | Always (spec exists) | Implementation vs `docs/cl-spec-specification-v0.2-draft.md` and design docs | Pick each normative statement in the scoped sections and probe it with `repl-eval` |
| **Edge Case Explorer** | Always | Boundary specs and values: empty/NIL, dotted and circular lists, huge integers, nested structures, duplicate keys, `:test` variants, zero/one-element ranges | `validate`/`explain`/`sample` with NIL, `'(1 . 2)`, a circular list, `:min-count 0`, alist with duplicate keys under `eql` vs `equal` |
| **Generation & Shrinking** | check-it backend, properties, function specs | Seed reproducibility, replay, shrink validity, AND-generation source policy, filter budget accounting, distinct keys under `:test` | Run the same property twice with one seed; replay the `Replay:` line; check the shrunk value still fails and satisfies the spec |
| **Agent Ergonomics** | Introspection, explain, `*-data`, results | cl-spec is designed for LLM agents: are results machine-readable, stable, complete, and free of unreadable objects? | Inspect `function-spec-data`, `call-check-data`, explain output, counterexample artifacts: can an agent act on them without reading source? |
| **Error Handling** | Always | Definition-time validation, condition types and slots, rollback of registry/extension slots on failure | Define malformed specs/properties/generators; confirm the error type, message, and that the registry is unchanged afterwards |
| **Maintainability** | Library-wide audits | Package boundaries (`:import-from` only, no `cl-spec` nickname inside `src/`), condition hierarchy, naming, file responsibilities, docstrings | Does the core avoid `check-it`? Are `*-data` / `*-result` naming conventions consistent? |
| **Security / Robustness** | Artifacts, readers, user-supplied forms | Reader-free artifact codec, no runtime `eval`/`intern`, resource exhaustion, non-termination | Feed crafted artifact data to the counterexample loader; deeply nested or cyclic values to the codec |
| **Performance** | Generation, large maps, registries | Scaling of validation/generation/shrinking, consing, registry indexes | Validate a 10^5-entry `hash-table-of`; time shrinking of a large failing input |

The example probes are patterns. Design actual probes from the context brief's
public API.

Briefly tell the user which perspectives were chosen and why, then proceed.

### 3. Spawn Testers

For each selected perspective, spawn a tester agent in parallel (multiple Agent
tool calls in one message):

```
subagent_type: "general-purpose"
```

**Tester prompt template:**

> You are a tester reviewing **cl-spec**, an executable semantic IR and property
> framework for Common Lisp, from the **{Perspective}** perspective.
>
> ## Context (from coordinator)
>
> - Scope: {from context brief}
> - Working directory: {project root}
> - Systems loaded: {from context brief}
> - Test baseline: {from context brief}
> - Contract baseline: {from context brief}
> - Source modules: {from context brief}
> - Public API: {from context brief}
> - Relevant docs: {from context brief}
> - Known gaps: {from context brief}
>
> ## Your role
>
> {Role description from the perspective table}
>
> **Focus area**: {focus area from table}
>
> ## How to work
>
> Use cl-mcp tools (NOT shell commands like grep/cat/sed). Key tools:
> - `fs-set-project-root` (call FIRST), `load-system`, `repl-eval`, `run-tests`
> - `clgrep-search`, `lisp-read-file` for code; `fs-read-file` for Markdown docs
> - `code-find`, `code-describe`, `code-find-references` (after load)
> - `spec-list`, `spec-symbol`, `spec-describe`, `spec-check` for registered
>   contracts and laws (seed is a decimal string; copy the `Replay:` line to replay)
> - Shell only for: `rove`, `mallet`, `git`
>
> **Workflow**: fs-set-project-root → load-system `cl-spec/check-it` (plus
> `cl-spec/instrument` / `cl-spec/specs` if relevant) → read code and docs →
> `repl-eval` probes (package `cl-spec/main` or `cl-user` with `cl-spec:` prefixes)
> → report.
>
> ## Ground rules
>
> - **Read-only.** Do not edit any file in the repository. Probe definitions live
>   only in the REPL.
> - **Isolate global state.** Other testers may share the REPL worker. Bind a fresh
>   registry for every probe that defines specs, properties or generators:
>   `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))) ...)`.
>   Prefix any global name you must create with `{perspective-slug}-`. Never call
>   a clear operation on the default registry, and remove any instrumentation you
>   install before finishing.
> - **Pass a seed** to every generated run so findings are reproducible.
> - **Respect documented scope.** These are documented limitations, not bugs:
>   {Out-of-scope list from this skill}. Report one only if docs and behavior
>   disagree.
> - Distinguish `:passed` from `:satisfied` evidence; a passed run with
>   insufficient evidence is not a verification.
>
> ## Severity criteria
>
> - **Critical**: Crashes, wrong verdicts, data loss, spec violations breaking core guarantees
> - **Major**: Incorrect behavior, missing validation, unhelpful errors, undocumented spec deviation
> - **Minor**: Style, naming, docs gaps, non-idiomatic patterns
>
> ## Output format
>
> Report your **top 5 most important findings** (fewer is fine if thorough).
> Quality over quantity.
>
> ### {Perspective} Review
>
> #### Issues Found
>
> ##### 1. [Issue title]
> - **Severity**: Critical|Major|Minor
> - **Location**: `path/to/file.lisp:line`
> - **Spec reference**: §N of the specification / doc path (if applicable)
> - **Description**: ...
> - **Reproduction**: a self-contained `repl-eval` expression (with fresh registry
>   binding and seed) that demonstrates the issue, plus the observed vs expected result
> - **Suggestion**: ...
>
> #### Positive Observations
> - [Things done well from this perspective]
>
> #### Summary
> - Issues: {N Critical, N Major, N Minor}
> - Overall assessment from this perspective (1-2 sentences)
>
> #### Coverage Statement
> What you tested, how many expressions you evaluated, which spec sections you
> checked, and — if zero issues — why you are confident.
>
> #### cl-mcp Tool Feedback
>
> Report observations about the cl-mcp tools you used (including the `spec-*`
> tools). Classify each as:
> - **Bug**: Wrong result, crash, unexpected behavior
> - **Friction**: Worked but awkward, required workarounds, confusing parameters
> - **Missing**: Needed a capability that no tool provided
> - **Praise**: Worked especially well, saved significant effort
>
> | # | Tool | Category | Observation |
> |---|------|----------|-------------|
> | 1 | tool-name | Category | What happened |
>
> IMPORTANT:
> - Always reproduce issues with `repl-eval` before reporting them.
> - Distinguish actual bugs from style preferences.
> - Focus on YOUR perspective.

### 4. Aggregate Results

After all testers return:

**Product issues:**

1. **Verify**: Reproduce every Critical/Major issue yourself with `repl-eval`
   (fresh registry, same seed). Drop or downgrade anything that does not
   reproduce or that falls under the out-of-scope list.
2. **Deduplicate**: Merge findings reported by several perspectives and note
   which ones (multi-perspective findings are likely more important).
3. **Prioritize**: Severity first (Critical > Major > Minor), then number of
   flagging perspectives.
4. **Categorize** by area, e.g. "IR / Normalization", "Validation & Explain",
   "Field specs", "Maps", "Tagged unions", "Generation", "Properties & Shrinking",
   "Function specs", "Counterexample artifacts", "Instrumentation",
   "Self-spec bundle", "Docs".

**cl-mcp feedback:**

5. **Collect** every tester's `cl-mcp Tool Feedback` table.
6. **Deduplicate**, noting how many testers reported each observation.
7. **Accumulate** into the persistent feedback log (Step 6).

### 5. Report

```
## Comprehensive Test Report: cl-spec — {scope}

### Test Configuration
- Perspectives used: {list}
- Date: {today}
- Branch / commit: {git rev-parse --short HEAD}
- Test baseline: {run-tests summary}
- Contract baseline: {spec-check summary, incl. :satisfied vs :passed}

### Summary
- Critical: {N}
- Major: {N}
- Minor: {N}
- Total issues: {N}

### Critical Issues
(deduplicated, with reproduction expressions and flagging perspectives)

### Major Issues

### Minor Issues

### Documented limitations confirmed
(out-of-scope behaviors observed to match their documentation, briefly)

### Positive Findings

### Recommended Actions
1. [Prioritized action item]
```

### 6. Accumulate cl-mcp Feedback

**Feedback file**: `~/.claude/memory/cl-mcp-feedback.md` (global, shared with the
cl-mcp project's runs of this skill).

If it exists, read it first and append only new observations with `Edit`. If not,
create it with `Write`:

```markdown
# cl-mcp Tool Feedback Log

Accumulated feedback from comprehensive-test runs. Each entry records
friction, bugs, missing capabilities, and praise observed while using
cl-mcp tools for real testing tasks.

---

## Run: {date} — cl-spec: {scope}

| # | Tool | Category | Testers | Observation |
|---|------|----------|---------|-------------|
| 1 | {tool} | Bug/Friction/Missing/Praise | {perspectives} | {description} |
```

**Rules:**
- Each run gets a dated section header naming cl-spec and the scope
- `Testers` lists the perspectives that reported the observation
- Deduplicate within a run; keep similar entries across runs (frequency matters)
- Mark resolved entries `[RESOLVED {date}]`

### 7. Next Steps

Ask the user:
- Fix Critical issues now (TDD: failing rove test or contract first)?
- Add regression tests / self-spec contracts for the gaps found?
- Save the report under `docs/` (e.g. `docs/reports/{date}-comprehensive-test-{scope}.md`)?
- Review cl-mcp feedback and file issues upstream in cl-mcp?
