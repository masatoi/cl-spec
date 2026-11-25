;;;; tests/time-limits-test.lisp
(defpackage #:cl-spec/tests/time-limits-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/generator #:run-generated-test)
  (:import-from #:cl-spec/src/property-runner #:property-result-trial-report)
  (:import-from #:cl-spec/src/backends/check-it))
(in-package #:cl-spec/tests/time-limits-test)

#+(and sbcl sb-thread)
(deftest property-run-timeout-preserves-completed-trials
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (calls 0))
    (cl-spec:defproperty slow-second ((value integer))
      (declare (ignore value))
      (when (= (incf calls) 2) (sleep 1))
      t)
    (let* ((result (cl-spec:run-property 'slow-second :seed 9
                                         :options '(:timeout 1/5 :trial-timeout 2
                                                    :coverage (:mode :observe))))
           (data (cl-spec:result-data result)))
      (ok (eq :timeout (getf data :status)))
      (ok (equal '(:limit :run :trial 2 :phase :property) (getf data :timeout)))
      (ok (= 2 calls))
      (ok (= 1 (getf data :trials) (getf (getf data :coverage) :trials)))
      (ok (= 1 (getf (property-result-trial-report result) :checked))))))

#+(and sbcl sb-thread)
(defun sleeping-target ()
  (handler-case (sleep 1) (error () :caught))
  t)

#+(and sbcl sb-thread)
(deftest check-function-replays-time-limits
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (options (list :trial-timeout 1/10 :timeout 3)))
    (cl-spec:defspec-function sleeping-target (:args) (:returns (member t)))
    (let* ((first (cl-spec:check-function 'sleeping-target :trials 2 :seed 11 :options options))
           (first-data (cl-spec:result-data first)))
      (setf (getf options :trial-timeout) 2)
      (let ((second (cl-spec:result-data (cl-spec:check-function 'sleeping-target :seed first))))
        (ok (and (eq :timeout (getf first-data :status))
                 (eq :timeout (getf second :status))))
        (ok (equal '(:limit :trial :trial 1 :phase :target) (getf first-data :timeout)))
        (ok (equal (getf first-data :timeout) (getf second :timeout)))
        (ok (equal '(:trial-timeout 1/10 :timeout 3) (getf second :options)))))))

#+(and sbcl sb-thread)
(deftest timeout-names-the-state-frame-observer-phase
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (slow-snapshot nil)
        (snapshots 0))
    (cl-spec:register-state-observer
     :rows :version 1 :source 'snapshot-phase-probe
     :snapshot (lambda ()
                 (when (= (incf snapshots) slow-snapshot) (sleep 1))
                 0)
     :compare (lambda (before after)
                (declare (ignore before after))
                nil)
     :project (lambda (snapshot key)
                (declare (ignore key))
                (values snapshot t)))
    (cl-spec:defspec-function identity
      (:args (value (member 7)))
      (:returns integer)
      (:modifies (:rows)))
    (loop for snapshot in '(1 2)
          for phase in '(:capture :state-post)
          do (setf slow-snapshot snapshot snapshots 0)
             (let* ((result (cl-spec:check-function
                             'identity :trials 1 :seed 41
                             :options '(:timeout 3 :trial-timeout 1/10)))
                    (data (cl-spec:result-data result)))
               (ok (eq :timeout (getf data :status)))
               (ok (eq phase (getf (getf data :timeout) :phase)))))))

#+(and sbcl sb-thread)
(deftest shrink-timeout-retains-the-latest-accepted-counterexample
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defgenerator timed-integer ()
      (:shrink (value)
        (if (= value 20) (list 10) (progn (sleep 1) nil)))
      20)
    (cl-spec:defspec shrink-input integer (:generator timed-integer))
    (cl-spec:defproperty shrinking ((value shrink-input)) (< value 0))
    (let* ((result (cl-spec:run-property 'shrinking :seed 6 :options '(:timeout 1/5)))
           (data (cl-spec:result-data result)))
      (ok (eq :timeout (getf data :status)))
      (ok (equal '(:limit :run :trial 1 :phase :shrinking) (getf data :timeout)))
      (ok (equal '(value 20) (getf data :counterexample)))
      (ok (equal '(value 10) (getf data :shrunk-counterexample)))
      (ok (= 1 (getf (property-result-trial-report result) :checked))))))

#+(and sbcl sb-thread)
(defun counterexample-target (&rest arguments)
  (declare (ignore arguments))
  0)

#+(and sbcl sb-thread)
(deftest function-shrink-timeout-preserves-original-and-accepted-bindings
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (calls 0))
    (cl-spec:defspec-function counterexample-target
      (:args (left integer) (right integer))
      (:returns integer)
      (:post (progn (when (> (incf calls) 2) (sleep 1)) nil)))
    (let* ((result (cl-spec:check-function 'counterexample-target :trials 1 :seed 42
                                          :options '(:timeout 1/5)))
           (data (cl-spec:result-data result)))
      (ok (equal '(:limit :run :trial 1 :phase :shrinking) (getf data :timeout)))
      (ok (eq :used (getf data :shrunk-outcome)))
      (ok (equal '(left -4 right 9) (getf data :counterexample)))
      (ok (equal '(left -2 right 9) (getf data :shrunk-counterexample))))))

#+(and sbcl sb-thread)
(deftest function-shrink-timeout-preserves-optional-rest-and-key-bindings
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defgenerator mixed-call-arguments ()
      (:shrink (arguments)
        (if (= (first arguments) 20)
            (list (list 10))
            (progn (sleep 1) nil)))
      (list 20 11 :limit 3))
    (cl-spec:defspec-function counterexample-target
      (:args (required integer)
             &optional (optional integer optional-p)
             &rest (tail (list-of t))
             &key ((:limit limit) integer limit-p))
      (:args-generator mixed-call-arguments)
      (:returns integer)
      (:post nil))
    (let* ((result (cl-spec:check-function 'counterexample-target :trials 1 :seed 42
                                          :options '(:timeout 1/5)))
           (data (cl-spec:result-data result)))
      (ok (equal '(:limit :run :trial 1 :phase :shrinking) (getf data :timeout)))
      (ok (eq :used (getf data :shrunk-outcome)))
      (ok (equal '(required 20 optional 11 optional-p t tail (:limit 3) limit 3 limit-p t)
                 (getf data :counterexample)))
      (ok (equal '(required 10 optional nil optional-p nil tail nil limit nil limit-p nil)
                 (getf data :shrunk-counterexample))))))

#+(and sbcl sb-thread)
(deftest state-machine-shrink-timeout-preserves-the-command-counterexample
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (calls 0))
    (cl-spec:defstate-machine slow-meter
        (commands (tuple (member :advance) (range integer 1 100)) :min-length 1 :max-length 5)
      :model 0 :target 1
      :model-step (lambda (state command) (declare (ignore command)) (values state state))
      :target-step (lambda (state command)
                     (declare (ignore command))
                     (when (> (incf calls) 1) (sleep 1))
                     (values state state))
      :trials (:normal 1))
    (let* ((result (cl-spec:run-property 'slow-meter :seed 42 :options '(:timeout 1/5)))
           (data (cl-spec:result-data result))
           (arguments (getf (getf data :failure) :arguments)))
      (ok (equal '(:limit :run :trial 1 :phase :shrinking) (getf data :timeout)))
      (ok arguments)
      (ok (equal (list 'commands (first arguments)) (getf data :counterexample))))))

#+(and sbcl sb-thread)
(deftest fixture-cleanup-has-its-own-timeout-and-unwinds-the-wrapper
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (cleanups 0) (wrapper-exits 0) (slow-cleanup nil))
    (cl-spec:defspec-function sleeping-target
      (:args)
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (incf wrapper-exits)))
        (:setup (context) (declare (ignore recipe context)) nil)
        (:cleanup (context) (declare (ignore recipe context))
          (incf cleanups)
          (when slow-cleanup (sleep 1))))
      (:returns (member t)))
    (dolist (cleanup-status '(:completed :timeout))
      (setf slow-cleanup (eq cleanup-status :timeout))
      (let* ((data (cl-spec:result-data
                    (cl-spec:check-function 'sleeping-target :trials 1 :seed 3
                     :options '(:trial-timeout 1/10 :cleanup-timeout 1/10))))
             (timeout (getf data :timeout)))
        (ok (eq :timeout (getf data :status)))
        (ok (eql 1 (getf timeout :trial)))
        (ok (eq :target (getf timeout :phase)))
        (ok (eq :trial (getf timeout :limit)))
        (ok (eq cleanup-status (getf (getf timeout :cleanup) :status)))))
    (ok (= 2 cleanups wrapper-exits))))

#+(and sbcl sb-thread)
(deftest generation-timeout-does-not-count-a-trial
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (property-ran nil) (draw-finished nil))
    (cl-spec:defgenerator slow-draw ()
      (sleep 1)
      (setf draw-finished t)
      7)
    (cl-spec:defspec slow-input integer (:generator slow-draw))
    (cl-spec:defproperty timed-draw ((value slow-input))
      (declare (ignore value))
      (setf property-ran t))
    (let ((data (cl-spec:result-data
                 (cl-spec:run-property 'timed-draw :seed 2 :options '(:trial-timeout 1/10)))))
      (ok (eq :timeout (getf data :status)))
      (ok (equal '(:limit :trial :trial 1 :phase :generation) (getf data :timeout)))
      (ok (zerop (getf data :trials)))
      (ok (eq :interrupted (getf (getf data :generation-report) :termination)))
      (ok (not (or property-ran draw-finished))))))

#+(and sbcl sb-thread)
(deftest cleanup-can-expire-after-a-successful-fixture-call
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (target-ran nil) (cleanup-finished nil))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe integer))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe))
          (sleep 1)
          (setf cleanup-finished t)))
      (:returns (satisfies integerp))
      (:post (setf target-ran (integerp result))))
    (let* ((data (cl-spec:result-data
                  (cl-spec:check-function 'identity :trials 1 :seed 2
                   :options '(:cleanup-timeout 1/10 :coverage (:mode :observe)))))
           (timeout (getf data :timeout)))
      (ok target-ran)
      (ok (not cleanup-finished))
      (ok (eq :timeout (getf data :status)))
      (ok (eq :fixture-cleanup (getf timeout :phase)))
      (ok (eq :cleanup (getf timeout :limit)))
      (ok (eq :timeout (getf (getf timeout :cleanup) :status)))
      (ok (zerop (getf (getf data :coverage) :trials))))))

(defclass legacy-time-backend () ())

(defmethod run-generated-test ((backend legacy-time-backend) property &key options)
  (declare (ignore property options))
  (error "timed execution must not invoke a legacy backend"))

#+(and sbcl sb-thread)
(deftest an-outer-deadline-still-bounds-a-nested-fixture-cleanup
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (cleanup-started nil) (cleanup-finished nil))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe integer))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe))
          (setf cleanup-started t)
          (sleep 1)
          (setf cleanup-finished t)))
      (:returns integer))
    (cl-spec:defproperty nested-run ((value integer))
      (declare (ignore value))
      (cl-spec:check-function 'identity :trials 1 :seed 3
        :options '(:cleanup-timeout 2))
      t)
    (let* ((outer (cl-spec:run-property 'nested-run :seed 2 :options '(:timeout 1/4)))
           (data (cl-spec:result-data outer))
           (timeout (getf data :timeout)))
      (ok cleanup-started)
      (ok (not cleanup-finished))
      (ok (eq :timeout (getf data :status)))
      (ok (eq :property (getf timeout :phase))))))

#+(and sbcl sb-thread)
(deftest nested-fixtures-use-their-own-cleanup-limits
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (nested-check nil) (nested-timeout nil)
        (cleanup-delay 1/8) (cleanup-started nil) (cleanup-finished nil) (wrapper-exits 0))
    (cl-spec:defspec-function identity
      (:args (value integer))
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (incf wrapper-exits)))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe))
          (setf cleanup-started t)
          (sleep cleanup-delay)
          (setf cleanup-finished t)))
      (:returns integer))
    (flet ((direct ()
             (eq :passed (getf (cl-spec:fixture-check-data
                                (cl-spec:check-fixture 'identity 1)) :status)))
           (run-outer (options)
             (cl-spec:result-data (cl-spec:run-property 'outer-fixture :seed 2
                                                       :options options))))
      (cl-spec:defproperty inner-fixture ()
        (:trials (:normal 1))
        (direct))
      (cl-spec:defproperty outer-fixture ()
        (:trials (:normal 1))
        (funcall nested-check))
      (let ((checks (list #'direct
                          (lambda ()
                            (eq :passed (cl-spec:property-result-status
                                         (cl-spec:check-function 'identity :trials 1 :seed 3))))
                          (lambda ()
                            (eq :passed (cl-spec:property-result-status
                                         (cl-spec:run-property 'inner-fixture :seed 4)))))))
        (dolist (limit '(:timeout :trial-timeout))
          (dolist (check checks)
            (setf nested-check check cleanup-finished nil wrapper-exits 0)
            (let ((data (run-outer (list limit 2 :cleanup-timeout 1/40))))
              (ok (eq :passed (getf data :status)))
              (ok (null (getf data :timeout)))
              (ok cleanup-finished)
              (ok (= wrapper-exits 1))))
          (setf nested-check #'direct cleanup-started nil cleanup-finished nil
                wrapper-exits 0 cleanup-delay 1/2)
          (let* ((data (run-outer (list limit 1/5 :cleanup-timeout 1)))
                 (timeout (getf data :timeout)))
            (ok (eq :timeout (getf data :status)))
            (ok (equal (list :limit (ecase limit (:timeout :run) (:trial-timeout :trial))
                             :trial 1 :phase :property)
                       timeout))
            (ok cleanup-started)
            (ok (not cleanup-finished))
            (ok (= wrapper-exits 1)))
          (setf cleanup-delay 1/8)))
      (setf cleanup-finished nil wrapper-exits 0
            nested-check
            (lambda ()
              (let ((data (cl-spec:result-data
                           (cl-spec:check-function 'identity :trials 1 :seed 3
                             :options '(:cleanup-timeout 1/40)))))
                (setf nested-timeout (getf data :timeout))
                (eq :timeout (getf data :status)))))
      (ok (eq :passed (getf (run-outer '(:timeout 2)) :status)))
      (ok (eq :fixture-cleanup (getf nested-timeout :phase)))
      (ok (eq :cleanup (getf nested-timeout :limit)))
      (ok (equal '(:status :timeout :limit :cleanup) (getf nested-timeout :cleanup)))
      (ok (not cleanup-finished))
      (ok (= wrapper-exits 1)))))

#+(and sbcl sb-thread)
(deftest enclosing-cleanup-timeout-unwinds-an-untimed-around-fixture
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (events nil))
    (cl-spec:defspec-function identity
      (:args (value integer)) (:returns integer)
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (push :inner-wrapper events)))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe))
          (push :inner-cleanup events)
          (sleep 1/3)
          (push :inner-finished events))))
    (cl-spec:defspec-function list
      (:args) (:returns (member nil))
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (push :outer-wrapper events)))
        (:setup (context) (declare (ignore context recipe)) nil)
        (:cleanup (context) (declare (ignore context recipe))
          (push :outer-cleanup events)
          (cl-spec:check-fixture 'identity 1)
          (push :outer-finished events))))
    (let* ((result (cl-spec:check-function 'list :trials 1 :seed 1
                                          :options '(:cleanup-timeout 1/10)))
           (data (cl-spec:result-data result))
           (timeout (getf data :timeout)))
      (ok (eq :timeout (getf data :status)))
      (ok (eq :fixture-cleanup (getf timeout :phase)))
      (ok (eq :cleanup (getf timeout :limit)))
      (ok (equal '(:status :timeout :limit :cleanup) (getf timeout :cleanup)))
      (ok (equal '(:outer-cleanup :inner-cleanup :inner-wrapper :outer-wrapper)
                 (reverse events))))))

#+(and sbcl sb-thread)
(deftest enclosing-run-timeout-bounds-cancellation-of-an-untimed-fixture
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (entry-point nil) (interrupt-in nil) (events nil))
    (cl-spec:defspec-function sleeping-target
      (:args) (:returns (member t))
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe (member 0)))
        (:around (run) (unwind-protect (funcall run) (push :rollback events)))
        (:setup (context) (declare (ignore context recipe))
          (push :setup events)
          (case interrupt-in
            (:setup (sleep 1/4))
            (:caller (throw 'cancel-fixture-check :caller)))
          (push :setup-finished events)
          nil)
        (:cleanup (context) (declare (ignore context recipe))
          (push :cleanup events)
          (sleep 1/3)
          (push :cleanup-finished events))))
    (cl-spec:defproperty interrupting-nested-fixture ()
      (:trials (:normal 1))
      (ecase entry-point
        (:direct (cl-spec:check-fixture 'sleeping-target 0))
        (:generated (cl-spec:check-function 'sleeping-target :trials 1 :seed 2)))
      (push :outer-continued events)
      t)
    (dolist (entry '(:direct :generated))
      (dolist (phase '(:setup :target))
        (dolist (limit '(:timeout :trial-timeout))
          (setf interrupt-in phase entry-point entry events nil)
          (let* ((result (cl-spec:run-property 'interrupting-nested-fixture :seed 1
                            :options (list limit 1/10 :cleanup-timeout 1/20)))
                 (data (cl-spec:result-data result))
                 (timeout (getf data :timeout)))
            (ok (eq :timeout (getf data :status)))
            (ok (eq (if (eq limit :timeout) :run :trial) (getf timeout :limit)))
            (ok (eq :property (getf timeout :phase)))
            (ok (eql 1 (getf timeout :trial)))
            (ok (equal '(:status :timeout :limit :cleanup) (getf timeout :cleanup)))
            (ok (equal (if (eq phase :setup)
                           '(:setup :cleanup :rollback)
                           '(:setup :setup-finished :cleanup :rollback))
                       (reverse events)))))))
    (setf interrupt-in :caller entry-point :direct events nil)
    (ok (eq :caller
            (catch 'cancel-fixture-check
              (cl-spec:run-property 'interrupting-nested-fixture :seed 1
                                    :options '(:timeout 2 :cleanup-timeout 1/20)))))
    (ok (equal '(:setup :cleanup :cleanup-finished :rollback) (reverse events)))))

#+(and sbcl sb-thread)
(deftest pending-enclosing-timeout-keeps-separate-nested-cleanup-results
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (inner-result nil) (inner-cap nil) (inner-deadline nil)
        (defer-cleanup-p nil) (events nil))
    (cl-spec:defspec-function identity
      (:args (value integer)) (:returns integer)
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (push :inner-wrapper events)))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe))
          (push :inner-cleanup events)
          (if defer-cleanup-p
              (sb-sys:without-interrupts (sleep 1/6))
              (sleep 1/4))
          (push :inner-finished events))))
    (cl-spec:defspec-function sleeping-target
      (:args) (:returns (member t))
      (:fixture
        (:isolation :around) (:version 1) (:recipe (recipe integer))
        (:around (run) (unwind-protect (funcall run) (push :outer-wrapper events)))
        (:setup (context) (declare (ignore context recipe)) nil)
        (:cleanup (context) (declare (ignore context recipe))
          (push :outer-cleanup events)
          (setf inner-result (cl-spec:check-function 'identity :trials 1 :seed 1
                              :options (list :cleanup-timeout inner-cap
                                             :timeout inner-deadline)))
          (push :outer-finished events))))
    (loop for (outer-cap current-inner-cap current-inner-timeout defer-p inner-first-p)
          in '((1 1/40 nil nil t)
               (1/6 1 nil nil nil)
               (1/10 1/25 nil t nil)
               (1/10 1/25 3/40 t nil))
          do (setf inner-cap current-inner-cap inner-deadline current-inner-timeout
                   defer-cleanup-p defer-p inner-result nil events nil)
             (let* ((result (cl-spec:check-function 'sleeping-target :trials 1 :seed 2
                              :options (list :timeout 1/5 :cleanup-timeout outer-cap)))
                    (data (cl-spec:result-data result))
                    (timeout (getf data :timeout)))
               (ok (eq :timeout (getf data :status)))
               (ok (eq :target (getf timeout :phase)))
               (ok (eq :run (getf timeout :limit)))
               (ok (eql 1 (getf timeout :trial)))
               (if inner-first-p
                   (let* ((inner-data (when inner-result (cl-spec:result-data inner-result)))
                          (inner-timeout (getf inner-data :timeout)))
                     (ok (eq :timeout (getf inner-data :status)))
                     (ok (eq :fixture-cleanup (getf inner-timeout :phase)))
                     (ok (eq :cleanup (getf inner-timeout :limit)))
                     (ok (equal '(:status :timeout :limit :cleanup)
                                (getf inner-timeout :cleanup)))
                     (ok (equal '(:status :completed) (getf timeout :cleanup)))
                     (ok (equal '(:outer-cleanup :inner-cleanup :inner-wrapper
                                  :outer-finished :outer-wrapper)
                                (reverse events))))
                   (progn
                     (ok (null inner-result))
                     (ok (equal '(:status :timeout :limit :cleanup) (getf timeout :cleanup)))
                     (ok (equal '(:outer-cleanup :inner-cleanup :inner-wrapper :outer-wrapper)
                                (reverse events)))))))))

(deftest timing-options-are-refused-on-an-unparticipating-backend
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (cl-spec:*generator-backend* (make-instance 'legacy-time-backend)))
    (cl-spec:defproperty unsupported-timer ((value integer))
      (:trials (:normal 1))
      (integerp value))
    (ok (handler-case
            (progn (cl-spec:run-property 'unsupported-timer :options '(:timeout 1)) nil)
          (cl-spec:invalid-argument () t)))))

#+(and sbcl sb-thread)
(defclass slow-run-registry (cl-spec/src/registry::hash-table-registry) ())

#+(and sbcl sb-thread)
(defvar *lookup-delay* nil)

#+(and sbcl sb-thread)
(defmethod cl-spec/src/registry:registry-find-property :around ((registry slow-run-registry) name)
  (declare (ignore name))
  (when *lookup-delay* (sleep *lookup-delay*))
  (call-next-method))

#+(and sbcl sb-thread)
(defmethod cl-spec/src/registry:registry-find-function-spec :around
    ((registry slow-run-registry) name)
  (declare (ignore name))
  (when *lookup-delay* (sleep *lookup-delay*))
  (call-next-method))

#+(and sbcl sb-thread)
(deftest whole-run-limit-includes-registry-lookups
  (let ((cl-spec:*registry* (make-instance 'slow-run-registry))
        (property-ran nil) (function-ran nil))
    (cl-spec:defproperty lookup-property ((x integer))
      (declare (ignore x))
      (setf property-ran t))
    (cl-spec:defspec-function identity (:args (x integer)) (:returns integer)
      (:post (progn (setf function-ran t) t)))
    (let* ((*lookup-delay* 1/4)
           (options '(:timeout 1/20))
           (property (cl-spec:result-data
                      (cl-spec:run-property 'lookup-property :seed 4 :options options)))
           (function (cl-spec:result-data
                      (cl-spec:check-function 'identity :trials 1 :seed 4 :options options))))
      (dolist (data (list property function))
        (ok (eq :timeout (getf data :status)))
        (ok (equal '(:limit :run :trial 1 :phase :preparation) (getf data :timeout)))
        (ok (zerop (getf data :trials)))
        (ok (equal options (getf data :options)))
        (ok (eql 4 (getf data :seed))))
      (ok (eq :property (getf property :entity-kind)))
      (ok (eq :function-spec (getf function :entity-kind)))
      (ok (not (or property-ran function-ran))))))

#+(and sbcl sb-thread)
(deftest preparation-and-execution-share-the-run-deadline
  (let ((cl-spec:*registry* (make-instance 'slow-run-registry))
        (started nil) (finished nil))
    (cl-spec:defproperty shared-deadline ((x integer))
      (:trials (:normal 1))
      (declare (ignore x))
      (setf started t)
      (sleep 1/4)
      (setf finished t))
    (let* ((*lookup-delay* 1/4)
           (result (cl-spec:run-property 'shared-deadline :seed 4 :options '(:timeout 2/5)))
           (data (cl-spec:result-data result)))
      (ok started)
      (ok (not finished))
      (ok (equal '(:limit :run :trial 1 :phase :property) (getf data :timeout))))))

#+(and sbcl sb-thread)
(defvar *delay-shrink-filter* nil)

#+(and sbcl sb-thread)
(defun slow-first-shrink-filter (value)
  (when *delay-shrink-filter*
    (setf *delay-shrink-filter* nil)
    (sleep 1/4))
  (integerp value))

#+(and sbcl sb-thread)
(deftest trial-limit-includes-native-candidate-prefilters
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*delay-shrink-filter* nil))
    (cl-spec:defproperty filtered-shrink ((x (and integer (satisfies slow-first-shrink-filter))))
      (:trials (:normal 1))
      (declare (ignore x))
      (setf *delay-shrink-filter* t)
      nil)
    (let* ((result (cl-spec:run-property 'filtered-shrink :seed 42
                                       :options '(:trial-timeout 1/20)))
           (data (cl-spec:result-data result)))
      (ok (eq :timeout (getf data :status)))
      (ok (equal '(:limit :trial :trial 1 :phase :shrinking) (getf data :timeout)))
      (ok (getf data :counterexample))
      (ok (null (getf data :shrunk-counterexample))))))

#+(and sbcl sb-thread)
(deftest inner-cleanup-keeps-its-shorter-limit-during-outer-timeout
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (started nil) (finished nil))
    (cl-spec:defspec-function sleeping-target
      (:args) (:returns (member t))
      (:fixture
        (:isolation :fresh) (:version 1) (:recipe (recipe integer))
        (:setup (context) (declare (ignore recipe context)) nil)
        (:cleanup (context) (declare (ignore recipe context))
          (setf started t)
          (sleep 1/5)
          (setf finished t))))
    (cl-spec:defproperty outer-run ((x integer))
      (declare (ignore x))
      (cl-spec:check-function 'sleeping-target :trials 1 :seed 3
                             :options '(:cleanup-timeout 1/20))
      t)
    (let* ((result (cl-spec:run-property 'outer-run :seed 2
                                       :options '(:timeout 1/10 :cleanup-timeout 1)))
           (timeout (getf (cl-spec:result-data result) :timeout)))
      (ok started)
      (ok (not finished))
      (ok (eq :run (getf timeout :limit)))
      (ok (eq :property (getf timeout :phase)))
      (ok (equal '(:status :timeout :limit :cleanup) (getf timeout :cleanup))))))

#+(and sbcl sb-thread)
(deftest state-post-deadline-reports-the-state-post-phase
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (x integer)) (:returns integer)
      (:state-post (progn (sleep 1/4) t)))
    (let* ((result (cl-spec:check-function 'identity :trials 1 :seed 5
                                         :options '(:trial-timeout 1/20)))
           (data (cl-spec:result-data result)))
      (ok (eq :timeout (getf data :status)))
      (ok (equal '(:limit :trial :trial 1 :phase :state-post) (getf data :timeout))))))

#+(and sbcl sb-thread)
(defclass slow-counterexample-property (cl-spec:property) ())

#+(and sbcl sb-thread)
(defvar *slow-projection-value* nil)

#+(and sbcl sb-thread)
(defvar *counterexample-projections* nil)

#+(and sbcl sb-thread)
(defmethod cl-spec/src/property:property-named-arguments :around
    ((property slow-counterexample-property) arguments)
  (push (first arguments) *counterexample-projections*)
  (when (eql *slow-projection-value* (first arguments))
    (sleep 1/4))
  (call-next-method))

#+(and sbcl sb-thread)
(deftest run-limit-includes-counterexample-projection
  (let* ((*slow-projection-value* 7)
         (*counterexample-projections* nil)
         (property (make-instance 'slow-counterexample-property
                                  :name 'slow-projection :arguments '((x (member 7)))
                                  :function (constantly nil) :trials '(:normal 1)
                                  :metadata '(:shrink nil)))
         (data (cl-spec:result-data
                (cl-spec:run-property property :seed 2 :options '(:timeout 1/10)))))
    (ok (eq :timeout (getf data :status)))
    (ok (equal '(:limit :run :trial 1 :phase :finalization) (getf data :timeout)))
    (ok (eql 1 (getf data :trials)))
    (ok (equal '(7) *counterexample-projections*))
    (ok (equal '(7) (getf data :counterexample)))
    (ok (equal '(7) (getf (getf data :failure) :arguments)))
    (ok (>= (getf data :elapsed) 1/20))))

#+(and sbcl sb-thread)
(deftest projection-timeout-preserves-an-earlier-named-counterexample
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*slow-projection-value* 10)
        (*counterexample-projections* nil))
    (cl-spec:defgenerator projected-integer ()
      (:shrink (value) (when (= value 20) (list 10)))
      20)
    (cl-spec:defspec projected-input integer (:generator projected-integer))
    (let* ((property (make-instance 'slow-counterexample-property
                                    :name 'projected-shrink :arguments '((x projected-input))
                                    :function (constantly nil) :trials '(:normal 1)))
           (data (cl-spec:result-data
                  (cl-spec:run-property property :seed 2 :options '(:timeout 1/10)))))
      (ok (eq :timeout (getf data :status)))
      (ok (eq :finalization (getf (getf data :timeout) :phase)))
      (ok (equal '(10 20) *counterexample-projections*))
      (ok (equal '(x 20) (getf data :counterexample)))
      (ok (equal '(10) (getf data :shrunk-counterexample)))
      (ok (equal '(10) (getf (getf data :shrunk-failure) :arguments))))))

#+(and sbcl sb-thread)
(defvar *argument-check-delay* nil)

#+(and sbcl sb-thread)
(defvar *argument-check-count* 0)

#+(and sbcl sb-thread)
(defmethod cl-spec/src/property:property-call-arguments-p :around
    ((property slow-counterexample-property) arguments)
  (declare (ignore arguments))
  (incf *argument-check-count*)
  (when *argument-check-delay* (sleep *argument-check-delay*))
  (call-next-method))

#+(and sbcl sb-thread)
(deftest run-limit-includes-counterexample-argument-verification
  (let* ((*argument-check-delay* 1/4)
         (*argument-check-count* 0)
         (*counterexample-projections* nil)
         (property (make-instance 'slow-counterexample-property
                                  :name 'slow-argument-check :arguments '((x (member 7)))
                                  :function (constantly nil) :trials '(:normal 1)
                                  :metadata '(:shrink nil)))
         (data (cl-spec:result-data
                (cl-spec:run-property property :seed 4 :options '(:timeout 1/10)))))
    (ok (eq :timeout (getf data :status)))
    (ok (eq :finalization (getf (getf data :timeout) :phase)))
    (ok (eql 1 (getf data :trials)))
    (ok (eql 1 *argument-check-count*))
    (ok (null *counterexample-projections*))
    (ok (null (getf data :counterexample)))
    (ok (equal '(7) (getf (getf data :failure) :arguments)))))

#+(and sbcl sb-thread)
(defvar *definition-description-delay* nil)

#+(and sbcl sb-thread)
(defmethod cl-spec/src/schema:definition-description :around
    ((property slow-counterexample-property))
  (when *definition-description-delay* (sleep *definition-description-delay*))
  (call-next-method))

#+(and sbcl sb-thread)
(deftest suite-preserves-the-identity-of-an-early-timeout
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (property (make-instance 'slow-counterexample-property
                                 :name 'slow-description :arguments '((x (member 7)))
                                 :function (constantly t) :trials '(:normal 1))))
    (cl-spec:register-property property)
    (let* ((*definition-description-delay* 1/4)
           (suite (cl-spec:check-contracts :names '((:property slow-description)) :seeds '(4)
                                           :options '(:timeout 1/10)))
           (entry (first (getf suite :entries)))
           (result (getf entry :result)))
      (ok (eq :timeout (getf entry :status)))
      (ok (eq :failed (getf entry :verdict)))
      (ok (eq 'slow-description (getf result :name)))
      (ok (eq :preparation (getf (getf result :timeout) :phase)))
      (ok (eql 0 (getf result :trials))))))

#+(and sbcl sb-thread)
(defvar *trial-reporting-delay* nil)

#+(and sbcl sb-thread)
(defmethod cl-spec/src/generator:backend-trial-reporting :around
    ((backend cl-spec/src/backends/check-it::check-it-backend))
  (when *trial-reporting-delay* (sleep *trial-reporting-delay*))
  (call-next-method))

#+(and sbcl sb-thread)
(deftest backend-capability-timeout-precedes-measurement
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (calls 0))
    (cl-spec:defproperty delayed-capability ((x (member 7)))
      (declare (ignore x))
      (incf calls))
    (let* ((*trial-reporting-delay* 1/4)
           (result (cl-spec:run-property 'delayed-capability :seed 4
                     :options '(:timeout 1/10 :coverage (:mode :observe))))
           (data (cl-spec:result-data result)))
      (ok (eq :timeout (getf data :status)))
      (ok (eq :preparation (getf (getf data :timeout) :phase)))
      (ok (= 0 calls (getf data :trials)))
      (ok (eq :not-collected (getf (getf data :coverage) :availability)))
      (ok (eq :not-collected (property-result-trial-report result))))))

(deftest invalid-run-limits-are-refused
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty timed ((value integer)) (integerp value))
    (dolist (options '((:timeout -1) (:trial-timeout 0) (:cleanup-timeout "slow")))
      (ok (handler-case (progn (cl-spec:run-property 'timed :options options) nil)
            (cl-spec:invalid-argument () t))))))

#+sbcl
(deftest nonfinite-run-limits-name-the-refused-option
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty finite-limit-probe ((x (member 1))) (eql x 1))
    (cl-spec:defspec-function identity (:args (x integer)) (:returns integer))
    (let ((entry-points
            (list (cons 'cl-spec:run-property
                        (lambda (options)
                          (cl-spec:run-property 'finite-limit-probe :options options)))
                  (cons 'cl-spec:check-function
                        (lambda (options)
                          (cl-spec:check-function 'identity :trials 1 :options options)))
                  (cons 'cl-spec:check-contracts
                        (lambda (options)
                          (cl-spec:check-contracts :names '((:property finite-limit-probe))
                                                   :options options))))))
      (dolist (positive-infinity '(sb-ext:single-float-positive-infinity
                                   sb-ext:double-float-positive-infinity))
        (let* ((infinity (symbol-value positive-infinity))
               (nan (sb-int:with-float-traps-masked (:invalid) (- infinity infinity))))
          (dolist (value (list infinity (- infinity) nan))
            (dolist (option '(:timeout :trial-timeout :cleanup-timeout))
              (dolist (entry entry-points)
                (ok (equal (list (car entry) option)
                           (handler-case (progn (funcall (cdr entry) (list option value)) nil)
                             (cl-spec:invalid-argument (condition)
                               (list (cl-spec/src/conditions:invalid-argument-operator condition)
                                     (cl-spec/src/conditions:invalid-argument-argument condition)))
                             (error (condition) (type-of condition)))))))))))))
