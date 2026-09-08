;;;; src/introspection.lisp
;;;;
;;;; Introspection API (specification §38).  Structured data is the primary
;;;; representation and the DESCRIBE-* functions are projections of it, because
;;;; the intended first-class consumer is a coding agent rather than a human
;;;; reading a REPL transcript.

(defpackage #:cl-spec/src/introspection
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:export #:describe-spec
           #:describe-property
           #:spec-data
           #:property-data))

(in-package #:cl-spec/src/introspection)

(defun spec-data (spec-designator &optional (registry *registry*))
  "Return a plist describing the registered spec named by SPEC-DESIGNATOR.

The plist has the shape

  (:name <symbol> :kind <keyword> :source-form <form>
   :children (<nested plist> ...))

and is what SPEC-DATA's JSON and MCP projections are built from.

Not implemented yet."
  (declare (ignore spec-designator registry))
  (error 'not-implemented :operator 'spec-data))

(defun property-data (property-designator &optional (registry *registry*))
  "Return a plist describing the registered property named by
PROPERTY-DESIGNATOR: its name, targets, kind, argument specs, tags,
documentation, source form, source location and trial configuration.

Not implemented yet."
  (declare (ignore property-designator registry))
  (error 'not-implemented :operator 'property-data))

(defun describe-spec (spec-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (SPEC-DATA SPEC-DESIGNATOR) to STREAM.

Returns NIL.  This is a projection of SPEC-DATA and must not report anything
SPEC-DATA does not already carry.

Not implemented yet."
  (declare (ignore spec-designator stream))
  (error 'not-implemented :operator 'describe-spec))

(defun describe-property (property-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (PROPERTY-DATA PROPERTY-DESIGNATOR) to
STREAM.  Returns NIL.

Not implemented yet."
  (declare (ignore property-designator stream))
  (error 'not-implemented :operator 'describe-property))
