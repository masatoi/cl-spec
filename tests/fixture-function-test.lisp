;;;; tests/fixture-function-test.lisp
(defpackage #:cl-spec/tests/fixture-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main))
(in-package #:cl-spec/tests/fixture-function-test)

(defvar *setups* 0)
(defvar *cleanups* 0)
(defvar *calls* 0)
(defvar *mode* :correct)
(defvar *objects* nil)

(defun withdraw (account amount)
  (incf *calls*)
  (push account *objects*)
  (unless (eq *mode* :missing-update) (decf (car account) amount))
  :receipt)

(defun register-contract ()
  (funcall
   (compile nil
            '(lambda ()
               (cl-spec:defspec-function withdraw
                 (:args (account (list-of integer)) (amount (range integer 1 100)))
                 (:fixture
                   (:isolation :fresh)
                   (:version 1)
                   (:recipe (recipe (tuple (range integer 0 100)
                                           (range integer 1 100))))
                   (:setup (context)
                     (incf *setups*)
                     (setf (gethash :account context) (list (first recipe)))
                     (when (eq *mode* :setup-error) (error "setup error"))
                     (if (eq *mode* :bad-arguments)
                         (list :invalid (second recipe))
                         (list (gethash :account context) (second recipe))))
                   (:cleanup (context)
                     (declare (ignore recipe))
                     (incf *cleanups*)
                     (clrhash context)
                     (when (eq *mode* :cleanup-error) (error "cleanup error"))))
                 (:pre (>= (car account) amount))
                 (:capture (before (car account)))
                 (:returns keyword)
                 (:state-post (= (car account) (- before amount))))))))

(defun fixture-check (recipe)
  (funcall (find-symbol "CHECK-FIXTURE" "CL-SPEC") 'withdraw recipe))

(defun fixture-data (result)
  (funcall (find-symbol "FIXTURE-CHECK-DATA" "CL-SPEC") result))

(defmacro with-contract (&body body)
  `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
         (*setups* 0) (*cleanups* 0) (*calls* 0) (*objects* nil) (*mode* :correct))
     (register-contract)
     ,@body))

(deftest fixture-direct-fresh-state
  (with-contract
    (let ((first (fixture-data (fixture-check '(30 10))))
          (second (fixture-data (fixture-check '(30 10)))))
      (ok (eq :passed (getf first :status)))
      (ok (eq :passed (getf second :status)))
      (ok (= 2 (getf first :schema-version)))
      (ok (eq :fixture-recipe (getf first :input-kind)))
      (ok (= 2 *setups* *cleanups* *calls*))
      (ok (not (eq (first *objects*) (second *objects*)))))))

(deftest fixture-state-violation-retains-identity
  (with-contract
    (let* ((*mode* :missing-update)
           (data (fixture-data (fixture-check '(30 10)))))
      (ok (eq :failed (getf data :status)))
      (ok (equal '(:state-postcondition 0)
                 (getf (getf data :observation) :signature)))
      (ok (= 1 *setups* *cleanups* *calls*)))))

(deftest fixture-rejected-pre-still-cleans
  (with-contract
    (let ((data (fixture-data (fixture-check '(3 10)))))
      (ok (eq :rejected (getf data :status)))
      (ok (= 1 *setups* *cleanups*))
      (ok (zerop *calls*)))))

(deftest fixture-setup-and-call-schema-errors
  (with-contract
    (dolist (mode '(:setup-error :bad-arguments))
      (let* ((*mode* mode) (data (fixture-data (fixture-check '(30 10)))))
        (ok (eq :error (getf data :status)))
        (ok (eq (if (eq mode :setup-error) :fixture-setup-error
                    :fixture-arguments-error)
                (getf data :reason)))))
    (ok (= 2 *setups* *cleanups*))
    (ok (zerop *calls*))))

(deftest fixture-cleanup-error-is-not-a-pass
  (with-contract
    (let* ((*mode* :cleanup-error)
           (data (fixture-data (fixture-check '(30 10)))))
      (ok (eq :error (getf data :status)))
      (ok (eq :fixture-cleanup-error (getf data :reason)))
      (ok (eq :unknown (getf (getf data :lifecycle) :state)))
      (ok (eq :passed (getf (getf data :observation) :status))))))

(deftest direct-call-metadata-does-not-claim-a-recipe
  (with-contract
    (let ((data (cl-spec:call-check-data (cl-spec:check-call 'withdraw (list (list 30) 10)))))
      (ok (not (eq :fixture-recipe (getf data :input-kind))))
      (ok (eq :direct-call (getf data :execution-mode))))))

(deftest direct-call-does-not-own-fixture
  (with-contract
    (let* ((account (list 30))
           (result (cl-spec:check-call 'withdraw (list account 10))))
      (ok (eq :passed (cl-spec:call-check-result-status result)))
      (ok (= 20 (car account)))
      (ok (zerop *setups*))
      (ok (zerop *cleanups*)))))

(deftest fixture-declaration-introspection
  (with-contract
    (let ((data (cl-spec:function-spec-data 'withdraw)))
      (ok (eq :fresh (getf (getf data :fixture) :isolation)))
      (ok (= 1 (getf (getf data :fixture) :version)))
      (ok (getf data :definition-digest-complete))
      (ok (zerop *setups*))
      (ok (zerop *calls*)))))