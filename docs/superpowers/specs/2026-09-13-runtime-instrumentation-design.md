# Runtime instrumentation design

Implement specification §20 in the opt-in `cl-spec/instrument` system. The existing
required positional argument and primary return value contract remains unchanged.

API: `(instrument-function name :registry registry :scopes '(:input :output :post))`.
The existing `(instrument-function name registry)` call remains supported. The module
package gains nickname `cl-spec/instrument`; core does not import the wrapper module.

`:input` validates arity, argument specs and preconditions before invoking the target.
`:output` validates the primary return value. `:post` evaluates postconditions using
the primary value and the arguments (including target mutations), as check-function does.
The argument contract describes the entire call, even when the target accepts extras.
All scopes are enabled by default; an explicit empty list is allowed. All actual return
values and target conditions pass through unchanged when checks succeed. A spec-violation from pre is an input refusal via the shared precondition-refuses-p.
Other pre errors and post predicate errors propagate. Argument and return spec predicates retain existing explain/validate semantics:
predicate errors become structured :predicate-errored evidence except authoring errors. Structured violations extend
`spec-violation` with function, scope and reason readers; failed DSL post forms retain index. The inherited spec slot holds actual IR:
argument/return specs, an arity tuple, or synthetic pre/post predicates. Pre values are
argument lists; post values are (primary-value . arguments). Error records use error-datum.

Use ANSI `fdefinition` wrappers rather than implementation-specific advice. Only ordinary
symbol-named functions outside COMMON-LISP are supported; macros, special operators and generic functions are
rejected before changing state. Generic function replacement would break subsequent defmethod.
Compile explainers on installation and capture the contract's predicate functions. Reinstall
refreshes checks and scopes without stacking wrappers. Uninstrument restores only if the current
fdefinition is the installed wrapper; redefinitions or fmakunbound are never overwritten.
`instrumented-function-p` tests actual wrapper identity and removes stale entries.
Replaced definitions must be queried or uninstrumented to release their stored entry;
there is no portable redefinition notification hook.
Named references follow the existing explainer compilation semantics. Named references resolve against the captured registry on every call. Reinstall after
contract edits to refresh the directly captured checks. Already captured function objects and inlined or
lexical calls cannot be intercepted. Installation/removal must be serialized by callers with
function redefinition; no portable atomic fdefinition compare-and-swap is available.

Metadata obtains instrumentation availability from a core generic with default `:unavailable`;
the optional module supplies the function-spec method. Availability denotes a supported target,
not active state; `instrumented-function-p` reports active state. No generator is needed.
Uncaptured result capabilities are unknown. Undefined targets use unbound-target; other
unsupported definitions use unsupported-instrumentation-target with name and reason.

Tests cover scope isolation, pre/arity rejection before side effects, one target invocation,
structured failures, all returned values, original target conditions, repeated installation,
redefinition/unbinding, registry selection, invalid requests and capability boundaries.
