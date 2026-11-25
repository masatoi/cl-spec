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
          (second (fixture-data (cl-spec:check-fixture 'withdraw '(30 10) :registry nil))))
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
      (ok (getf (getf data :fixture) :recipe-spec))
      (ok (= 1 (loop for (key) on data by #'cddr count (eq key :fixture))))
      (ok (getf data :definition-digest-complete))
      (ok (zerop *setups*))
      (ok (zerop *calls*)))))

(defvar *around-active* nil)

(defvar *around-balance* 100)

(defvar *around-events* nil)

(defvar *around-event-hook* nil)

(defvar *outer-trial* nil)

(defvar *nested-fixture-data* nil)

(defun around-event (event)
  (assert *around-active*)
  (push event *around-events*)
  (when *around-event-hook*
    (funcall *around-event-hook* event)))

(defun around-withdraw (amount)
  (around-event :target)
  (case *mode*
    (:escape-in-trial (throw 'target-escape :escaped))
    (:escape-target-outward (throw 'escape :escaped)))
  (decf *around-balance* amount)
  :receipt)

(defun register-around-contract (&optional (result-form :ignored))
  (funcall
   (compile nil
            `(lambda ()
               (cl-spec:defspec-function around-withdraw
                 (:args (amount (range integer 1 100)))
                 (:fixture
                   (:isolation :around)
                   (:version 1)
                   (:recipe (recipe (range integer 1 100)))
                   (:around (trial)
                     (let ((*around-active* t)
                           (balance *around-balance*))
                       (around-event :enter)
                       (unwind-protect
                            (case *mode*
                              (:skip nil)
                              (:signal (error "around error"))
                              (:escape (throw 'escape :escaped))
                              (:double
                               (funcall trial)
                               (handler-case (funcall trial) (error () nil)))
                              (:escape-in-trial (catch 'target-escape (funcall trial)))
                              (:return-past-trial
                               (block canceled
                                 (let ((*around-event-hook*
                                         (lambda (event)
                                           (when (eq event :target)
                                             (return-from canceled :escaped)))))
                                   (funcall trial))))
                              (:double-via-nested-check
                               (funcall trial)
                               (let ((*mode* :try-outer-thunk) (*outer-trial* trial)
                                     (*around-balance* 100))
                                 (cl-spec:check-fixture 'around-withdraw 9)))
                              (:try-outer-thunk
                               (handler-case (funcall *outer-trial*) (error () nil))
                               (funcall trial))
                              (:first-call-via-nested-check
                               (let ((*mode* :use-outer-thunk) (*outer-trial* trial))
                                 (setf *nested-fixture-data*
                                       (fixture-data
                                        (cl-spec:check-fixture 'around-withdraw 9
                                                               :coverage '(:mode :observe))))))
                              (:use-outer-thunk
                               (let ((*around-balance* 100)) (funcall *outer-trial*))
                               (funcall trial))
                              (:escape-after
                               (funcall trial)
                               (throw 'escape :escaped))
                              (otherwise (funcall trial)))
                         (setf *around-balance* balance)
                         (around-event :rollback)))
                     ,result-form)
                   (:setup (context)
                     (around-event :setup)
                     (list recipe))
                   (:cleanup (context)
                     (around-event :cleanup)))
                 (:capture (before (progn (around-event :capture) *around-balance*)))
                 (:returns keyword)
                 (:state-post (progn
                                (around-event :state-post)
                                (and (member *mode*
                                             '(:correct :double-via-nested-check
                                               :try-outer-thunk :use-outer-thunk))
                                     (= 100 before)
                                     (= *around-balance* (- before amount))))))))))

(defmacro with-around-contract (&body body)
  `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
         (*around-balance* 100) (*around-events* nil) (*mode* :correct))
     (register-around-contract)
     ,@body))

(deftest around-fixture-rolls-back-after-each-complete-trial
  (with-around-contract
    (dotimes (i 2)
      (let* ((data (fixture-data (cl-spec:check-fixture 'around-withdraw 7)))
             (lifecycle (getf data :lifecycle)))
        (ok (eq :passed (getf data :status)))
        (ok (eq :around (getf lifecycle :isolation)))
        (ok (eq :completed (getf lifecycle :around)))
        (ok (= 100 *around-balance*))
        (ok (equal '(:enter :setup :capture :target :state-post :cleanup :rollback)
                   (reverse *around-events*)))
        (setf *around-events* nil)))))

(deftest around-fixture-errors-cannot-pass-or-repeat-a-trial
  (with-around-contract
    (loop for (mode reason calls)
            in '((:skip :fixture-around-thunk-not-called 0)
                 (:signal :fixture-around-error 0)
                 (:double :fixture-around-thunk-repeated 1)
                 (:escape-in-trial :fixture-around-nonlocal-exit 1)
                 (:return-past-trial :fixture-around-nonlocal-exit 1))
          do (let* ((*mode* mode)
                    (*around-events* nil)
                    (data (fixture-data (cl-spec:check-fixture 'around-withdraw 7)))
                    (lifecycle (getf data :lifecycle)))
               (ok (eq :error (getf data :status)))
               (ok (eq reason (getf data :reason)))
               (ok (eq :aborted (getf lifecycle :completion)))
               (ok (eq :unknown (getf lifecycle :state)))
               (ok (eq (plusp calls) (getf lifecycle :target-called)))
               (ok (= calls (count :target *around-events*)))
               (ok (= calls (count :cleanup *around-events*)))
               (ok (= 100 *around-balance*))))))

(defun run-around-check (entry-point)
  (ecase entry-point
    (:direct (cl-spec:check-fixture 'around-withdraw 7))
    (:generated (cl-spec:check-function 'around-withdraw :trials 1 :seed 41))))

(deftest around-fixture-propagates-outward-throws
  (with-around-contract
    (loop for (mode events)
            in '((:escape (:enter :rollback))
                 (:escape-target-outward (:enter :setup :capture :target :cleanup :rollback))
                 (:escape-after
                  (:enter :setup :capture :target :state-post :cleanup :rollback)))
          do (dolist (entry-point '(:direct :generated))
               (let ((*mode* mode) (*around-events* nil))
                 (ok (eq :escaped (catch 'escape (run-around-check entry-point))))
                 (ok (equal events (reverse *around-events*)))
                 (ok (= 100 *around-balance*)))))))

(deftest around-fixture-honors-caller-restart-after-cleanup
  (with-around-contract
    (dolist (entry-point '(:direct :generated))
      (let ((*around-events* nil)
            (*around-event-hook*
              (lambda (event)
                (when (eq event :target)
                  (signal 'simple-condition :format-control "stop the fixture")))))
        (ok (eq :restarted
                (restart-case
                    (handler-bind ((simple-condition
                                     (lambda (condition)
                                       (declare (ignore condition))
                                       (invoke-restart :stop-fixture))))
                      (run-around-check entry-point))
                  (:stop-fixture () :restarted))))
        (ok (equal '(:enter :setup :capture :target :cleanup :rollback)
                   (reverse *around-events*)))
        (ok (= 100 *around-balance*))))))

#+(and sbcl sb-thread)
(deftest around-fixture-honors-caller-timeout-after-cleanup
  (with-around-contract
    (dolist (entry-point '(:direct :generated))
      (let ((*around-events* nil)
            (*around-event-hook* (lambda (event) (when (eq event :target) (sleep 3)))))
        (ok (eq :timed-out
                (handler-case
                    (sb-ext:with-timeout 0.5 (run-around-check entry-point))
                  (sb-ext:timeout () :timed-out))))
        (ok (equal '(:enter :setup :capture :target :cleanup :rollback)
                   (reverse *around-events*)))
        (ok (= 100 *around-balance*))))))

#+(and sbcl sb-thread)
(deftest bounded-around-cleanup-preserves-a-pending-caller-exit
  (with-around-contract
    (dolist (options '((:cleanup-timeout 1/10) (:timeout 1/2 :cleanup-timeout 2)))
      (dolist (exit '(:deadline :restart))
        (let* ((cleanup-completed nil)
               (*around-events* nil)
               (*around-event-hook*
                 (lambda (phase)
                   (case phase
                     (:target
                      (ecase exit
                        (:deadline (sleep 3))
                        (:restart (signal 'simple-condition :format-control "cancel"))))
                     (:cleanup
                      (sleep 3)
                      (setf cleanup-completed t))))))
          (flet ((check ()
                   (cl-spec:check-function 'around-withdraw :trials 1 :seed 41
                                           :options options)))
            (ok (eq exit
                    (ecase exit
                      (:deadline
                       (handler-case (sb-ext:with-timeout 1/5 (check))
                         (sb-ext:timeout () :deadline)))
                      (:restart
                       (restart-case
                           (handler-bind ((simple-condition
                                            (lambda (condition)
                                              (declare (ignore condition))
                                              (invoke-restart :stop-fixture))))
                             (check))
                         (:stop-fixture () :restart)))))))
          (ok (equal '(:enter :setup :capture :target :cleanup :rollback)
                     (reverse *around-events*)))
          (ok (not cleanup-completed)))))))

#+(and sbcl sb-thread)
(deftest around-fixture-propagates-interrupts-throughout-wrapper
  (with-around-contract
    (loop for (phase events)
            in '((:enter (:enter))
                 (:target (:enter :setup :capture :target :cleanup :rollback))
                 (:rollback
                  (:enter :setup :capture :target :state-post :cleanup :rollback)))
          do (let ((*around-events* nil)
                   (*around-event-hook*
                     (lambda (event)
                       (when (eq event phase)
                         (sb-thread:interrupt-thread sb-thread:*current-thread*
                           (lambda () (signal 'sb-sys:interactive-interrupt)))))))
               (ok (eq :interrupted
                       (handler-case (run-around-check :direct)
                         (sb-sys:interactive-interrupt () :interrupted))))
               (ok (equal events (reverse *around-events*)))
               (ok (= 100 *around-balance*))))))

(deftest nested-around-check-cannot-hide-a-repeated-outer-call
  (with-around-contract
    (let ((*mode* :double-via-nested-check))
      (let ((data (fixture-data (cl-spec:check-fixture 'around-withdraw 7))))
        (ok (eq :error (getf data :status)))
        (ok (eq :fixture-around-thunk-repeated (getf data :reason)))
        (ok (= 2 (count :target *around-events*) (count :cleanup *around-events*)))))))

(deftest nested-around-first-call-keeps-each-coverage-trial-independent
  (with-around-contract
    (let ((*mode* :first-call-via-nested-check) (*nested-fixture-data* nil))
      (let ((outer (fixture-data (cl-spec:check-fixture 'around-withdraw 7
                                                       :coverage '(:mode :observe)))))
        (dolist (data (list outer *nested-fixture-data*))
          (ok (eq :passed (getf data :status)))
          (ok (eql 1 (getf (getf data :coverage) :trials))))))))

(deftest around-fixture-source-contributes-to-the-digest
  (with-around-contract
    (let ((before (cl-spec:function-spec-data 'around-withdraw)))
      (register-around-contract :changed)
      (let ((after (cl-spec:function-spec-data 'around-withdraw)))
        (ok (getf before :definition-digest-complete))
        (ok (getf after :definition-digest-complete))
        (ok (not (equal (getf before :definition-digest)
                        (getf after :definition-digest))))))))

(deftest around-fixture-shrinks-replays-and-rechecks
  (with-around-contract
    (let* ((*mode* :broken)
           (result (cl-spec:check-function 'around-withdraw :trials 20 :seed 41))
           (artifact (cl-spec:make-counterexample-artifact result))
           (wire (cl-spec:serialize-counterexample-artifact artifact))
           (restored (cl-spec:deserialize-counterexample-artifact wire))
           (replay (cl-spec:check-function 'around-withdraw :seed result))
           (recheck (cl-spec:recheck-counterexample restored :state-policy :fixture)))
      (ok (eq :failed (cl-spec:property-result-status result)))
      (ok (cl-spec:property-result-shrunk-counterexample result))
      (ok (equal (cl-spec:property-result-shrunk-counterexample result)
                 (cl-spec:property-result-shrunk-counterexample replay)))
      (ok (eq :same-failure (getf recheck :status)))
      (ok (= 100 *around-balance*))
      (ok (> (count :enter *around-events*) 3))
      (ok (= (count :enter *around-events*) (count :cleanup *around-events*)
             (count :rollback *around-events*) (count :target *around-events*))))))
