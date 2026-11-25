;;;; tests/state-frame-test.lisp
(defpackage #:cl-spec/tests/state-frame-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/execution #:failure-identities-match-p)
  (:import-from #:cl-spec/src/backends/check-it))
(in-package #:cl-spec/tests/state-frame-test)

(defvar *rows* nil)
(defvar *change-undeclared-p* t)
(defvar *target-calls* 0)

(defun frame-target (key)
  (incf *target-calls*)
  (setf (gethash key *rows*) 9)
  (when *change-undeclared-p*
    (setf (gethash :locked *rows*) '(:balance 9)))
  :receipt)

(defun register-frame (key-form)
  (funcall
   (compile nil
            `(lambda ()
               (cl-spec:defspec-function frame-target
                 (:args (key (member :account)))
                 (:capture (allowed key))
                 (:modifies (:rows ,key-form) (:rows :audit))
                 (:returns keyword))))))

(defun register-table-observer (version)
  (cl-spec:register-hash-table-state-observer :rows (lambda () *rows*) :version version))

(defun checked-frame (argument)
  (cl-spec:call-check-data (cl-spec:check-call 'frame-target (list argument))))

(defun frame-batch-target (keys)
  (incf *target-calls*)
  (incf (gethash '(:batch :count) *rows* 0))
  (dolist (key keys) (incf (gethash key *rows* 0)))
  (when *change-undeclared-p*
    (incf (gethash :unlisted *rows* 0)))
  keys)

(deftest runtime-key-set-allows-each-key-and-preserves-scalar-list-keys
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal))
        (*target-calls* 0)
        (*change-undeclared-p* nil)
        (use-override-p nil)
        (override nil)
        (key-evaluations 0))
    (register-table-observer 1)
    (cl-spec:defspec-function frame-batch-target
      (:args (keys (list-of keyword)))
      (:modifies (:rows '(:batch :count)
                  (:each (progn (incf key-evaluations)
                                (if use-override-p override keys)))))
      (:returns (list-of keyword)))
    (dolist (keys '((:a :b :a) nil))
      (let ((data (cl-spec:call-check-data (cl-spec:check-call 'frame-batch-target (list keys)))))
        (ok (eq :passed (getf data :status)))))
    (let* ((*change-undeclared-p* t)
           (data (cl-spec:call-check-data (cl-spec:check-call 'frame-batch-target '((:a)))))
           (observation (getf data :observation))
           (frame (getf (getf observation :state) :frame)))
      (ok (eq :failed (getf data :status)))
      (ok (eq :unlisted (getf frame :key))))
    (let ((cycle (list :a)))
      (setf (cdr cycle) cycle use-override-p t)
      (dolist (bad (list :a (cons :a :b) cycle))
        (setf override bad)
        (let* ((data (cl-spec:call-check-data (cl-spec:check-call 'frame-batch-target '((:a)))))
               (observation (getf data :observation))
               (frame (getf (getf observation :state) :frame)))
          (ok (eq :error (getf data :status)))
          (ok (eq :allowed-keys (getf frame :stage)))
          (ok (eq 'cl-spec:invalid-argument (getf frame :condition-type))))))
    (ok (= 6 key-evaluations))
    (ok (= 3 *target-calls*))))

(deftest reports-an-undeclared-change-and-preserves-the-evidence
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal)))
    (register-table-observer 1)
    (register-frame 'allowed)
    (setf (gethash :locked *rows*) nil)
    (let* ((data (checked-frame :account))
           (observation (getf data :observation))
           (frame (getf (getf observation :state) :frame)))
      (setf (gethash :locked *rows*) :changed-later)
      (ok (eq :failed (getf data :status)))
      (ok (eq :state-post (getf data :failure-phase)))
      (ok (eq :state-postcondition (getf observation :reason)))
      (ok (eq :rows (getf frame :observer)))
      (ok (eq :locked (getf frame :key)))
      (ok (equal '(:present t :value nil) (getf frame :before)))
      (ok (equal '(:present t :value (:balance 9)) (getf frame :after))))))

(deftest declared-frame-and-observer-version-contribute-to-the-digest
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal))
        (*change-undeclared-p* nil))
    (register-table-observer 1)
    (register-frame 'allowed)
    (let ((before (cl-spec:function-spec-data 'frame-target)))
      (ok (getf before :definition-digest-complete))
      (ok (eq :passed (getf (checked-frame :account) :status)))
      (register-frame ':other)
      (let ((changed-frame (cl-spec:function-spec-data 'frame-target)))
        (ok (not (equal (getf before :definition-digest)
                        (getf changed-frame :definition-digest))))
        (register-table-observer 2)
        (register-frame ':other)
        (let ((changed-observer (cl-spec:function-spec-data 'frame-target)))
          (ok (getf changed-observer :definition-digest-complete))
          (ok (not (equal (getf changed-frame :definition-digest)
                          (getf changed-observer :definition-digest)))))))))

(defstruct row balance)

(defun opaque-row-snapshot ()
  (make-row :balance (gethash :amount *rows*)))

(defun opaque-row-changes (before after)
  (unless (eql (row-balance before) (row-balance after))
    (list :amount)))

(defun opaque-row-projection (snapshot key)
  (assert (eq :amount key))
  (values (list :balance (row-balance snapshot)) t))

(defun update-opaque-row ()
  (incf (gethash :amount *rows*)))

(deftest wraps-opaque-snapshots-with-a-user-projection
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal)))
    (setf (gethash :amount *rows*) 10)
    (cl-spec:register-state-observer :opaque :version 1 :snapshot 'opaque-row-snapshot
                                    :compare 'opaque-row-changes :project 'opaque-row-projection)
    (cl-spec:defspec-function update-opaque-row
      (:args) (:returns integer) (:modifies (:opaque)))
    (let* ((data (cl-spec:call-check-data (cl-spec:check-call 'update-opaque-row nil)))
           (frame (getf (getf (getf data :observation) :state) :frame)))
      (ok (eq :failed (getf data :status)))
      (ok (equal '(:present t :value (:balance 10)) (getf frame :before)))
      (ok (equal '(:present t :value (:balance 11)) (getf frame :after))))))

(deftest a-failed-before-snapshot-calls-no-target
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*target-calls* 0))
    (cl-spec:register-state-observer
     :rows :version 1 :source 'failing-observer
     :snapshot (lambda () (error "snapshot failure"))
     :compare 'opaque-row-changes :project 'opaque-row-projection)
    (register-frame 'allowed)
    (let* ((data (checked-frame :account))
           (observation (getf data :observation))
           (frame (getf (getf observation :state) :frame)))
      (ok (zerop *target-calls*))
      (ok (eq :error (getf data :status)))
      (ok (eq :capture (getf data :failure-phase)))
      (ok (eq :contract-error (getf observation :reason)))
      (ok (eq :rows (getf frame :observer)))
      (ok (eq :before (getf frame :stage))))))

(deftest pre-call-frame-errors-retain-the-selected-case
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*target-calls* 0)
        (failed-stage nil))
    (cl-spec:register-state-observer :records :version 1
      :snapshot (lambda ()
                  (when (eq failed-stage :before) (error "Before snapshot failed"))
                  nil)
      :compare (lambda (before after) (declare (ignore before after)) nil)
      :project (lambda (snapshot key) (declare (ignore snapshot key)) (values nil nil)))
    (cl-spec:defspec-function frame-target
      (:args (key keyword))
      (:modifies (:records
                  (if (eq failed-stage :allowed-keys) (error "Allowed keys failed") key)))
      (:cases
        (:primary (:when (eq key :primary)) (:returns keyword))
        (:other (:when (not (eq key :primary))) (:returns keyword))))
    (dolist (stage '(:allowed-keys :before))
      (setf failed-stage stage)
      (let* ((data (cl-spec:call-check-data (cl-spec:check-call 'frame-target '(:primary))))
             (observation (getf data :observation))
             (observer (when (eq stage :before) :records)))
        (ok (eq :error (getf data :status)))
        (ok (eq :primary (getf observation :case)))
        (ok (equal (list :case :primary :state-frame :error observer stage 'simple-error)
                   (getf observation :signature)))
        (ok (some (lambda (gap)
                    (and (eq :case-never-called (getf gap :kind))
                         (eq :primary (getf gap :case))))
                  (getf (getf data :evidence) :gaps)))
        (ok (zerop *target-calls*))))))

(deftest fixture-frame-evidence-survives-artifact-roundtrip
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (register-table-observer 1)
    (cl-spec:defspec-function frame-target
      (:args (key (member :account)))
      (:returns keyword)
      (:modifies (:rows key))
      (:fixture (:isolation :around) (:version 1)
        (:recipe (recipe (member :account)))
        (:around (trial)
          (let ((*rows* (make-hash-table :test #'equal)))
            (funcall trial)))
        (:setup (context) (list recipe))
        (:cleanup (context) nil)))
    (let* ((result (cl-spec:check-fixture 'frame-target :account))
           (artifact (cl-spec:make-counterexample-artifact result))
           (wire (cl-spec:serialize-counterexample-artifact artifact))
           (saved (cl-spec:deserialize-counterexample-artifact wire))
           (recheck (cl-spec:recheck-counterexample saved :state-policy :fixture))
           (state (getf (getf (getf recheck :observation) :observation) :state))
           (frame (getf state :frame)))
      (ok (eq :same-failure (getf recheck :status)))
      (ok (equal '(:present nil) (getf frame :before)))
      (ok (equal '(:present t :value (:balance 9)) (getf frame :after))))))

(deftest capture-rebinding-refuses-a-stale-compiled-frame
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal)))
    (register-table-observer 1)
    (let ((contract
            (cl-spec:defspec-function frame-target
              (:args (key (member :account)))
              (:capture (allowed key) (other :locked))
              (:modifies (:rows allowed))
              (:returns keyword))))
      (ok (eq :failed (getf (checked-frame :account) :status)))
      (ok (handler-case
              (progn
                (reinitialize-instance
                 contract :capture-bindings '((other :locked) (allowed key))
                 :capture-functions (list (lambda (key) (declare (ignore key)) :locked)
                                          (lambda (key other) (declare (ignore other)) key)))
                nil)
            (cl-spec:invalid-function-spec-form () t)))
      ;; Change it again so a fresh check would detect the forbidden row.
      (remhash :locked *rows*)
      (ok (eq :failed (getf (checked-frame :account) :status))))))

(deftest argument-rebinding-refuses-a-stale-compiled-frame
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal)))
    (register-table-observer 1)
    (let ((contract
            (cl-spec:defspec-function frame-target
              (:args (key (member :account)))
              (:modifies (:rows key))
              (:returns keyword))))
      (ok (handler-case
              (progn
                (reinitialize-instance contract :argument-specs '((renamed (member :account))))
                nil)
            (cl-spec:invalid-function-spec-form () t))))))

(deftest frame-failures-use-observer-key-equality
  (let ((base-key (make-array 6 :element-type 'base-char :initial-contents "locked"))
        (char-key (make-array 6 :element-type 'character :initial-contents "locked")))
    (ok (equal base-key char-key))
    (ok (failure-identities-match-p (list :state-frame :rows base-key)
                                    (list :state-frame :rows char-key)))
    (ok (not (failure-identities-match-p (list :state-frame :rows base-key)
                                         (list :state-frame :other char-key))))))

(deftest observer-projection-must-report-presence-explicitly
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*rows* (make-hash-table :test #'equal)))
    (setf (gethash :amount *rows*) 10)
    (cl-spec:register-state-observer
     :opaque :version 1 :source 'missing-presence :snapshot 'opaque-row-snapshot
     :compare 'opaque-row-changes
     :project (lambda (snapshot key)
                (declare (ignore key))
                (list :balance (row-balance snapshot))))
    (cl-spec:defspec-function update-opaque-row
      (:args) (:returns integer) (:modifies (:opaque)))
    (let* ((data (cl-spec:call-check-data (cl-spec:check-call 'update-opaque-row nil)))
           (observation (getf data :observation))
           (frame (getf (getf observation :state) :frame)))
      (ok (eq :error (getf data :status)))
      (ok (eq :contract-error (getf observation :reason)))
      (ok (eq :project-before (getf frame :stage))))))
