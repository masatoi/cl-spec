;;;; src/dsl.lisp
;;;;
;;;; Surface macros (specification §37).  The macros are syntax sugar only:
;;;; they capture the source form and location and hand everything else to the
;;;; normalizer and the registry.  Keeping them thin is what lets the DSL
;;;; change without disturbing the Semantic IR or the introspection API.
;;;;
;;;; Each macro expands successfully even while the normalizer is a stub, so a
;;;; file using the DSL still compiles; the NOT-IMPLEMENTED condition is
;;;; signalled when the expansion runs.

(defpackage #:cl-spec/src/dsl
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:register-spec)
  (:import-from #:cl-spec/src/property
                #:register-property)
  (:import-from #:cl-spec/src/function-spec
                #:register-function-spec)
  (:import-from #:cl-spec/src/utils/source-location
                #:current-source-location)
  (:export #:defspec
           #:defspec-function
           #:defproperty
           #:defgenerator))

(in-package #:cl-spec/src/dsl)

(defmacro defspec (name form)
  "Define a spec named NAME from spec DSL FORM.

FORM is normalized into a Semantic IR object and registered in *REGISTRY*.
The original form and the definition site are kept on the resulting spec.

  (defspec positive-integer
    (and integer (range 1 *)))"
  (let ((location (current-source-location)))
    `(register-spec ',name
                    (normalize-spec-form ',form
                                         :name ',name
                                         :source-location ',location))))

(defun expand-function-spec-definition (name clauses source-location)
  "Build a FUNCTION-SPEC from the CLAUSES of a DEFSPEC-FUNCTION form.

CLAUSES are the :ARGS, :RETURNS, :PRE and :POST clauses as written.

Not implemented yet."
  (declare (ignore name clauses source-location))
  (error 'not-implemented :operator 'defspec-function))

(defmacro defspec-function (name &body clauses)
  "Attach a contract to the existing function NAME without redefining it.

  (defspec-function transfer
    (:args (from account) (to account) (amount positive-money))
    (:returns transaction))"
  (let ((location (current-source-location)))
    `(register-function-spec
      (expand-function-spec-definition ',name ',clauses ',location))))

(defun expand-property-definition (name arguments body source-location)
  "Build a PROPERTY from the parts of a DEFPROPERTY form.

ARGUMENTS is the list of (VARIABLE SPEC-DESIGNATOR) bindings; BODY is the
option clauses such as (:ABOUT ...) followed by the predicate forms.

Not implemented yet."
  (declare (ignore name arguments body source-location))
  (error 'not-implemented :operator 'defproperty))

(defmacro defproperty (name arguments &body body)
  "Define a property named NAME over generated ARGUMENTS.

BODY starts with option clauses such as (:ABOUT ...), (:KIND ...) and
(:TAGS ...), followed by the forms of the property predicate.  A NIL result or
a signalled condition counts as a failure.

  (defproperty addition-preserves-order
      ((x positive-integer) (y positive-integer))
    (:about +)
    (:kind :monotonicity)
    (> (+ x y) x))"
  (let ((location (current-source-location)))
    `(register-property
      (expand-property-definition ',name ',arguments ',body ',location))))

(defun expand-generator-definition (name lambda-list body source-location)
  "Register a user-defined generator built from a DEFGENERATOR form.

Not implemented yet."
  (declare (ignore name lambda-list body source-location))
  (error 'not-implemented :operator 'defgenerator))

(defmacro defgenerator (name lambda-list &body body)
  "Define a custom generator named NAME (specification §11).

Use this when a spec cannot express how values should be produced, for example
when generation must satisfy a global invariant.

  (defgenerator small-integer ()
    (random 100))"
  (let ((location (current-source-location)))
    `(expand-generator-definition ',name ',lambda-list ',body ',location)))
