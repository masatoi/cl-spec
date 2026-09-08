;;;; src/generator.lisp
;;;;
;;;; Generator backend protocol (specification §10, §12).  Neither the IR nor
;;;; the property runner may depend on a concrete generation engine, so the
;;;; engine is installed at load time into *GENERATOR-BACKEND* by a separate
;;;; system (CL-SPEC/CHECK-IT).  Adding an exhaustive, fuzzing or SMT backend
;;;; later means adding methods, not editing this file.

(defpackage #:cl-spec/src/generator
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:no-generator-backend)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:*generator-backend*
           #:current-generator-backend
           #:compile-generator
           #:generate-value
           #:run-generated-test
           #:generator-for
           #:sample))

(in-package #:cl-spec/src/generator)

(defvar *generator-backend* nil
  "The generator backend in effect, or NIL when none is installed.

Loading the CL-SPEC/CHECK-IT system installs a CHECK-IT-BACKEND here.  Rebind
it to swap backends for a dynamic extent, for example in tests.")

(defun current-generator-backend ()
  "Return *GENERATOR-BACKEND*, signalling NO-GENERATOR-BACKEND when it is NIL."
  (or *generator-backend*
      (error 'no-generator-backend)))

(defgeneric compile-generator (backend spec &key context options)
  (:documentation "Compile SPEC into a BACKEND-specific generator object.

CONTEXT carries resolution state such as the registry; OPTIONS carries
generation parameters such as size limits.  The returned object is opaque to
everything except BACKEND and GENERATE-VALUE."))

(defgeneric generate-value (backend compiled-generator &key seed)
  (:documentation "Produce one value from COMPILED-GENERATOR using BACKEND.

SEED, when supplied, makes the value reproducible (specification §15)."))

(defgeneric run-generated-test (backend property &key options)
  (:documentation "Run PROPERTY on BACKEND and return a PROPERTY-RESULT.

The backend owns trial generation, failure detection and shrinking; the caller
owns interpretation of the result."))

(defun generator-for (spec-designator &key context options)
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.

Not implemented yet."
  (declare (ignore spec-designator context options))
  (error 'not-implemented :operator 'generator-for))

(defun sample (spec-designator &key (count 10) seed)
  "Return a list of COUNT values generated from SPEC-DESIGNATOR.

SEED, when supplied, makes the sequence reproducible.  Intended for inspecting
what a spec admits, from the REPL or from an LLM agent.

Not implemented yet."
  (declare (ignore spec-designator count seed))
  (error 'not-implemented :operator 'sample))
