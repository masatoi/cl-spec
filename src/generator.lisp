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
                #:no-generator-backend)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:*generator-backend*
           #:current-generator-backend
           #:compile-generator
           #:generate-value
           #:run-generated-test
           #:generator-for
           #:sample
           #:backend-default-trials))

(in-package #:cl-spec/src/generator)

(defvar *generator-backend* nil
  "The generator backend in effect, or NIL when none is installed.

Loading the CL-SPEC/CHECK-IT system installs a CHECK-IT-BACKEND here.  Rebind
it to swap backends for a dynamic extent, for example in tests.

A rebinding does not cross a thread boundary.  §48 puts the time limit on the
execution host, so a host that runs checks off the calling thread has to carry
this value over itself -- PROGV, or an explicit argument.  Without that, a run
started on another thread reads the global value, and if a backend is installed
there it generates rather than reporting NO-GENERATOR-BACKEND.")

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

(defgeneric backend-default-trials (backend)
  (:documentation "Return the trial count BACKEND uses when a property names none.

The core cannot read check-it's own default, so the backend answers for it."))

(defun generator-for (spec-designator &key context options (registry *registry*))
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
The result is opaque to everything but the backend and GENERATE-VALUE."
  (let ((spec (resolve-spec spec-designator registry)))
    (compile-generator (current-generator-backend) spec
                       :context (or context (list :registry registry))
                       :options options)))

(defun sample (spec-designator &key (count 10) seed (registry *registry*))
  "Return a list of COUNT values generated from SPEC-DESIGNATOR.

SEED, when supplied, makes the whole sequence reproducible.  Intended for
inspecting what a spec admits, from the REPL or from an agent."
  (let ((backend (current-generator-backend))
        (generator (generator-for spec-designator :registry registry)))
    (flet ((draw ()
             (loop repeat count collect (generate-value backend generator))))
      (if seed
          (let ((*random-state* (seed->random-state seed)))
            (draw))
          (draw)))))
