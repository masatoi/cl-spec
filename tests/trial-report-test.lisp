;;;; tests/trial-report-test.lisp
(defpackage #:cl-spec/tests/trial-report-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend* #:run-generated-test #:backend-trial-reporting)
  (:import-from #:cl-spec/src/execution
                #:begin-trial-report #:note-trial-outcome #:observe-trial #:make-trial-observation)
  (:import-from #:cl-spec/src/trial-report #:end-trial-report))
(in-package #:cl-spec/tests/trial-report-test)

(defclass spoofing-backend () ())

(defmethod run-generated-test ((backend spoofing-backend) property &key options)
  (declare (ignore backend property))
  (list :status :passed :trials (getf options :trials) :rejected 0
        :trial-report '(:collection :complete :checked 100 :counts (:passed 100))))

(defclass reporting-backend ()
  ((mode :initarg :mode :reader mode)))

(defmethod backend-trial-reporting ((backend reporting-backend)) :trial-report-v1)

(defmethod run-generated-test ((backend reporting-backend) property &key options)
  (declare (ignore options))
  (unless (eq :missing-begin (mode backend)) (begin-trial-report property))
  (when (eq :double-begin (mode backend)) (begin-trial-report property))
  (let ((observation (if (eq :wrong-run (mode backend))
                         (make-trial-observation :property property)
                         (observe-trial property '(1)))))
    (note-trial-outcome property observation)
    (when (eq :duplicate (mode backend)) (note-trial-outcome property observation)))
  (unless (eq :missing-end (mode backend)) (end-trial-report property))
  (when (eq :after-end (mode backend))
    (note-trial-outcome property (observe-trial property '(2))))
  (case (mode backend)
    (:malformed (list :status :passed :trials))
    (:count-mismatch (list :status :skipped :trials 0 :rejected 0))
    (otherwise (list :status :passed :trials 1 :rejected 0))))

(deftest incoherent-trial-reports-are-refused
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty report-probe ((x integer)) (:trials (:normal 1)) t)
    (dolist (mode '(:missing-begin :double-begin :wrong-run :duplicate
                   :missing-end :after-end :count-mismatch :malformed))
      (let ((*generator-backend* (make-instance 'reporting-backend :mode mode)))
        (ok (handler-case (progn (cl-spec:run-property 'report-probe :seed 1) nil)
              (cl-spec:invalid-backend-result () t)))))))

(deftest backend-cannot-supply-its-own-evidence-counts
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (*generator-backend* (make-instance 'spoofing-backend)))
    (cl-spec:defproperty spoof-probe ((x integer)) (:trials (:normal 1)) t)
    (ok (handler-case (progn (cl-spec:run-property 'spoof-probe :seed 1) nil)
          (cl-spec:invalid-backend-result () t)))))

(deftest case-counts-must-agree-with-normal-trials
  (let ((report '(:collection :complete :counts (:passed 1 :failed 0 :error 0) :checked 1)))
    (dolist (entry '((:name :only :called 1 :passed 0 :failed 0 :error 1)
                     (:name :only :called 2 :passed 1 :failed 0 :error 0)))
      (ok (handler-case
              (progn (cl-spec/src/trial-report::validate-case-trial-report
                      report (list :declared-cases '(:only) :cases (list entry))) nil)
            (cl-spec:invalid-backend-result () t))))
    (ok (cl-spec/src/trial-report::validate-case-trial-report
         report '(:declared-cases (:only)
                  :cases ((:name :only :called 1 :passed 1 :failed 0 :error 0)))))))
