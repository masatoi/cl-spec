;;;; tests/state-frame-test.lisp
(defpackage #:cl-spec/tests/state-frame-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
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
