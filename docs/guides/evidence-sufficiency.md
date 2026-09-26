# Evidence sufficiency

Execution status and evidence sufficiency answer different questions.
`:passed` means that the observed execution found no contract violation.
It does not mean that every declared case was checked, or that an application
is safe to change.

The core APIs are:

- `(evidence-summary result)`: saved facts with `:assessment :not-assessed`.
- `(assess-evidence result policy)`: a separate assessment against explicit requirements.

Both accept property/function run results, `call-check-result`, and
`fixture-check-result`. They inspect saved facts without calling targets,
predicates, fixture hooks or generators, and without consulting the current registry.
Returned lists and strings are defensive copies.

## Passed, but insufficient

This example uses only the core system and leaves the current registry untouched.

```lisp
(asdf:load-system :cl-spec)

(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
  (cl-spec:defspec-function identity
    (:args (x integer))
    (:cases
      (:nonnegative (:when (>= x 0)) (:returns integer))
      (:negative (:when (< x 0)) (:returns integer))))
  (let* ((result (cl-spec:check-call 'identity '(3)))
         (assessment
           (cl-spec:assess-evidence
            result
            '(:policy-version 1
              :requirements ((:kind :all-declared-cases :min-checked 1))))))
    (list (getf assessment :execution-status)
          (getf assessment :assessment)
          (getf assessment :gaps))))
;; => (:PASSED :INSUFFICIENT
;;     ((:KIND :CASE-CHECKS-BELOW-MINIMUM :CASE :NEGATIVE
;;       :REQUIRED 1 :OBSERVED 0 :SOURCE (:CASE-REPORT :CASES :NEGATIVE))))
```

Declaring two cases does not imply that a single call exercised both.
Their names are captured before execution; redefining the contract later does
not change this result's evidence.

## Policies

Version 1 accepts a nonempty list of these requirements, at most one of each:

| Requirement | Meaning |
|---|---|
| `(:kind :min-checked-trials :count N)` | At least N ordinary trials concluded `:passed` or `:failed`. |
| `(:kind :all-declared-cases :min-checked N)` | Each declared case has at least N concluded verdicts. |
| `(:kind :requested-trials-completed)` | The generated run reached its saved trial budget. |

N must be a positive integer. Unknown keys, unknown or repeated kinds, duplicate
keys, invalid versions, malformed lists and cycles signal
`invalid-evidence-policy`. Its `invalid-evidence-policy-reason` reader explains
the refusal. Unsupported requirements are not silently ignored.

For example:

```lisp
'(:policy-version 1
  :requirements ((:kind :min-checked-trials :count 100)
                 (:kind :all-declared-cases :min-checked 1)
                 (:kind :requested-trials-completed)))
```

No default sufficiency policy is applied. The consumer chooses thresholds
appropriate to the intended task.

## Assessment and availability

| Assessment | Meaning |
|---|---|
| `:satisfied` | Every applicable requirement is supported by measured facts. |
| `:insufficient` | At least one requirement has a measured shortfall. |
| `:unknown` | No known shortfall, but required measurements are missing. |
| `:not-assessed` | No policy was applied, or all its requirements are inapplicable. |

A known shortfall takes precedence over unknown measurements; both `:gaps` and
`:unknowns` remain available. All-inapplicable policies carry
`:reason :no-applicable-requirements`.

Each dimension separately records `:collected`, `:not-collected`, or
`:not-applicable`. Measured zero is different from missing data:

```lisp
(getf
 (cl-spec:assess-evidence
  (make-instance 'cl-spec:property-result :status :passed :trials 100)
  '(:policy-version 1 :requirements ((:kind :min-checked-trials :count 1))))
 :assessment)
;; => :UNKNOWN
```

Old or manually constructed results do not acquire invented checked counts from
`:trials - :rejected`. Legacy backends can still run, but their normal-trial
measurement is unknown unless they implement the reporting protocol.

Direct checks have scope `:single-call`; generated results have scope
`:single-run`. A generated budget is inapplicable to a direct check.
No declared cases is inapplicable only when the saved declaration confirms it;
an absent declaration snapshot remains unknown.

## What is counted

Checked means an ordinary trial with a final `:passed` or `:failed` verdict.
It does not mean success, nor execution of every postcondition after an earlier
violation. Expected conditions satisfying `:signals` count as passed.
Precondition refusal, contract evaluation error, and fixture lifecycle error do
not count. A case's target may have been called without reaching a verdict.

Shrink candidates, bounded-filter attempts and artifact rechecks do not increase
the original run's count. If a shrink candidate's cleanup fails, the existing
`:run-error` is preserved, while the earlier ordinary trial counts remain intact.

Thus `:failed` or `:error` can coexist with `:satisfied`: the policy's measured
requirements were met, but execution still failed. Consumers must inspect both
`:execution-status` and `:assessment`. A satisfied assessment is not a correctness
proof or permission to change code.

## Integration and limits

`result-data`, `call-check-data` and `fixture-check-data` include an additive
`:evidence` summary. Existing outer schema versions and artifact formats remain
unchanged. `schema-info` describes the separate version-one evidence protocol.

Summary `:gaps` lists observed omissions; assessment `:gaps` only lists violations
of the supplied policy. `:limitations` records the scope of the evidence;
`:diagnostics` retains generation, shrink and capability reports without treating
capabilities as executed checks.

Optional-field, numeric-boundary and combination coverage are not measured by
version 1. There is no aggregation across runs or automatic unreachable-case
exclusion. A declaration digest does not identify the target implementation;
unknown target revision stays explicit. The cl-mcp adapter is a separate change.

Backend implementers opt in through
`cl-spec/src/generator:backend-trial-reporting`, returning `:trial-report-v1`.
They open reporting with `begin-trial-report`, submit each ordinary observation
exactly once with `note-trial-outcome`, and close with
`cl-spec/src/trial-report:end-trial-report`. The runner owns the resulting report
and rejects backend-supplied `:trial-report` keys, wrong-run/duplicate observations,
incomplete reporting, inconsistent trial/case counts, or execution status that
contradicts the reported verdicts. Duplicate detection does not retain completed
observations. A retained original failure must have been reported as an ordinary trial. The shipped check-it
class opts in; subclasses overriding execution must opt in explicitly.
