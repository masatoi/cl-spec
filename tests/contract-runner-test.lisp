;;;; tests/contract-runner-test.lisp

(defpackage #:cl-spec/tests/contract-runner-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defproperty #:defspec-function
                #:invalid-argument #:check-contracts)
  (:import-from #:cl-spec/src/generator #:*generator-backend* #:run-generated-test)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/contract-runner-test)

(defvar *calls* 0)

(define-condition runner-expected-error (error) ())

(defun runner-target (value)
  (incf *calls*)
  (if (minusp value) (error 'runner-expected-error) value))

(defun register-runner-definitions ()
  (defspec-function runner-target
    (:args (value (member 7)))
    (:returns integer))
  (defproperty runner-target ((value (member 7)))
    (:trials (:normal 2))
    (:tags :runner-ci)
    (= 7 value)))

(defun run-verdict (report)
  (getf (first (getf report :entries)) :verdict))

(deftest selectors-run-registered-definitions-and-report-real-seeds
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (register-runner-definitions)
    (testing "a bare name selects both definitions and typed names disambiguate"
      (let* ((*print-base* 16)
             (report (check-contracts :names '(runner-target (:property runner-target))
                                      :seeds '(9007199254740993 0) :trials 1
                                      :options '(:target-revision "abc")))
             (entries (getf report :entries)))
        (ok (eq :passed (getf report :status)))
        (ok (= 2 *calls*))
        (ok (equal '(:function-spec :property :function-spec :property)
                   (mapcar (lambda (entry) (getf entry :kind)) entries)))
        (ok (equal '("9007199254740993" "9007199254740993" "0" "0")
                   (mapcar (lambda (entry) (getf entry :seed)) entries)))
        (ok (every (lambda (entry)
                     (let ((data (getf entry :result)))
                       (and (eq :passed (getf entry :verdict))
                            (stringp (getf data :definition-digest))
                            (equal '(:target-revision "abc") (getf data :options))
                            (= (parse-integer (getf entry :seed)) (getf data :seed)))))
                   entries))))
    (testing "package names and tags work with an explicit registry"
      (defproperty cl-user::untagged-runner-property ((value (member 7)))
        (:trials (:normal 1))
        (= 7 value))
      (let ((saved *registry*)
            (*registry* (make-hash-table-registry)))
        (ok (= 2 (length (getf (check-contracts :package (symbol-package 'runner-target)
                                                :registry saved :trials 1)
                               :entries))))
        (ok (equal '(:property)
                   (mapcar (lambda (entry) (getf entry :kind))
                           (getf (check-contracts :tag :runner-ci :registry saved) :entries))))
        (let ((report (check-contracts :registry saved :trials 1)))
          (ok (eq :passed (getf report :status)))
          (ok (= 3 (length (getf report :entries))))
          (dolist (entry (getf report :entries))
            (ok (= (parse-integer (getf entry :seed)) (getf (getf entry :result) :seed)))))))))

(deftest empty-missing-and-invalid-selections-cannot-pass
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (dolist (report (list (check-contracts) (check-contracts :names nil)
                          (check-contracts :package "NO-SUCH-TEST-PACKAGE")
                          (check-contracts :tag :absent)))
      (ok (eq :failed (getf report :status)))
      (ok (eq :empty-selection (getf (first (getf report :problems)) :kind))))
    (register-runner-definitions)
    (ok (eq :failed (getf (check-contracts :seeds nil) :status)))
    (let* ((report (check-contracts :tag :runner-ci :profile :smoke :seeds '(4)))
           (entry (first (getf report :entries))))
      (ok (eq :failed (getf report :status)))
      (ok (eq :unknown-profile (getf entry :status))))
    (ok (zerop *calls*))
    (let* ((report (check-contracts :names '((:function-spec missing) missing
                                             (:function-spec runner-target))
                                    :seeds '(12) :trials 1))
           (entries (getf report :entries)))
      (ok (eq :failed (getf report :status)))
      (ok (equal '(:not-registered :not-registered :passed)
                 (mapcar (lambda (entry) (getf entry :status)) entries)))
      (ok (equal '("12" "12" "12") (mapcar (lambda (entry) (getf entry :seed)) entries)))
      (ok (= 1 *calls*)))
    (ok (handler-case
            (progn (check-contracts :names '(runner-target) :tag :runner-ci) nil)
          (invalid-argument () t)))
    (ok (handler-case
            (progn (check-contracts :seeds '(4 -1)) nil)
          (invalid-argument () t)))
    (ok (= 1 *calls*))))

(deftest missing-execution-evidence-and-unreached-cases-fail
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (defspec-function runner-target
      (:args (value (member 7))) (:pre nil) (:returns integer))
    (dolist (trials '(0 3))
      (let* ((report (check-contracts :trials trials :seeds '(4)))
             (entry (first (getf report :entries))))
        (ok (eq :failed (getf report :status)))
        (ok (eq :skipped (getf entry :status)))
        (ok (eq :insufficient (getf (getf entry :assessment) :assessment)))))
    (ok (zerop *calls*))
    (defspec-function runner-target
      (:args (value (member 7)))
      (:cases
        (:positive (:when (plusp value)) (:returns integer))
        (:negative (:when (minusp value)) (:signals (type runner-expected-error)))))
    (let* ((report (check-contracts :trials 3 :seeds '(4)))
           (entry (first (getf report :entries))))
      (ok (eq :failed (getf report :status)))
      (ok (eq :passed (getf entry :status)))
      (ok (eq :negative (getf (first (getf (getf entry :assessment) :gaps)) :case)))
      (ok (= 3 *calls*)))))

(defclass unmeasured-backend ()
  ((status :initarg :status :initform :passed :reader backend-status)))

(defmethod run-generated-test ((backend unmeasured-backend) property &key options)
  (declare (ignore property))
  (list :status (backend-status backend) :trials (getf options :trials) :rejected 0))

(deftest legacy-backends-and-escaped-conditions-cannot-pass
  (let ((*registry* (make-hash-table-registry)))
    (register-runner-definitions)
    (let* ((*generator-backend* (make-instance 'unmeasured-backend))
           (report (check-contracts :names '((:property runner-target)) :seeds '(7)))
           (entry (first (getf report :entries))))
      (ok (eq :failed (getf report :status)))
      (ok (eq :passed (getf entry :status)))
      (ok (eq :unknown (getf (getf entry :assessment) :assessment))))
    (let* ((*generator-backend* nil)
           (report (check-contracts :names '((:property runner-target)) :seeds '(7)))
           (entry (first (getf report :entries))))
      (ok (eq :failed (getf report :status)))
      (ok (eq :condition-signalled (getf entry :status)))
      (ok (eq 'cl-spec:no-generator-backend (getf (getf entry :condition) :type)))
      (ok (equal "7" (getf entry :seed))))))

(deftest unrecognised-backend-statuses-cannot-pass
  (let ((*registry* (make-hash-table-registry)))
    (register-runner-definitions)
    (dolist (status '(:done :timeout))
      (let* ((*generator-backend* (make-instance 'unmeasured-backend :status status))
             (report (check-contracts :names '((:property runner-target)) :seeds '(7)))
             (entry (first (getf report :entries))))
        (ok (eq :failed (getf report :status)))
        (ok (eq :failed (getf entry :verdict)))
        (ok (equal "7" (getf entry :seed)))))))

(deftest failing-examples-do-not-erase-run-results-or-stop-later-examples
  (let ((*registry* (make-hash-table-registry)) (*calls* 0))
    (defspec-function runner-target
      (:args (value (member -1)))
      (:cases (:negative (:when t) (:signals (type runner-expected-error)))))
    (let* ((report (check-contracts :seeds '(3) :trials 2
                                    :examples '((runner-target (7))
                                                (runner-target (-1) :other)
                                                (runner-target (-1) :negative))))
           (examples (getf report :examples)))
      (ok (eq :failed (getf report :status)))
      (ok (eq :passed (run-verdict report)))
      (ok (equal '(:failed :failed :passed)
                 (mapcar (lambda (row) (getf row :verdict)) examples)))
      (ok (eq :negative (getf (second examples) :actual-case)))
      (ok (eq :case-mismatch (getf (first (getf (second examples) :problems)) :kind)))
      (ok (eq :passed (getf (getf (third examples) :result) :status)))
      (ok (= 4 *calls*)))))

(deftest a-real-counterexample-keeps-both-run-and-replay-data
  (let ((*registry* (make-hash-table-registry)))
    (defproperty always-fails ((value (member 7))) (:trials (:normal 2)) (zerop value))
    (let* ((report (check-contracts :seeds '(41)))
           (entry (first (getf report :entries)))
           (result (getf entry :result)))
      (ok (eq :failed (getf report :status)))
      (ok (eq :failed (getf entry :status)))
      (ok (equal "41" (getf entry :seed)))
      (ok (stringp (getf result :definition-digest)))
      (ok (equal '(value 7) (getf result :counterexample))))))

(deftest fixture-runs-keep-their-version-two-projection
  (let ((*registry* (make-hash-table-registry)) (*calls* 0) (cleaned 0))
    (defspec-function runner-target
      (:args (value (member 7)))
      (:fixture
        (:isolation :fresh) (:version 1)
        (:recipe (recipe (member 7)))
        (:setup (context) (declare (ignore context)) (list recipe))
        (:cleanup (context) (declare (ignore context recipe)) (incf cleaned)))
      (:returns integer))
    (let* ((report (check-contracts :trials 2 :seeds '(14)))
           (result (getf (first (getf report :entries)) :result)))
      (ok (eq :passed (getf report :status)))
      (ok (eql 2 (getf result :schema-version)))
      (ok (eq :fixture-recipe (getf result :input-kind)))
      (ok (= 2 *calls* cleaned)))))
