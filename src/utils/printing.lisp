;;;; src/utils/printing.lisp

(defpackage #:cl-spec/src/utils/printing
  (:use #:cl)
  (:export #:with-bounded-printing
           #:abbreviate-for-print
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

(defconstant +printed-string-limit+ 1000
  "The longest string ABBREVIATE-FOR-PRINT leaves to be printed in full.")

(defconstant +printed-integer-bits+ 4096
  "The widest integer, in bits, ABBREVIATE-FOR-PRINT leaves to be printed in full.

Printing an integer in decimal costs more than linear time in its size, so a
value of millions of bits takes seconds per copy printed, not only space.")

(defconstant +report-text-limit+ 10000
  "The most characters CONDITION-REPORT-TEXT keeps of one condition's report.")

(defstruct (abbreviation (:constructor make-abbreviation (text)))
  "Stands in for a value too large to print, and prints as TEXT."
  (text "" :type string))

(defmethod print-object ((object abbreviation) stream)
  (write-string (abbreviation-text object) stream))

(defun abbreviate-atom (object)
  "Return an ABBREVIATION for a string or integer too large to print, or NIL."
  (cond ((and (stringp object) (> (length object) +printed-string-limit+))
         (make-abbreviation
          (format nil "#<STRING of ~D characters starting ~S>"
                  (length object) (subseq object 0 (min 80 (length object))))))
        ((and (integerp object) (> (integer-length object) +printed-integer-bits+))
         (make-abbreviation
          (format nil "#<INTEGER of ~D bits>" (integer-length object))))))

(defun abbreviate-for-print (value)
  "Return VALUE, or a copy of the part of it the printer will show, made printable
in bounded time and space.

*PRINT-LENGTH* and *PRINT-LEVEL* bound how much of a list or a vector is printed,
but a string or an integer is printed whole however large it is.  Within the part
the current limits will print, every string longer than +PRINTED-STRING-LIMIT+ and
every integer wider than +PRINTED-INTEGER-BITS+ is replaced by an abbreviation
naming its size.  Lists and general vectors are copied only that far, so the copy
is bounded by the limits whatever VALUE's size, and shared and circular structure
is kept, so *PRINT-CIRCLE* still labels it.  A value with nothing to abbreviate is
returned as it is.  Call it within WITH-BOUNDED-PRINTING, which sets the limits."
  (let ((copies (make-hash-table :test #'eq))
        (length-limit *print-length*)
        (level-limit *print-level*)
        (changed nil))
    (labels ((walk (object depth)
               (let ((abbreviation (abbreviate-atom object)))
                 (cond
                   (abbreviation (setf changed t) abbreviation)
                   ((not (or (consp object) (general-vector-p object))) object)
                   ((gethash object copies))
                   ((and level-limit (>= depth level-limit))
                    ;; Printed as # whatever it holds.
                    object)
                   ((consp object) (copy-spine object depth))
                   (t (copy-vector object depth)))))
             (general-vector-p (object)
               (and (vectorp object)
                    (not (stringp object))
                    (eq (array-element-type object) t)))
             (copy-spine (list depth)
               (let* ((head (cons nil nil))
                      (cell head)
                      (source list))
                 (setf (gethash list copies) head)
                 (loop for index from 0
                       do (setf (car cell) (walk (car source) (1+ depth)))
                          (let ((next (cdr source)))
                            (cond
                              ((and length-limit (>= (1+ index) length-limit) (consp next))
                               ;; Printed as ... whatever follows.
                               (setf (cdr cell) next)
                               (return))
                              ((atom next)
                               (setf (cdr cell) (walk next (1+ depth)))
                               (return))
                              ((gethash next copies)
                               (setf (cdr cell) (gethash next copies))
                               (return))
                              (t
                               (let ((new (cons nil nil)))
                                 (setf (gethash next copies) new
                                       (cdr cell) new
                                       cell new
                                       source next))))))
                 head))
             (copy-vector (vector depth)
               ;; One element past the limit is kept so the printer still ends
               ;; the copy with ..., and nothing further is copied.
               (let* ((shown (if length-limit
                                 (min (length vector) length-limit)
                                 (length vector)))
                      (copy (make-array (min (length vector) (1+ shown)))))
                 (setf (gethash vector copies) copy)
                 (dotimes (index (length copy) copy)
                   (setf (aref copy index)
                         (if (< index shown)
                             (walk (aref vector index) (1+ depth))
                             (aref vector index)))))))
      (let ((result (walk value 0)))
        (if changed result value)))))

(defun truncate-text (text limit)
  "Return TEXT, cut to LIMIT characters with a note of how many were dropped."
  (if (<= (length text) limit)
      text
      (format nil "~A... [~D more characters]"
              (subseq text 0 limit) (- (length text) limit))))

(defun condition-report-text (condition)
  "Render CONDITION as text without losing evidence to a broken condition printer.

The report is printed under WITH-BOUNDED-PRINTING, because a condition caught
while checking a value usually prints that value, which may be circular or very
large.  A report that itself signals is replaced by the condition's type, so a
printer the user supplied can neither stop nor unwind the caller.  The printer's
limits do not bound a string a report quotes, so the text is also cut to
+REPORT-TEXT-LIMIT+ characters.  NIL renders as NIL."
  (when condition
    (handler-case
        (truncate-text (with-bounded-printing ()
                         (princ-to-string condition))
                       +report-text-limit+)
      (error () (format nil "~S (condition report unavailable)" (type-of condition))))))
