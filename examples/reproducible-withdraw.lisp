;;;; examples/reproducible-withdraw.lisp
(defpackage #:cl-spec/examples/reproducible-withdraw
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defgenerator #:defspec
                #:defspec-function #:check-function #:property-result-status #:property-result-trials
                #:property-result-shrunk-counterexample #:make-counterexample-artifact
                #:counterexample-artifact-data #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact #:recheck-counterexample)
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:make-example-registry #:register-example! #:demo-recheck #:demo-rollback))
(in-package #:cl-spec/examples/reproducible-withdraw)

(defstruct account
  "A mutable account rebuilt from data for every trial."
  balance id)

(defun withdraw-missing-update (account amount)
  "Return a plausible receipt while deliberately forgetting the balance update."
  (list :account (account-id account) :amount amount))

(defvar *ledger* nil
  "One shared balance cell for the rollback demonstration.")

(defmacro with-ledger-rollback (&body body)
  "Run BODY against the shared ledger and restore the original balance on exit."
  (let ((balance (gensym "BALANCE")))
    `(let ((,balance (car *ledger*)))
       (unwind-protect (progn ,@body)
         (setf (car *ledger*) ,balance)))))

(defun withdraw-from-ledger (amount)
  "Debit the shared ledger and return the remaining balance."
  (decf (car *ledger*) amount))

(defun make-example-registry ()
  "Return an empty registry dedicated to this example."
  (make-hash-table-registry))

(defun register-example! (registry)
  "Register the fresh-account and rollback-ledger contracts."
  (let ((*registry* registry))
    (defgenerator withdrawal-recipes ()
      (:shrink (recipe)
        (when (> (first recipe) 1)
          (list (list 1 (second recipe) 1))))
      (list 30 7 10))
    (defspec withdrawal-recipe
      (tuple (range integer 0 1000) integer (range integer 1 1000))
      (:generator withdrawal-recipes))
    (defspec-function withdraw-missing-update
      (:args (account (satisfies account-p)) (amount (range integer 1 1000)))
      (:fixture
        (:isolation :fresh) (:version 1)
        (:recipe (recipe withdrawal-recipe))
        (:setup (context)
          (destructuring-bind (balance id amount) recipe
            (let ((account (make-account :balance balance :id id)))
              (setf (gethash :account context) account)
              (list account amount))))
        (:cleanup (context) (clrhash context)))
      (:pre (<= amount (account-balance account)))
      (:capture (balance-before (account-balance account))
                (id-before (account-id account)))
      (:returns list)
      (:state-post (= (account-balance account) (- balance-before amount))
                   (= (account-id account) id-before)))
    (defspec-function withdraw-from-ledger
      (:args (amount (range integer 1 10)))
      (:fixture
        (:isolation :around) (:version 1)
        (:recipe (recipe (range integer 1 10)))
        (:around (trial) (with-ledger-rollback (funcall trial)))
        (:setup (context) (list recipe))
        (:cleanup (context) nil))
      (:capture (balance-before (car *ledger*)))
      (:returns integer)
      (:state-post (= balance-before 100)
                   (= (car *ledger*) (- balance-before amount)))))
  registry)

(defun demo-recheck (registry)
  "Shrink a state violation, serialize it, and recheck the saved recipe once."
  (let* ((result (check-function 'withdraw-missing-update :trials 1 :seed 42
                                :registry registry))
         (artifact (make-counterexample-artifact result))
         (restored (deserialize-counterexample-artifact
                    (serialize-counterexample-artifact artifact)))
         (recheck (recheck-counterexample restored :state-policy :fixture :registry registry)))
    (list :status (property-result-status result)
          :shrunk-recipe (getf (property-result-shrunk-counterexample result) 'recipe)
          :artifact-version (getf (counterexample-artifact-data restored) :artifact-version)
          :recheck (getf recheck :status))))

(defun demo-rollback (registry)
  "Withdraw twice from one ledger, with rollback restoring it before each new trial."
  (let ((*ledger* (list 100)))
    (let ((result (check-function 'withdraw-from-ledger :trials 2 :seed 42
                                  :registry registry)))
      (list :status (property-result-status result)
            :trials (property-result-trials result)
            :balance (car *ledger*)))))
