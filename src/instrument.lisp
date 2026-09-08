;;;; src/instrument.lisp
;;;;
;;;; Runtime contract checking (specification §20).  Instrumentation replaces a
;;;; function's definition with a wrapper that validates arguments and return
;;;; value against its registered function spec.  It is a separate system
;;;; because production images should be able to load cl-spec without gaining
;;;; the ability to rewrite fdefinitions.

(defpackage #:cl-spec/src/instrument
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/validator
                #:validate)
  (:export #:*instrumented-functions*
           #:instrumented-function-p
           #:instrument-function
           #:uninstrument-function))

(in-package #:cl-spec/src/instrument)

(defvar *instrumented-functions* (make-hash-table :test #'eq)
  "Symbol -> the original function object, for every instrumented function.

UNINSTRUMENT-FUNCTION restores from this table, so an entry here is the single
source of truth for whether a function is currently wrapped.")

(defun instrumented-function-p (name)
  "Return true when NAME currently has an instrumentation wrapper installed."
  (nth-value 1 (gethash name *instrumented-functions*)))

(defun instrument-function (name &optional (registry *registry*))
  "Wrap NAME so that each call validates arguments and result against its
registered function spec in REGISTRY.

Signals UNKNOWN-SPEC when no function spec is registered for NAME.  A violation
signals SPEC-VIOLATION from inside the wrapper, so the caller sees the failure
at the call site rather than downstream.

Not implemented yet."
  (declare (ignore name registry))
  (error 'not-implemented :operator 'instrument-function))

(defun uninstrument-function (name)
  "Restore the original definition of NAME and forget its wrapper.

Returns true when a wrapper was removed, NIL when NAME was not instrumented.

Not implemented yet."
  (declare (ignore name))
  (error 'not-implemented :operator 'uninstrument-function))
