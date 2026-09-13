# cl-spec/specs

Optional executable specifications of cl-spec's own APIs and semantic laws.

System `cl-spec/specs`, 4 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Functions**: [`contract-names`](#contract-names) · [`property-names`](#property-names) · [`register-instrumentation-specifications`](#register-instrumentation-specifications) · [`register-specifications`](#register-specifications)

## Functions

<a name="contract-names"></a>
### contract-names

*Function*

Return the public functions covered by this executable specification bundle.

<a name="property-names"></a>
### property-names

*Function*

Return the executable semantic laws in this specification bundle.

<a name="register-instrumentation-specifications"></a>
### register-instrumentation-specifications

*Function*

Register the optional status API contract after CL-SPEC/INSTRUMENT is loaded.
Return its name. This bundle never loads the instrumentation system itself.

<a name="register-specifications"></a>
### register-specifications

*Function*

Install executable contracts and laws in CL-SPEC:*REGISTRY*.
Loading CL-SPEC/SPECS installs these once. Call this function again after
CLEAR-REGISTRY or with a freshly bound registry. It does not instrument functions.
Generators exercise finite subsets. Most API contracts accept broader domains;
the malformed-normalization contract explicitly names its finite input corpus.

