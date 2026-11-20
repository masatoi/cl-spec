;;;; examples/withdraw-cancellation.lisp

(defpackage #:cl-spec/examples/withdraw-cancellation
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defstate-machine #:check-state-machine
                #:run-property #:replay-property #:property-result-status #:property-result-trials
                #:property-result-counterexample #:property-result-shrunk-counterexample
                #:property-result-failure-signature #:property-result-explanation
                #:trial-observation-status #:trial-observation-signature
                #:make-counterexample-artifact #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact #:recheck-counterexample
                #:*generator-backend*)
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:register-example! #:demo-double-cancellation #:withdrawal-history))

(in-package #:cl-spec/examples/withdraw-cancellation)

(defstruct account
  "One mutable account and the status of a single withdrawal request."
  (balance 100) (status :new))

(defun step-model (status command)
  "Derive the expected balance from the abstract transaction status."
  (let ((next (ecase command
                (:balance status)
                (:withdraw (if (eq status :new) :withdrawn status))
                (:cancel (if (eq status :withdrawn) :cancelled status)))))
    (values next (if (eq next :withdrawn) 90 100))))

(defun refund (account)
  (incf (account-balance account) 10)
  (setf (account-status account) :cancelled))

(defun cancel-again (account)
  "Deliberate bug: a cancelled withdrawal still qualifies for a refund."
  (unless (eq (account-status account) :new) (refund account)))

(defun cancel-once (account)
  "Refund a withdrawal exactly once."
  (when (eq (account-status account) :withdrawn) (refund account)))

(defun step-account (account command cancel)
  "Apply COMMAND to the mutable account and observe its balance."
  (ecase command
    (:balance)
    (:withdraw
     (when (eq :new (account-status account))
       (decf (account-balance account) 10)
       (setf (account-status account) :withdrawn)))
    (:cancel (funcall cancel account)))
  (values account (account-balance account)))

(defun register-example! (registry &key repaired)
  "Register WITHDRAWAL-HISTORY in REGISTRY, using the double refund bug unless REPAIRED."
  (let ((*registry* registry)
        (cancel (if repaired #'cancel-once #'cancel-again)))
    (defstate-machine withdrawal-history
        (commands (member :withdraw :cancel :balance) :max-length 12)
      :model :new :target (make-account)
      :model-step #'step-model
      :target-step (lambda (account command) (step-account account command cancel))
      :invariant (lambda (status account) (eq status (account-status account)))
      :about (step-account) :trials (:normal 100)
      :documentation "A cancellation refunds a withdrawal exactly once."))
  registry)

(defun demo-double-cancellation (&key (seed 2))
  "Generate, shrink, and replay withdrawal commands against broken and repaired accounts.
SEED 2 demonstrates a strictly shorter failing sequence on the check-it/SBCL backend."
  (let* ((broken (register-example! (make-hash-table-registry)))
         (repaired (register-example! (make-hash-table-registry) :repaired t))
         (result (run-property 'withdrawal-history :registry broken :seed seed))
         (original (getf (property-result-counterexample result) 'commands))
         (shrunk (getf (property-result-shrunk-counterexample result) 'commands))
         (selected (or shrunk original)))
    (unless (eq :failed (property-result-status result))
      (return-from demo-double-cancellation (list :status (property-result-status result)
                                                  :seed seed)))
    (let* ((replay (replay-property 'withdrawal-history result :registry broken))
           (fixed (run-property 'withdrawal-history :seed seed :registry repaired))
           (wire (serialize-counterexample-artifact (make-counterexample-artifact result)))
           (saved (deserialize-counterexample-artifact wire))
           (*generator-backend* nil))
      (flet ((direct (registry)
               (check-state-machine 'withdrawal-history selected :registry registry))
             (recheck (registry)
               (getf (recheck-counterexample saved :state-policy :stateless :registry registry)
                     :status)))
        (list :status (property-result-status result) :seed seed
              :trials (property-result-trials result) :original original :shrunk shrunk
              :signature (property-result-failure-signature result)
              :divergence (property-result-explanation result)
              :replayed-original (getf (property-result-counterexample replay) 'commands)
              :replayed-shrunk (getf (property-result-shrunk-counterexample replay) 'commands)
              :direct-signature (trial-observation-signature (direct broken))
              :saved-recheck (recheck broken)
              :repaired-direct (trial-observation-status (direct repaired))
              :repaired-recheck (recheck repaired) :repaired-run (property-result-status fixed))))))
