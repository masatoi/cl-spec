;;;; tests/coverage-direct-test.lisp
(defpackage #:cl-spec/tests/coverage-direct-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/field-spec #:plist-structure-error)
  (:import-from #:cl-spec/src/coverage #:coverage-data #:coverage-schema))
(in-package #:cl-spec/tests/coverage-direct-test)

(defun stage (report kind name)
  (getf (find name
             (getf (find kind (getf report :dimensions)
                         :key (lambda (d) (getf d :kind))) :stages)
             :key (lambda (s) (getf s :stage))) :buckets))

(defun count-bucket (report kind name bucket)
  (second (assoc bucket (stage report kind name))))

(defun mutating (payload)
  (setf (getf payload :memo) :changed)
  1)

(deftest direct-coverage-snapshots-before-mutation
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function mutating
      (:args (payload (plist (:optional (:memo t))))) (:returns integer))
    (let* ((result (cl-spec:check-call 'mutating (list nil) :coverage '(:mode :observe)))
           (report (coverage-data result)))
      (ok (= 1 (count-bucket report :field-presence :checked :absent)))
      (ok (eq :single-call (getf report :scope)))
      (ok (getf (cl-spec:call-check-data result) :coverage))
      (cl-spec:defspec-function mutating (:args (payload t)) (:returns integer))
      (ok (equal report (coverage-data result)))
      (setf (getf report :scope) :changed)
      (ok (eq :single-call (getf (coverage-data result) :scope))))))

(deftest coverage-schema-and-report-carry-definition-identity
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer))))) (:returns t))
    (let* ((contract (cl-spec:find-function-spec 'identity))
           (schema (coverage-schema contract))
           (result (cl-spec:check-call 'identity (list nil) :coverage '(:mode :observe)))
           (saved (getf (coverage-data result) :schema)))
      (ok (stringp (getf (getf schema :subject) :definition-digest)))
      (ok (equal (getf schema :subject) (getf saved :subject))))))

(deftest direct-stages-reflect-pre-and-post-errors
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo t)))))
      (:pre (getf payload :memo)) (:returns t) (:post (error "post error")))
    (let ((rejected (coverage-data (cl-spec:check-call 'identity (list nil)
                                    :coverage '(:mode :observe))))
          (error (coverage-data (cl-spec:check-call 'identity (list '(:memo 1))
                                 :coverage '(:mode :observe)))))
      (ok (= 1 (count-bucket rejected :field-presence :domain-valid :absent)))
      (ok (= 0 (count-bucket rejected :field-presence :target-observed :absent)))
      (ok (= 1 (count-bucket error :field-presence :target-observed :present)))
      (ok (= 0 (count-bucket error :field-presence :checked :present))))))

(deftest omitted-optional-argument-is-not-present-nil-plist
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function list
      (:args &optional (payload (plist (:optional (:memo t)))))
      (:returns t))
    (let* ((result (cl-spec:check-call 'list nil :coverage '(:mode :observe)))
           (data (coverage-data result))
           (row (find :checked (getf (first (getf data :dimensions)) :stages)
                      :key (lambda (s) (getf s :stage)))))
      (ok (= 1 (getf row :not-applicable-trials)))
      (ok (= 0 (count-bucket data :field-presence :checked :absent))))))

(deftest fixture-coverage-waits-for-cleanup-and-keeps-input-space
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (cleanup-error nil))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo t)))))
      (:fixture (:isolation :fresh) (:version 1) (:recipe (recipe integer))
                (:setup (context) (declare (ignore context)) (list (list :memo recipe)))
                (:cleanup (context) (declare (ignore context))
                          (when cleanup-error (error "cleanup error"))))
      (:returns t))
    (let ((report (coverage-data (cl-spec:check-fixture 'identity 1
                                  :coverage '(:mode :observe)))))
      (ok (= 1 (getf report :trials)))
      (ok (= 1 (count-bucket report :field-presence :checked :present))))
    (setf cleanup-error t)
    (let ((report (coverage-data (cl-spec:check-fixture 'identity 1
                                  :coverage '(:mode :observe)))))
      (ok (= 1 (count-bucket report :field-presence :target-observed :present)))
      (ok (= 0 (count-bucket report :field-presence :checked :present))))))

(deftest fixture-coverage-records-unavailable-input-reason
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer)))))
      (:fixture (:isolation :fresh) (:version 1) (:recipe (recipe integer))
                (:setup (context) (declare (ignore context))
                        (if (zerop recipe) (error "setup failure") nil))
                (:cleanup (context) (declare (ignore context))))
      (:returns t))
    (loop for recipe in '(0 1 "invalid") for reason in '(:setup :argument-binding :recipe)
          do (let* ((result (cl-spec:check-fixture 'identity recipe :coverage '(:mode :observe)))
                    (report (coverage-data result)))
               (ok (= 1 (getf report :input-unavailable)))
               (ok (= 1 (getf (getf report :input-unavailable-reasons) reason 0)))))))

(defun count-record-scans (record thunk)
  "Return THUNK's result and the number of structural inspections of RECORD."
  (let ((original (fdefinition 'plist-structure-error)) (scans 0))
    (unwind-protect
         (progn
           (setf (fdefinition 'plist-structure-error)
                 (lambda (value)
                   (when (eq value record) (incf scans))
                   (funcall original value)))
           (values (funcall thunk) scans))
      (setf (fdefinition 'plist-structure-error) original))))

(deftest coverage-indexes-each-plist-once-per-capture
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (record (list :n 2 :memo nil)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:required (:n (range integer 1 2))) (:optional (:memo t)))))
      (:fixture (:isolation :fresh) (:version 1) (:recipe (recipe integer))
                (:setup (context) (declare (ignore context recipe)) (list record))
                (:cleanup (context) (declare (ignore context recipe))))
      (:returns t))
    (flet ((observe ()
             (flet ((run (coverage)
                      (count-record-scans
                       record (lambda () (cl-spec:check-fixture 'identity 1 :coverage coverage)))))
               (multiple-value-bind (baseline ordinary-scans) (run nil)
                 (multiple-value-bind (result observed-scans) (run '(:mode :observe))
                   (ok (= (1+ ordinary-scans) observed-scans))
                   (ok (eq (getf (cl-spec:fixture-check-data baseline) :status)
                           (getf (cl-spec:fixture-check-data result) :status)))
                   (coverage-data result))))))
      (let ((report (observe)))
        (ok (= 1 (count-bucket report :field-presence :checked :present)))
        (ok (= 1 (count-bucket report :numeric-boundary :checked :upper)))
        (ok (= 1 (count-bucket report :extra-key-presence :checked :absent))))
      (setf (cdr record) (list 1 :extra 3))
      (let ((report (observe)))
        (ok (= 1 (count-bucket report :field-presence :checked :absent)))
        (ok (= 1 (count-bucket report :numeric-boundary :checked :lower)))
        (ok (= 1 (count-bucket report :extra-key-presence :checked :present))))
      (setf (cdr record) (list 1 :n 2))
      (let ((report (observe)))
        (dolist (dimension (getf report :dimensions))
          (let ((stage (find :domain-valid (getf dimension :stages)
                             :key (lambda (s) (getf s :stage)))))
            (ok (zerop (getf stage :observed-trials)))))))))

(deftest evidence-summary-preserves-coverage-scope
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo (range integer 0 2)))))) (:returns t))
    (let* ((result (cl-spec:check-call 'identity (list nil) :coverage '(:mode :observe)))
           (summary (cl-spec:evidence-summary result)))
      (ok (equal (coverage-data result) (getf summary :coverage)))
      (ok (member :partial-optional-field-coverage (getf summary :limitations)))
      (ok (member :partial-boundary-coverage (getf summary :limitations)))
      (ok (not (member :no-optional-field-coverage (getf summary :limitations))))
      (ok (eq :passed (getf summary :execution-status)))
      (ok (eq :not-assessed (getf summary :assessment))))))

(deftest direct-coverage-disabled-and-exercise-refusal
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity (:args (payload t)) (:returns t))
    (ok (eq :disabled (getf (coverage-data (cl-spec:check-call 'identity '(1))) :reason)))
    (ok (handler-case (progn (cl-spec:check-call 'identity '(1)
                              :coverage '(:mode :exercise)) nil)
          (cl-spec/src/coverage:unsupported-coverage-operation () t)))))
