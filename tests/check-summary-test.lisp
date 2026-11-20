;;;; tests/check-summary-test.lisp

(defpackage #:cl-spec/tests/check-summary-test
  (:use #:cl)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main #:format-check-summary))

(in-package #:cl-spec/tests/check-summary-test)

(defvar *calls* 0)

(defun counted (x)
  (incf *calls*)
  x)

(deftest direct-summary-uses-saved-case-evidence
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (*calls* 0))
    (cl-spec:defspec-function counted
      (:args (x integer))
      (:cases (:nonnegative (:when (>= x 0)) (:returns integer))
              (:negative (:when (< x 0)) (:returns integer))))
    (let* ((result (cl-spec:check-call 'counted '(3)))
           (policy '(:policy-version 1 :requirements ((:kind :all-declared-cases :min-checked 1))))
           (line (format-check-summary result :policy policy)))
      (ok (string= "COUNTED passed | evidence insufficient | case NEGATIVE checked 0 of 1" line))
      (ok (string= (format nil "~A~%" line)
                   (with-output-to-string (out)
                     (ok (null (format-check-summary result :policy policy :stream out))))))
      (ok (search "evidence not-assessed | case NEGATIVE never called"
                  (format-check-summary result)))
      (ok (= 1 *calls*)))))

(deftest generated-check-displays-measured-trials
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty bounded ((x (member 1)))
      (:trials (:normal 2))
      (= x 1))
    (let ((result (cl-spec:run-property 'bounded))
          (policy '(:policy-version 1 :requirements ((:kind :min-checked-trials :count 3))))
          (expected "BOUNDED passed | evidence insufficient | checked 2 of 3"))
      (ok (string= expected (format-check-summary result :policy policy)))
      (ok (string= (format nil "~A~%" expected)
                   (with-output-to-string (*standard-output*)
                     (format-check-summary result :policy policy :stream t)))))))

(deftest unmeasured-and-inapplicable-remain-distinct
  (let ((old (make-instance 'cl-spec:property-result :status :failed :trials 7))
        (minimum '(:policy-version 1 :requirements ((:kind :min-checked-trials :count 1)))))
    (ok (search "failed | evidence unknown | checked-trials unknown"
                (format-check-summary old :policy minimum)))
    (ok (handler-case (progn (format-check-summary old :policy nil) nil)
          (cl-spec:invalid-evidence-policy () t))))
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity (:args (x integer)) (:returns integer))
    (ok (search "evidence not-assessed | no applicable requirements"
                (format-check-summary
                 (cl-spec:check-call 'identity '(1))
                 :policy '(:policy-version 1 :requirements
                           ((:kind :requested-trials-completed))))))))

(deftest summary-stays-on-one-line-for-escaped-names
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (x integer))
      (:cases (:|two
lines| (:when (minusp x)) (:returns integer))
              (:other (:when (>= x 0)) (:returns integer))))
    (let ((line (format-check-summary (cl-spec:check-call 'identity '(0)))))
      (ok (null (position #\Newline line)))
      (ok (search "two lines never called" line)))))
