;;;; src/check-summary.lisp

(defpackage #:cl-spec/src/check-summary
  (:use #:cl)
  (:import-from #:cl-spec/src/evidence #:evidence-summary #:assess-evidence)
  (:export #:format-check-summary))

(in-package #:cl-spec/src/check-summary)

(defun single-line-name (symbol)
  "Render a saved name without allowing a control character to split the report."
  (substitute-if #\Space
                 (lambda (char)
                   (let ((code (char-code char)))
                     (or (< code 32) (member code '(127 133 8232 8233)))))
                 (symbol-name symbol)))

(defun write-finding (stream finding)
  "Write one observed gap or missing measurement from the evidence protocol."
  (let ((case (getf finding :case))
        (kind (getf finding :kind)))
    (when case
      (format stream "case ~A " (single-line-name case)))
    (case kind
      (:case-never-called (write-string "never called" stream))
      (:no-checked-trials (write-string "checked 0" stream))
      (:measurement-not-collected
       (format stream "~A unknown"
               (if case "checked" (string-downcase (getf finding :dimension)))))
      ((:case-checks-below-minimum :checked-trials-below-minimum :requested-trials-not-completed)
       (format stream "~A ~D of ~D"
               (if (eq kind :requested-trials-not-completed) "trials completed" "checked")
               (getf finding :observed) (getf finding :required))))))

(defun format-check-summary (result &key (policy nil policy-p) stream)
  "Return one line describing RESULT's saved execution status and evidence.

With POLICY, report the explicit assessment, observed shortfalls and missing
measurements. Omitting POLICY shows unassessed evidence and any observed gaps.
Accepts the generated and direct results supported by EVIDENCE-SUMMARY.
With an output STREAM, write the line and a newline and return NIL.
T selects standard output. Formatting never reruns the check."
  (let* ((data (if policy-p (assess-evidence result policy) (evidence-summary result)))
         (name (getf (getf data :subject) :name))
         (line (with-output-to-string (out)
                 (when name
                   (format out "~A " (single-line-name name)))
                 (format out "~A | evidence ~A"
                         (string-downcase (or (getf data :execution-status) :unknown))
                         (string-downcase (getf data :assessment)))
                 (when (eq :no-applicable-requirements (getf data :reason))
                   (write-string " | no applicable requirements" out))
                 (dolist (findings (list (getf data :gaps) (getf data :unknowns)))
                   (dolist (finding findings)
                     (write-string " | " out)
                     (write-finding out finding))))))
    (if stream
        (progn (write-line line (if (eq stream t) *standard-output* stream)) nil)
        line)))
