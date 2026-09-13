# cl-spec/check-it

check-it based generator construction and property execution backend.

System `cl-spec/check-it`, 3 exported symbols. Docstrings are reproduced from the source; accessor entries use their class slot's documentation, and a leading summary paragraph is followed by the rest of the docstring verbatim.

## Contents

**Functions**: [`default-trials`](#default-trials) · [`install-check-it-backend`](#install-check-it-backend)

**Classes**: [`check-it-backend`](#check-it-backend)

## Functions

<a name="default-trials"></a>
### default-trials

*Function*

Return check-it's current default number of trials per property run.

<a name="install-check-it-backend"></a>
### install-check-it-backend

*Function*

Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

```text
Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation.
```


## Classes

<a name="check-it-backend"></a>
### check-it-backend

*Class*

Generator backend delegating to the check-it library.

