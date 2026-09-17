# Task: the result projection drops state evidence

## Reported behaviour

`result-data` must keep the observed state evidence of a failing
state-observing run under `:failure :state`, with the capture bindings that
completed and the state-post verdict. In this checkout the `:state` key is
missing from the projected observation.

## Required change

Restore the `:state` key in the observation projection so it appears exactly
when the run reported state evidence and stays absent otherwise. Keep the
outcome, failure phase and failure reason unchanged.

## Where

Only `src/property-runner.lisp`.

## How you will be judged

A small state-post-violating contract is run and the projected evidence is read
directly, and the self-specification bundle (when present) is run over the same
evidence. Do not change tests or specifications to make the report go away.
