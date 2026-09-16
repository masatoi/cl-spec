;;;; examples/stateful-withdraw.lisp
;;;;
;;;; Executable integration example for explicit pre-observation and post-run
;;;; state constraints (specification §17.3).  The walkthrough lives in
;;;; docs/guides/state-observation-walkthrough.md.
;;;;
;;;; Loading this file defines a condition, a small ACCOUNT structure, several
;;;; withdrawal implementations and one registry constructor only.  It does not
;;;; register a contract, draw a value or run a demo, so it never changes the
;;;; caller's *REGISTRY*.  Call REGISTER-EXAMPLE! to register the example's
;;;; contracts in a dedicated registry, and the DEMO-* entry points to run the
;;;; walkthrough.  Each input is a (BALANCE ID AMOUNT) triple and the generator
;;;; builds a fresh ACCOUNT per trial, so no trial starts from the object an
;;;; earlier trial mutated.

(defpackage #:cl-spec/examples/stateful-withdraw
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry*
                #:make-hash-table-registry
                #:defgenerator #:defspec-function #:check-function
                #:function-check-result-case-report
                #:function-check-result-failure-reason
                #:property-result-status #:property-result-failure-phase
                #:property-result-failure-evidence #:property-result-shrink-report
                #:property-result-schema-metadata
                #:trial-observation-signature #:trial-observation-state
                #:make-counterexample-artifact
                #:invalid-counterexample-artifact
                #:invalid-counterexample-artifact-reason
                #:unsupported-stateful-operation
                #:unsupported-stateful-operation-reason)
  ;; This example is an ASDF package-inferred subsystem, so this bare
  ;; :IMPORT-FROM declares its check-it generator backend dependency without
  ;; importing a symbol.  See examples/structured-data.lisp for the same note.
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:withdraw-account #:make-account
           #:account-balance #:account-id
           #:insufficient-funds #:insufficient-funds-balance
           #:insufficient-funds-amount
           #:balance-verification-failed
           #:balance-verification-failed-actual
           #:balance-verification-failed-expected
           #:make-example-registry #:register-example!
           #:withdraw! #:withdraw-without-recording!
           #:withdraw-then-refuse! #:withdraw-renumbered!
           #:withdraw-asserted!
           #:demo-successful-withdrawal #:demo-missing-update
           #:demo-refusal-that-mutated #:demo-renumbered-account
           #:demo-verification-error #:demo-limits))

(in-package #:cl-spec/examples/stateful-withdraw)

(defstruct (withdraw-account (:constructor make-account (balance id))
                             (:conc-name account-))
  "A deliberately small account: the balance and the identifier are integers."
  balance
  id)

(define-condition insufficient-funds (error)
  ((balance :initarg :balance :reader insufficient-funds-balance)
   (amount :initarg :amount :reader insufficient-funds-amount))
  (:report (lambda (condition stream)
             (format stream "Cannot withdraw ~D from ~D."
                     (insufficient-funds-amount condition)
                     (insufficient-funds-balance condition))))
  (:documentation "The expected error of the example's withdrawal contract."))

(define-condition balance-verification-failed (error)
  ((actual :initarg :actual :reader balance-verification-failed-actual)
   (expected :initarg :expected :reader balance-verification-failed-expected))
  (:report (lambda (condition stream)
             (format stream "Balance is ~D, expected ~D."
                     (balance-verification-failed-actual condition)
                     (balance-verification-failed-expected condition))))
  (:documentation "Signalled by a state-post form that verifies with ERROR.

A predicate that returns NIL is a STATE-POSTCONDITION violation; a form that
signals becomes a STATE-POST-ERROR instead.  This example shows both."))

(defvar *target-calls* 0
  "Target invocations of the currently running demo, for reporting and testing.")

(defvar *example-inputs* nil
  "The (BALANCE ID AMOUNT) triples the scripted generator returns, front to back.

A special rather than a closure so a demo can state its inputs in one place and
the contract can name one registered generator.")

;;; Targets.  A correct one and four mistakes, each a separate named function:
;;; no demo rewrites an fdefinition.

(defun withdraw! (account amount)
  "Withdraw AMOUNT when the balance allows it, or signal INSUFFICIENT-FUNDS.

A correct implementation: it changes the balance exactly once and never touches
the identifier."
  (incf *target-calls*)
  (if (<= amount (account-balance account))
      (progn (decf (account-balance account) amount)
             (list :receipt amount))
      (error 'insufficient-funds :balance (account-balance account) :amount amount)))

(defun withdraw-without-recording! (account amount)
  "Answer the receipt but leave the balance alone."
  (incf *target-calls*)
  (if (<= amount (account-balance account))
      (list :receipt amount)
      (error 'insufficient-funds :balance (account-balance account) :amount amount)))

(defun withdraw-then-refuse! (account amount)
  "Change the balance and then signal the expected error."
  (incf *target-calls*)
  (if (<= amount (account-balance account))
      (progn (decf (account-balance account) amount)
             (list :receipt amount))
      (progn (decf (account-balance account) 1)
             (error 'insufficient-funds :balance (account-balance account)
                                        :amount amount))))

(defun withdraw-renumbered! (account amount)
  "Withdraw correctly but also change the declared identifier."
  (incf *target-calls*)
  (if (<= amount (account-balance account))
      (progn (decf (account-balance account) amount)
             (setf (account-id account) 99)
             (list :receipt amount))
      (error 'insufficient-funds :balance (account-balance account) :amount amount)))

(defun withdraw-asserted! (account amount)
  "Answer the receipt but leave the balance alone, for the asserting contract."
  (incf *target-calls*)
  (if (<= amount (account-balance account))
      (list :receipt amount)
      (error 'insufficient-funds :balance (account-balance account) :amount amount)))

(defun assert-balance-is (account expected)
  "Signal BALANCE-VERIFICATION-FAILED unless ACCOUNT's balance is EXPECTED."
  (unless (= (account-balance account) expected)
    (error 'balance-verification-failed
           :actual (account-balance account) :expected expected)))

(defun make-example-registry ()
  "Return a fresh registry for this example.  Nothing is registered yet."
  (make-hash-table-registry))

(defun register-example! (&optional (registry (make-example-registry)))
  "Register the example's generator and contracts in REGISTRY and return it.

The caller's *REGISTRY* is neither read nor written."
  (let ((*registry* registry))
    (defgenerator scripted-accounts ()
      "Build a fresh ACCOUNT from the next (BALANCE ID AMOUNT) triple."
      (destructuring-bind (balance id amount) (pop *example-inputs*)
        (list (make-account balance id) amount)))
    (defspec-function withdraw!
      "A successful call reduces the balance, a refusal leaves it, the id stays."
      (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
      (:args-generator scripted-accounts)
      (:capture
        (balance-before (account-balance account))
        (id-before (account-id account)))
      (:cases
        (:sufficient-funds
          "The amount fits: the balance drops by exactly the amount."
          (:when (<= amount balance-before))
          (:returns (satisfies listp))
          (:state-post (= (account-balance account) (- balance-before amount))
                       (eql (account-id account) id-before)))
        (:insufficient-funds
          "The amount does not fit: the expected error, and no balance change."
          (:when (> amount balance-before))
          (:signals (type insufficient-funds))
          (:state-post (= (account-balance account) balance-before)
                       (eql (account-id account) id-before)))))
    (defspec-function withdraw-without-recording!
      "The same contract, attached to the target that forgets the balance."
      (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
      (:args-generator scripted-accounts)
      (:capture
        (balance-before (account-balance account))
        (id-before (account-id account)))
      (:cases
        (:sufficient-funds
          (:when (<= amount balance-before))
          (:returns (satisfies listp))
          (:state-post (= (account-balance account) (- balance-before amount))
                       (eql (account-id account) id-before)))
        (:insufficient-funds
          (:when (> amount balance-before))
          (:signals (type insufficient-funds))
          (:state-post (= (account-balance account) balance-before)
                       (eql (account-id account) id-before)))))
    (defspec-function withdraw-then-refuse!
      "The contract that catches a refusal performed after a partial update."
      (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
      (:args-generator scripted-accounts)
      (:capture
        (balance-before (account-balance account))
        (id-before (account-id account)))
      (:cases
        (:insufficient-funds
          (:when (> amount balance-before))
          (:signals (type insufficient-funds))
          (:state-post (= (account-balance account) balance-before)
                       (eql (account-id account) id-before)))))
    (defspec-function withdraw-renumbered!
      "The contract that also declares the identifier unchanged."
      (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
      (:args-generator scripted-accounts)
      (:capture
        (balance-before (account-balance account))
        (id-before (account-id account)))
      (:cases
        (:sufficient-funds
          (:when (<= amount balance-before))
          (:returns (satisfies listp))
          (:state-post (= (account-balance account) (- balance-before amount))
                       (eql (account-id account) id-before)))))
    (defspec-function withdraw-asserted!
      "A state-post that verifies with ERROR, so a mistake is a contract error."
      (:args (account (satisfies withdraw-account-p)) (amount (range integer 1 1000)))
      (:args-generator scripted-accounts)
      (:capture (balance-before (account-balance account)))
      (:cases
        (:sufficient-funds
          (:when (<= amount balance-before))
          (:returns (satisfies listp))
          (:state-post (progn (assert-balance-is account (- balance-before amount)) t)))))
    registry))

(defun summarize-run (result)
  "Project RESULT as the data the walkthrough reads."
  (let* ((evidence (property-result-failure-evidence result))
         (state (and evidence (trial-observation-state evidence)))
         (report (function-check-result-case-report result)))
    (list :status (property-result-status result)
          :failure-phase (property-result-failure-phase result)
          :target-calls *target-calls*
          :failure-reason (function-check-result-failure-reason result)
          :signature (and evidence (trial-observation-signature evidence))
          :state state
          :shrink-termination (let ((report (property-result-shrink-report result)))
                                (and (listp report) (getf report :termination)))
          :cases (getf report :cases)
          :capture-errors (getf report :capture-errors)
          :never-called (getf report :never-called))))

(defun run-scripted (registry name inputs trials)
  "Check NAME in REGISTRY over INPUTS with a fresh call counter."
  (let ((*registry* registry)
        (*example-inputs* (copy-list inputs))
        (*target-calls* 0))
    (summarize-run (check-function name :trials trials :seed 1))))

(defun demo-successful-withdrawal (&optional (registry (register-example!)))
  "Show a correct withdrawal and a correct refusal both passing.

The first input fits and the second does not; each trial builds its own account,
and both cases check the balance and the identifier after the call."
  (run-scripted registry 'withdraw! '((30 7 10) (10 7 50)) 2))

(defun demo-missing-update (&optional (registry (register-example!)))
  "Show a target that returns the right receipt but forgets the balance.

The outcome contract passes; the state-post fails on its first form, so the
result is :FAILED / :STATE-POSTCONDITION with phase :STATE-POST and the failing
form's position in the failure identity."
  (run-scripted registry 'withdraw-without-recording! '((30 7 10)) 1))

(defun demo-refusal-that-mutated (&optional (registry (register-example!)))
  "Show the expected error signalled after a partial balance change.

The raw outcome keeps the INSUFFICIENT-FUNDS condition, but the final result is
still :FAILED / :STATE-POSTCONDITION: signalling the right error does not excuse
the state change."
  (run-scripted registry 'withdraw-then-refuse! '((10 7 50)) 1))

(defun demo-renumbered-account (&optional (registry (register-example!)))
  "Show an unrelated declared value changing while the balance is correct."
  (run-scripted registry 'withdraw-renumbered! '((30 7 10)) 1))

(defun demo-verification-error (&optional (registry (register-example!)))
  "Show a state-post form that signals, distinct from a violation.

Here the verification helper calls ERROR, so the result is :ERROR /
:CONTRACT-ERROR with phase :STATE-POST and a structured explanation, not a
:STATE-POSTCONDITION violation."
  (run-scripted registry 'withdraw-asserted! '((30 7 10)) 1))

(defun demo-limits (&optional (registry (register-example!)))
  "Report what this first version does not do, without hiding it.

A state-observing contract is not shrunk (:STATE-RESTORATION-UNAVAILABLE), and
its result cannot be saved as a counterexample artifact
(:STATEFUL-CONTRACT-UNSUPPORTED).  A new run with an integer seed is still
allowed; the author supplies the fresh initial state."
  (let* ((*registry* registry)
         (*example-inputs* '((30 7 10)))
         (*target-calls* 0)
         (result (check-function 'withdraw-without-recording! :trials 1 :seed 1))
         (artifact (handler-case (progn (make-counterexample-artifact result) nil)
                     (invalid-counterexample-artifact (condition)
                       (invalid-counterexample-artifact-reason condition))))
         (replay (handler-case (progn (check-function 'withdraw-without-recording!
                                                      :seed result)
                                      nil)
                   (unsupported-stateful-operation (condition)
                     (unsupported-stateful-operation-reason condition)))))
    (list :shrink-termination (let ((report (property-result-shrink-report result)))
                                (and (listp report) (getf report :termination)))
          :state-constraints
          (getf (property-result-schema-metadata result) :state-constraints)
          :artifact artifact
          :replay replay)))
