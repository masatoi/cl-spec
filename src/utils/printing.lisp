;;;; src/utils/printing.lisp

(defpackage #:cl-spec/src/utils/printing
  (:use #:cl)
  (:export #:with-bounded-printing
           #:condition-report-text))

(in-package #:cl-spec/src/utils/printing)

(defmacro with-bounded-printing ((&key one-line) &body body)
  "Run BODY with printer settings under which printing any value terminates.

BODY usually prints a value that failed a spec, and such a value may be circular
or nested deeper than the printer's stack.  *PRINT-CIRCLE* is bound to T, so a
cycle is printed with #N= labels instead of without end, and *PRINT-LENGTH* and
*PRINT-LEVEL* keep a limit the caller already set but replace an unlimited NIL
with 20 elements and 8 levels.

With ONE-LINE true *PRINT-PRETTY* is also bound to NIL.  A condition report
prints its data in the middle of a sentence, where the pretty printer would break
a long list into one element per line at the column the sentence has reached."
  `(let ((*print-circle* t)
         (*print-length* (or *print-length* 20))
         (*print-level* (or *print-level* 8))
         ,@(when one-line '((*print-pretty* nil))))
     ,@body))

(defun condition-report-text (condition)
  "Render CONDITION as text without losing evidence to a broken condition printer.

The report is printed under WITH-BOUNDED-PRINTING, because a condition caught
while checking a value usually prints that value, which may be circular or very
large.  A report that itself signals is replaced by the condition's type, so a
printer the user supplied can neither stop nor unwind the caller.  NIL renders
as NIL."
  (when condition
    (handler-case
        (with-bounded-printing ()
          (princ-to-string condition))
      (error () (format nil "~S (condition report unavailable)" (type-of condition))))))
