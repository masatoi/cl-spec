# Task: the function-spec projection drops declared capture bindings

## Reported behaviour

`function-spec-data` must project the ordered `:capture` declarations of a
contract that declares them, each as `(:name NAME :form FORM)`. In this checkout
the declared capture bindings are missing from the projection.

## Required change

Restore the `:capture` key so it lists the contract's declared capture bindings
in order when the contract declares any, and stays absent when it declares none.
Leave the case and state-post projection unchanged.

## Where

Only `src/introspection.lisp`.

## How you will be judged

A contract with one declared capture is projected and the expected key is read
directly, and the self-specification bundle (when present) is run over the same
declaration. Do not change tests or specifications to make the report go away.
