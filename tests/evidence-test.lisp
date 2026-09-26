;;;; tests/evidence-test.lisp
(defpackage #:cl-spec/tests/evidence-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/evidence
                #:evidence-facts #:evidence-summary #:assess-evidence
                #:invalid-evidence-policy))
(in-package #:cl-spec/tests/evidence-test)

(defclass saved-result ()
  ((facts :initarg :facts :accessor facts)))

(defmethod evidence-facts ((result saved-result))
  (facts result))

(defun saved (&key (checked 3) (cases '(:normal :overflow)) (report-p t))
  (make-instance
   'saved-result :facts
   (list :execution-status :passed :scope :single-run :subject '(:name example)
         :trials 3 :budget 3 :declared-cases cases
         :trial-report (if report-p
                           (list :report-version 1 :collection :complete
                                 :unit :normal-trials :counts
                                 (list :passed checked :failed 0 :rejected (- 3 checked) :error 0)
                                 :checked checked)
                           :not-collected)
         :case-report (if report-p
                          '(:cases ((:name :normal :called 3 :passed 3 :failed 0 :error 0)
                                    (:name :overflow :called 0 :passed 0 :failed 0 :error 0)))
                          :not-collected))))

(deftest passed-can-have-insufficient-case-evidence
  (let ((data (assess-evidence
               (saved)
               '(:policy-version 1 :requirements
                 ((:kind :min-checked-trials :count 3)
                  (:kind :all-declared-cases :min-checked 1))))))
    (ok (eq :passed (getf data :execution-status)))
    (ok (eq :insufficient (getf data :assessment)))
    (ok (equal '(:overflow) (mapcar (lambda (gap) (getf gap :case)) (getf data :gaps))))
    (ok (null (getf data :unknowns)))))

(deftest summary-never-implies-sufficient
  (let ((summary (evidence-summary (saved))))
    (ok (eq :not-assessed (getf summary :assessment)))
    (ok (find :case-never-called (getf summary :gaps) :key (lambda (x) (getf x :kind))))))

(deftest unknown-is-not-zero-and-known-gap-wins
  (let* ((result (saved :report-p nil))
         (policy '(:policy-version 1 :requirements
                   ((:kind :min-checked-trials :count 1))))
         (unknown (assess-evidence result policy)))
    (ok (eq :unknown (getf unknown :assessment)))
    (ok (null (getf unknown :gaps)))
    (setf (getf (facts result) :trials) 1)
    (let ((mixed (assess-evidence result
                  '(:policy-version 1 :requirements
                    ((:kind :requested-trials-completed)
                     (:kind :min-checked-trials :count 1))))))
      (ok (eq :insufficient (getf mixed :assessment)))
      (ok (= 1 (length (getf mixed :gaps)) (length (getf mixed :unknowns)))))))

(deftest policy-is-explicit-and-inapplicable-is-not-satisfied
  (ok (eq :satisfied
          (getf (assess-evidence (saved)
                  '(:policy-version 1 :requirements
                    ((:kind :min-checked-trials :count 3)
                     (:kind :requested-trials-completed))))
                :assessment)))
  (ok (eq :not-assessed
          (getf (assess-evidence (saved :cases nil)
                  '(:policy-version 1 :requirements
                    ((:kind :all-declared-cases :min-checked 1))))
                :assessment)))
  (ok (eq :insufficient
          (getf (assess-evidence (saved :checked 0)
                  '(:policy-version 1 :requirements
                    ((:kind :min-checked-trials :count 1))))
                :assessment))))

(deftest policy-validation-is-closed-and-cycle-safe
  (let ((cycle (list :policy-version 1)))
    (setf (cddr cycle) cycle)
    (dolist (policy
             (list nil cycle
                   '(:policy-version 2 :requirements ((:kind :requested-trials-completed)))
                   '(:policy-version 1 :requirements nil)
                   '(:policy-version 1 :requirements ((:kind :min-checked-trials :count 0)))
                   '(:policy-version 1 :requirements ((:kind :unknown)))
                   '(:policy-version 1 :requirements
                     ((:kind :requested-trials-completed) (:kind :requested-trials-completed)))
                   '(:policy-version 1 :requirements ((:kind :requested-trials-completed :x 1)))
                   '(:policy-version 1 :policy-version 1 :requirements
                     ((:kind :requested-trials-completed)))))
      (ok (handler-case (progn (assess-evidence (saved) policy) nil)
            (invalid-evidence-policy () t))))))

(deftest assessment-copies-inputs-and-keeps-execution-independent
  (let ((result (saved :cases nil))
         (policy (copy-tree '(:policy-version 1 :requirements
                              ((:kind :min-checked-trials :count 2))))))
    (setf (getf (facts result) :execution-status) :failed)
    (let ((data (assess-evidence result policy)))
      (ok (eq :satisfied (getf data :assessment)))
      (ok (eq :failed (getf data :execution-status)))
      (setf (getf (getf data :policy) :policy-version) 9
            (getf (getf data :subject) :name) 'changed)
      (ok (= 1 (getf policy :policy-version)))
      (ok (eq 'example (getf (getf (evidence-summary result) :subject) :name)))
      (ok (equal (assess-evidence result policy) (assess-evidence result policy))))))
