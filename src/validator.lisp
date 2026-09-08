;;;; src/validator.lisp
;;;;
;;;; Validator compiler and the value-checking entry points (specification
;;;; §9.1, §20).  The public architecture is a compiler rather than a recursive
;;;; interpreter so that validation artifacts can be cached and specialised per
;;;; backend, even though the first implementation may simply interpret.

(defpackage #:cl-spec/src/validator
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:spec-display-name)
  (:export #:compile-validator
           #:validp
           #:validate))

(in-package #:cl-spec/src/validator)

(declaim (ftype (function (spec &key (:context t)) function) compile-validator))

(defun compile-validator (spec &key context)
  "Compile SPEC into a function of one argument returning a generalized boolean.

CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The validator is a thin wrapper over the explainer so that the two can never
disagree about whether a value is admissible."
  (let ((explainer (compile-explainer spec :context context)))
    (lambda (value)
      (null (funcall explainer value nil)))))

(defun validp (spec-designator value &key (registry *registry*))
  "Return true when VALUE satisfies the spec named by SPEC-DESIGNATOR.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
Signals UNKNOWN-SPEC when a symbol resolves to nothing."
  (let ((spec (resolve-spec spec-designator registry)))
    (null (funcall (compile-explainer spec :context (list :registry registry))
                   value nil))))

(defun validate (spec-designator value &key (registry *registry*))
  "Return VALUE when it satisfies SPEC-DESIGNATOR, otherwise signal SPEC-VIOLATION.

The signalled condition carries the structured error list produced by
EXPLAIN-DATA so that callers do not have to re-run the check."
  (let* ((spec (resolve-spec spec-designator registry))
         (errors (funcall (compile-explainer spec :context (list :registry registry))
                          value nil)))
    (when errors
      (error 'spec-violation
             :spec (spec-display-name spec-designator spec)
             :value value
             :path (getf (first errors) :path)
             :errors errors))
    value))
