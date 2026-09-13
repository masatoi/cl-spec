;;;; tests/counterexample-function-test.lisp
(defpackage #:cl-spec/tests/counterexample-function-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/counterexample
                #:make-counterexample-artifact
                #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
                #:recheck-counterexample)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:register-function-spec #:check-function)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-status #:property-result-shrunk-evidence
                #:property-result-failure-evidence)
  (:import-from #:cl-spec/src/execution #:trial-observation-arguments)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:*generator-backend*)
  (:import-from #:cl-spec/src/generator-definition #:custom-generator #:register-generator)
  (:import-from #:cl-spec/src/backends/check-it))
(in-package #:cl-spec/tests/counterexample-function-test)

(defvar *behavior* :bad)
(defvar *calls* 0)
(defvar *inputs* nil)
(defvar *admit* t)

(defun artifact-target (&optional value)
  (incf *calls*)
  (push value *inputs*)
  (ecase *behavior*
    (:bad :wrong-return)
    (:fixed (or value 1))
    (:simple-error (error "expected diagnostic"))
    (:type-error (error 'type-error :datum :bad :expected-type 'integer))))

(defun contract (registry &rest options)
  (register-function-spec
    (apply #'make-instance 'function-spec :name 'artifact-target
           :source-form '(defspec-function artifact-target) options)
    registry))

(defun recheck-status (artifact registry)
  (getf (recheck-counterexample artifact :registry registry :state-policy :stateless) :status))

(deftest recheck-selects-original-and-accepted-shrunk-inputs
  (let* ((registry (make-hash-table-registry)) (*behavior* :bad) (*calls* 0) (*inputs* nil)
         (definition (contract registry :argument-specs '((x (range integer 10 10000)))
                                        :return-spec 'integer))
         (result (check-function definition :trials 1 :seed 42 :registry registry))
         (original (trial-observation-arguments (property-result-failure-evidence result)))
         (shrunk (property-result-shrunk-evidence result)))
    (ok shrunk)
    (when shrunk
      (let ((reduced (trial-observation-arguments shrunk)))
        (ok (< (first reduced) (first original)))
        (setf *inputs* nil)
        (ok (eq :same-failure
                (recheck-status (make-counterexample-artifact result :selection :original) registry)))
        (ok (equal (list (first original)) *inputs*))
        (setf *inputs* nil)
        (ok (eq :same-failure
                (recheck-status (make-counterexample-artifact result :selection :shrunk) registry)))
        (ok (equal (list (first reduced)) *inputs*))))))

(deftest direct-recheck-never-invokes-replaced-generator
  (let* ((registry (make-hash-table-registry)) (*behavior* :bad) (*calls* 0) (*inputs* nil)
         (draws 0)
         (generator (make-instance 'custom-generator :name 'saved-arguments
                                  :source-form '(defgenerator saved-arguments () (list 25))
                                  :function (lambda () (incf draws) (list 25)))))
    (register-generator generator registry)
    (let* ((definition (contract registry :argument-specs '((x integer))
                                          :argument-generator 'saved-arguments
                                          :return-spec 'integer))
           (artifact (make-counterexample-artifact
                       (check-function definition :trials 1 :seed 42 :registry registry)))
           (draw-count draws)
           (calls *calls*))
      (reinitialize-instance generator :function (lambda () (incf draws) (error "generator invoked")))
      (let ((*generator-backend* nil))
        (ok (eq :same-failure (recheck-status artifact registry))))
      (ok (= draw-count draws))
      (ok (= (1+ calls) *calls*)))))

(deftest recheck-distinguishes-new-error-type
  (let* ((registry (make-hash-table-registry)) (*behavior* :simple-error)
         (*calls* 0) (*inputs* nil)
         (definition (contract registry :argument-specs nil :return-spec 'integer))
         (artifact (make-counterexample-artifact
                     (check-function definition :trials 1 :seed 42 :registry registry))))
    (ok (eq :same-failure (recheck-status artifact registry)))
    (setf *behavior* :type-error)
    (ok (eq :different-failure (recheck-status artifact registry)))))

(deftest recheck-precondition-refuses-without-target-call
  (let* ((registry (make-hash-table-registry)) (*behavior* :bad) (*calls* 0) (*inputs* nil)
         (*admit* t)
         (definition (contract registry :argument-specs '((x integer)) :return-spec 'integer
                                        :preconditions '(*admit*)
                                        :precondition-function
                                        (lambda (x) (declare (ignore x)) *admit*)))
         (artifact (make-counterexample-artifact
                     (check-function definition :trials 1 :seed 42 :registry registry)))
         (calls *calls*))
    (setf *admit* nil)
    (ok (eq :precondition-rejected (recheck-status artifact registry)))
    (ok (= calls *calls*))))

(deftest signals-recheck-observes-required-error
  (let* ((registry (make-hash-table-registry)) (*behavior* :fixed) (*calls* 0) (*inputs* nil)
         (definition (contract registry :argument-specs nil :signal-spec 'simple-error))
         (result (check-function definition :trials 1 :seed 42 :registry registry))
         (artifact (make-counterexample-artifact result)))
    (ok (eq :failed (property-result-status result)))
    (ok (eq :same-failure (recheck-status artifact registry)))
    (setf *behavior* :simple-error)
    (ok (eq :passed (recheck-status artifact registry)))
    (setf *behavior* :type-error)
    (ok (eq :different-failure (recheck-status artifact registry)))))

(deftest returns-recheck-observes-target-repair
  (let* ((registry (make-hash-table-registry)) (*behavior* :bad) (*calls* 0) (*inputs* nil)
         (definition (contract registry :argument-specs '((x (range integer 10 100)))
                                        :return-spec 'integer))
         (result (check-function definition :trials 1 :seed 42 :registry registry))
         (artifact (deserialize-counterexample-artifact
                     (serialize-counterexample-artifact (make-counterexample-artifact result))))
         (calls *calls*))
    (ok (eq :failed (property-result-status result)))
    (ok (eq :same-failure (recheck-status artifact registry)))
    (ok (= *calls* (1+ calls)))
    (setf *behavior* :fixed)
    (ok (eq :passed (recheck-status artifact registry)))
    (ok (= *calls* (+ calls 2)))))
