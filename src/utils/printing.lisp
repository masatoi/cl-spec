;;;; src/utils/printing.lisp

(defpackage #:cl-spec/src/utils/printing
  (:use #:cl)
  (:export #:with-bounded-printing))

(in-package #:cl-spec/src/utils/printing)

(defmacro with-bounded-printing (() &body body)
  "Run BODY with printer settings under which printing any value terminates.

BODY usually prints a value that failed a spec, and such a value may be circular
or nested deeper than the printer's stack.  *PRINT-CIRCLE* is bound to T, so a
cycle is printed with #N= labels instead of without end, and *PRINT-LENGTH* and
*PRINT-LEVEL* keep a limit the caller already set but replace an unlimited NIL
with 20 elements and 8 levels."
  `(let ((*print-circle* t)
         (*print-length* (or *print-length* 20))
         (*print-level* (or *print-level* 8)))
     ,@body))
