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

(deftest invalid-run-limits-are-refused
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty timed ((value integer)) (integerp value))
    (dolist (options '((:timeout -1) (:trial-timeout 0) (:cleanup-timeout "slow")))
      (ok (handler-case (progn (cl-spec:run-property 'timed :options options) nil)
            (cl-spec:invalid-argument () t))))))
