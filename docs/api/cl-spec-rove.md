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
OPTIONS supplies the remaining CHECK-CONTRACTS arguments such as :SEEDS,
:TRIALS or :REGISTRY. The test reports the seed used. On failure its assertion
includes the saved counterexample and definition digest when available.
```

