;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
  (:import-from #:check-it
                #:*num-trials*
                #:generate
                #:*size*)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/backends/check-it-generators
                #:compile-spec-generator)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:backend-default-trials)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:check-it-backend
           #:install-check-it-backend
           #:default-trials))

(in-package #:cl-spec/src/backends/check-it)

(defclass check-it-backend ()
  ()
  (:documentation "Generator backend delegating to the check-it library."))

(defun default-trials ()
  "Return check-it's current default number of trials per property run."
  *num-trials*)

(defstruct (compiled-generator (:constructor make-compiled-generator (generator size)))
  "A check-it generator together with the CHECK-IT:*SIZE* its bounds require.

Pairing the two is what stops check-it from clamping a range away: *SIZE* has to
be raised around GENERATE, and only the compiler knows how far."
  (generator nil :read-only t)
  (size 0 :read-only t))

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator paired with the size its bounds need.

OPTIONS is accepted for protocol compatibility; check-it takes its sizing from
its own specials rather than per-generator options."
  (declare (ignore backend options))
  (multiple-value-bind (generator size) (compile-spec-generator spec context)
    (make-compiled-generator generator size)))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally from a seeded state."
  (declare (ignore backend))
  (flet ((draw ()
           (let ((*size* (max *size* (compiled-generator-size compiled-generator))))
             (generate (compiled-generator-generator compiled-generator)))))
    (if seed
        (let ((*random-state* (seed->random-state seed)))
          (draw))
        (draw))))

(defmethod backend-default-trials ((backend check-it-backend))
  "Return check-it's current default number of trials."
  (declare (ignore backend))
  *num-trials*)

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Run PROPERTY through check-it, shrinking any counterexample.

Not implemented yet."
  (declare (ignore backend property options))
  (error 'not-implemented :operator 'run-generated-test))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
