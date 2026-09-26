;;;; src/trial-report.lisp
(defpackage #:cl-spec/src/trial-report
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:import-from #:cl-spec/src/property #:property)
  (:import-from #:cl-spec/src/execution
                #:begin-trial-report #:note-trial-outcome #:trial-observation-status
                #:observation-from-current-run-p #:snapshot-value
                #:claim-observation-report #:observation-reported-to-p)
  (:export #:*trial-report-context* #:make-trial-report-context
           #:end-trial-report #:completed-trial-report #:validate-case-trial-report))
(in-package #:cl-spec/src/trial-report)

(defclass trial-report-context ()
  ((property :initarg :property :reader report-property)
   (phase :initform :new :accessor report-phase)
   (token :initform (list nil) :reader report-token)
   (counts :initform (list :passed 0 :failed 0 :rejected 0 :error 0) :accessor report-counts))
  (:documentation "Run-owned normal-trial measurements; never stored on a definition."))

(defvar *trial-report-context* nil
  "The current opt-in backend's normal-trial report context.")

(defun make-trial-report-context (property)
  "Create an unopened measurement context for PROPERTY."
  (make-instance 'trial-report-context :property property))

(defun require-report-phase (property phase)
  "Require the active report to belong to PROPERTY and be in PHASE."
  (let ((report *trial-report-context*))
    (unless (and report (eq property (report-property report)) (eq phase (report-phase report)))
      (error 'invalid-backend-result :reason "trial report has wrong owner or lifecycle phase"))
    report))

(defmethod begin-trial-report :after ((property property))
  (when *trial-report-context*
    (setf (report-phase (require-report-phase property :new)) :open)))

(defmethod note-trial-outcome :after ((property property) observation)
  (when *trial-report-context*
    (let ((report (require-report-phase property :open)))
      (unless (and (observation-from-current-run-p observation property)
                   (member (trial-observation-status observation) '(:passed :failed :rejected :error)))
        (error 'invalid-backend-result :reason "duplicate or foreign normal-trial observation"))
      (claim-observation-report observation (report-token report))
      (incf (getf (report-counts report) (trial-observation-status observation))))))

(defun end-trial-report (property)
  "Close an opt-in report after the backend's final normal-trial observation."
  (when *trial-report-context*
    (setf (report-phase (require-report-phase property :open)) :closed)))

(defun completed-trial-report (property outcome)
  "Validate measured counts against OUTCOME and return copied ordinary data."
  (let* ((report (require-report-phase property :closed))
         (counts (report-counts report)))
    (unless (and (eql (loop for (key count) on counts by #'cddr sum count)
                      (getf outcome :trials))
                 (eql (getf counts :rejected) (getf outcome :rejected 0)))
      (error 'invalid-backend-result :reason "trial report counts disagree with backend outcome"))
    (let ((original (getf outcome :failure))
          (abort (getf outcome :run-error))
          (failures (+ (getf counts :failed) (getf counts :error))))
      (unless (and
               (or (not (member (getf outcome :status) '(:passed :skipped)))
                   (zerop failures))
               (if (or original abort)
                   ;; A shrink-only abort follows a reported ordinary failure.
                   ;; With no original, the abort itself must be an ordinary trial.
                   (and (plusp failures)
                        (observation-reported-to-p (or original abort) (report-token report)))
                   (zerop failures)))
        (error 'invalid-backend-result
               :reason "trial verdicts disagree with retained failure or execution status")))
    (snapshot-value
     (list :report-version 1 :collection :complete :unit :normal-trials
           :counts counts :checked (+ (getf counts :passed) (getf counts :failed))))))

(defun validate-case-trial-report (report cases)
  "Cross-check independently counted ordinary trials and named case verdicts."
  (when (and (listp report) (eq :complete (getf report :collection))
             (listp cases) (getf cases :declared-cases))
    (let ((passed 0) (failed 0) (errors 0))
      (dolist (entry (getf cases :cases))
        (unless (and (every (lambda (key) (typep (getf entry key) '(integer 0 *)))
                            '(:called :passed :failed :error))
                     (= (getf entry :called)
                        (+ (getf entry :passed) (getf entry :failed) (getf entry :error))))
          (error 'invalid-backend-result :reason "case report has inconsistent counts"))
        (incf passed (getf entry :passed))
        (incf failed (getf entry :failed))
        (incf errors (getf entry :error)))
      (let ((counts (getf report :counts)))
        (unless (and (= passed (getf counts :passed))
                     (= failed (getf counts :failed))
                     (<= errors (getf counts :error)))
          (error 'invalid-backend-result :reason "case and normal-trial verdicts disagree")))))
  cases)
