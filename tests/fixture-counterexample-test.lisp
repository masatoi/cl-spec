;;;; tests/fixture-counterexample-test.lisp
(defpackage #:cl-spec/tests/fixture-counterexample-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
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

(deftest fixture-artifact-requires-explicit-state-policy
  (with-contract
    (let* ((*mode* :missing-update)
           (artifact (cl-spec:make-counterexample-artifact (fixture-check '(30 10)))))
      (ok (eq :unsupported (getf (cl-spec:recheck-counterexample artifact) :status)))
      (ok (= 1 *setups*)))))

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

(deftest cleanup-error-is-not-persistable
  (with-contract
    (let* ((*mode* :cleanup-error)
           (result (fixture-check '(30 10))))
      (ok (handler-case
              (progn (cl-spec:make-counterexample-artifact result) nil)
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