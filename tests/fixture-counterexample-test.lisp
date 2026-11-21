;;;; tests/fixture-counterexample-test.lisp
(defpackage #:cl-spec/tests/fixture-counterexample-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/fixture #:trial-fixture)
  (:import-from #:cl-spec/src/generator #:*generator-backend*)
  (:import-from #:cl-spec/tests/fixture-function-test
                #:with-contract #:withdraw #:fixture-check #:*mode*
                #:*setups* #:*cleanups* #:*calls*))
(in-package #:cl-spec/tests/fixture-counterexample-test)

(deftest direct-fixture-artifact-roundtrip-and-repair
  (with-contract
    (let* ((*mode* :missing-update)
           (*generator-backend* nil)
           (result (fixture-check '(30 10)))
           (artifact (cl-spec:make-counterexample-artifact result))
           (wire (cl-spec:serialize-counterexample-artifact artifact))
           (restored (cl-spec:deserialize-counterexample-artifact wire)))
      (ok (= 2 (getf (cl-spec:counterexample-artifact-data restored) :artifact-version)))
      (ok (eq :same-failure
              (getf (cl-spec:recheck-counterexample restored :state-policy :fixture) :status)))
      (setf *mode* :correct)
      (ok (eq :passed
              (getf (cl-spec:recheck-counterexample restored :state-policy :fixture) :status)))
      (ok (= 3 *setups* *cleanups* *calls*)))))

(deftest rechecks-a-historical-fixture-artifact
  ;; The AV1 fixture was emitted by 33affd3a298bce022aa7ab210f5b09591374abc4.
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*generator-backend* nil))
    ;; Construct the declaration lists at run time to avoid compiler literal sharing.
    (let ((fixture (make-instance 'trial-fixture
                                  :version 1
                                  :recipe-name 'recipe
                                  :recipe-spec 'integer
                                  :setup-function (lambda (recipe context)
                                                    (declare (ignore context))
                                                    (list recipe))
                                  :setup-forms (list (list 'list 'recipe))
                                  :cleanup-function (lambda (recipe context)
                                                      (declare (ignore recipe context))
                                                      nil)
                                  :cleanup-forms (list nil))))
      (cl-spec:register-function-spec
       (make-instance 'cl-spec:function-spec
                      :name 'identity
                      :argument-specs (list (list 'value 'integer))
                      :return-spec 'string
                      :fixture fixture)))
    (let* ((path (asdf:system-relative-pathname "cl-spec" "tests/fixtures/counterexample-v2.av1"))
           (artifact (cl-spec:deserialize-counterexample-artifact (uiop:read-file-string path)))
           (data (cl-spec:counterexample-artifact-data artifact))
           (recheck (cl-spec:recheck-counterexample artifact :state-policy :fixture))
           (observation (getf recheck :observation)))
      (ok (eql 2 (getf data :artifact-version)))
      (ok (equal '(27) (getf (getf data :original) :arguments)))
      (ok (eq :same-failure (getf recheck :status)))
      (ok (eq :return-spec (getf observation :reason)))
      (ok (eq :completed (getf (getf observation :lifecycle) :cleanup))))))

(deftest base-string-fixture-recipe-survives-setup-and-recheck
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*setups* 0) (*cleanups* 0))
    (cl-spec:defspec-function length
      (:args (value string))
      (:fixture (:isolation :fresh) (:version 1)
                (:recipe (recipe simple-base-string))
                (:setup (context)
                  (declare (ignore context))
                  (incf *setups*)
                  (list recipe))
                (:cleanup (context)
                  (declare (ignore recipe context))
                  (incf *cleanups*)))
      (:returns string))
    (let* ((recipe (make-array 3 :element-type 'base-char :initial-contents "abc"))
           (result (cl-spec:check-fixture 'length recipe))
           (status (getf (cl-spec:fixture-check-data result) :status)))
      ;; LENGTH returns an integer, so reaching the target produces a return failure.
      (ok (eq :failed status))
      (ok (= 1 *setups* *cleanups*))
      (when (eq :failed status)
        (let* ((wire (cl-spec:serialize-counterexample-artifact
                      (cl-spec:make-counterexample-artifact result)))
               (restored (cl-spec:deserialize-counterexample-artifact wire)))
          (ok (eq :same-failure (getf (cl-spec:recheck-counterexample
                                       restored :state-policy :fixture) :status)))
          (ok (= 2 *setups* *cleanups*)))))))

(deftest fixture-artifact-requires-explicit-state-policy
  (with-contract
    (let* ((*mode* :missing-update)
           (artifact (cl-spec:make-counterexample-artifact (fixture-check '(30 10)))))
      (ok (eq :unsupported (getf (cl-spec:recheck-counterexample artifact) :status)))
      (ok (= 1 *setups*)))))

(deftest fixture-artifact-recheck-records-a-missing-target
  ;; A version 1 recheck records an error the run met as :CONTRACT-ERROR; the
  ;; fixture recheck let UNBOUND-TARGET escape, so a batch of rechecks over
  ;; saved fixture artifacts stopped at the first one whose target was gone.
  (with-contract
    (let* ((*mode* :missing-update)
           (artifact (cl-spec:make-counterexample-artifact (fixture-check '(30 10))))
           (target (fdefinition 'withdraw)))
      (fmakunbound 'withdraw)
      (let ((record (unwind-protect
                         (handler-case
                             (cl-spec:recheck-counterexample artifact :state-policy :fixture)
                           (error (condition) (list :signalled (type-of condition))))
                      (setf (fdefinition 'withdraw) target))))
        (ok (eq :contract-error (getf record :status)) (prin1-to-string record))
        (ok (= 2 (getf record :schema-version)))))))

(deftest fixture-artifact-refuses-changed-definition
  (with-contract
    (let* ((*mode* :missing-update)
           (artifact (cl-spec:make-counterexample-artifact (fixture-check '(30 10))))
           (contract (cl-spec:find-function-spec 'withdraw))
           (fixture (funcall (find-symbol "FUNCTION-SPEC-FIXTURE" "CL-SPEC") contract)))
      (reinitialize-instance fixture :version 2)
      (ok (eq :definition-mismatch
              (getf (cl-spec:recheck-counterexample artifact :state-policy :fixture) :status)))
      (ok (= 1 *setups*)))))

(deftest passed-fixture-results-are-refused-as-not-failure-evidence
  ;; A passed run completed its lifecycle; the refusal is that nothing failed.
  (with-contract
    (flet ((artifact-refusal (result &optional (selection :selected))
             (handler-case
                 (progn (cl-spec:make-counterexample-artifact result :selection selection) nil)
               (cl-spec:invalid-counterexample-artifact (condition)
                 (cl-spec:invalid-counterexample-artifact-reason condition)))))
      (let ((generated (cl-spec:check-function 'withdraw :trials 3 :seed 41)))
        (ok (eq :not-failure-evidence (artifact-refusal (fixture-check '(30 10)))))
        (ok (eq :not-failure-evidence (artifact-refusal generated)))
        ;; Not :MISSING-SHRUNK-EVIDENCE: there is no failure to have shrunk.
        (ok (eq :not-failure-evidence (artifact-refusal generated :shrunk)))))))

(deftest cleanup-error-is-not-persistable
  (with-contract
    (let* ((*mode* :cleanup-error)
           (result (fixture-check '(30 10))))
      (ok (handler-case
              (progn (cl-spec:make-counterexample-artifact result) nil)
            (cl-spec:invalid-counterexample-artifact () t))))))

(deftest malformed-fixture-artifact-metadata-is-refused
  (with-contract
    (let* ((*mode* :missing-update)
           (artifact (cl-spec:make-counterexample-artifact (fixture-check '(30 10))))
           (data (cl-spec:counterexample-artifact-data artifact)))
      (setf (getf data :metadata-omissions) '((:field :original :reason :omitted)))
      (ok (handler-case
              (progn
                (cl-spec:deserialize-counterexample-artifact
                 (cl-spec/src/utils/artifact-values:serialize-artifact-value data))
                nil)
            (cl-spec:invalid-counterexample-artifact () t))))))

(deftest generated-fixture-artifact-rechecks-selected-recipe
  (with-contract
    (let* ((*mode* :missing-update)
           (result (cl-spec:check-function 'withdraw :trials 30 :seed 41))
           (artifact (cl-spec:make-counterexample-artifact result))
           (setups *setups*)
           (*generator-backend* nil))
      (ok (eq :same-failure
              (getf (cl-spec:recheck-counterexample artifact :state-policy :fixture) :status)))
      (ok (= (1+ setups) *setups*))
      (ok (= *setups* *cleanups*)))))
