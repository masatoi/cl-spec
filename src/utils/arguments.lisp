;;;; src/utils/arguments.lisp

(defpackage #:cl-spec/src/utils/arguments
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:check-argument
           #:check-keyword-arguments
           #:run-options-p
           #:check-run-options))

(in-package #:cl-spec/src/utils/arguments)

(defun check-argument (value type operator argument)
  "Return VALUE when it is of TYPE, otherwise signal INVALID-ARGUMENT.

OPERATOR names the public function being called and ARGUMENT the parameter
VALUE was passed as, so the refusal says which one was wrong."
  (if (typep value type)
      value
      (error 'invalid-argument :datum value :expected-type type
                               :operator operator :argument argument)))

(defun check-keyword-arguments (arguments allowed operator)
  "Return ARGUMENTS after refusing any keyword in it that is not in ALLOWED.

ARGUMENTS is the keyword tail an entry point received through &REST; the entry
point declares &ALLOW-OTHER-KEYS so that a misspelt keyword reaches this check
rather than failing in the Lisp's own argument parsing with a condition outside
CL-SPEC-ERROR (issue #79).  :ALLOW-OTHER-KEYS itself is accepted, as Common Lisp
accepts it for every function with keyword parameters."
  (loop for (key) on arguments by #'cddr
        unless (or (member key allowed) (eq key :allow-other-keys))
          do (error 'invalid-argument
                    :operator operator :argument key :datum key
                    :expected-type `(member ,@allowed)
                    :reason "it is not a keyword argument of this operator"))
  arguments)

(defparameter +runner-owned-options+ '(:trials :registry)
  "Keys a runner sets itself on the options it hands its backend.

A caller's value for one of them was silently replaced, so it is refused instead.")

(defun run-options-p (options)
  "Recognize runner options: a finite plist of keyword keys the runner does not own.

Keys other than the runner-owned :TRIALS and :REGISTRY are allowed, because a
backend may read options of its own and a result records every option it ran
with."
  (and (finite-list-p options)
       (evenp (length options))
       (loop for (key) on options by #'cddr
             always (and (keywordp key) (not (member key +runner-owned-options+))))))

(defun check-run-options (options operator)
  "Return OPTIONS after refusing a malformed runner options plist for OPERATOR.

The plist shape is checked as :OPTIONS; :GENERATION-BUDGET must be a
non-negative integer and :SHRINK-BUDGET an integer from 0 to 100000, each
refused under its own name.  Checking at the public entry point names the
operator the caller called rather than the internal one that would otherwise
fail first (issue #79)."
  (check-argument options '(or null (satisfies run-options-p)) operator :options)
  (let ((generation-budget (getf options :generation-budget :absent))
        (shrink-budget (getf options :shrink-budget :absent)))
    (unless (eq generation-budget :absent)
      (check-argument generation-budget '(integer 0 *) operator :generation-budget))
    (unless (eq shrink-budget :absent)
      (check-argument shrink-budget '(integer 0 100000) operator :shrink-budget)))
  options)
