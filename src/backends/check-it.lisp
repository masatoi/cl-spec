;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
  (:import-from #:check-it
                #:*num-trials*)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:compile-generator
                #:generate-value
                #:run-generated-test)
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

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator.

Not implemented yet."
  (declare (ignore backend spec context options))
  (error 'not-implemented :operator 'compile-generator))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally seeded.

Not implemented yet."
  (declare (ignore backend compiled-generator seed))
  (error 'not-implemented :operator 'generate-value))

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
