# cl-spec/specs

Optional executable specifications of cl-spec's own APIs and semantic laws.

System `cl-spec/specs`, 9 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Functions**: [`check-registry-implementation`](#check-registry-implementation) · [`contract-names`](#contract-names) · [`evidence-policy`](#evidence-policy) · [`property-names`](#property-names) · [`register-instrumentation-specifications`](#register-instrumentation-specifications) · [`register-specifications`](#register-specifications) · [`registry-conformance-names`](#registry-conformance-names) · [`registry-implementation-p`](#registry-implementation-p)

**Variables**: [`*registry-constructor*`](#registry-constructor)

## Functions

<a name="check-registry-implementation"></a>
### check-registry-implementation

*Function* · `(constructor &key (seeds (quote (1 42 2026))) (trials 50))`

Run the registry-protocol contracts and laws against registries CONSTRUCTOR returns.

```text
CONSTRUCTOR is a function of no arguments returning a fresh, empty registry.  It
is called once before any check to confirm REGISTRY-IMPLEMENTATION-P, and a
TYPE-ERROR is signalled otherwise.  The bundle is registered in a private
registry, so CL-SPEC:*REGISTRY* is left untouched.  Every contract runs TRIALS
trials and every law its declared :NORMAL budget, once per seed in SEEDS.

Return two values: true when every run passed with :SATISFIED evidence under
EVIDENCE-POLICY, and a list of one plist per run with :KIND, :NAME, :SEED,
:STATUS, :ASSESSMENT and :RESULT.  Executing the checks requires a generator
backend such as CL-SPEC/CHECK-IT to be loaded.
```

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

<a name="registry-conformance-names"></a>
### registry-conformance-names

*Function*

Return the contracts and laws that describe the REGISTRY-* protocol itself.

```text
Each builds the registry it checks with MAKE-REGISTRY-UNDER-TEST, so
CHECK-REGISTRY-IMPLEMENTATION runs exactly these against another implementation.
The value is a plist of :CONTRACTS and :PROPERTIES name lists.
```

<a name="registry-implementation-p"></a>
### registry-implementation-p

*Function* · `(object)`

True when every REGISTRY-* protocol function has a primary method for OBJECT.

```text
The check dispatches on OBJECT as the registry argument with NIL for the others,
so it describes implementations that specialize only the registry, as the
built-in HASH-TABLE-REGISTRY does.  It inspects method applicability only and
calls none of the methods.  The core's unqualified :AROUND validation methods
apply to every object and are not counted.
```


## Variables

<a name="registry-constructor"></a>
### *registry-constructor*

*Variable*

Function of no arguments returning an empty registry for the registry-protocol checks.

```text
Every registry law and registry contract in the bundle builds the registry it
checks through MAKE-REGISTRY-UNDER-TEST, so binding this special runs the same
checks against another implementation of the REGISTRY-* protocol, including a
deliberately faulty one.  The registration fixture reads it at setup, so a saved
recipe rechecked under the same binding reconstructs the same implementation.
```

