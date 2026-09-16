;;;; tests/state-observation-test.lisp
;;;;
;;;; Explicit pre-observation (:CAPTURE) and post-run state constraints
;;;; (:STATE-POST) for Function Specs (specification §17.3).  Tests are grouped
;;;; by the invariant they pin down rather than by the function they call, and
;;;; every passing trial starts from a fresh account drawn by a controlled
;;;; generator instead of depending on what a seed happens to draw.

(defpackage #:cl-spec/tests/state-observation-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec
                #:defspec-function #:defgenerator #:check-function
                #:find-function-spec #:make-hash-table-registry
                #:function-spec-data #:result-data
                #:definition-digest #:definition-description
                #:function-check-result-case-report
                #:function-check-result-failure-reason
                #:property-result-status #:property-result-trials
                #:property-result-rejected #:property-result-failure-phase
                #:property-result-failure-evidence #:property-result-shrunk-evidence
                #:property-result-condition #:property-result-shrink-report
                #:property-result-schema-metadata
                #:trial-observation-case #:trial-observation-signature
                #:trial-observation-state #:trial-observation-outcome
                #:make-counterexample-artifact #:recheck-counterexample
                #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason
                #:unsupported-stateful-operation
                #:unsupported-stateful-operation-operation
                #:unsupported-stateful-operation-reason
                #:capture-error
                #:state-post-error #:state-post-error-index
                #:state-post-error-case #:state-post-error-original-condition
                #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-case
                #:function-spec-cases
                #:function-spec-capture-bindings #:function-spec-capture-functions
                #:function-spec-state-postconditions)
  (:import-from #:cl-spec/src/schema
                #:definition-instrumentation-capability #:definition-shrink-enabled-p
                #:definition-state-constraints)
  (:import-from #:cl-spec/src/instrument
                #:instrument-function #:instrumented-function-p
                #:unsupported-instrumentation-target
                #:unsupported-instrumentation-target-reason))

(in-package #:cl-spec/tests/state-observation-test)

;;; Fixtures

(define-condition insufficient-funds (error)
  ((balance :initarg :balance :reader insufficient-funds-balance)
   (amount :initarg :amount :reader insufficient-funds-amount)))

(defstruct (account (:constructor make-account (balance id))) balance id)

(defclass opaque-box () ((tag :initform :opaque)))

;; Intern RESULT in this package so the capture/RESULT collision check has a
;; symbol to find, exactly as a contract with a :POST would.
(defparameter *result* 'result)

(defvar *calls* 0 "Target invocations counted by the current test.")
(defvar *capture-runs* 0 "Capture form evaluations counted by the current test.")
(defvar *guard-runs* 0 "Case guard evaluations counted by the current test.")
(defvar *state-runs* 0 "State-post form evaluations counted by the current test.")
(defvar *last-args* nil "Argument list the target last received.")

(defvar *scenario* :correct "Which behaviour SCENARIO-TARGET performs.")
(defvar *draw-balance* 30 "Balance the next drawn account gets.")
(defvar *draw-id* 7 "Identifier the next drawn account gets.")
(defvar *draw-amount* 10 "Amount the next draw passes to the target.")

(defun reset-counters ()
  (setf *calls* 0 *capture-runs* 0 *guard-runs* 0 *state-runs* 0 *last-args* nil))

(defun refuses-p (thunk)
  "True when THUNK signals INVALID-FUNCTION-SPEC-FORM."
  (handler-case (progn (funcall thunk) nil)
    (invalid-function-spec-form () t)))

(defmacro refuses (&body body)
  "True when BODY signals INVALID-FUNCTION-SPEC-FORM."
  `(refuses-p (lambda () ,@body)))

(defmacro with-fresh-registry (&body body)
  "Run BODY with an empty registry, so another test's contract is invisible."
  `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
     ,@body))

(defmacro with-live-generator ((name) &body body)
  "Register a fresh-account generator NAME, then run BODY.

Each draw builds a new ACCOUNT from the current *DRAW-BALANCE* / *DRAW-ID* and
passes *DRAW-AMOUNT*, so a trial never starts from the object an earlier trial
mutated."
  `(progn
     (cl-spec:defgenerator ,name ()
       (list (make-account *draw-balance* *draw-id*) *draw-amount*))
     ,@body))

(defmacro with-shrinky-generator ((name) &body body)
  "Register a fresh-account generator NAME that also offers a shrink candidate."
  `(progn
     (cl-spec:defgenerator ,name ()
       (:shrink (value)
        (declare (ignore value))
        (list (list (make-account 1 7) 1)))
       (list (make-account *draw-balance* *draw-id*) *draw-amount*))
     ,@body))

(defmacro define-target (name)
  "Define NAME as a target that performs the current *SCENARIO*."
  `(defun ,name (acct amount)
     (scenario-target acct amount)))

(defmacro define-withdraw-contract (name generator)
  "Define target NAME and register its two-case withdrawal contract.

Capture observes the balance and the identifier before the call; each case
checks after the call that the observed values moved the way it requires."
  `(progn
     (define-target ,name)
     (cl-spec:defspec-function ,name
       (:args (account (satisfies account-p)) (amount (range integer 1 200)))
       (:args-generator ,generator)
       (:capture
         (balance-before (account-balance account))
         (id-before (account-id account)))
       (:cases
         (:sufficient-funds
           (:when (<= amount balance-before))
           (:returns (satisfies listp))
           (:state-post (= (account-balance account) (- balance-before amount))
                        (eql (account-id account) id-before)))
         (:insufficient-funds
           (:when (> amount balance-before))
           (:signals (type insufficient-funds))
           (:state-post (= (account-balance account) balance-before)
                        (eql (account-id account) id-before)))))))

(defmacro define-plain-contract (name generator)
  "Define target NAME and register a featureless string-return contract."
  `(progn
     (define-target ,name)
     (cl-spec:defspec-function ,name
       (:args (account (satisfies account-p)) (amount (range integer 1 200)))
       (:args-generator ,generator)
       (:returns string))))

(defun scenario-target (acct amount)
  "Perform the behaviour *SCENARIO* names, returning a receipt or signalling."
  (incf *calls*)
  (setf *last-args* (list acct amount))
  (let ((balance (account-balance acct)))
    (flet ((take ()
             (decf (account-balance acct) amount)
             (list :receipt amount))
           (refuse ()
             (error 'insufficient-funds :balance balance :amount amount)))
      (ecase *scenario*
        (:correct (if (<= amount balance) (take) (refuse)))
        (:no-update (if (<= amount balance) (list :receipt amount) (refuse)))
        (:double (if (<= amount balance)
                     (progn (take) (decf (account-balance acct) amount)
                            (list :receipt amount))
                     (refuse)))
        (:id-change (if (<= amount balance)
                        (progn (take) (setf (account-id acct) 99)
                               (list :receipt amount))
                        (refuse)))
        (:partial (if (<= amount balance)
                      (take)
                      (progn (decf (account-balance acct) 1) (refuse))))))))

(defun failing-evidence (result)
  "Return the failure observation RESULT selected, or NIL."
  (or (property-result-shrunk-evidence result)
      (property-result-failure-evidence result)))

(defun observation-state (result)
  "Return the state evidence of RESULT's selected failure, or NIL."
  (let ((evidence (failing-evidence result)))
    (when evidence (trial-observation-state evidence))))

(defun report-case (report name)
  "Return the :CASES entry of REPORT for NAME."
  (find name (getf report :cases) :key (lambda (entry) (getf entry :name))))

(defun configure-draw (&key (balance 30) (amount 10) (id 7) (scenario :correct))
  (setf *draw-balance* balance *draw-id* id *draw-amount* amount
        *scenario* scenario))

(defun run-scenario (&key (trials 1) (seed 1) (balance 30) (amount 10) (id 7)
                            (scenario :correct) (name 'scenario-target))
  "Draw a fresh account per trial and check NAME's registered contract."
  (configure-draw :balance balance :amount amount :id id :scenario scenario)
  (check-function name :trials trials :seed seed))

;;; A. Declaration and binding

(deftest capture-and-state-post-declare-and-project
  (with-fresh-registry
    (with-live-generator (declared-args)
      (define-withdraw-contract declared-target declared-args)
      (let* ((contract (find-function-spec 'declared-target))
             (data (function-spec-data 'declared-target))
             (cases (getf data :cases)))
        (testing "the declaration is structured, not hidden in metadata"
          (ok (equal '((balance-before (account-balance account))
                       (id-before (account-id account)))
                     (function-spec-capture-bindings contract)))
          (ok (= 2 (length (function-spec-capture-functions contract))))
          (ok (null (function-spec-state-postconditions contract))))
        (testing "the projection exposes capture and per-case state-post"
          (ok (equal '((:name balance-before :form (account-balance account))
                       (:name id-before :form (account-id account)))
                     (getf data :capture)))
          (ok (null (getf data :state-post)))
          (ok (equal '((= (account-balance account) (- balance-before amount))
                       (eql (account-id account) id-before))
                     (getf (first cases) :state-post))))
        (testing "no executable closure reaches the projection"
          (labels ((closures (value)
                     (cond ((functionp value) (list value))
                           ((consp value) (mapcan #'closures value))
                           (t nil))))
            (ok (null (closures data)))))))))

(deftest a-case-less-contract-declares-capture-and-state-post
  (with-fresh-registry
    (with-live-generator (simple-args)
      (define-target simple-target)
      (cl-spec:defspec-function simple-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator simple-args)
        (:capture (balance-before (account-balance account)))
        (:returns (satisfies listp))
        (:state-post (<= (account-balance account) balance-before)))
      (let ((contract (find-function-spec 'simple-target))
            (data (function-spec-data 'simple-target)))
        (ok (null (function-spec-cases contract)))
        (ok (equal '((:name balance-before :form (account-balance account)))
                   (getf data :capture)))
        (ok (equal '((<= (account-balance account) balance-before))
                   (getf data :state-post)))))))

(deftest a-signals-contract-may-carry-state-post
  (with-fresh-registry
    (with-live-generator (signals-args)
      (define-target signals-target)
      (cl-spec:defspec-function signals-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator signals-args)
        (:capture (balance-before (account-balance account)))
        (:signals (type insufficient-funds))
        (:state-post (= (account-balance account) balance-before)))
      (reset-counters)
      (let ((result (run-scenario :name 'signals-target :balance 10 :amount 50)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 1 *calls*))))))

(deftest signals-still-refuses-post-and-post-values
  (with-fresh-registry
    (testing "the existing exclusivity is not relaxed by :state-post"
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:signals (type error))
                       (:post (eql result 1))))))
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:signals (type error))
                       (:post))))))
    (testing "an empty :post is a written clause in a case too"
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:cases (:a (:when t) (:signals (type error)) (:post))))))))))

(deftest capture-refuses-malformed-and-colliding-bindings
  (with-fresh-registry
    (flet ((refuse-capture (clause)
             (refuses (macroexpand-1
                       `(cl-spec:defspec-function f
                          (:args (x integer) (y integer))
                          (:capture ,@clause)
                          (:returns integer))))))
      (testing "shape and name rules"
        (ok (refuse-capture nil))
        (ok (refuse-capture '(x)))
        (ok (refuse-capture '((a))))
        (ok (refuse-capture '((a 1 2)))))
      (testing "a name must be a unique bindable variable"
        (ok (refuse-capture '((1 1))))
        (ok (refuse-capture '((:a 1))))
        (ok (refuse-capture '((t 1))))
        (ok (refuse-capture '((&optional 1))))
        (ok (refuse-capture '((a 1) (a 2)))))
      (testing "a name may not collide with an existing binding"
        (ok (refuse-capture '((x 1))))
        (ok (refuse-capture '((result 1)))))
      (testing "a name may not collide with a :post-values name"
        (ok (refuses (macroexpand-1
                      '(cl-spec:defspec-function f
                         (:args (x integer))
                         (:capture (v 1))
                         (:returns (values integer))
                         (:post-values (v) (eql result 1))))))))))

(deftest capture-and-state-post-refuse-forbidden-positions-and-duplicates
  (with-fresh-registry
    (testing ":capture is top-level only, at most once"
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:capture (a 1))
                       (:capture (b 2))
                       (:returns integer)))))
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:cases (:a (:when t) (:capture (v 1)) (:returns integer))))))))
    (testing ":state-post is one clause, non-empty, and not both positions"
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:returns integer)
                       (:state-post)))))
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:returns integer)
                       (:state-post (= x 1))
                       (:state-post (= x 2))))))
      (ok (refuses (macroexpand-1
                    '(cl-spec:defspec-function f
                       (:args (x integer))
                       (:cases (:a (:when t) (:returns integer) (:state-post (= x 1))))
                       (:state-post (= x 2)))))))))

(deftest a-capture-form-sees-earlier-captures-in-order
  (with-fresh-registry
    (with-live-generator (ordered-args)
      (define-target ordered-target)
      (cl-spec:defspec-function ordered-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator ordered-args)
        (:capture (first-value (account-balance account))
                  (second-value (+ first-value amount)))
        (:returns (satisfies listp))
        (:state-post (eql second-value 0)))
      (reset-counters)
      (let* ((result (run-scenario :name 'ordered-target :balance 30 :amount 10))
             (capture (getf (observation-state result) :capture)))
        (testing "the later form read the earlier capture value"
          (ok (eq :failed (property-result-status result)))
          (ok (equal '(30 40) (getf capture :values))))
        (testing "the declaration order is reported"
          (ok (equal '(first-value second-value) (getf capture :declared)))
          (ok (eq :completed (getf capture :status))))))))

(deftest a-capture-form-may-not-read-a-later-capture
  (with-fresh-registry
    (ok (refuses (macroexpand-1
                  '(cl-spec:defspec-function f
                     (:args (x integer))
                     (:capture (a b) (b 1))
                     (:returns integer)))))))

(deftest a-captured-nil-is-a-value-not-an-absence
  (with-fresh-registry
    (with-live-generator (nil-args)
      (define-target nil-capture-target)
      (cl-spec:defspec-function nil-capture-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator nil-args)
        (:capture (observed nil))
        (:returns (satisfies listp))
        (:state-post (eql observed 1)))
      (reset-counters)
      (let* ((result (run-scenario :name 'nil-capture-target :scenario :no-update))
             (capture (getf (observation-state result) :capture)))
        (testing "a captured NIL is reported as completed with a NIL value"
          (ok (eq :failed (property-result-status result)))
          (ok (eq :completed (getf capture :status)))
          (ok (equal '(nil) (getf capture :values)))))
      (testing "a predicate may test the NIL value it captured"
        (define-target nil-pass-target)
        (cl-spec:defspec-function nil-pass-target
          (:args (account (satisfies account-p)) (amount (range integer 1 200)))
          (:args-generator nil-args)
          (:capture (observed nil))
          (:returns (satisfies listp))
          (:state-post (null observed)))
        (reset-counters)
        (let ((result (run-scenario :name 'nil-pass-target :scenario :no-update)))
          (ok (eq :passed (property-result-status result))))))))

(deftest capture-does-not-change-the-target-call-layout
  (with-fresh-registry
    (with-live-generator (layout-args)
      (define-target layout-target)
      (cl-spec:defspec-function layout-target
        (:args (account (satisfies account-p))
               &optional (amount (range integer 1 200) amount-supplied-p))
        (:args-generator layout-args)
        (:capture (before (account-balance account)))
        (:returns (satisfies listp))
        (:state-post (or amount-supplied-p (eql before before))))
      (reset-counters)
      (let ((result (run-scenario :name 'layout-target :scenario :correct)))
        (testing "the optional argument and its supplied flag still bind"
          (ok (eq :passed (property-result-status result)))
          (ok (= 1 *calls*)))
        (testing "the capture is not passed to the target"
          (ok (= 2 (length *last-args*))))))))

(deftest programmatic-one-sided-updates-are-refused
  (with-fresh-registry
    (let ((contract (make-instance 'function-spec
                                   :name 'programmatic-target
                                   :argument-specs '((x integer))
                                   :return-spec 'integer)))
      (testing "capture forms and functions change together"
        (ok (refuses (reinitialize-instance contract
                                            :capture-bindings '((a 1)))))
        (ok (refuses (reinitialize-instance contract
                                            :capture-functions (list (lambda () 1)))))
        (ok (refuses (make-instance 'function-spec
                                    :name 'mismatched
                                    :argument-specs '((x integer))
                                    :capture-bindings '((a 1) (b 2))
                                    :capture-functions (list (lambda () 1))))))
      (testing "state-post forms and function change together"
        (ok (refuses (reinitialize-instance contract
                                            :state-postconditions '((= x 1)))))
        (ok (refuses (reinitialize-instance contract
                                            :state-postcondition-function (lambda (x) x)))))
      (testing "a case state-post follows the same rule"
        (ok (refuses (make-instance 'function-case
                                    :name :a
                                    :when-forms '(t)
                                    :when-function (lambda () t)
                                    :outcome-kind :returns
                                    :outcome-spec 'integer
                                    :state-postconditions '(t))))
        (ok (refuses (make-instance 'function-case
                                    :name :a
                                    :when-forms '(t)
                                    :when-function (lambda () t)
                                    :outcome-kind :returns
                                    :outcome-spec 'integer
                                    :state-postcondition-function (lambda () t)))))
      (testing "changing the capture list requires the predicates that read it"
        (let ((dependent (make-instance 'function-spec
                                        :name 'dependent-target
                                        :argument-specs '((x integer))
                                        :capture-bindings '((a 1))
                                        :capture-functions
                                        (list (lambda (x) (declare (ignore x)) 1))
                                        :return-spec 'integer
                                        :state-postconditions '(t)
                                        :state-postcondition-function
                                        (lambda (x a) (declare (ignore x a)) t))))
          (ok (refuses (reinitialize-instance dependent
                                              :capture-bindings '((b 1))
                                              :capture-functions
                                              (list (lambda (x) (declare (ignore x)) 1)))))
          (ok (handler-case
                  (progn (reinitialize-instance dependent
                                                :capture-bindings '((b 1))
                                                :capture-functions
                                                (list (lambda (x) (declare (ignore x)) 1))
                                                :state-postconditions '(t)
                                                :state-postcondition-function
                                                (lambda (x b) (declare (ignore x b)) t))
                         t)
                (invalid-function-spec-form () nil))))))))

(deftest a-refused-capture-edit-keeps-the-registered-contract
  (with-fresh-registry
    (with-live-generator (kept-args)
      (define-withdraw-contract kept-target kept-args)
      (let* ((contract (find-function-spec 'kept-target))
             (before (definition-digest contract))
             (bindings (function-spec-capture-bindings contract)))
        (ok (refuses (reinitialize-instance contract
                                            :capture-bindings '((only-one 1)))))
        (ok (equal before (definition-digest contract)))
        (ok (equal bindings (function-spec-capture-bindings contract)))))))

;;; B. Evaluation order and call counts

(deftest a-pre-refusal-runs-nothing-else
  (with-fresh-registry
    (with-live-generator (pre-args)
      (define-target pre-target)
      (cl-spec:defspec-function pre-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator pre-args)
        (:pre (progn (incf *guard-runs*) (> amount 1000)))
        (:capture (before (progn (incf *capture-runs*) (account-balance account))))
        (:returns (satisfies listp))
        (:state-post (progn (incf *state-runs*) (= before before))))
      (reset-counters)
      (let ((result (run-scenario :name 'pre-target :trials 3)))
        (ok (eq :skipped (property-result-status result)))
        (ok (= 3 (property-result-rejected result)))
        (ok (= 0 *capture-runs*))
        (ok (= 0 *state-runs*))
        (ok (= 0 *calls*))))))

(deftest capture-runs-once-per-trial-in-declaration-order
  (with-fresh-registry
    (with-live-generator (counted-args)
      (define-target counted-capture-target)
      (cl-spec:defspec-function counted-capture-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator counted-args)
        (:capture (a (progn (incf *capture-runs*) (account-balance account)))
                  (b (progn (incf *capture-runs*) (account-id account))))
        (:returns (satisfies listp))
        (:state-post (eql b b)))
      (reset-counters)
      (let ((result (run-scenario :name 'counted-capture-target
                                  :scenario :correct :trials 4)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 4 (property-result-trials result)))
        (ok (= 8 *capture-runs*))))))

(deftest a-capture-error-stops-the-trial-before-the-target
  (with-fresh-registry
    (with-live-generator (boom-args)
      (define-target capture-boom-target)
      (cl-spec:defspec-function capture-boom-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator boom-args)
        (:capture (a (account-balance account))
                  (b (error 'insufficient-funds :balance 0 :amount 0))
                  (c (progn (incf *capture-runs*) (account-id account))))
        (:returns (satisfies listp))
        (:state-post (progn (incf *state-runs*) t)))
      (reset-counters)
      (let* ((result (check-function 'capture-boom-target :trials 2 :seed 1))
             (capture (getf (observation-state result) :capture)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :capture (property-result-failure-phase result)))
        (ok (= 0 *calls*))
        (ok (= 0 *capture-runs*))
        (ok (= 0 *state-runs*))
        (testing "only the completed bindings are recorded"
          (ok (eq :error (getf capture :status)))
          (ok (equal '(a b c) (getf capture :declared)))
          (ok (= 1 (length (getf capture :values)))))))))

(deftest selection-and-guard-errors-call-no-target
  (with-fresh-registry
    (with-live-generator (selection-args)
      (define-target selection-target)
      (cl-spec:defspec-function selection-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator selection-args)
        (:capture (before (account-balance account)))
        (:cases
          (:a (:when (<= amount before)) (:returns (satisfies listp))
              (:state-post t))
          (:b (:when (<= amount before)) (:returns (satisfies listp))
              (:state-post t))))
      (reset-counters)
      (let ((result (run-scenario :name 'selection-target)))
        (ok (eq :case-selection (property-result-failure-phase result)))
        (ok (= 0 *calls*))
        (ok (= 0 *state-runs*))))))

(deftest the-target-runs-once-per-trial-and-only-the-selected-state-post-runs
  (with-fresh-registry
    (with-live-generator (once-args)
      (define-target once-target)
      (cl-spec:defspec-function once-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator once-args)
        (:capture (before (account-balance account)))
        (:cases
          (:sufficient (:when (<= amount before)) (:returns (satisfies listp))
                       (:state-post (progn (incf *state-runs*) t)))
          (:insufficient (:when (> amount before)) (:signals (type insufficient-funds))
                         (:state-post (progn (incf *state-runs*) t)))))
      (reset-counters)
      (let* ((result (run-scenario :name 'once-target :trials 3))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 3 *calls*))
        (ok (= 3 *state-runs*))
        (ok (= 3 (getf (report-case report :sufficient) :called)))
        (ok (= 0 (getf (report-case report :insufficient) :called)))))))

(deftest introspection-and-reports-do-not-re-execute
  (with-fresh-registry
    (with-live-generator (query-args)
      (define-withdraw-contract query-target query-args)
      (reset-counters)
      (let ((result (run-scenario :name 'query-target :trials 2)))
        (let ((calls *calls*) (captures *capture-runs*) (states *state-runs*))
          (function-spec-data 'query-target)
          (definition-digest (find-function-spec 'query-target))
          (definition-description (find-function-spec 'query-target))
          (function-check-result-case-report result)
          (result-data result)
          (ok (= calls *calls*))
          (ok (= captures *capture-runs*))
          (ok (= states *state-runs*)))))))

(deftest an-outcome-failure-first-leaves-state-post-not-evaluated
  (with-fresh-registry
    (with-live-generator (outcome-args)
      (define-target wrong-return-target)
      (cl-spec:defspec-function wrong-return-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator outcome-args)
        (:capture (before (account-balance account)))
        (:returns string)
        (:state-post (progn (incf *state-runs*) t)))
      (reset-counters)
      (let* ((result (run-scenario :name 'wrong-return-target))
             (state (observation-state result)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (ok (= 0 *state-runs*))
        (ok (eq :not-evaluated (getf (getf state :state-post) :status)))
        (ok (eq :outcome-failed (getf (getf state :state-post) :reason)))
        (testing "the passed capture half is still reported"
          (ok (eq :completed (getf (getf state :capture) :status))))))))

;;; C. What state constraints detect

(deftest a-correct-withdrawal-passes
  (with-fresh-registry
    (with-live-generator (c1-args)
      (define-withdraw-contract c1-target c1-args)
      (reset-counters)
      (let ((result (run-scenario :name 'c1-target :scenario :correct
                                  :balance 30 :amount 10)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 1 *calls*))
        (ok (= 1 (getf (report-case (function-check-result-case-report result)
                                    :sufficient-funds)
                       :passed)))))))

(deftest a-missing-update-is-a-state-post-violation
  (with-fresh-registry
    (with-live-generator (c2-args)
      (define-withdraw-contract c2-target c2-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'c2-target :scenario :no-update))
             (state (observation-state result)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :state-postcondition (function-check-result-failure-reason result)))
        (ok (eq :state-post (property-result-failure-phase result)))
        (ok (equal '(:case :sufficient-funds :state-postcondition 0)
                   (trial-observation-signature (failing-evidence result))))
        (ok (eq :violation (getf (getf state :state-post) :status)))
        (ok (= 0 (getf (getf state :state-post) :index)))))))

(deftest a-double-update-is-a-state-post-violation
  (with-fresh-registry
    (with-live-generator (c3-args)
      (define-withdraw-contract c3-target c3-args)
      (reset-counters)
      (let ((result (run-scenario :name 'c3-target :scenario :double)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :state-postcondition (function-check-result-failure-reason result)))))))

(deftest a-correct-refusal-passes
  (with-fresh-registry
    (with-live-generator (c4-args)
      (define-withdraw-contract c4-target c4-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'c4-target :scenario :correct
                                   :balance 10 :amount 50))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 1 (getf (report-case report :insufficient-funds) :passed)))))))

(deftest a-partial-update-then-refusal-is-a-state-post-violation
  (with-fresh-registry
    (with-live-generator (c5-args)
      (define-withdraw-contract c5-target c5-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'c5-target :scenario :partial
                                   :balance 10 :amount 50))
             (evidence (failing-evidence result))
             (report (function-check-result-case-report result)))
        (testing "the expected error was signalled but does not make the trial pass"
          (ok (eq :failed (property-result-status result)))
          (ok (eq :state-postcondition (function-check-result-failure-reason result)))
          (ok (eq :signaled (getf (trial-observation-outcome evidence) :kind)))
          (ok (eq 'insufficient-funds
                  (getf (trial-observation-outcome evidence) :condition-type))))
        (testing "the calling case is counted as failed, not passed"
          (ok (= 1 (getf (report-case report :insufficient-funds) :failed)))
          (ok (= 0 (getf (report-case report :insufficient-funds) :passed))))))))

(deftest a-declared-identifier-changing-is-a-state-post-violation
  (with-fresh-registry
    (with-live-generator (c6-args)
      (define-withdraw-contract c6-target c6-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'c6-target :scenario :id-change))
             (state (observation-state result)))
        (ok (eq :failed (property-result-status result)))
        (ok (equal '(:case :sufficient-funds :state-postcondition 1)
                   (trial-observation-signature (failing-evidence result))))
        (ok (= 1 (getf (getf state :state-post) :index)))
        (ok (equal '(eql (account-id account) id-before)
                   (getf (getf state :state-post) :form)))))))

;;; D. Errors, evidence and counting

(deftest a-state-post-error-keeps-the-case-and-the-outcome
  (with-fresh-registry
    (with-live-generator (d1-args)
      (define-target state-boom-target)
      (cl-spec:defspec-function state-boom-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator d1-args)
        (:capture (before (account-balance account)))
        (:cases
          (:a (:when (<= amount before)) (:returns (satisfies listp))
              (:state-post (error 'insufficient-funds :balance 0 :amount 0)))))
      (reset-counters)
      (let* ((result (run-scenario :name 'state-boom-target :scenario :no-update))
             (condition (property-result-condition result))
             (report (function-check-result-case-report result))
             (evidence (failing-evidence result)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :state-post (property-result-failure-phase result)))
        (ok (typep condition 'state-post-error))
        (ok (eq :a (state-post-error-case condition)))
        (ok (= 0 (state-post-error-index condition)))
        (ok (eq 'insufficient-funds
                (type-of (state-post-error-original-condition condition))))
        (ok (eq :a (trial-observation-case evidence)))
        (ok (getf (trial-observation-outcome evidence) :values))
        (ok (= 1 (getf (report-case report :a) :error)))
        (ok (= 1 (getf (report-case report :a) :called)))))))

(deftest the-same-condition-type-is-classified-by-its-phase
  (with-fresh-registry
    (with-live-generator (d2-args)
      (testing "a capture condition is a contract error, not the target's error"
        (define-target phase-capture-target)
        (cl-spec:defspec-function phase-capture-target
          (:args (account (satisfies account-p)) (amount (range integer 1 200)))
          (:args-generator d2-args)
          (:capture (x (error 'insufficient-funds :balance 0 :amount 0)))
          (:signals (type insufficient-funds)))
        (reset-counters)
        (let ((result (run-scenario :name 'phase-capture-target)))
          (ok (eq :capture (property-result-failure-phase result)))
          (ok (eq :error (property-result-status result)))
          (ok (typep (property-result-condition result) 'capture-error))
          (ok (= 0 *calls*))))
      (testing "the target's own expected error passes"
        (define-target phase-target-error)
        (cl-spec:defspec-function phase-target-error
          (:args (account (satisfies account-p)) (amount (range integer 1 200)))
          (:args-generator d2-args)
          (:signals (type insufficient-funds)))
        (reset-counters)
        (let ((result (run-scenario :name 'phase-target-error
                                    :balance 10 :amount 50)))
          (ok (eq :passed (property-result-status result)))
          (ok (null (property-result-failure-phase result)))))
      (testing "a state-post condition is a post-target contract error"
        (define-target phase-state-target)
        (cl-spec:defspec-function phase-state-target
          (:args (account (satisfies account-p)) (amount (range integer 1 200)))
          (:args-generator d2-args)
          (:returns (satisfies listp))
          (:state-post (error 'insufficient-funds :balance 0 :amount 0)))
        (reset-counters)
        (let ((result (run-scenario :name 'phase-state-target :scenario :no-update)))
          (ok (eq :state-post (property-result-failure-phase result)))
          (ok (= 1 *calls*)))))))

(deftest an-expected-error-that-mutated-is-not-counted-as-passed
  (with-fresh-registry
    (with-live-generator (d3-args)
      (define-withdraw-contract d3-target d3-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'd3-target :scenario :partial
                                   :balance 10 :amount 50))
             (report (function-check-result-case-report result)))
        (ok (eq :failed (property-result-status result)))
        (ok (= 0 (getf (report-case report :insufficient-funds) :passed)))
        (ok (= 1 (getf (report-case report :insufficient-funds) :failed)))))))

(deftest each-trial-is-counted-once-from-its-final-classification
  (with-fresh-registry
    (with-live-generator (d4-args)
      (define-withdraw-contract d4-target d4-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'd4-target :scenario :no-update))
             (report (function-check-result-case-report result))
             (entry (report-case report :sufficient-funds)))
        (ok (= 1 (getf entry :called)))
        (ok (= 1 (getf entry :failed)))
        (ok (= 0 (getf entry :passed)))
        (ok (= 0 (getf entry :error)))))))

(deftest a-capture-failure-is-not-a-selection-error-or-a-target-call
  (with-fresh-registry
    (with-live-generator (d5-args)
      (define-target capture-count-target)
      (cl-spec:defspec-function capture-count-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator d5-args)
        (:capture (x (error 'insufficient-funds :balance 0 :amount 0)))
        (:cases
          (:a (:when t) (:returns (satisfies listp)))))
      (reset-counters)
      (let* ((result (check-function 'capture-count-target :trials 1 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :capture (property-result-failure-phase result)))
        (ok (= 0 (getf report :case-selection-errors)))
        (ok (= 1 (getf report :capture-errors)))
        (ok (= 0 (getf (report-case report :a) :called)))
        (ok (= 0 *calls*))))))

(deftest a-post-target-phase-keeps-the-target-call
  (with-fresh-registry
    (with-live-generator (d6-args)
      (define-withdraw-contract d6-target d6-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'd6-target :scenario :no-update))
             (report (function-check-result-case-report result)))
        (ok (eq :state-post (property-result-failure-phase result)))
        (ok (= 1 (getf (report-case report :sufficient-funds) :called)))
        (ok (equal '(:insufficient-funds) (getf report :never-called)))))))

(deftest an-opaque-capture-value-does-not-lose-the-failure
  (with-fresh-registry
    (with-live-generator (d7-args)
      (define-target opaque-target)
      (cl-spec:defspec-function opaque-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator d7-args)
        (:capture (box (make-instance 'opaque-box)))
        (:returns (satisfies listp))
        (:state-post (eq box nil)))
      (reset-counters)
      (let* ((result (run-scenario :name 'opaque-target :scenario :no-update))
             (state (observation-state result)))
        (ok (eq :failed (property-result-status result)))
        (ok (equal '(:state-postcondition 0)
                   (trial-observation-signature (failing-evidence result))))
        (ok (typep (first (getf (getf state :capture) :values)) 'opaque-box))))))

(deftest runs-do-not-share-captures-or-counters
  (with-fresh-registry
    (with-live-generator (d8-args)
      (define-withdraw-contract d8-target d8-args)
      (reset-counters)
      (let ((first-run (run-scenario :name 'd8-target :scenario :no-update
                                     :balance 30 :amount 10 :seed 1))
            (second-run (run-scenario :name 'd8-target :scenario :correct
                                      :balance 40 :amount 5 :seed 2)))
        (ok (eq :failed (property-result-status first-run)))
        (ok (eq :passed (property-result-status second-run)))
        (ok (equal '(30 7) (getf (getf (observation-state first-run) :capture) :values)))
        (ok (null (observation-state second-run)))
        (ok (not (eq (function-check-result-case-report first-run)
                     (function-check-result-case-report second-run))))))))

;;; E. Shrinking, replay and artifacts

(deftest a-stateful-failure-is-not-shrunk
  (with-fresh-registry
    (with-live-generator (e1-args)
      (define-withdraw-contract e1-target e1-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'e1-target :scenario :no-update))
             (report (property-result-shrink-report result)))
        (ok (= 1 *calls*))
        (ok (eq :state-restoration-unavailable (getf report :termination)))
        (ok (= 0 (getf report :candidates)))
        (ok (null (property-result-shrunk-evidence result)))
        (ok (eq :present (getf (property-result-schema-metadata result)
                               :state-constraints)))))))

(deftest a-custom-shrinker-does-not-bypass-the-state-limit
  (with-fresh-registry
    (with-shrinky-generator (e2-args)
      (define-withdraw-contract e2-target e2-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'e2-target :scenario :no-update))
             (report (property-result-shrink-report result)))
        (ok (eq :failed (property-result-status result)))
        (ok (= 1 *calls*))
        (ok (eq :state-restoration-unavailable (getf report :termination)))
        (ok (null (property-result-shrunk-evidence result)))))))

(deftest a-pre-target-failure-keeps-the-not-a-target-failure-reason
  (with-fresh-registry
    (with-live-generator (e3-args)
      (define-target e3-target)
      (cl-spec:defspec-function e3-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator e3-args)
        (:capture (x (error 'insufficient-funds :balance 0 :amount 0)))
        (:returns (satisfies listp))
        (:state-post t))
      (reset-counters)
      (let* ((result (check-function 'e3-target :trials 1 :seed 1))
             (report (property-result-shrink-report result)))
        (ok (eq :capture (property-result-failure-phase result)))
        (ok (eq :not-a-target-failure (getf report :termination)))
        (ok (= 0 *calls*))))))

(deftest replaying-a-past-result-is-refused-before-the-target
  (with-fresh-registry
    (with-live-generator (e4-args)
      (define-withdraw-contract e4-target e4-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'e4-target :scenario :no-update))
             (before *calls*)
             (outcome (handler-case
                          (progn (check-function 'e4-target :seed result) nil)
                        (unsupported-stateful-operation (condition)
                          (list :operation
                                (unsupported-stateful-operation-operation condition)
                                :reason
                                (unsupported-stateful-operation-reason condition))))))
        (ok (equal '(:operation :replay :reason :state-restoration-unavailable)
                   outcome))
        (ok (= before *calls*))))))

(deftest a-new-integer-seed-run-is-allowed
  (with-fresh-registry
    (with-live-generator (e5-args)
      (define-withdraw-contract e5-target e5-args)
      (reset-counters)
      (let ((result (run-scenario :name 'e5-target :scenario :correct
                                  :trials 3 :seed 99)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 3 (property-result-trials result)))))))

(deftest counterexample-artifacts-are-refused-with-the-stateful-reason
  (with-fresh-registry
    (with-live-generator (e6-args)
      (define-withdraw-contract e6-target e6-args)
      (reset-counters)
      (let* ((result (run-scenario :name 'e6-target :scenario :no-update))
             (reason (handler-case
                         (progn (make-counterexample-artifact result) nil)
                       (invalid-counterexample-artifact (condition)
                         (invalid-counterexample-artifact-reason condition)))))
        (ok (eq :stateful-contract-unsupported reason))))))

(deftest rechecking-a-stateful-definition-is-refused-before-the-target
  (with-fresh-registry
    ;; Integer arguments keep the saved evidence inside the artifact codec, so
    ;; the test can build a real artifact and then change the definition.
    (cl-spec:defgenerator e7-args () (list 5))
    (defun e7-target (x)
      (declare (ignore x))
      (incf *calls*)
      42)
    (reset-counters)
    (cl-spec:defspec-function e7-target
      (:args (x integer))
      (:args-generator e7-args)
      (:returns string))
    (let* ((result (check-function 'e7-target :trials 1 :seed 1))
           (artifact (make-counterexample-artifact result)))
      (cl-spec:defspec-function e7-target
        (:args (x integer))
        (:args-generator e7-args)
        (:capture (before x))
        (:returns string)
        (:state-post t))
      (let ((before *calls*)
            (outcome (recheck-counterexample artifact :state-policy :stateless)))
        (ok (eq :unsupported (getf outcome :status)))
        (ok (eq :stateful-contract-unsupported (getf outcome :detail)))
        (ok (= before *calls*))))))

(deftest featureless-shrinking-is-unchanged
  (with-fresh-registry
    (with-live-generator (e8-args)
      (define-plain-contract e8-target e8-args)
      (reset-counters)
      (let ((result (run-scenario :name 'e8-target :scenario :no-update)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (ok (null (getf (property-result-schema-metadata result)
                        :state-constraints)))))))

;;; F. Compatibility and non-executing queries

(deftest a-featureless-contract-gains-no-new-keys
  (with-fresh-registry
    (with-live-generator (f1-args)
      (define-plain-contract f1-target f1-args)
      (let* ((contract (find-function-spec 'f1-target))
             (data (function-spec-data 'f1-target))
             (description (definition-description contract)))
        (ok (null (getf data :capture)))
        (ok (null (getf data :state-post)))
        (ok (null (getf description :capture)))
        (ok (null (getf description :state-post)))
        (ok (null (definition-state-constraints contract)))
        (ok (definition-shrink-enabled-p contract))))))

(deftest declaring-capture-or-state-post-changes-the-digest
  (with-fresh-registry
    (with-live-generator (f2-args)
      (define-target f2-target)
      (cl-spec:defspec-function f2-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator f2-args)
        (:returns string))
      (let ((before (definition-digest (find-function-spec 'f2-target))))
        (cl-spec:defspec-function f2-target
          (:args (account (satisfies account-p)) (amount (range integer 1 200)))
          (:args-generator f2-args)
          (:capture (before (account-balance account)))
          (:returns string)
          (:state-post t))
        (ok (not (equal before
                        (definition-digest (find-function-spec 'f2-target)))))))))

(deftest introspection-and-capability-run-no-contract-code
  (with-fresh-registry
    (with-live-generator (f3-args)
      (define-target f3-target)
      (cl-spec:defspec-function f3-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator f3-args)
        (:capture (before (progn (incf *capture-runs*) (account-balance account))))
        (:cases
          (:a (:when (progn (incf *guard-runs*) (<= amount before)))
              (:returns (satisfies listp))
              (:state-post (progn (incf *state-runs*) (= before before))))))
      (reset-counters)
      (function-spec-data 'f3-target)
      (definition-digest (find-function-spec 'f3-target))
      (definition-description (find-function-spec 'f3-target))
      (definition-state-constraints (find-function-spec 'f3-target))
      (definition-shrink-enabled-p (find-function-spec 'f3-target))
      (definition-instrumentation-capability (find-function-spec 'f3-target))
      (ok (= 0 *capture-runs*))
      (ok (= 0 *guard-runs*))
      (ok (= 0 *state-runs*))
      (ok (= 0 *calls*)))))

(deftest instrumentation-refuses-without-breaking-the-function
  (with-fresh-registry
    (with-live-generator (f4-args)
      (define-withdraw-contract f4-target f4-args)
      (let ((contract (find-function-spec 'f4-target))
            (reason (handler-case
                        (progn (instrument-function 'f4-target) nil)
                      (unsupported-instrumentation-target (condition)
                        (unsupported-instrumentation-target-reason condition)))))
        (ok (eq :state-constraints-unsupported reason))
        (ok (eq :unavailable (definition-instrumentation-capability contract)))
        (ok (not (instrumented-function-p 'f4-target)))
        (testing "the target is still an ordinary function"
          (reset-counters)
          (configure-draw :balance 10 :amount 5 :scenario :correct)
          (ok (equal '(:receipt 5) (f4-target (make-account 10 7) 5))))))))

(deftest zero-trial-and-all-rejected-runs-still-report-known-zeros
  (with-fresh-registry
    (with-live-generator (f5-args)
      (define-withdraw-contract f5-target f5-args)
      (reset-counters)
      (let ((report (function-check-result-case-report
                     (check-function 'f5-target :trials 0 :seed 1))))
        (ok (= 0 (getf report :capture-errors)))
        (ok (= 0 (getf report :case-selection-errors)))
        (ok (equal '(:sufficient-funds :insufficient-funds)
                   (getf report :never-called)))))
    (with-live-generator (f5b-args)
      (define-target f5b-target)
      (cl-spec:defspec-function f5b-target
        (:args (account (satisfies account-p)) (amount (range integer 1 200)))
        (:args-generator f5b-args)
        (:pre nil)
        (:capture (before (account-balance account)))
        (:returns (satisfies listp))
        (:state-post t))
      (reset-counters)
      (let ((result (check-function 'f5b-target :trials 3 :seed 1)))
        (ok (eq :skipped (property-result-status result)))
        (ok (= 3 (property-result-rejected result)))
        (ok (= 0 *capture-runs*))
        (ok (= 0 *calls*))))))
