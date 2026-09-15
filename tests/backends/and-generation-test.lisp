;;;; tests/backends/and-generation-test.lisp
;;;;
;;;; Acceptance tests for bounded-AND generation composability
;;;; (docs/superpowers/specs/2026-09-16-and-generation-composability-design.md §6).

(defpackage #:cl-spec/tests/backends/and-generation-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry
                #:registry-register-spec #:registry-register-generator)
  (:import-from #:cl-spec/src/generator-definition #:custom-generator)
  (:import-from #:cl-spec/src/generator
                #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable
                #:generator-unavailable-reason
                #:generation-budget-exhausted
                #:generation-budget-exhausted-attempts
                #:generation-budget-exhausted-budget
                #:generation-budget-exhausted-rejections
                #:generation-budget-exhausted-phase
                #:generation-budget-exhausted-path)
  (:import-from #:cl-spec/src/generation-request
                #:generation-report-p #:make-generation-request #:generation-request-report)
  (:import-from #:cl-spec/src/dsl #:defproperty)
  (:import-from #:cl-spec/src/property-runner
                #:run-property #:property-result-status #:property-result
                #:property-result-generation-report #:property-result-failure-phase
                #:property-result-failure-reason #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:result-data)
  (:import-from #:cl-spec/src/counterexample
                #:make-counterexample-artifact #:invalid-counterexample-artifact))

(in-package #:cl-spec/tests/backends/and-generation-test)

(defun ordered-period-p (plist)
  "The inter-field constraint the README-style period example adds to a plist."
  (<= (getf plist :start) (getf plist :end)))

(defun register-counting-spec (registry spec-name generator-name sequence)
  "Register GENERATOR-NAME drawing SEQUENCE in order, then repeating its last value."
  (let ((remaining (copy-list sequence)))
    (registry-register-generator
     registry generator-name
     (make-instance 'custom-generator
                    :name generator-name
                    :function (lambda ()
                                (if (rest remaining)
                                    (pop remaining)
                                    (first remaining)))))
    (registry-register-spec
     registry spec-name
     (normalize-spec-form 'integer :name spec-name :generator generator-name))))

(defun sample-spec (form &rest args)
  "Return (VALUES VALUES REPORT) for the normalized FORM."
  (apply #'sample (normalize-spec-form form) args))

(deftest structured-source-composes-with-a-predicate
  (let* ((spec (normalize-spec-form
                '(and (plist (:required (:start integer) (:end integer)))
                      (satisfies ordered-period-p))))
         (values (sample spec :count 30 :seed 42)))
    (ok (plusp (length values)))
    (ok (every (lambda (value) (validp spec value)) values))
    (testing "the report describes one request and passes the report validator"
      (multiple-value-bind (again report) (sample spec :count 30 :seed 42)
        (ok (equal values again))
        (ok (generation-report-p report))
        (ok (eq :request (getf report :scope)))
        (ok (eq :completed (getf report :termination)))
        (ok (= 30 (getf report :generated-values)))))))

(deftest numeric-folding-regressions-hold
  (testing "an unbounded upper bound still folds without a type error"
    (ok (every (lambda (value) (and (integerp value) (>= value 1)))
               (sample-spec '(and integer (range 1 *)) :count 20 :seed 1))))
  (testing "overlapping ranges intersect"
    (ok (every (lambda (value) (<= 10 value 20))
               (sample-spec '(and integer (range 1 20) (range 10 100)) :count 20 :seed 1))))
  (testing "an empty folded range keeps its construction diagnosis"
    (ok (handler-case
            (progn (sample-spec '(and integer (range 10 20) (range 30 40)) :count 1) nil)
          (generator-unavailable (condition)
            (search "empty" (generator-unavailable-reason condition))))))
  (testing "a reference folds its target and a residual predicate filters"
    (let ((*registry* (make-hash-table-registry)))
      (registry-register-spec *registry* 'my-range
                              (normalize-spec-form '(and integer (range 1 10))
                                                   :name 'my-range))
      (let ((values (sample-spec '(and my-range (satisfies oddp)) :count 20 :seed 2)))
        (ok (every (lambda (value) (and (oddp value) (<= 1 value 10))) values))))))

(deftest nonnumeric-type-does-not-block-a-structured-source
  (let ((values (sample-spec '(and (type list) (list-of integer)) :count 20 :seed 1)))
    (ok (plusp (length values)))
    (ok (every (lambda (value) (and (listp value) (every #'integerp value))) values))))

(deftest no-source-still-reports-ordinary-unavailability
  (ok (handler-case
          (progn (sample-spec '(and (satisfies oddp) (satisfies plusp)) :count 1) nil)
        (generation-budget-exhausted () nil)
        (generator-unavailable (condition)
          (search "no conjunct" (generator-unavailable-reason condition))))))

(deftest impossible-filter-exhausts-with-a-report
  (ok (handler-case
          (progn (sample-spec '(and (member 1) (satisfies evenp))
                              :count 1 :generation-budget 7)
                 nil)
        (generation-budget-exhausted (condition)
          (and (typep condition 'generator-unavailable)
               (= 7 (generation-budget-exhausted-attempts condition))
               (= 7 (generation-budget-exhausted-budget condition))
               (= 7 (generation-budget-exhausted-rejections condition))
               (eq :generation (generation-budget-exhausted-phase condition))
               (equal '(0) (generation-budget-exhausted-path condition))
               (search "unsatisfiable" (princ-to-string condition)))))))

(deftest last-permitted-candidate-and-explicit-zero
  (let ((*registry* (make-hash-table-registry)))
    (register-counting-spec *registry* 'count-up 'count-up-gen '(0 0 0 1))
    (register-counting-spec *registry* 'count-down 'count-down-gen '(0 0 0 0))
    (testing "the last permitted reservation may succeed"
      (multiple-value-bind (values report)
          (sample-spec '(and count-up (satisfies plusp)) :count 1 :generation-budget 4)
        (ok (equal '(1) values))
        (ok (= 4 (getf report :attempts)))
        (ok (= 3 (getf report :rejections)))
        (ok (eq :completed (getf report :termination)))))
    (testing "a further reservation is denied before another source call"
      (ok (handler-case
              (progn (sample-spec '(and count-down (satisfies plusp))
                                  :count 1 :generation-budget 4)
                     nil)
            (generation-budget-exhausted (condition)
              (and (= 4 (generation-budget-exhausted-attempts condition))
                   (= 4 (generation-budget-exhausted-rejections condition)))))))
    (testing "explicit zero is not an omission"
      (ok (handler-case
              (progn (sample-spec '(and count-up (satisfies plusp))
                                  :count 1 :generation-budget 0)
                     nil)
            (generation-budget-exhausted (condition)
              (and (= 0 (generation-budget-exhausted-attempts condition))
                   (= 0 (generation-budget-exhausted-budget condition))))))
      (multiple-value-bind (values report)
          (sample (normalize-spec-form 'integer) :count 1 :generation-budget 0)
        (ok (plusp (length values)))
        (ok (= 0 (getf report :budget)))
        (ok (eq :explicit (getf report :budget-source)))
        (ok (eq :completed (getf report :termination)))))))

(deftest sibling-filters-share-one-request-budget
  (testing "a shared budget covers both element filters"
    (let ((*registry* (make-hash-table-registry)))
      (register-counting-spec *registry* 'count-a 'count-a-gen '(0 0 1))
      (register-counting-spec *registry* 'count-b 'count-b-gen '(0 0 1))
      (multiple-value-bind (values report)
          (sample-spec '(tuple (and count-a (satisfies plusp))
                               (and count-b (satisfies plusp)))
                       :count 1 :generation-budget 6)
        (ok (equal '((1 1)) values))
        (ok (= 6 (getf report :attempts)))
        (ok (= 4 (getf report :rejections))))))
  (testing "one request's budget is not reset between elements"
    (let ((*registry* (make-hash-table-registry)))
      (register-counting-spec *registry* 'count-c 'count-c-gen '(0 0 1))
      (register-counting-spec *registry* 'count-d 'count-d-gen '(0 0 1))
      (ok (handler-case
              (progn (sample-spec '(tuple (and count-c (satisfies plusp))
                                          (and count-d (satisfies plusp)))
                                  :count 1 :generation-budget 5)
                     nil)
            (generation-budget-exhausted () t))))))

(deftest a-difficult-value-may-exceed-one-thousand-candidates
  (let ((*registry* (make-hash-table-registry)))
    (register-counting-spec *registry* 'hard 'hard-gen
                            (append (make-list 1500 :initial-element 0) '(1)))
    (multiple-value-bind (values report)
        (sample-spec '(and hard (satisfies plusp)) :count 1 :generation-budget 2000)
      (ok (equal '(1) values))
      (ok (= 1501 (getf report :attempts)))
      (ok (eq :completed (getf report :termination))))))

(deftest sequential-requests-get-fresh-counters
  (let ((spec (normalize-spec-form '(and (member 1) (satisfies plusp)))))
    (multiple-value-bind (values-a report-a) (sample spec :count 5 :seed 9)
      (multiple-value-bind (values-b report-b) (sample spec :count 5 :seed 9)
        (ok (equal values-a values-b))
        (ok (equal report-a report-b))
        (ok (= 5 (getf report-a :generated-values)))))))

(deftest capability-is-construction-only
  (let ((backend (make-instance 'check-it-backend)))
    (testing "an impossible but constructible filter is still :available"
      (ok (equal '(:generation :available :shrinking :available)
                 (backend-capabilities
                  backend (normalize-spec-form '(and (member 1) (satisfies evenp)))))))
    (testing "no source is :unavailable"
      (ok (equal '(:generation :unavailable :shrinking :unavailable)
                 (backend-capabilities
                  backend (normalize-spec-form '(and (satisfies oddp) (satisfies plusp)))))))))

(deftest report-validator-rejects-incoherent-reports
  (let ((valid (generation-request-report (make-generation-request :planned 3))))
    (ok (generation-report-p valid))
    (flet ((broken (key value)
             (let ((copy (copy-list valid)))
               (setf (getf copy key) value)
               copy)))
      (ok (not (generation-report-p (broken :attempts 4000))))
      (ok (not (generation-report-p (broken :rejections 5))))
      (ok (not (generation-report-p (broken :generated-values 4))))
      (ok (not (generation-report-p (broken :termination :budget-exhausted))))
      (ok (not (generation-report-p (broken :scope :global))))
      (ok (not (generation-report-p (broken :policy :other))))
      (let ((copy (copy-list valid)))
        (setf (getf copy :phases)
              (list :generation (list :attempts 1 :rejections 1)
                    :shrinking (list :attempts 0 :rejections 0)))
        (ok (not (generation-report-p copy)))))))

(deftest runner-reports-the-generation-only-error-branch
  (let ((*registry* (make-hash-table-registry)))
    (defproperty impossible-law
        ((x (and (member 1) (satisfies evenp))))
      (:trials (:normal 5))
      t)
    (let* ((result (run-property 'impossible-law :seed 1
                                 :options '(:generation-budget 8)))
           (report (property-result-generation-report result)))
      (ok (eq :error (property-result-status result)))
      (ok (eq :generation (property-result-failure-phase result)))
      (ok (eq :generation-budget-exhausted (property-result-failure-reason result)))
      (ok (null (property-result-counterexample result)))
      (ok (generation-report-p report))
      (ok (eq :budget-exhausted (getf report :termination)))
      (ok (eq :generation (getf report :exhaustion-phase)))
      (testing "result-data exposes the report and the phase"
        (let ((data (result-data result)))
          (ok (equal report (getf data :generation-report)))
          (ok (eq :generation (getf data :failure-phase)))
          (ok (eq :generation-budget-exhausted (getf data :failure-reason)))))
      (testing "no counterexample artifact is manufactured from a generation-only result"
        (ok (handler-case
                (progn (make-counterexample-artifact result) nil)
              (invalid-counterexample-artifact () t)))))))

(deftest runner-reports-generation-work-for-target-outcomes
  (let ((*registry* (make-hash-table-registry)))
    (defproperty filtered-law
        ((x (and (plist (:required (:start integer) (:end integer)))
                 (satisfies ordered-period-p))))
      (:trials (:normal 30))
      (< (getf x :start) (getf x :end)))
    (let* ((result (run-property 'filtered-law :seed 5))
           (report (property-result-generation-report result))
           (data (result-data result)))
      (ok (member (property-result-status result) '(:passed :failed)))
      (ok (generation-report-p report))
      (ok (plusp (getf report :attempts)))
      (ok (eq :request (getf report :scope)))
      (ok (equal report (getf data :generation-report)))
      (ok (eq :not-collected
              (getf (result-data (make-instance 'property-result
                                                :trials 0 :status :pending))
                    :generation-report))))))

(deftest shrinking-never-adopts-a-candidate-outside-the-and
  (let ((*registry* (make-hash-table-registry))
        (spec (normalize-spec-form '(and (range integer 1 100) (satisfies oddp)))))
    (defproperty odd-under-fifty
        ((x (and (range integer 1 100) (satisfies oddp))))
      (:trials (:normal 100))
      (< x 50))
    (let* ((result (run-property 'odd-under-fifty :seed 3))
           (original (getf (property-result-counterexample result) 'x))
           (shrunk (getf (property-result-shrunk-counterexample result) 'x)))
      (ok (eq :failed (property-result-status result)))
      (ok (validp spec original))
      (testing "any adopted reduction still satisfies the whole AND"
        (when shrunk
          (ok (validp spec shrunk))
          (ok (>= shrunk 50)))))))
