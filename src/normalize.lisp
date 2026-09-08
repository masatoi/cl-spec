;;;; src/normalize.lisp
;;;;
;;;; Spec DSL -> Semantic IR (specification §9, §37).  The macros in
;;;; SRC/DSL.LISP are pure syntax sugar; all meaning is assigned here, so the
;;;; DSL can change without disturbing the IR or the introspection API.

(defpackage #:cl-spec/src/normalize
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:normalize-spec-form
           #:*spec-primitives*))

(in-package #:cl-spec/src/normalize)

(defparameter *spec-primitives*
  '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
    "LIST-OF" "VECTOR-OF" "CONS-OF" "TUPLE" "NULLABLE"
    "INSTANCE-OF")
  "Spec DSL head names the MVP normalizer accepts (specification §9, §52).

Heads are matched by SYMBOL-NAME, not by symbol identity: a DSL form is written
in the user's own package, so RANGE in (RANGE 1 *) there is not EQ to the RANGE
interned here.  Anything not named in this list is either a reference to a
registered spec or an error.")

(declaim (ftype (function (t &key (:name symbol) (:source-location list)) spec)
                normalize-spec-form))

(defun normalize-spec-form (form &key name source-location)
  "Normalize spec DSL FORM into a Semantic IR object.

NAME is the symbol the resulting spec will be registered under, or NIL for an
anonymous inline spec.  SOURCE-LOCATION is a plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION.

The returned spec keeps FORM verbatim in its SPEC-SOURCE-FORM slot.

Not implemented yet."
  (declare (ignore form name source-location))
  (error 'not-implemented :operator 'normalize-spec-form))
