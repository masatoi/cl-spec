;;;; tests/function-cases-test.lisp
;;;;
;;;; Named per-condition Function Spec cases.  The tests are grouped by the
;;;; invariant they pin down rather than by the function they call, and the
;;;; selection ones drive a controlled input sequence instead of depending on
;;;; what a seed happens to draw.

(defpackage #:cl-spec/tests/function-cases-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec
                #:defspec-function #:defgenerator #:check-function
                #:find-function-spec #:make-hash-table-registry
                #:function-spec-data #:result-data
                #:definition-digest #:definition-description
                #:function-check-result-case-report
                #:function-check-result-failure-reason
                #:function-check-result-explanation
                #:function-check-result-shrunk-outcome
                #:function-check-result
                #:property-result-status #:property-result-trials
                #:property-result-rejected #:property-result-failure-phase
                #:property-result-failure-evidence #:property-result-shrunk-evidence
                #:property-result-counterexample #:property-result-shrunk-counterexample
                #:property-result-condition #:property-result-shrink-report
                #:property-result-seed
                #:trial-observation-case #:trial-observation-signature
                #:failure-identities-match-p
                #:make-counterexample-artifact #:recheck-counterexample
                #:counterexample-artifact-data #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact
                #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason
                #:case-selection-error #:case-selection-error-kind
                #:case-selection-error-cases #:case-selection-error-case
                #:case-selection-error-original-condition
                #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/function-spec
                #:function-case #:function-spec
                #:function-spec-cases)
  (:import-from #:cl-spec/src/schema
                #:definition-instrumentation-capability)
  (:import-from #:cl-spec/src/instrument
                #:instrument-function #:instrumentation-status
                #:instrumented-function-p #:uninstrument-function
                #:refresh-instrumentation #:*instrumented-functions*
                #:unsupported-instrumentation-target
                #:unsupported-instrumentation-target-reason))

(in-package #:cl-spec/tests/function-cases-test)

;;; Helpers

(define-condition insufficient-funds (error) ())

(defun refuses-p (thunk)
  "True when THUNK signals INVALID-FUNCTION-SPEC-FORM."
  (handler-case (progn (funcall thunk) nil)
    (invalid-function-spec-form () t)))

(defmacro refuses (&body body)
  "True when BODY signals INVALID-FUNCTION-SPEC-FORM."
  `(refuses-p (lambda () ,@body)))

(defmacro with-scripted-generator ((name inputs) &body body)
  "Register generator NAME drawing INPUTS in order, then run BODY.

INPUTS is a literal list of argument lists.  A controlled sequence keeps case
selection tests off the seed, so 'both cases happened to be sampled' never
decides whether they pass."
  (let ((script (gensym "SCRIPT")))
    `(let ((,script ',inputs))
       (cl-spec:defgenerator ,name () (pop ,script))
       ,@body)))

(defmacro with-fresh-registry (&body body)
  "Run BODY with an empty registry, so a contract from another test is invisible."
  `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
     ,@body))

(defvar *calls* 0 "Target invocations the current test counts.")

(defun reset-calls () (setf *calls* 0))

(defun balance-conditional (balance amount)
  "Return the remainder, or signal the named error when the balance is short."
  (incf *calls*)
  (if (<= amount balance)
      (- balance amount)
      (error 'insufficient-funds)))

(defun balance-returning (balance amount)
  "A conforming-target-shaped function that never signals."
  (incf *calls*)
  (- balance amount))

(defun balance-wrong-error (balance amount)
  "Signal an error of the wrong type for the expected-error case."
  (declare (ignore balance amount))
  (incf *calls*)
  (error "not-insufficient-funds"))

(defun pair-sum (a b)
  "Return the sum and the difference as two values."
  (incf *calls*)
  (values (+ a b) (- a b)))

(defun broken-arity (x)
  "Call CONS with too many arguments, which is a PROGRAM-ERROR at run time."
  (incf *calls*)
  (funcall (symbol-function 'cons) x 1 2))

(defun probe (x)
  "Return the same sign as X, used by the selection-error tests."
  (incf *calls*)
  (if (plusp x) x (- x)))

(defun overlapping (x)
  "An identity whose contract's guards overlap at zero."
  (incf *calls*)
  x)

(defun guarded (x)
  "An identity behind a contract with a signalling guard."
  (incf *calls*)
  x)

(defun counted (x)
  "An identity whose guard is counted."
  (incf *calls*)
  x)

(defun gated (x)
  "An identity behind a contract with a common :PRE."
  (incf *calls*)
  x)

(defun optional-target (x &optional y)
  "An identity whose optional argument the guards observe."
  (incf *calls*)
  (if y (+ x y) x))

(defun confusing (x)
  "Ignoring its input's sign, return its magnitude."
  (incf *calls*)
  (abs x))

(defun never-selected (x)
  "An identity used by the :when NIL test."
  (incf *calls*)
  x)

(defun selective (x)
  "An identity used by the non-selected-outcome test."
  (incf *calls*)
  x)

(defun wrong-sign (x)
  "An identity used by the case-less artifact test."
  (incf *calls*)
  x)

(defun incremental (x)
  "Return one more than X, which violates a spec that demands exactly one."
  (incf *calls*)
  (1+ x))

(defun instrumented-probe (x)
  "An ordinary function used by the unsupported-instrumentation test."
  (incf *calls*)
  x)

(defun capability-probe (x)
  "An ordinary function used by the capability-query test."
  (incf *calls*)
  x)

(defun report-case (report name)
  "Return the :CASES entry of REPORT for NAME."
  (find name (getf report :cases) :key (lambda (entry) (getf entry :name))))

;;; A. Declaration

(deftest cases-declare-ordered-named-outcomes
  (with-fresh-registry
    (cl-spec:defspec-function balance-conditional
      (:args (balance (range integer 0 100)) (amount (range integer 0 100)))
      (:cases
        (:sufficient-funds
          "Return the remainder."
          (:when (<= amount balance))
          (:returns (range integer 0 *))
          (:post (= result (- balance amount))))
        (:insufficient-funds
          (:when (> amount balance))
          (:signals (type insufficient-funds)))))
    (let* ((contract (find-function-spec 'balance-conditional))
           (data (function-spec-data 'balance-conditional))
           (cases (getf data :cases)))
      (testing "the cases stay on the one contract registered under the name"
        (ok (typep contract 'function-spec))
        (ok (= 2 (length (function-spec-cases contract)))))
      (testing "selection is exclusive and the order is declaration order"
        (ok (eq :exclusive (getf data :case-selection)))
        (ok (equal '(:sufficient-funds :insufficient-funds)
                   (mapcar (lambda (case) (getf case :name)) cases))))
      (testing "each case projects its guard, outcome kind and normalized outcome"
        (let ((sufficient (first cases)))
          (ok (equal '(<= amount balance) (getf sufficient :when)))
          (ok (eq :returns (getf sufficient :outcome)))
          (ok (eq :range (getf (getf sufficient :returns) :kind)))
          (ok (equal '((= result (- balance amount)))
                     (getf sufficient :postconditions)))
          (ok (string= "Return the remainder." (getf sufficient :documentation))))
        (let ((insufficient (second cases)))
          (ok (eq :signals (getf insufficient :outcome)))
          (ok (eq :type (getf (getf insufficient :signals) :kind)))
          (ok (null (getf insufficient :returns)))))
      (testing "the projection carries no executable closure"
        (let ((flat (labels ((flatten (value)
                               (cond ((functionp value) (list value))
                                     ((consp value) (mapcan #'flatten value))
                                     (t nil))))
                      (flatten data))))
          (ok (null flat)))))))

(deftest a-case-less-projection-has-no-case-keys
  (with-fresh-registry
    (cl-spec:defspec-function balance-returning
      (:args (balance integer) (amount integer))
      (:returns integer))
    (let ((data (function-spec-data 'balance-returning)))
      (ok (null (getf data :cases)))
      (ok (null (getf data :case-selection)))
      (ok (nth-value 1 (definition-digest (find-function-spec 'balance-returning)))))))

(deftest malformed-case-declarations-are-refused
  (testing "an empty :cases clause is refused"
    (ok (refuses (macroexpand-1 '(cl-spec:defspec-function f (:cases))))))
  (testing "a duplicate case name is refused"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases
                      (:a (:when t) (:returns integer))
                      (:a (:when nil) (:returns integer))))))))
  (testing "a case without :when is refused"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:returns integer))))))))
  (testing "a case with two outcome clauses, or none, is refused"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t) (:returns integer) (:signals t)))))))
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t))))))))
  (testing "postconditions on a :signals case are refused in this version"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t) (:signals error) (:post t))))))))
  (testing "unknown and duplicated case clauses are refused"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t) (:returns integer) (:pre t)))))))
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t) (:when t) (:returns integer))))))))
  (testing "a non-keyword case name and a two-form :when are refused"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (a (:when t) (:returns integer)))))))
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when t t) (:returns integer))))))))
  (testing "a case cannot share a contract with a top-level outcome"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:returns integer)
                    (:cases (:a (:when t) (:returns integer))))))))
  (testing "a case guard cannot read the return value"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                    (:args (x integer))
                    (:cases (:a (:when result) (:returns integer)))))))))

(defun guarded-case (outcome &key (name :a) (when-forms '(t)) (when-function (lambda (x)
                                                                               (declare (ignore x))
                                                                               t)))
  "Build a well-formed case for the construction-path tests."
  (make-instance 'function-case
                 :name name :when-forms when-forms :when-function when-function
                 :outcome-kind (if (eq outcome :signals) :signals :returns)
                 :outcome-spec (if (eq outcome :signals) 'error 'integer)
                 :source-form (list name (cons :when when-forms) (list outcome 'integer))))

(deftest programmatic-case-construction-obeys-the-same-rules
  (testing "a guard predicate and its form must be present together"
    (ok (refuses (make-instance 'function-case
                                :name :a :when-forms '((plusp x))
                                :outcome-kind :returns :outcome-spec 'integer
                                :source-form '(:a (:when (plusp x)) (:returns integer)))))
    (ok (refuses (make-instance 'function-case
                                :name :a
                                :when-function (lambda (x) (declare (ignore x)) t)
                                :outcome-kind :returns :outcome-spec 'integer
                                :source-form '(:a (:when t) (:returns integer))))))
  (testing "a case name and an outcome kind are checked"
    (ok (refuses (guarded-case :returns :name "a")))
    (ok (refuses (make-instance 'function-case
                                :name :a :when-forms '(t)
                                :when-function (lambda () t)
                                :outcome-kind :either :outcome-spec 'integer
                                :source-form '(:a (:when t) (:returns integer))))))
  (testing "a contract refuses cases combined with its own outcome"
    (let ((case (guarded-case :returns)))
      (ok (refuses (make-instance 'function-spec
                                  :name 'f :argument-specs '((x integer))
                                  :return-spec 'integer :cases (list case))))
      (ok (refuses (make-instance 'function-spec
                                  :name 'f :argument-specs '((x integer))
                                  :cases (list case case))))))
  (testing "a case post-value binding is checked against the contract's arguments"
    (ok (refuses
         (make-instance 'function-case
                        :name :a :when-forms '(t)
                        :when-function (lambda (x) (declare (ignore x)) t)
                        :outcome-kind :returns
                        :outcome-spec '(values integer integer)
                        :post-value-variables '(x)
                        :postconditions '(t)
                        :postcondition-function (lambda (values x)
                                                  (declare (ignore values x))
                                                  t)
                        :source-form '(:a (:when t) (:returns (values integer integer))
                                       (:post-values (x) t)))))))

(deftest a-refused-case-edit-keeps-the-registered-contract
  (with-fresh-registry
    (cl-spec:defspec-function balance-returning
      (:args (balance integer) (amount integer))
      (:cases (:sufficient-funds (:when (<= amount balance)) (:returns integer))))
    (let* ((contract (find-function-spec 'balance-returning))
           (before (definition-digest contract)))
      (ok (refuses (reinitialize-instance contract :cases 'not-a-case-list)))
      (ok (equal before (definition-digest contract)))
      (ok (= 1 (length (function-spec-cases contract)))))))

;;; B. Selection

(deftest exactly-one-matching-case-is-selected-and-called-once
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((10 4) (4 10)))
      (cl-spec:defspec-function balance-conditional
        (:args (balance (range integer 0 100)) (amount (range integer 0 100)))
        (:args-generator scripted)
        (:cases
          (:sufficient-funds (:when (<= amount balance)) (:returns (range integer 0 *)))
          (:insufficient-funds (:when (> amount balance))
                               (:signals (type insufficient-funds)))))
      (let* ((result (check-function 'balance-conditional :trials 2 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 2 *calls*))
        (ok (= 1 (getf (report-case report :sufficient-funds) :called)))
        (ok (= 1 (getf (report-case report :insufficient-funds) :called)))
        (ok (null (getf report :never-called)))))))

(deftest no-matching-case-calls-no-target
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((5) (0)))
      (cl-spec:defspec-function probe
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:positive (:when (plusp x)) (:returns (range integer 1 *)))
          (:negative (:when (minusp x)) (:returns (range integer 1 *)))))
      (let* ((result (check-function 'probe :trials 2 :seed 1))
             (report (function-check-result-case-report result))
             (condition (property-result-condition result)))
        (testing "the error is a contract-side selection error"
          (ok (eq :error (property-result-status result)))
          (ok (eq :contract-error (function-check-result-failure-reason result)))
          (ok (eq :case-selection (property-result-failure-phase result)))
          (ok (typep condition 'case-selection-error))
          (ok (eq :no-matching-case (case-selection-error-kind condition))))
        (testing "the target is not called and no case is credited"
          (ok (= 1 *calls*))
          (ok (= 0 (property-result-rejected result)))
          (ok (= 1 (getf report :case-selection-errors)))
          (ok (= 1 (getf (report-case report :positive) :called)))
          (ok (equal '(:negative) (getf report :never-called))))
        (testing "the failure identity is the selection error and is not shrunk"
          (ok (equal '(:case-selection :no-matching-case)
                     (trial-observation-signature
                      (property-result-failure-evidence result))))
          (ok (eq :none (function-check-result-shrunk-outcome result)))
          (ok (eq :not-a-target-failure
                  (getf (property-result-shrink-report result) :termination))))))))

(deftest ambiguous-case-calls-no-target
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((0)))
      (cl-spec:defspec-function overlapping
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:non-negative (:when (>= x 0)) (:returns integer))
          (:non-positive (:when (<= x 0)) (:returns integer))))
      (let* ((result (check-function 'overlapping :trials 1 :seed 1))
             (condition (property-result-condition result)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :case-selection (property-result-failure-phase result)))
        (ok (= 0 *calls*))
        (ok (eq :ambiguous-case (case-selection-error-kind condition)))
        (ok (equal '(:non-negative :non-positive) (case-selection-error-cases condition)))
        (ok (equal '(:case-selection :ambiguous-case)
                   (trial-observation-signature
                    (property-result-failure-evidence result))))
        (ok (equal '(:non-negative :non-positive)
                   (getf (function-check-result-explanation result) :cases)))))))

(deftest a-matching-case-does-not-hide-a-later-guard-error
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1)))
      (cl-spec:defspec-function guarded
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:first (:when t) (:returns integer))
          (:second (:when (error "later guard exploded")) (:returns integer))))
      (let* ((result (check-function 'guarded :trials 1 :seed 1))
             (condition (property-result-condition result)))
        (testing "every guard runs, so a later error is observed rather than skipped"
          (ok (eq :error (property-result-status result)))
          (ok (eq :case-guard-error (case-selection-error-kind condition)))
          (ok (eq :second (case-selection-error-case condition)))
          (ok (typep (case-selection-error-original-condition condition) 'simple-error))
          (ok (= 0 *calls*)))
        (testing "the explanation names the case and keeps the original condition"
          (let ((data (function-check-result-explanation result)))
            (ok (eq :case-selection-error (getf data :kind)))
            (ok (eq :second (getf data :case)))
            (ok (eq 'simple-error (getf data :condition-type)))
            (ok (stringp (getf data :condition-report)))))))))

(deftest guards-run-once-per-admitted-trial
  (with-fresh-registry
    (reset-calls)
    (let ((guard-calls 0))
      (with-scripted-generator (scripted ((1) (2) (3)))
        (cl-spec:defspec-function counted
          (:args (x integer))
          (:args-generator scripted)
          (:cases
            (:always (:when (progn (incf guard-calls) t)) (:returns integer))))
        (let ((result (check-function 'counted :trials 3 :seed 1)))
          (ok (eq :passed (property-result-status result)))
          (ok (= 3 guard-calls))
          (ok (= 3 *calls*)))))))

(deftest precondition-refusal-skips-cases-and-target
  (with-fresh-registry
    (reset-calls)
    (let ((guard-calls 0))
      (with-scripted-generator (scripted ((5)))
        (cl-spec:defspec-function gated
          (:args (x integer))
          (:args-generator scripted)
          (:pre (< x 0))
          (:cases
            (:always (:when (progn (incf guard-calls) t)) (:returns integer))))
        (let* ((result (check-function 'gated :trials 1 :seed 1))
               (report (function-check-result-case-report result)))
          (ok (eq :skipped (property-result-status result)))
          (ok (= 1 (property-result-trials result)))
          (ok (= 1 (property-result-rejected result)))
          (ok (= 0 guard-calls))
          (ok (= 0 *calls*))
          (ok (= 0 (getf report :case-selection-errors)))
          (ok (equal '(:always) (getf report :never-called))))))))

(deftest guards-see-optional-and-suppliedness-bindings
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1) (2 5)))
      (cl-spec:defspec-function optional-target
        (:args (x integer) &optional (y integer y-p))
        (:args-generator scripted)
        (:cases
          (:supplied (:when y-p) (:returns integer))
          (:omitted (:when (not y-p)) (:returns integer))))
      (let* ((result (check-function 'optional-target :trials 2 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 1 (getf (report-case report :supplied) :called)))
        (ok (= 1 (getf (report-case report :omitted) :called)))))))

(deftest a-returned-value-does-not-reselect-the-case
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((-5)))
      (cl-spec:defspec-function confusing
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:negative-input (:when (minusp x)) (:returns (range integer -100 -1)))
          (:positive-input (:when (plusp x)) (:returns (range integer 0 *)))))
      ;; The target returns +5 for a negative input, which would satisfy the
      ;; other case's spec.  The case came from the input, so a "would have
      ;; matched" case is not searched for afterwards.
      (let ((result (check-function 'confusing :trials 1 :seed 1)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :negative-input (trial-observation-case
                                 (property-result-failure-evidence result))))
        (ok (eq :return-spec (function-check-result-failure-reason result)))))))

(deftest a-when-form-of-nil-never-selects
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1)))
      (cl-spec:defspec-function never-selected
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:never (:when nil) (:returns integer))
          (:always (:when t) (:returns integer))))
      (let* ((result (check-function 'never-selected :trials 1 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (equal '(:never) (getf report :never-called)))
        (ok (= 1 (getf (report-case report :always) :called)))))))

;;; C. Post-selection outcome contracts

(deftest case-outcomes-classify-like-case-less-contracts
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((10 3) (3 10) (10 10)))
      (cl-spec:defspec-function balance-conditional
        (:args (balance (range integer 0 100)) (amount (range integer 0 100)))
        (:args-generator scripted)
        (:cases
          (:sufficient-funds (:when (<= amount balance))
                             (:returns (range integer 0 *))
                             (:post (= result (- balance amount))))
          (:insufficient-funds (:when (> amount balance))
                               (:signals (type insufficient-funds)))))
      (let* ((result (check-function 'balance-conditional :trials 3 :seed 1))
             (report (function-check-result-case-report result)))
        (testing "a successful expected-error trial counts as a pass for its case"
          (ok (eq :passed (property-result-status result)))
          (ok (= 3 *calls*))
          (ok (= 2 (getf (report-case report :sufficient-funds) :called)))
          (ok (= 1 (getf (report-case report :insufficient-funds) :called)))
          (ok (= 1 (getf (report-case report :insufficient-funds) :passed))))))))

(deftest a-returning-function-missing-an-expected-error-is-a-missing-condition
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1 2)))
      (cl-spec:defspec-function balance-returning
        (:args (balance integer) (amount integer))
        (:args-generator scripted)
        (:cases
          (:no-error (:when t) (:signals (type insufficient-funds)))))
      (let ((result (check-function 'balance-returning :trials 1 :seed 1)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :missing-condition (function-check-result-failure-reason result)))
        (ok (equal '(:case :no-error :missing-condition)
                   (trial-observation-signature
                    (property-result-failure-evidence result))))))))

(deftest a-wrong-condition-is-a-condition-spec-failure
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1 2)))
      (cl-spec:defspec-function balance-wrong-error
        (:args (balance integer) (amount integer))
        (:args-generator scripted)
        (:cases
          (:expected (:when t) (:signals (type insufficient-funds)))))
      (let ((result (check-function 'balance-wrong-error :trials 1 :seed 1)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :condition-spec (function-check-result-failure-reason result)))))))

(deftest case-post-values-bind-fixed-returns
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((3 4)))
      (cl-spec:defspec-function pair-sum
        (:args (a integer) (b integer))
        (:args-generator scripted)
        (:cases
          (:sum (:when t)
                (:returns (values integer integer))
                (:post-values (total difference)
                  (and (= total (+ a b)) (= difference (- a b)))))))
      (let ((result (check-function 'pair-sum :trials 1 :seed 1)))
        (ok (eq :passed (property-result-status result))))))
  (testing "a case :post-values name list is checked against the case arity"
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function bad
                    (:args (a integer))
                    (:cases
                      (:sum (:when t)
                            (:returns (values integer integer))
                            (:post-values (only-one) (declare (ignore only-one)) t)))))))))

(deftest a-non-selected-case-outcome-never-runs
  (with-fresh-registry
    (reset-calls)
    (let ((post-calls 0))
      (with-scripted-generator (scripted ((1)))
        (cl-spec:defspec-function selective
          (:args (x integer))
          (:args-generator scripted)
          (:cases
            (:chosen (:when t) (:returns integer)
                     (:post (progn (incf post-calls) t)))
            (:other (:when nil) (:returns integer)
                    (:post (error "the unchosen case must not run")))))
        (let ((result (check-function 'selective :trials 1 :seed 1)))
          (ok (eq :passed (property-result-status result)))
          (ok (= 1 post-calls)))))))

(deftest a-signals-case-does-not-certify-a-broken-call
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1)))
      (cl-spec:defspec-function broken-arity
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:any-error (:when t) (:signals (type error)))))
      ;; The target signals a PROGRAM-ERROR, which never satisfies (type error)
      ;; as an expected outcome.
      (let ((result (check-function 'broken-arity :trials 1 :seed 1)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :condition (function-check-result-failure-reason result)))))))

;;; D. Report

(deftest a-failing-case-is-counted-with-its-outcome
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((2)))
      (cl-spec:defspec-function incremental
        (:args (x (range integer 0 100)))
        (:args-generator scripted)
        (:cases
          (:zero (:when (zerop x)) (:returns (range integer 1 1)))
          (:positive (:when (plusp x)) (:returns (range integer 1 1)))))
      (let* ((result (check-function 'incremental :trials 1 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :failed (property-result-status result)))
        (ok (= 1 (getf (report-case report :positive) :called)))
        (ok (= 1 (getf (report-case report :positive) :failed)))
        (ok (= 0 (getf (report-case report :zero) :called)))
        (ok (equal '(:zero) (getf report :never-called)))))))

(deftest shrinking-calls-do-not-inflate-a-case-count
  (with-fresh-registry
    (reset-calls)
    (cl-spec:defspec-function incremental
      (:args (x (range integer 0 100)))
      (:cases
        (:zero (:when (zerop x)) (:returns (range integer 1 1)))
        (:positive (:when (plusp x)) (:returns (range integer 1 1)))))
    (let* ((result (check-function 'incremental :trials 20 :seed 3))
           (report (function-check-result-case-report result)))
      (testing "shrinking ran, and its invocations are not trials"
        (ok (eq :failed (property-result-status result)))
        (ok (eq :used (function-check-result-shrunk-outcome result)))
        (ok (= 1 (property-result-trials result)))
        (ok (= 1 (getf (report-case report :positive) :called)))))))

(deftest the-case-report-survives-result-data
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((7 3)))
      (cl-spec:defspec-function balance-conditional
        (:args (balance integer) (amount integer))
        (:args-generator scripted)
        (:cases
          (:sufficient-funds (:when (<= amount balance)) (:returns integer))
          (:insufficient-funds (:when (> amount balance))
                               (:signals (type insufficient-funds)))))
      (let* ((result (check-function 'balance-conditional :trials 1 :seed 1))
             (data (result-data result)))
        (ok (equal (function-check-result-case-report result) (getf data :case-report)))
        (ok (eq :normal-trials (getf (getf data :case-report) :unit)))
        (ok (eq :exclusive (getf (getf data :case-report) :selection)))))))

(deftest case-counters-belong-to-one-run
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((5 1) (5 1)))
      (cl-spec:defspec-function balance-conditional
        (:args (balance integer) (amount integer))
        (:args-generator scripted)
        (:cases
          (:sufficient-funds (:when (<= amount balance)) (:returns integer))
          (:insufficient-funds (:when (> amount balance))
                               (:signals (type insufficient-funds)))))
      (let ((first-run (check-function 'balance-conditional :trials 1 :seed 1))
            (second-run (check-function 'balance-conditional :trials 1 :seed 1)))
        (ok (= 1 (getf (report-case (function-check-result-case-report first-run)
                                    :sufficient-funds)
                       :called)))
        (ok (= 1 (getf (report-case (function-check-result-case-report second-run)
                                    :sufficient-funds)
                       :called)))
        (ok (not (eq (function-check-result-case-report first-run)
                     (function-check-result-case-report second-run))))))))

(deftest a-result-without-a-run-reports-not-collected
  (let ((result (make-instance 'function-check-result :trials 0 :property 'f)))
    (ok (eq :not-collected (function-check-result-case-report result)))
    (ok (eq :not-collected (getf (result-data result) :case-report)))))

(deftest a-fully-rejected-run-reports-an-empty-measurement
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((1)))
      (cl-spec:defspec-function gated
        (:args (x integer))
        (:args-generator scripted)
        (:pre nil)
        (:cases (:always (:when t) (:returns integer))))
      (let* ((result (check-function 'gated :trials 1 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :skipped (property-result-status result)))
        (ok (= 1 (property-result-rejected result)))
        (ok (= 0 (getf (report-case report :always) :called)))
        (ok (= 0 (getf report :case-selection-errors)))
        (ok (equal '(:always) (getf report :never-called)))))))

;;; E. Evidence, shrinking, replay and artifacts

(deftest the-case-name-is-part-of-the-failure-identity
  (let ((inner '(:return-value :return-spec ((:kind :out-of-range)))))
    (testing "the same inner failure in two cases is two failures"
      (ok (failure-identities-match-p (cons :case (cons :a inner))
                                      (cons :case (cons :a inner))))
      (ok (not (failure-identities-match-p (cons :case (cons :a inner))
                                           (cons :case (cons :b inner))))))
    (testing "the rules inside a case are the established ones"
      (ok (failure-identities-match-p '(:case :a :return-value :return-spec ())
                                      '(:case :a :return-value :postcondition
                                        (:post-form 0))))
      (ok (not (failure-identities-match-p
                '(:case :a :return-value :postcondition (:post-form 0))
                '(:case :a :return-value :postcondition nil)))))
    (testing "a wrapped identity never matches an unwrapped one"
      (ok (not (failure-identities-match-p (cons :case (cons :a inner)) inner)))
      (ok (not (failure-identities-match-p inner (cons :case (cons :a inner))))))))

(deftest shrinking-stays-inside-the-selected-case
  (with-fresh-registry
    (reset-calls)
    (cl-spec:defspec-function incremental
      (:args (x (range integer 0 100)))
      (:cases
        (:zero (:when (zerop x)) (:returns (range integer 1 1)))
        (:positive (:when (plusp x)) (:returns (range integer 1 1)))))
    (let* ((result (check-function 'incremental :trials 20 :seed 3))
           (shrunk (property-result-shrunk-evidence result)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :used (function-check-result-shrunk-outcome result)))
      (ok (eq :positive (trial-observation-case shrunk)))
      (ok (equal (trial-observation-signature (property-result-failure-evidence result))
                 (trial-observation-signature shrunk)))
      (ok (plusp (getf (property-result-shrunk-counterexample result) 'x))))))

(deftest an-artifact-round-trip-preserves-the-case
  (with-fresh-registry
    (reset-calls)
    (cl-spec:defspec-function incremental
      (:args (x (range integer 0 100)))
      (:cases
        (:zero (:when (zerop x)) (:returns (range integer 1 1)))
        (:positive (:when (plusp x)) (:returns (range integer 1 1)))))
    (let* ((result (check-function 'incremental :trials 20 :seed 3))
           (artifact (make-counterexample-artifact result))
           (data (counterexample-artifact-data artifact))
           (recheck (recheck-counterexample artifact :state-policy :stateless)))
      (testing "the persisted signature keeps the case wrapper"
        (ok (eq :case (first (getf (getf data :original) :signature))))
        (ok (eq :positive (second (getf (getf data :original) :signature)))))
      (testing "a direct recheck recognises the same case's failure"
        (ok (eq :same-failure (getf recheck :status))))
      (testing "a deserialized copy behaves the same"
        (ok (eq :same-failure
                (getf (recheck-counterexample
                       (deserialize-counterexample-artifact
                        (serialize-counterexample-artifact artifact))
                       :state-policy :stateless)
                      :status)))))))

(deftest a-case-selection-failure-is-not-persisted
  (with-fresh-registry
    (reset-calls)
    (with-scripted-generator (scripted ((0)))
      (cl-spec:defspec-function probe
        (:args (x integer))
        (:args-generator scripted)
        (:cases
          (:positive (:when (plusp x)) (:returns integer))
          (:negative (:when (minusp x)) (:returns integer))))
      (let ((result (check-function 'probe :trials 1 :seed 1)))
        (ok (eq :case-selection (property-result-failure-phase result)))
        (ok (eq :case-selection-failure
                (handler-case (progn (make-counterexample-artifact result) :no-error)
                  (invalid-counterexample-artifact (condition)
                    (invalid-counterexample-artifact-reason condition)))))))))

(deftest replay-reproduces-the-case-and-the-failure
  (with-fresh-registry
    (reset-calls)
    (cl-spec:defspec-function incremental
      (:args (x (range integer 0 100)))
      (:cases
        (:zero (:when (zerop x)) (:returns (range integer 1 1)))
        (:positive (:when (plusp x)) (:returns (range integer 1 1)))))
    (let* ((first-run (check-function 'incremental :trials 5 :seed 11))
           (replay (check-function 'incremental :seed first-run)))
      (ok (eq :failed (property-result-status first-run)))
      (ok (eq :failed (property-result-status replay)))
      (ok (equal (property-result-counterexample first-run)
                 (property-result-counterexample replay)))
      (ok (equal (trial-observation-case (property-result-failure-evidence first-run))
                 (trial-observation-case (property-result-failure-evidence replay))))
      (ok (eq (property-result-seed first-run) (property-result-seed replay))))))

(deftest a-case-less-artifact-still-round-trips
  (with-fresh-registry
    (reset-calls)
    ;; Independent generation, not the scripted generator: a completed digest is
    ;; what a recheck compares, and a generator whose own source holds a gensym
    ;; would make the digest incomplete for a reason unrelated to cases.
    (cl-spec:defspec-function wrong-sign
      (:args (x (range integer 1 10)))
      (:returns (range integer 100 *)))
    (let* ((result (check-function 'wrong-sign :trials 1 :seed 1))
           (artifact (make-counterexample-artifact result))
           (signature (getf (getf (counterexample-artifact-data artifact) :original)
                            :signature)))
      (testing "an unchanged case-less signature has no case wrapper"
        (ok (eq :return-value (first signature))))
      (testing "and a deserialized copy rechecks as the same failure"
        (ok (eq :same-failure
                (getf (recheck-counterexample
                       (deserialize-counterexample-artifact
                        (serialize-counterexample-artifact artifact))
                       :state-policy :stateless)
                      :status)))))))

;;; F. Digest and unsupported paths

(deftest the-digest-notices-a-case-change
  (with-fresh-registry
    (cl-spec:defspec-function mutable
      (:args (x integer))
      (:cases
        (:low (:when (<= x 0)) (:returns integer))
        (:high (:when (> x 0)) (:returns integer))))
    (let* ((contract (find-function-spec 'mutable))
           (before (definition-digest contract)))
      (cl-spec:defspec-function mutable
        (:args (x integer))
        (:cases
          (:low (:when (< x 0)) (:returns integer))
          (:high (:when (>= x 0)) (:returns integer))))
      (ok (not (equal before (definition-digest (find-function-spec 'mutable)))))
      (testing "cases are described as child definitions, not as opaque data"
        (multiple-value-bind (data children links complete)
            (definition-description (find-function-spec 'mutable))
          (declare (ignore data links))
          (ok complete)
          (ok (= 2 (length (remove-if-not (lambda (child)
                                            (typep child 'function-case))
                                          children)))))))))

(deftest a-case-carrying-contract-refuses-instrumentation-safely
  (with-fresh-registry
    (reset-calls)
    (cl-spec:defspec-function instrumented-probe
      (:args (x integer))
      (:cases (:always (:when t) (:returns integer))))
    (let ((contract (find-function-spec 'instrumented-probe)))
      (testing "capability does not claim support"
        (ok (eq :unavailable (definition-instrumentation-capability contract))))
      (testing "installation refuses before replacing the function"
        (ok (eq :named-cases-unsupported
                (handler-case (progn (instrument-function 'instrumented-probe) :no-error)
                  (unsupported-instrumentation-target (condition)
                    (unsupported-instrumentation-target-reason condition)))))
        (ok (eq :not-installed (getf (instrumentation-status 'instrumented-probe) :status)))
        (ok (= 1 (instrumented-probe 1)))
        (ok (= 1 *calls*))))))

(deftest a-capability-query-runs-no-guard-and-no-target
  (with-fresh-registry
    (reset-calls)
    (let ((guard-calls 0))
      (cl-spec:defspec-function capability-probe
        (:args (x integer))
        (:cases (:always (:when (progn (incf guard-calls) t)) (:returns integer))))
      (testing "the capability answer is construction-only"
        (ok (eq :unavailable
                (definition-instrumentation-capability (find-function-spec 'capability-probe))))
        (ok (= 0 guard-calls))
        (ok (= 0 *calls*)))
      (testing "and the refusal reason is about the cases, not the target"
        (ok (eq :named-cases-unsupported
                (handler-case (progn (instrument-function 'capability-probe) :no-error)
                  (unsupported-instrumentation-target (condition)
                    (unsupported-instrumentation-target-reason condition)))))
        (ok (= 0 guard-calls))
        (ok (= 0 *calls*))))))

(deftest changing-an-installed-contract-to-cases-refuses-refresh
  (with-fresh-registry
    (reset-calls)
    (let ((*instrumented-functions* (make-hash-table :test #'eq)))
      (unwind-protect
           (progn
             (cl-spec:defspec-function instrumented-probe
               (:args (x integer))
               (:returns integer))
             (instrument-function 'instrumented-probe)
             (ok (instrumented-function-p 'instrumented-probe))
             (testing "changing the contract to :cases leaves the wrapper stale"
               (cl-spec:defspec-function instrumented-probe
                 (:args (x integer))
                 (:cases (:always (:when t) (:returns integer))))
               (ok (eq :named-cases-unsupported
                       (handler-case
                           (progn (refresh-instrumentation 'instrumented-probe) :no-error)
                         (unsupported-instrumentation-target (condition)
                           (unsupported-instrumentation-target-reason condition)))))
               (testing "and the existing wrapper is preserved"
                 (ok (instrumented-function-p 'instrumented-probe))
                 (ok (= 3 (instrumented-probe 3)))))
             (testing "explicit uninstrumentation still restores the target"
               (ok (uninstrument-function 'instrumented-probe))
               (ok (not (instrumented-function-p 'instrumented-probe)))))
        (when (instrumented-function-p 'instrumented-probe)
          (uninstrument-function 'instrumented-probe))))))
