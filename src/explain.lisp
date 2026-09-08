;;;; src/explain.lisp
;;;;
;;;; Structured explanation (specification §22).  The structured plist is the
;;;; primary representation; the human readable rendering, the condition report
;;;; and any JSON/MCP projection are all derived from it.

(defpackage #:cl-spec/src/explain
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:compile-explainer
           #:explain-data
           #:explain))

(in-package #:cl-spec/src/explain)

(declaim (ftype (function (spec &key (:context t)) function) compile-explainer))

(defun compile-explainer (spec &key context)
  "Compile SPEC into a function of one argument returning structured explain data.

CONTEXT carries compilation options such as the registry to resolve references
against.  The returned function always produces a plist, whether or not the
value is valid.

Not implemented yet."
  (declare (ignore spec context))
  (error 'not-implemented :operator 'compile-explainer))

(defun explain-data (spec-designator value)
  "Return a plist describing whether VALUE satisfies SPEC-DESIGNATOR and why not.

The plist has the shape

  (:valid <boolean> :spec <symbol> :value <value> :path <list>
   :errors ((:kind <keyword> :predicate <symbol>
             :expected <form> :actual <value>) ...))

and is the representation every other explanation surface is derived from.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'explain-data))

(defun explain (spec-designator value &optional (stream *standard-output*))
  "Print a human readable rendering of (EXPLAIN-DATA SPEC-DESIGNATOR VALUE).

Writes to STREAM and returns NIL.  This is a projection of EXPLAIN-DATA and
must not compute anything EXPLAIN-DATA does not already report.

Not implemented yet."
  (declare (ignore spec-designator value stream))
  (error 'not-implemented :operator 'explain))
