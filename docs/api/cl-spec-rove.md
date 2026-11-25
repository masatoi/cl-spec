# cl-spec/rove

Optional Rove tests backed by the contract suite verdict.

System `cl-spec/rove`, 1 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Macros**: [`deftest-contract`](#deftest-contract)

## Macros

<a name="deftest-contract"></a>
### deftest-contract

*Macro* · `(test-name target &rest options)`

Define a Rove test that runs TARGET and uses CHECK-CONTRACTS to judge it.

```text
TARGET is a literal name or a (:FUNCTION-SPEC NAME) or (:PROPERTY NAME) pair.
OPTIONS supplies non-selector CHECK-CONTRACTS arguments such as :SEEDS,
:TRIALS, :POLICY or :REGISTRY. The macro rejects :NAMES, :PACKAGE and :TAG
during expansion. The test reports the seed used. Its failure description
includes the saved counterexample, definition digest and example conditions
when available. On SBCL, caller deadlines and interrupts propagate out of the test.
```

