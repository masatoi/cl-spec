# cl-spec/specs

Optional executable specifications of cl-spec's own APIs and semantic laws.

System `cl-spec/specs`, 5 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Functions**: [`contract-names`](#contract-names) · [`evidence-policy`](#evidence-policy) · [`property-names`](#property-names) · [`register-instrumentation-specifications`](#register-instrumentation-specifications) · [`register-specifications`](#register-specifications)

## Functions

<a name="contract-names"></a>
### contract-names

*Function*

Return the public functions covered by this executable specification bundle.

<a name="evidence-policy"></a>
### evidence-policy

*Function* · `(trials)`

Return the evidence policy a run of this bundle is held to for a TRIALS budget.

```text
A :PASSED status says only that the observed trials found no violation.  This
policy is the separate claim, checked with CL-SPEC:ASSESS-EVIDENCE, that the run
completed its budget, that every one of its TRIALS reached a passed or failed
verdict, and that each declared case reached at least one verdict.  It inspects
saved facts only; it neither reruns the check nor proves the domain covered.
```

<a name="property-names"></a>
### property-names

*Function*

Return the executable semantic laws in this specification bundle.

<a name="register-instrumentation-specifications"></a>
### register-instrumentation-specifications

*Function*

Register the optional instrumentation API contracts after CL-SPEC/INSTRUMENT is loaded.
Return the INSTRUMENTATION-STATUS name. This bundle never loads the instrumentation
system itself, so every instrumentation symbol is resolved here by name.

<a name="register-specifications"></a>
### register-specifications

*Function*

Install executable contracts and laws in CL-SPEC:*REGISTRY*.
Loading CL-SPEC/SPECS installs these once. Call this function again after
CLEAR-REGISTRY or with a freshly bound registry. It does not instrument functions.
Generators exercise finite subsets. Most API contracts accept broader domains;
the malformed-normalization contract and the validate cases explicitly name
their finite input corpora, and the registry write contract names its scenarios.

