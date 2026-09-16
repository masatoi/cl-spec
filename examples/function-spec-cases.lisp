;;;; examples/function-spec-cases.lisp
;;;;
;;;; Executable integration example for named per-condition Function Spec cases
;;;; (specification §17.2).  The walkthrough lives in
;;;; docs/guides/function-spec-cases-walkthrough.md.
;;;;
;;;; Loading this file defines a condition, some pure functions and one special
;;;; only.  It does not register a contract, draw a value or run a demo, so it
;;;; never changes the caller's *REGISTRY*.  Call REGISTER-EXAMPLE! to register
;;;; the example's contracts in a dedicated registry, and the DEMO-* entry
;;;; points to run the walkthrough.  The input sequences are controlled through
;;;; a scripted argument generator, so a demo never depends on what a seed
;;;; happens to draw.

(defpackage #:cl-spec/examples/function-spec-cases
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry*
                #:make-hash-table-registry
                #:defgenerator #:defspec-function #:check-function
                #:function-check-result-case-report
                #:function-check-result-failure-reason
                #:function-check-result-explanation
                #:property-result-status #:property-result-failure-phase
                #:property-result-failure-evidence
                #:trial-observation-case #:trial-observation-signature)
  ;; This example is an ASDF package-inferred subsystem, so this bare
  ;; :IMPORT-FROM declares its check-it generator backend dependency without
  ;; importing a symbol.  See examples/structured-data.lisp for the same note.
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:insufficient-funds #:insufficient-funds-balance #:insufficient-funds-amount
           #:make-example-registry #:register-example!
           #:remaining-balance #:broken-remaining-balance
           #:overlapping-balance #:gapped-balance
           #:demo-both-outcomes #:demo-wrong-implementation
           #:demo-selection-errors #:demo-unchecked-cases))

(in-package #:cl-spec/examples/function-spec-cases)

(define-condition insufficient-funds (error)
  ((balance :initarg :balance :reader insufficient-funds-balance)
   (amount :initarg :amount :reader insufficient-funds-amount))
  (:report (lambda (condition stream)
             (format stream "Cannot withdraw ~D from ~D."
                     (insufficient-funds-amount condition)
                     (insufficient-funds-balance condition))))
  (:documentation "The expected error of the example's withdrawal contract."))

(defvar *target-calls* 0
  "Target invocations of the currently running demo, for reporting and testing.")

(defvar *example-inputs* nil
  "The argument lists the scripted generator returns, front to back.

A special rather than a closure so a demo can state its inputs in one place and
the contract can name one registered generator.")

(defun remaining-balance (balance amount)
  "Return what is left, or signal INSUFFICIENT-FUNDS.  Pure; no state changes."
  (incf *target-calls*)
  (if (<= amount balance)
      (- balance amount)
      (error 'insufficient-funds :balance balance :amount amount)))

(defun broken-remaining-balance (balance amount)
  "A deliberately wrong target: it answers 0 instead of signalling."
  (incf *target-calls*)
  (if (<= amount balance)
      (- balance amount)
      0))

(defun overlapping-balance (balance amount)
  "A target whose contract's two conditions overlap when the amounts are equal."
  (incf *target-calls*)
  (- balance amount))

(defun gapped-balance (balance amount)
  "A target whose contract's two conditions leave the equal amounts uncovered."
  (incf *target-calls*)
  (- balance amount))

(defun make-example-registry ()
  "Return a fresh registry for this example.  Nothing is registered yet."
  (make-hash-table-registry))

(defun register-example! (&optional (registry (make-example-registry)))
  "Register the example's generator and contracts in REGISTRY and return it.

The caller's *REGISTRY* is neither read nor written."
  (let ((*registry* registry))
    (defgenerator scripted-arguments ()
      "Return the next scripted argument list, so a demo controls its inputs."
      (pop *example-inputs*))
    (defspec-function remaining-balance
      "Require the remainder when the balance suffices, and the named error when it does not."
      (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
      (:args-generator scripted-arguments)
      (:cases
        (:sufficient-funds
          "The amount fits: return the remaining balance."
          (:when (<= amount balance))
          (:returns (range integer 0 *))
          (:post (= result (- balance amount))))
        (:insufficient-funds
          "The amount does not fit: signal the named error."
          (:when (> amount balance))
          (:signals (type insufficient-funds)))))
    (defspec-function broken-remaining-balance
      "The same two conditions, attached to the deliberately wrong target."
      (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
      (:args-generator scripted-arguments)
      (:cases
        (:sufficient-funds
          (:when (<= amount balance))
          (:returns (range integer 0 *)))
        (:insufficient-funds
          (:when (> amount balance))
          (:signals (type insufficient-funds)))))
    (defspec-function overlapping-balance
      "Two conditions that both hold when the amounts are equal."
      (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
      (:args-generator scripted-arguments)
      (:cases
        (:at-least (:when (>= balance amount)) (:returns (range integer 0 *)))
        (:at-most (:when (<= balance amount)) (:returns (range integer 0 *)))))
    (defspec-function gapped-balance
      "Two conditions that leave the equal amounts uncovered."
      (:args (balance (range integer 0 1000)) (amount (range integer 1 1000)))
      (:args-generator scripted-arguments)
      (:cases
        (:surplus (:when (> balance amount)) (:returns (range integer * -1)))
        (:deficit (:when (< balance amount)) (:returns (range integer * -1)))))
    registry))

(defun summarize-run (result)
  "Project RESULT as the data the walkthrough reads."
  (let ((evidence (property-result-failure-evidence result))
        (report (function-check-result-case-report result)))
    (list :status (property-result-status result)
          :failure-phase (property-result-failure-phase result)
          :target-calls *target-calls*
          :case (and evidence (trial-observation-case evidence))
          :failure-reason (function-check-result-failure-reason result)
          :signature (and evidence (trial-observation-signature evidence))
          :selection-error (getf (function-check-result-explanation result) :case-error)
          :cases (getf report :cases)
          :never-called (getf report :never-called)
          :case-selection-errors (getf report :case-selection-errors))))

(defun run-scripted (registry name inputs trials)
  "Check NAME in REGISTRY over INPUTS with a fresh call counter."
  (let ((*registry* registry)
        (*example-inputs* (copy-list inputs))
        (*target-calls* 0))
    (summarize-run (check-function name :trials trials :seed 1))))

(defun demo-both-outcomes (&optional (registry (register-example!)))
  "Check one contract that requires a return in one case and an error in the other.

Both cases are exercised by the two scripted inputs, and each contributes its own
call and outcome counts."
  (let ((*registry* registry)
        (*example-inputs* (list '(10 2) '(2 10)))
        (*target-calls* 0))
    (summarize-run (check-function 'remaining-balance :trials 2 :seed 1))))

(defun demo-wrong-implementation (&optional (registry (register-example!)))
  "Check the deliberately wrong target and report the case that caught it.

The target answers 0 instead of signalling, so the expected-error case reports
:MISSING-CONDITION.  This is a target bug, and the report names the case it
belongs to; it is not a case-selection error."
  (let ((*registry* registry)
        (*example-inputs* (list '(2 10)))
        (*target-calls* 0))
    (summarize-run (check-function 'broken-remaining-balance :trials 1 :seed 1))))

(defun demo-selection-errors (&optional (registry (register-example!)))
  "Report a duplicated condition and a missing one, side by side.

Neither is a target bug: in both runs the target is never called, the result is
:ERROR with :FAILURE-PHASE :CASE-SELECTION, and the explanation carries the
selection error kind instead of a counterexample."
  (list :ambiguous (run-scripted registry 'overlapping-balance '((5 5)) 1)
        :missing (run-scripted registry 'gapped-balance '((5 5)) 1)))

(defun demo-unchecked-cases (&optional (registry (register-example!)))
  "Report a passing run whose second case no trial reached.

The status is :PASSED because nothing that ran was violated.  :NEVER-CALLED says
which declared case was not exercised, so a passing status is not read as proof
that every case holds."
  (let ((*registry* registry)
        (*example-inputs* (list '(10 2)))
        (*target-calls* 0))
    (summarize-run (check-function 'remaining-balance :trials 1 :seed 1))))
