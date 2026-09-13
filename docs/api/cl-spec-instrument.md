# cl-spec/instrument

Runtime instrumentation that checks registered contracts at call sites.

System `cl-spec/instrument`, 13 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Functions**: [`instrument-function`](#instrument-function) · [`instrumentation-status`](#instrumentation-status) · [`instrumented-function-p`](#instrumented-function-p) · [`refresh-instrumentation`](#refresh-instrumentation) · [`uninstrument-function`](#uninstrument-function)

**Accessors**: [`instrumentation-violation-function`](#instrumentation-violation-function) · [`instrumentation-violation-reason`](#instrumentation-violation-reason) · [`instrumentation-violation-scope`](#instrumentation-violation-scope) · [`unsupported-instrumentation-target-name`](#unsupported-instrumentation-target-name) · [`unsupported-instrumentation-target-reason`](#unsupported-instrumentation-target-reason)

**Conditions**: [`instrumentation-violation`](#instrumentation-violation) · [`unsupported-instrumentation-target`](#unsupported-instrumentation-target)

**Variables**: [`*instrumented-functions*`](#instrumented-functions)

## Functions

<a name="instrument-function"></a>
### instrument-function

*Function* · `(name &rest options)`

Install checks for NAME and return NAME; refresh an existing wrapper without stacking.

```text
OPTIONS accepts :REGISTRY (NIL or omitted means *REGISTRY*) and :SCOPES
(default (:INPUT :OUTPUT :POST)). The positional registry argument is also accepted.
:INPUT checks arity, argument specs and :PRE; :OUTPUT checks the primary value;
:POST checks postconditions. NIL scopes disables checks. All target values and
conditions pass through. Failed checks signal INSTRUMENTATION-VIOLATION.

Only ordinary symbol-named functions outside COMMON-LISP are supported.
Missing contracts signal UNKNOWN-FUNCTION-SPEC, undefined targets UNBOUND-TARGET,
and unsupported definitions UNSUPPORTED-INSTRUMENTATION-TARGET.
:INPUT describes the entire argument list, not a prefix of the target lambda list.
Checks capture the contract at installation; reinstall to refresh it. Previously
captured function objects, lexical and inlined calls are not intercepted.
```

<a name="instrumentation-status"></a>
### instrumentation-status

*Function* · `(name &key (registry *registry*))`

Describe installed checks without changing the function or installation table.
Local declaration changes are stale. Named dependencies resolve dynamically, so
their changes are reported separately. Incomplete evidence is indeterminate.
Installed omissions and digest exclusions are installation-time snapshots.
Current omissions are freshly collected; :NOT-COLLECTED distinguishes absent
inspection from a known empty omission list.

<a name="instrumented-function-p"></a>
### instrumented-function-p

*Function* · `(name)`

Return true while NAME's fdefinition is our wrapper; forget stale installation state.

<a name="refresh-instrumentation"></a>
### refresh-instrumentation

*Function* · `(name &key (registry nil registry-p) (scopes nil scopes-p))`

Rebuild an active installation against its original target without stacking wrappers.
Omitted REGISTRY and SCOPES retain the installation's settings. Refuse external
redefinitions and missing installations, preserving the function and table.

<a name="uninstrument-function"></a>
### uninstrument-function

*Function* · `(name)`

Restore NAME's original function only if its installed wrapper is still current.
Return true when restored, NIL otherwise. Forget stale entries without overwriting
a later redefinition or undoing FMAKUNBOUND.


## Accessors

<a name="instrumentation-violation-function"></a>
### instrumentation-violation-function

*Accessor* of `instrumentation-violation` · `(condition)`

Symbol naming the wrapped function.

<a name="instrumentation-violation-reason"></a>
### instrumentation-violation-reason

*Accessor* of `instrumentation-violation` · `(condition)`

The failed arity, argument, precondition,
return or postcondition check.

<a name="instrumentation-violation-scope"></a>
### instrumentation-violation-scope

*Accessor* of `instrumentation-violation` · `(condition)`

The failed :INPUT, :OUTPUT or :POST scope.

<a name="unsupported-instrumentation-target-name"></a>
### unsupported-instrumentation-target-name

*Accessor* of `unsupported-instrumentation-target` · `(condition)`

The name whose definition cannot be wrapped.

<a name="unsupported-instrumentation-target-reason"></a>
### unsupported-instrumentation-target-reason

*Accessor* of `unsupported-instrumentation-target` · `(condition)`

Why this definition is unsupported.


## Conditions

<a name="instrumentation-violation"></a>
### instrumentation-violation

*Condition* · extends spec-violation

Runtime contract failure with SPEC-VIOLATION's structured error evidence.

<a name="unsupported-instrumentation-target"></a>
### unsupported-instrumentation-target

*Condition* · extends cl-spec-error, program-error

A defined target is not an ordinary writable function supported by this module.


## Variables

<a name="instrumented-functions"></a>
### *instrumented-functions*

*Variable*

Symbol -&gt; private installation entry. Bind a fresh table only in isolated tests.
Installations and function redefinitions must be serialized by the caller.

