;;;; tests/coverage-direct-test.lisp
(defpackage #:cl-spec/tests/coverage-direct-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
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
