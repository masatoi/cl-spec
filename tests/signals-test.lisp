;;;; tests/signals-test.lisp

(defpackage #:cl-spec/tests/signals-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main
                #:*registry* #:make-hash-table-registry #:defspec-function
                #:function-spec #:register-function-spec #:check-function
                #:invalid-function-spec-form #:property-result-status
                #:property-result-condition #:function-check-result-failure-reason
                #:function-check-result-explanation #:function-spec-data
                #:function-spec-signal-spec #:function-spec-return-spec
                #:spec #:spec-source-form #:definition-digest
                #:find-function-spec #:defspec #:result-data
                #:property-result-shrunk-counterexample #:property-result-counterexample
                #:function-check-result-shrunk-outcome #:property-result-rejected)
  (:import-from #:cl-spec/src/instrument
                #:instrument-function #:uninstrument-function
                #:unsupported-instrumentation-target
                #:unsupported-instrumentation-target-reason)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/signals-test)

(defvar *last-condition* nil
  "The actual condition raised by the current target invocation.")

(deftest signals-shrinking-stops-at-a-passing-error
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function missing-above-floor
      (:args (value (range integer 20 60)))
      (:signals (type simple-error)))
    (let ((result (check-function 'missing-above-floor :trials 50 :seed 1)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :missing-condition (function-check-result-failure-reason result)))
      (ok (equal '(value 21) (property-result-shrunk-counterexample result)))
      (ok (eq :used (function-check-result-shrunk-outcome result)))
      (ok (null (property-result-condition result)))
      (ok (equal '(:expected (:type simple-error))
                 (function-check-result-explanation result))))))

(deftest signals-shrinking-preserves-error-class
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function switch-error-class
      (:args (value (range integer 20 60)))
      (:signals (type division-by-zero)))
    (let ((result (check-function 'switch-error-class :trials 50 :seed 1)))
      (ok (eq :condition-spec (function-check-result-failure-reason result)))
      (ok (typep (property-result-condition result) 'simple-error))
      (ok (equal '(value 21) (property-result-shrunk-counterexample result)))
      (ok (eq :used (function-check-result-shrunk-outcome result)))
      (ok (> (getf (property-result-counterexample result) 'value) 21)))))

(defun missing-above-floor (value)
  "Return above twenty, but satisfy the expected error at the floor."
  (if (> value 20) value (error "expected at floor")))

(defun switch-error-class (value)
  "Raise different error classes across the shrink boundary."
  (if (> value 20)
      (error "value is ~D" value)
      (error 'type-error :datum value :expected-type 'string)))

(deftest signals-instrumentation-is-explicitly-unsupported
  (let ((*registry* (make-hash-table-registry))
        (original (fdefinition 'raise-error)))
    (defspec-function raise-error (:signals (type simple-error)))
    (unwind-protect
         (progn
           (ok (eq :unavailable
                   (getf (getf (function-spec-data 'raise-error) :capabilities)
                         :instrumentation)))
           (ok (handler-case (progn (instrument-function 'raise-error) nil)
                 (unsupported-instrumentation-target (condition)
                   (eq :expected-condition-contract
                       (unsupported-instrumentation-target-reason condition)))))
           (ok (eq original (fdefinition 'raise-error))))
      (uninstrument-function 'raise-error))))

(deftest signals-predicate-errors-do-not-pass
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function raise-error (:signals (satisfies broken-condition-predicate)))
    (let ((result (check-function 'raise-error :trials 1)))
      (ok (eq :condition-spec (function-check-result-failure-reason result)))
      (ok (eq :predicate-errored
              (getf (first (getf (function-check-result-explanation result) :errors)) :kind))))))

(defun broken-condition-predicate (condition)
  "Fail while checking a condition, without satisfying the contract."
  (declare (ignore condition))
  (error "predicate failed"))

(deftest signals-preconditions-still-gate-the-target
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function raise-error (:pre nil) (:signals (type simple-error)))
    (let ((result (check-function 'raise-error :trials 1)))
      (ok (not (eq :passed (property-result-status result))))
      (ok (plusp (property-result-rejected result))))))

(deftest signals-does-not-intercept-warnings
  (let ((*registry* (make-hash-table-registry))
        (warnings 0))
    (defspec-function warn-then-error (:signals (type simple-error)))
    (defspec-function warn-then-return (:signals t))
    (handler-bind ((warning (lambda (condition)
                              (incf warnings)
                              (muffle-warning condition))))
      (ok (eq :passed (property-result-status (check-function 'warn-then-error :trials 1))))
      (ok (eq :missing-condition
              (function-check-result-failure-reason
               (check-function 'warn-then-return :trials 1)))))
    (ok (= 2 warnings))))

(defun warn-then-return ()
  "Emit a warning and return without an error."
  (warn "ordinary warning")
  42)

(defun warn-then-error ()
  "Emit an ordinary warning before the required error."
  (warn "ordinary warning")
  (error "expected"))

(deftest signals-supports-composite-and-named-specs
  (let ((*registry* (make-hash-table-registry)))
    (defspec expected-error
      (and (type type-error) (satisfies type-error-datum-is-seven-p)))
    (defspec-function raise-type-error (:signals expected-error))
    (ok (eq :passed (property-result-status (check-function 'raise-type-error :trials 3))))
    (let ((digest (definition-digest 'raise-type-error :entity-kind :function-spec)))
      (defspec expected-error (type simple-error))
      (ok (not (equal digest
                      (definition-digest 'raise-type-error :entity-kind :function-spec))))
      (ok (eq :condition-spec
              (function-check-result-failure-reason
               (check-function 'raise-type-error :trials 1)))))))

(defun type-error-datum-is-seven-p (condition)
  "Check a condition slot through the existing predicate DSL."
  (= 7 (type-error-datum condition)))

(deftest signals-mismatch-retains-condition-and-explanation
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function raise-type-error (:signals (type simple-error)))
    (let* ((result (check-function 'raise-type-error :trials 1))
           (explanation (function-check-result-explanation result)))
      (ok (eq :error (property-result-status result)))
      (ok (eq :condition-spec (function-check-result-failure-reason result)))
      (ok (eq *last-condition* (property-result-condition result)))
      (ok (eq *last-condition* (getf explanation :value)))
      (ok (eq :type-failed (getf (first (getf explanation :errors)) :kind)))
      (ok (getf (getf (result-data result) :failure) :condition-report)))))

(defun raise-type-error ()
  "Signal a known condition object for evidence assertions."
  (setf *last-condition* (make-condition 'type-error :datum 7 :expected-type 'string))
  (error *last-condition*))

(deftest signals-dsl-registers-and-projects-the-contract
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function raise-error (:signals (type simple-error)))
    (let ((contract (find-function-spec 'raise-error))
           (data (function-spec-data 'raise-error))
           (digest (definition-digest 'raise-error :entity-kind :function-spec)))
      (ok (typep (function-spec-signal-spec contract) 'spec))
      (ok (eq :type (getf (getf data :signals) :kind)))
      (ok (null (getf data :returns)))
      (reinitialize-instance contract :signal-spec '(type type-error))
      (ok (not (equal digest
                      (definition-digest 'raise-error :entity-kind :function-spec)))))))

(deftest signals-construction-is-normalized-and-atomic
  (let* ((contract (make-instance 'function-spec :name 'raise-error
                                  :signal-spec '(type simple-error)))
         (original (function-spec-signal-spec contract)))
    (ok (typep original 'spec))
    (ok (equal '(type simple-error) (spec-source-form original)))
    (dolist (initargs '((:return-spec integer)
                        (:postconditions (t) :postcondition-function identity)))
      (ok (handler-case (progn (apply #'reinitialize-instance contract initargs) nil)
            (invalid-function-spec-form () t)))
      (ok (eq original (function-spec-signal-spec contract)))
      (ok (null (function-spec-return-spec contract))))
    (reinitialize-instance contract :signal-spec nil :return-spec 'integer)
    (ok (null (function-spec-signal-spec contract)))
    (ok (typep (function-spec-return-spec contract) 'spec))
    (ok (handler-case (progn (reinitialize-instance contract :signal-spec 'error) nil)
          (invalid-function-spec-form () t)))
    (ok (null (function-spec-signal-spec contract))))
  (ok (handler-case
          (progn (make-instance 'function-spec :signal-spec 'error :return-spec 't) nil)
        (invalid-function-spec-form () t))))

(deftest signals-grammar-is-strict
  (dolist (clauses '(((:signals)) ((:signals nil)) ((:signals error extra))
                     ((:signals . error)) ((:signals error) (:signals error))
                     ((:signals error) (:returns t))
                     ((:returns t) (:signals error))
                     ((:signals error) (:post))
                     ((:post t) (:signals error))))
    (ok (handler-case
            (progn (macroexpand-1 (cons 'defspec-function (cons 'raise-error clauses))) nil)
          (invalid-function-spec-form () t)) (prin1-to-string clauses))))

(defun raise-error ()
  "Signal the expected simple error."
  (error "expected"))

(defun return-normally ()
  "Return a value instead of the required error."
  42)

(deftest signals-clause-is-accepted
  (ok (handler-case
          (consp (macroexpand-1 '(defspec-function raise-error
                                  (:signals (type simple-error)))))
        (invalid-function-spec-form () nil))))

(deftest signals-checks-required-error
  (let ((*registry* (make-hash-table-registry)))
    (register-function-spec
     (make-instance 'function-spec :name 'raise-error :signal-spec '(type simple-error)))
    (ok (eq :passed (property-result-status (check-function 'raise-error :trials 1))))
    (register-function-spec
     (make-instance 'function-spec :name 'return-normally :signal-spec '(type simple-error)))
    (let ((result (check-function 'return-normally :trials 1)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :missing-condition (function-check-result-failure-reason result))))))
