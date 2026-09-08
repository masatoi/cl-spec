;;;; src/validator.lisp
;;;;
;;;; Validator compiler and the value-checking entry points (specification
;;;; §9.1, §20).  The public architecture is a compiler rather than a recursive
;;;; interpreter so that validation artifacts can be cached and specialised per
;;;; backend, even though the first implementation may simply interpret.

(defpackage #:cl-spec/src/validator
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:compile-validator
           #:validp
           #:validate))

(in-package #:cl-spec/src/validator)

(declaim (ftype (function (spec &key (:context t)) function) compile-validator))

(defun compile-validator (spec &key context)
  "Compile SPEC into a function of one argument returning a generalized boolean.

CONTEXT carries compilation options such as the registry to resolve references
against.  The returned function performs no explanation; use COMPILE-EXPLAINER
when structured failure data is needed.

Not implemented yet."
  (declare (ignore spec context))
  (error 'not-implemented :operator 'compile-validator))

(defun validp (spec-designator value)
  "Return true when VALUE satisfies the spec named by SPEC-DESIGNATOR.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
Signals UNKNOWN-SPEC when a symbol resolves to nothing.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'validp))

(defun validate (spec-designator value)
  "Return VALUE when it satisfies SPEC-DESIGNATOR, otherwise signal SPEC-VIOLATION.

The signalled condition carries the structured error list produced by
EXPLAIN-DATA so that callers do not have to re-run the check.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'validate))
