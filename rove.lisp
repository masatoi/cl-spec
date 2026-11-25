;;;; rove.lisp

(defpackage #:cl-spec/rove
  (:use #:cl)
  (:import-from #:cl-spec/main #:check-contracts)
  (:import-from #:cl-spec/src/utils/printing
                #:with-bounded-printing #:abbreviate-for-print #:reportable-condition)
  (:import-from #:rove #:deftest #:ok #:diag)
  (:export #:deftest-contract))

(in-package #:cl-spec/rove)

(defun diagnostic-value (value)
  "Print a saved diagnostic value even if it is circular or its printer signals."
  (handler-case
      (with-bounded-printing (:one-line t)
        (let ((*print-readably* nil))
          (prin1-to-string (abbreviate-for-print value))))
    (reportable-condition () "<unavailable>")))

(defun verdict-message (report)
  "Return the Rove description containing the verdict and replay information."
  (with-output-to-string (stream)
    (dolist (entry (getf report :entries))
      (let ((result (getf entry :result))
            (assessment (getf entry :assessment)))
        (format stream "~S ~S seed ~A, definition digest ~A~%"
                (getf entry :kind) (getf entry :name) (getf entry :seed)
                (getf result :definition-digest :unavailable))
        (unless (eq :passed (getf entry :verdict))
          (format stream "  ~A~%" (diagnostic-value (getf entry :problems)))
          (when (getf entry :condition)
            (format stream "  condition ~A~%" (diagnostic-value (getf entry :condition))))
          (when (or (getf assessment :gaps) (getf assessment :unknowns))
            (format stream "  evidence ~A~%"
                    (diagnostic-value (append (getf assessment :gaps)
                                              (getf assessment :unknowns)))))
          (when (or (getf result :failure) (getf result :counterexample))
            (format stream "  counterexample ~A~%"
                    (diagnostic-value (getf result :counterexample))))
          (when (getf result :shrunk-failure)
            (format stream "  shrunk counterexample ~A~%"
                    (diagnostic-value (getf result :shrunk-counterexample)))))))
    (dolist (row (getf report :examples))
      (unless (eq :passed (getf row :verdict))
        (format stream "~S example ~A failed ~A~%"
                (getf row :name) (diagnostic-value (getf row :arguments))
                (diagnostic-value (getf row :problems)))))
    (when (getf report :problems)
      (format stream "~A~%" (diagnostic-value (getf report :problems))))))

(defmacro deftest-contract (test-name target &rest options)
  "Define a Rove test that runs TARGET and uses CHECK-CONTRACTS to judge it.

TARGET is a literal name or a (:FUNCTION-SPEC NAME) or (:PROPERTY NAME) pair.
OPTIONS supplies the remaining CHECK-CONTRACTS arguments such as :SEEDS,
:TRIALS or :REGISTRY. The test reports the seed used. On failure its assertion
includes the saved counterexample and definition digest when available.
On SBCL, caller deadlines and interrupts propagate out of the test."
  (let ((report (gensym "REPORT"))
        (message (gensym "MESSAGE"))
        (passed (gensym "PASSED")))
    `(deftest ,test-name
       (let* ((,report (check-contracts :names ',(list target) ,@options))
              (,passed (eq :passed (getf ,report :status)))
              (,message (verdict-message ,report)))
         (when ,passed (diag ,message))
         (ok ,passed ,message)))))
