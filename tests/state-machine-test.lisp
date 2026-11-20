;;;; tests/state-machine-test.lisp

(defpackage #:cl-spec/tests/state-machine-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defstate-machine #:check-state-machine
                #:defproperty #:defspec #:property-data #:run-property #:property-result-status
                #:property-result-explanation #:property-result-failure-signature
                #:trial-observation-status #:trial-observation-signature #:trial-observation-value
                #:trial-observation-explanation #:trial-observation-condition
                #:invalid-property-form #:invalid-argument #:spec-violation #:property-result-trials
                #:make-counterexample-artifact #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact #:counterexample-artifact-data
                #:recheck-counterexample #:*generator-backend*)
  (:import-from #:cl-spec/src/state-machine #:state-machine-property)
  (:import-from #:cl-spec/src/coverage
                #:definition-coverage-schema #:observe-coverage-dimension #:coverage-data)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/state-machine-test)

(deftest public-state-machine-protocol
  (dolist (name '("DEFSTATE-MACHINE" "CHECK-STATE-MACHINE"))
    (multiple-value-bind (symbol access) (find-symbol name :cl-spec)
      (ok (eq :external access))
      (ok (and symbol (fboundp symbol))))))

(defun model-meter (model command)
  (let ((next (if (eq :reset command) 0 (+ model (second command)))))
    (values next next)))

(defun target-meter (target command)
  (setf (car target) (if (eq :reset command) 0 (+ (car target) (second command))))
  (values target (car target)))

(defun register-meter (registry &key (make-model (constantly 0)) (make-target (lambda () (list 0)))
                                     (model-step #'model-meter) (target-step #'target-meter)
                                     enabled invariant (compare #'eql))
  (let ((*registry* registry))
    (defspec meter-command (or (member :reset) (tuple (member :add) (range integer 0 4))))
    (defstate-machine meter (commands meter-command :max-length 8)
      :model (funcall make-model) :target (funcall make-target)
      :model-step model-step :target-step target-step
      :enabled enabled :invariant invariant :compare compare
      :about (target-meter) :trials (:smoke 8 :normal 30))))

(deftest direct-sequences-use-fresh-state-and-command-payloads
  (let* ((registry (make-hash-table-registry)) (targets nil) (models 0) (calls nil)
         (machine (register-meter registry :make-model (lambda () (incf models) 0)
                                 :make-target (lambda () (car (push (list 0) targets)))
                                 :target-step (lambda (state command)
                                                (push command calls)
                                                (target-meter state command)))))
    (dolist (trace '(((:add 2) (:add 3) :reset) ((:add 1)) ()))
      (ok (eq :passed (trial-observation-status
                       (check-state-machine machine trace :registry registry)))))
    (ok (= models (length targets) 3))
    (ok (= 3 (length (remove-duplicates targets :test #'eq))))
    (ok (equal (reverse calls) '((:add 2) (:add 3) :reset (:add 1))))
    (ok (eq :state-machine (getf (property-data 'meter :registry registry) :kind)))
    (ok (eq :passed (property-result-status
                     (run-property 'meter :registry registry :profile :smoke :seed 2))))))

(deftest first-divergence-preserves-its-observations
  (let* ((calls 0) (registry (make-hash-table-registry))
         (machine (register-meter registry :target-step
                                  (lambda (target command)
                                    (incf calls)
                                    (multiple-value-bind (state result)
                                        (target-meter target command)
                                      (values state (if (eq :reset command) result (1+ result)))))))
         (observation (check-state-machine machine '(:reset (:add 2) (:add 3)) :registry registry))
         (detail (trial-observation-explanation observation)))
    (ok (eq :failed (trial-observation-status observation)))
    (ok (equal '(:state-machine :observation-mismatch :add)
               (trial-observation-signature observation)))
    (ok (= 2 calls))
    (ok (= 1 (getf detail :index)))
    (ok (equal '(:add 2) (getf detail :command)))
    (ok (= 2 (getf detail :expected)))
    (ok (= 3 (getf detail :actual)))
    (let ((result (run-property machine :registry registry :seed 2)))
      (ok (eq :failed (property-result-status result)))
      (ok (equal (trial-observation-signature observation)
                 (property-result-failure-signature result)))
      (ok (eq :add (first (getf (property-result-explanation result) :command)))))))

(deftest inapplicable-command-stops-before-either-step
  (let* ((models 0) (targets 0) (registry (make-hash-table-registry))
         (machine (register-meter registry
                                  :enabled (lambda (model command)
                                             (not (and (plusp model) (eq command :reset))))
                                  :model-step (lambda (state command)
                                                (incf models) (model-meter state command))
                                  :target-step (lambda (state command)
                                                 (incf targets) (target-meter state command))))
         (observation (check-state-machine machine '((:add 3) :reset (:add 1)) :registry registry)))
    (ok (eq :rejected (trial-observation-status observation)))
    (ok (= models targets 1))
    (ok (= 1 (getf (trial-observation-value observation) :index)))
    (ok (eq :reset (getf (trial-observation-value observation) :command)))))

(deftest invariant-runs-initially-and-after-agreement
  (let* ((registry (make-hash-table-registry)) (positions nil)
         (machine (register-meter registry :invariant (lambda (model target)
                                                        (push (list model (car target)) positions)
                                                        (< model 3))))
         (observed (check-state-machine machine '((:add 1) (:add 3) :reset) :registry registry)))
    (ok (equal (reverse positions) '((0 0) (1 1) (4 4))))
    (ok (equal (trial-observation-signature observed) '(:state-machine :invariant-violation :add)))
    (ok (= 1 (getf (trial-observation-explanation observed) :index)))
    (let* ((initial (register-meter registry :invariant (constantly nil)))
           (bad (check-state-machine initial nil :registry registry)))
      (ok (equal '(:state-machine :invariant-violation nil) (trial-observation-signature bad)))
      (ok (null (getf (trial-observation-explanation bad) :index))))))

(deftest callback-errors-identify-phase-and-command
  (let ((registry (make-hash-table-registry))
        (broken (lambda (&rest ignored) (declare (ignore ignored)) (error "callback failed"))))
    (dolist (entry '((:make-model :model-setup nil) (:make-target :target-setup nil)
                     (:enabled :enabled :add) (:model-step :model-step :add)
                     (:target-step :target-step :add) (:compare :compare :add)
                     (:invariant :invariant nil)))
      (destructuring-bind (option phase operation) entry
        (let* ((machine (apply #'register-meter registry (list option broken)))
               (observation (check-state-machine machine '((:add 2)) :registry registry)))
          (ok (eq :error (trial-observation-status observation)))
          (ok (typep (trial-observation-condition observation) 'simple-error))
          (ok (equal (list :state-machine :machine-error phase operation 'simple-error)
                     (trial-observation-signature observation))))))))

(deftest invalid-input-is-refused-before-initialization
  (let* ((started 0) (registry (make-hash-table-registry))
         (machine (register-meter registry :make-model (lambda () (incf started) 0)))
         (cycle (list :reset)))
    (setf (cdr cycle) cycle)
    (dolist (trace (list :reset '(:reset . :bad) cycle '(()) '((:add . 1)) '(3)))
      (ok (handler-case (progn (check-state-machine machine trace :registry registry) nil)
            (invalid-argument () t))))
    (dolist (trace '((:unknown) ((:add 5)) ((:add)) ((:add 1 2))))
      (ok (handler-case (progn (check-state-machine machine trace :registry registry) nil)
            (spec-violation () t))))
    (ok (handler-case (progn (check-state-machine machine nil :registrry registry) nil)
          (invalid-argument () t)))
    (let ((*registry* registry))
      (defproperty ordinary ((n integer)) (integerp n))
      (ok (handler-case (progn (check-state-machine 'ordinary nil) nil)
            (invalid-argument () t))))
    (ok (zerop started))))

(deftest invalid-declarations-refuse-missing-duplicate-or-unknown-options
  (let ((required '(:model 0 :target 0 :model-step #'model-meter :target-step #'target-meter)))
    (dolist (options (list (cddr required) (append required '(:target 7))
                           (append required '(:trials-typo (:smoke 1)))
                           (append required '(:invariant))))
      (ok (handler-case
              (progn (macroexpand-1 `(defstate-machine bad (commands (member :reset)) ,@options))
                     nil)
            (invalid-property-form () t))))))

(deftest invalid-machine-reinitialization-restores-executable-definition
  (let* ((registry (make-hash-table-registry)) (machine (register-meter registry))
         (bindings (cl-spec:property-arguments machine)))
    (dolist (initargs (list '(:arguments nil)
                            '(:arguments ((first (list-of meter-command))
                                          (second (list-of meter-command))))
                            '(:arguments ((commands meter-command)))
                            (list :arguments (list (list 'commands
                                                        (make-instance 'cl-spec/src/ir:list-of-spec))))
                            '(:kind :invariant) '(:kind nil)))
      (ok (handler-case
              (progn (apply #'reinitialize-instance machine :documentation "uncommitted" initargs)
                     nil)
            (invalid-property-form () t)))
      (ok (eq bindings (cl-spec:property-arguments machine)))
      (ok (eq :state-machine (cl-spec:property-kind machine)))
      (ok (null (cl-spec:property-documentation machine))))
    (ok (eq machine (cl-spec:validate-definition machine)))
    (ok (eq :passed (trial-observation-status
                     (check-state-machine machine '((:add 3) :reset) :registry registry))))
    (ok (eq :passed (property-result-status
                     (run-property machine :registry registry :profile :smoke :seed 2))))))

(deftest corrupt-machine-replacement-is-refused-before-registry-or-index-writes
  (let* ((registry (make-hash-table-registry)) (original (register-meter registry))
         (replacement (register-meter (make-hash-table-registry))))
    (setf (slot-value replacement 'cl-spec/src/property::arguments) nil)
    (ok (handler-case (progn (cl-spec:validate-definition replacement) nil)
          (invalid-property-form () t)))
    (ok (handler-case
            (progn (cl-spec:registry-register-property registry 'meter replacement
                                                       :targets '(wrong-target) :tags '(:wrong))
                   nil)
          (invalid-property-form () t)))
    (ok (eq original (cl-spec:find-property 'meter registry)))
    (ok (equal '(meter) (cl-spec:properties-for 'target-meter registry)))
    (ok (null (cl-spec:properties-for 'wrong-target registry)))
    (ok (null (cl-spec:properties-with-tag :wrong registry)))))

(deftest artifacts-recheck-agreement-violation-and-error-without-generation
  (let ((registry (make-hash-table-registry)))
    (dolist (callback (list (list :compare (constantly nil))
                            (list :invariant (constantly nil))
                            (list :model-step (lambda (state command)
                                                (declare (ignore state command))
                                                (error "broken model")))))
      (let* ((machine (apply #'register-meter registry callback))
             (result (run-property machine :registry registry :seed 2))
             (saved (deserialize-counterexample-artifact
                     (serialize-counterexample-artifact (make-counterexample-artifact result))))
             (*generator-backend* nil)
             (data (counterexample-artifact-data saved)))
        (ok (eq :same-failure (getf (recheck-counterexample saved :registry registry
                                                            :state-policy :stateless) :status)))
        (ok (equal (property-result-failure-signature result)
                   (getf (getf data (getf data :selection)) :signature)))
        (register-meter registry :make-target (lambda () (error "different setup failure")))
        (ok (eq :different-failure (getf (recheck-counterexample saved :registry registry
                                                                 :state-policy :stateless) :status)))
        (register-meter registry)
        (ok (eq :passed (getf (recheck-counterexample saved :registry registry
                                                      :state-policy :stateless) :status)))))))

(deftest each-generated-or-shrunk-trace-gets-independent-live-states
  (let* ((models nil) (targets nil) (registry (make-hash-table-registry))
         (machine (register-meter registry
                                  :make-model (lambda () (car (push (list 0) models)))
                                  :make-target (lambda () (car (push (list 0) targets)))
                                  :model-step #'target-meter :compare (constantly nil)))
         (result (run-property machine :seed 2 :registry registry)))
    (ok (eq :failed (property-result-status result)))
    (ok (= (length models) (length targets)))
    (ok (> (length models) (property-result-trials result)))
    (ok (= (+ (length models) (length targets))
           (length (remove-duplicates (append models targets) :test #'eq))))))

(deftest step-must-supply-state-and-observation
  (let ((registry (make-hash-table-registry)))
    (dolist (entry (list (list :model-step (constantly 1))
                         (list :target-step (lambda (&rest args) (declare (ignore args)) (values)))
                         (list :target-step (lambda (&rest args)
                                               (declare (ignore args)) (values 1 2 3)))))
      (let* ((machine (apply #'register-meter registry entry))
             (observation (check-state-machine machine '(:reset) :registry registry)))
        (ok (eq :error (trial-observation-status observation)))
        (ok (typep (trial-observation-condition observation) 'program-error))
        (ok (eq (first entry) (getf (trial-observation-explanation observation) :phase)))))))

(defclass coverage-meter (state-machine-property) ())

(defmethod definition-coverage-schema ((machine coverage-meter) registry options)
  ;; The built-in plist provider leaves a list of commands unexpanded. Supply
  ;; one observable dimension through the public provider protocol for this test.
  (declare (ignore registry options))
  (list :schema-version 1 :record-kind :coverage-schema :dimensions
        (list (list :id :trace :kind :test-trace :buckets '(:trace) :targetable nil))))

(defmethod observe-coverage-dimension ((kind (eql :test-trace)) dimension bindings)
  (declare (ignore dimension bindings))
  '(:trace))

(deftest coverage-measures-first-admission-and-target-call-independent-of-verdict
  (dolist (scenario '((:pass :passed 1 1 1) (:mismatch :failed 1 1 1)
                      (:reject-first :skipped 0 0 0) (:reject-second :skipped 1 1 0)
                      (:model-error :error 1 0 0) (:target-error :error 1 1 0)))
    (destructuring-bind (mode status pre target checked) scenario
      (let* ((*registry* (make-hash-table-registry))
             (machine (defstate-machine coverage-machine
                          (commands (member :tick) :min-length 2 :max-length 2)
                        :model 0 :target 0 :trials (:normal 1)
                        :enabled (lambda (model command)
                                   (declare (ignore command))
                                   (case mode (:reject-first nil) (:reject-second (zerop model))
                                         (otherwise t)))
                        :model-step (lambda (model command)
                                      (declare (ignore command))
                                      (when (eq mode :model-error) (error "model failed"))
                                      (values (1+ model) model))
                        :target-step (lambda (target command)
                                       (declare (ignore command))
                                       (when (eq mode :target-error) (error "target failed"))
                                       (values (1+ target) (if (eq mode :mismatch) -1 target)))))
             (result (run-property (change-class machine 'coverage-meter) :seed 2
                                   :options '(:coverage (:mode :observe))))
             (stages (getf (first (getf (coverage-data result) :dimensions)) :stages)))
        (flet ((count-stage (name)
                 (getf (find name stages :key (lambda (stage) (getf stage :stage)))
                       :observed-trials)))
          (ok (eq status (property-result-status result)))
          (ok (eql pre (count-stage :pre-admitted)))
          (ok (eql target (count-stage :target-observed)))
          (ok (eql checked (count-stage :checked))))))))
