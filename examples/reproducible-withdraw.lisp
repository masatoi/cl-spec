;;;; examples/reproducible-withdraw.lisp
(defpackage #:cl-spec/examples/reproducible-withdraw
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defgenerator #:defspec
                #:defspec-function #:check-function #:property-result-status
                #:property-result-shrunk-counterexample #:make-counterexample-artifact
                #:counterexample-artifact-data #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact #:recheck-counterexample)
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:make-example-registry #:register-example! #:demo-recheck))
(in-package #:cl-spec/examples/reproducible-withdraw)

(defstruct account
  "A mutable account rebuilt from data for every trial."
  balance id)

(defun withdraw-missing-update (account amount)
  "Return a plausible receipt while deliberately forgetting the balance update."
  (list :account (account-id account) :amount amount))

(defun make-example-registry ()
  "Return an empty registry dedicated to this example."
  (make-hash-table-registry))

(defun register-example! (registry)
  "Register a deterministic recipe generator and failing withdrawal contract."
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
        (:cleanup (context) (declare (ignore recipe)) (clrhash context)))
      (:pre (<= amount (account-balance account)))
      (:capture (balance-before (account-balance account))
                (id-before (account-id account)))
      (:returns list)
      (:state-post (= (account-balance account) (- balance-before amount))
                   (= (account-id account) id-before))))
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