;;;; tests/rove-test.lisp

(defpackage #:cl-spec/tests/rove-test
  (:use #:cl)
  (:import-from #:cl-spec/rove #:deftest-contract)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defproperty #:definition-digest
                #:defgenerator #:defspec)
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

(deftest selectors-are-refused-during-macroexpansion
  (dolist (selector '(:names :package :tag))
    (ok (handler-case
            (progn (macroexpand-1 (list 'deftest-contract 'probe 'passing selector nil)) nil)
          (cl-spec:invalid-argument (condition)
            (eq selector (cl-spec:invalid-argument-argument condition))))))
  (ok (nth-value 1 (macroexpand-1 '(deftest-contract probe passing :profile :tag)))))

(defun fixed-example-error-target (value)
  (declare (ignore value))
  (error "Fixed example call failed with condition details"))

(deftest failed-examples-report-the-call-condition
  (let ((*registry* (make-hash-table-registry))
        (*report-stream* (make-string-output-stream)))
    (defproperty passing ((x (member 7))) (:trials (:normal 1)) (= x 7))
    (cl-spec:defspec-function fixed-example-error-target
      (:args (value integer)) (:returns integer))
    (unwind-protect
         (progn
           (deftest-contract failing-example (:property passing)
             :seeds '(17)
             :examples '((fixed-example-error-target (7)) (unknown-example-target (7))))
           (ok (null (run-test 'failing-example)))
           (let ((output (get-output-stream-string *report-stream*)))
             (ok (search "example (7) failed" output))
             (ok (search "Fixed example call failed with condition details" output))
             (ok (search "UNKNOWN-FUNCTION-SPEC" output :test #'char-equal))))
      (remove-test 'failing-example))))

(define-condition unprintable-counterexample (serious-condition) ())

(defclass opaque-counterexample () ())

(defmethod print-object ((object opaque-counterexample) stream)
  (declare (ignore object stream))
  (error 'unprintable-counterexample))

(deftest opaque-counterexample-keeps-the-rove-replay-message
  (let ((*registry* (make-hash-table-registry))
        (*report-stream* (make-string-output-stream)))
    (defgenerator opaque-generator () (make-instance 'opaque-counterexample))
    (defspec opaque-value (type opaque-counterexample) (:generator opaque-generator))
    (defproperty opaque-failure ((value opaque-value))
      (:trials (:normal 1))
      (not (typep value 'opaque-counterexample)))
    (unwind-protect
         (let ((digest (definition-digest 'opaque-failure :entity-kind :property)))
           (deftest-contract fail-opaque-contract (:property opaque-failure) :seeds '(41))
           (ok (null (run-test 'fail-opaque-contract)))
           (let ((output (get-output-stream-string *report-stream*)))
             (ok (search "seed 41" output))
             (ok (search digest output))
             (ok (search "counterexample <unavailable>" output))))
      (remove-test 'fail-opaque-contract))))

#+(and sbcl sb-thread)
(deftest contract-tests-propagate-caller-timeouts-and-interrupts
  (let ((*registry* (make-hash-table-registry))
        (*report-stream* (make-string-output-stream)))
    (unwind-protect
         (dolist (transfer '(:timeout :interrupt))
           (defproperty intercepted ((x (member 7)))
             (:trials (:normal 1))
             (declare (ignore x))
             (ecase transfer
               (:timeout (sleep 1/4))
               (:interrupt
                (sb-thread:interrupt-thread
                 sb-thread:*current-thread*
                 (lambda () (signal 'sb-sys:interactive-interrupt)))))
             t)
           (deftest-contract intercepted-contract (:property intercepted) :seeds '(41))
           (ok (eq transfer
                   (handler-case
                       (progn
                         (if (eq transfer :timeout)
                             (sb-ext:with-timeout 1/20 (run-test 'intercepted-contract))
                             (run-test 'intercepted-contract))
                         :returned)
                     (sb-ext:timeout () :timeout)
                     (sb-sys:interactive-interrupt () :interrupt)))))
      (remove-test 'intercepted-contract))))

(defclass slow-printed-counterexample () ())

(defmethod print-object ((object slow-printed-counterexample) stream)
  (declare (ignore object))
  (sleep 1/4)
  (write-string "Slow counterexample" stream))

#+(and sbcl sb-thread)
(deftest caller-deadline-stops-rove-counterexample-reporting
  (let ((*registry* (make-hash-table-registry))
        (*report-stream* (make-string-output-stream)))
    (defgenerator slow-printed-generator () (make-instance 'slow-printed-counterexample))
    (defspec slow-printed-value (type slow-printed-counterexample)
      (:generator slow-printed-generator))
    (defproperty slow-printed-failure ((value slow-printed-value))
      (:trials (:normal 1))
      (declare (ignore value))
      nil)
    (unwind-protect
         (progn
           (deftest-contract slow-printed-contract (:property slow-printed-failure)
             :seeds '(41))
           (ok (eq :timeout
                   (handler-case
                       (progn
                         (sb-ext:with-timeout 1/20 (run-test 'slow-printed-contract))
                         :returned)
                     (sb-ext:timeout () :timeout)))))
      (remove-test 'slow-printed-contract))))
