;;;; tests/rove-test.lisp

(defpackage #:cl-spec/tests/rove-test
  (:use #:cl)
  (:import-from #:cl-spec/rove #:deftest-contract)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defproperty #:definition-digest)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:rove #:deftest #:ok #:run-test #:remove-test #:*report-stream*))

(in-package #:cl-spec/tests/rove-test)

(deftest reports-the-seed-and-gives-rove-a-real-failure-with-replay-data
  (let ((*registry* (make-hash-table-registry))
        (*report-stream* (make-string-output-stream)))
    (defproperty passing ((x (member 7))) (:trials (:normal 1)) (= x 7))
    (defproperty failing ((x (member 7))) (:trials (:normal 1)) (zerop x))
    ;; The nested tests only belong to this assertion, including the expected failure.
    (unwind-protect
         (progn
           (deftest-contract pass-contract (:property passing) :seeds '(23))
           (deftest-contract fail-contract (:property failing) :seeds '(9007199254740993))
           (ok (run-test 'pass-contract))
           (ok (search "seed 23" (get-output-stream-string *report-stream*)))
           (ok (null (run-test 'fail-contract)))
           (let ((output (get-output-stream-string *report-stream*)))
             (ok (search "seed 9007199254740993" output))
             (ok (search (definition-digest 'failing :entity-kind :property) output))
             (ok (search "counterexample (" output))
             (ok (search "X 7)" output))))
      (remove-test 'pass-contract)
      (remove-test 'fail-contract))))
