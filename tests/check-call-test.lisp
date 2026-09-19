;;;; tests/check-call-test.lisp
;;;;
;;;; Direct concrete invocation checking (CHECK-CALL).  One caller-supplied raw
;;;; argument list is checked against a registered Function Spec with no
;;;; generation, shrinking or replay.  The suite pins the call-count invariants,
;;;; the binding semantics, the shared classifier's outcomes, exclusive case
;;;; selection, state observation and execution discipline, and compares the
;;;; one-shot classification with CHECK-FUNCTION over a generator that supplies
;;;; exactly the same arguments.

(defpackage #:cl-spec/tests/check-call-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec
                #:check-call
                #:check-function
                #:call-check-result
                #:call-check-result-arguments
                #:call-check-data
                #:call-check-result-definition
                #:call-check-result-failure-phase
                #:call-check-result-name
                #:call-check-result-observation
                #:call-check-result-source-form
                #:call-check-result-status
                #:defgenerator
                #:defspec-function
                #:definition-digest
                #:find-function-spec
                #:function-spec
                #:invalid-call-arguments
                #:invalid-call-arguments-arguments
                #:invalid-call-arguments-errors
                #:invalid-call-arguments-function
                #:invalid-call-arguments-reason
                #:make-hash-table-registry
                #:property-result-failure-reason
                #:property-result-failure-signature
                #:property-result-rejected
                #:property-result-status
                #:property-result-trials
                #:trial-observation-case
                #:trial-observation-condition
                #:trial-observation-explanation
                #:trial-observation-outcome
                #:trial-observation-reason
                #:trial-observation-signature
                #:trial-observation-state
                #:trial-observation-value
                #:unbound-target
                #:unknown-function-spec)
  ;; CHECK-FUNCTION generates arguments, so the comparison tests need a backend
  ;; installed.  The one-shot API itself must also work without it; the
  ;; dedicated test below binds *GENERATOR-BACKEND* to NIL to prove that.
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/check-call-test)

;;; Fixtures

(define-condition insufficient-funds (error)
  ())

(defvar *calls* 0 "Target invocations of the current check.")
(defvar *capture-runs* 0 "Capture form evaluations of the current check.")
(defvar *guard-runs* 0 "Case guard evaluations of the current check.")
(defvar *post-runs* 0 "Post form evaluations of the current check.")
(defvar *state-runs* 0 "State-post form evaluations of the current check.")
(defvar *last-arguments* nil "Argument list the target last received.")
(defvar *scenario* :identity "Which answer UNARY-TARGET and DYAD-TARGET give.")
(defvar *balance* 0 "Balance the stateful targets start from.")
(defvar *target-saw-capture* nil "True when the target ran after a completed capture.")
(defvar *scripted-arguments* nil "Whole argument list the scripted generator draws.")

(defun reset-counters ()
  (setf *calls* 0 *capture-runs* 0 *guard-runs* 0 *post-runs* 0 *state-runs* 0
        *last-arguments* nil *target-saw-capture* nil))

(defmacro with-fresh-registry (&body body)
  "Run BODY with an empty registry, so another test's contract is invisible."
  `(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
     ,@body))

(defun dyad-target (a b)
  "Two-argument target whose answer and effect follow *SCENARIO*."
  (incf *calls*)
  (setf *last-arguments* (list a b))
  (case *scenario*
    (:sum (+ a b))
    (:constant 7)
    (:string "not-an-integer")
    (:error (error 'simple-error :format-control "target signalled"))
    (:other-error (error 'insufficient-funds))
    (t (+ a b))))

(defun unary-target (n)
  "One-argument target whose answer and effect follow *SCENARIO*."
  (incf *calls*)
  (setf *last-arguments* (list n))
  (case *scenario*
    (:identity n)
    (:constant 7)
    (:error (error 'simple-error :format-control "target signalled"))
    (:funds-error (error 'insufficient-funds))
    (t n)))

(defun kw-target (a &key b)
  (incf *calls*)
  (setf *last-arguments* (list a :b b))
  (list a b))

(defun kw-open-target (a &key b &allow-other-keys)
  (incf *calls*)
  (setf *last-arguments* (list a :b b))
  (list a b))

(defun rest-target (head &rest tail)
  (incf *calls*)
  (setf *last-arguments* (cons head tail))
  (+ head (reduce #'+ tail :initial-value 0)))

(defun opt-target (a &optional (b nil b-p))
  (incf *calls*)
  (setf *last-arguments* (list a b b-p))
  (list a b))

(defun withdraw-target (amount)
  "Reduce *BALANCE* by AMOUNT and answer the receipt."
  (incf *calls*)
  (setf *last-arguments* (list amount))
  (if (<= amount *balance*)
      (progn (decf *balance* amount) amount)
      (error 'insufficient-funds)))

(defun forgetful-target (amount)
  "Answer a receipt without changing the balance."
  (incf *calls*)
  (setf *last-arguments* (list amount))
  amount)

(defun capture-error-target (amount)
  "Target a failing capture must prevent from running."
  (incf *calls*)
  (setf *last-arguments* (list amount))
  amount)

(defun signals-mutating-target (amount)
  "Signal the expected condition after mutating state, so state-post can fail."
  (incf *calls*)
  (setf *last-arguments* (list amount))
  (decf *balance* amount)
  (error 'insufficient-funds))

(defun order-target (amount)
  "Record whether the capture ran before this call."
  (incf *calls*)
  (setf *target-saw-capture* (plusp *capture-runs*))
  amount)

(defun mutating-target (items)
  "Change the head of the caller's list before answering it."
  (incf *calls*)
  (setf (car items) :mutated)
  items)

(defun refusal (thunk)
  "Return (REASON ERRORS) when THUNK signals INVALID-CALL-ARGUMENTS, else NIL."
  (handler-case (progn (funcall thunk) nil)
    (invalid-call-arguments (condition)
      (list (invalid-call-arguments-reason condition)
            (invalid-call-arguments-errors condition)))))

(defun observation (result)
  (call-check-result-observation result))

;;; Basic calls

(deftest a-passing-required-argument-call-is-reported-as-passed
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      "Sum two integers."
      (:args (a integer) (b integer))
      (:returns integer)
      (:post (= result (+ a b))))
    (reset-counters)
    (setf *scenario* :sum)
    (let ((result (check-call 'dyad-target (list 1 2))))
      (testing "the result is a public one-shot record, not a property result"
        (ok (typep result 'call-check-result))
        (ok (not (typep result 'cl-spec:property-result))))
      (testing "the invocation passed and the target ran exactly once"
        (ok (eq :passed (call-check-result-status result)))
        (ok (= 1 *calls*))
        (ok (equal '(1 2) *last-arguments*)))
      (testing "the observed outcome retains the returned value"
        (ok (equal '(:kind :returned :values (3))
                   (trial-observation-outcome (observation result))))
        (ok (eql 3 (trial-observation-value (observation result)))))
      (testing "the record names the contract and carries its evidence"
        (ok (eq 'dyad-target (call-check-result-name result)))
        (ok (equal '(1 2) (call-check-result-arguments result)))
        (ok (listp (call-check-result-definition result)))
        (ok (consp (call-check-result-source-form result)))))))

(deftest a-return-spec-violation-is-a-failure
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer))
    (reset-counters)
    (setf *scenario* :string)
    (let ((result (check-call 'dyad-target (list 1 2))))
      (ok (eq :failed (call-check-result-status result)))
      (ok (eq :return-spec (trial-observation-reason (observation result))))
      (ok (consp (trial-observation-explanation (observation result))))
      (ok (= 1 *calls*)))))

(deftest a-postcondition-violation-is-a-failure
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer)
      (:post (= result (+ a b))))
    (reset-counters)
    (setf *scenario* :constant)
    (let ((result (check-call 'dyad-target (list 1 2))))
      (ok (eq :failed (call-check-result-status result)))
      (ok (eq :postcondition (trial-observation-reason (observation result))))
      (ok (= 1 *calls*)))))

(deftest an-unexpected-target-error-is-an-error-with-the-target-condition
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer))
    (reset-counters)
    (setf *scenario* :error)
    (let ((result (check-call 'dyad-target (list 1 2))))
      ;; The shared classifier reports :ERROR with reason :CONDITION when the
      ;; target signals a condition the contract did not expect; this matches
      ;; generated checking rather than inventing a second verdict.
      (ok (eq :error (call-check-result-status result)))
      (ok (eq :condition (trial-observation-reason (observation result))))
      (ok (typep (trial-observation-condition (observation result)) 'simple-error))
      (ok (= 1 *calls*)))))

(deftest an-expected-error-passes-and-is-missing-or-wrong-otherwise
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:signals (type simple-error)))
    (testing "the expected condition is a pass"
      (reset-counters)
      (setf *scenario* :error)
      (ok (eq :passed (call-check-result-status (check-call 'dyad-target (list 1 2)))))
      (ok (= 1 *calls*)))
    (testing "a normal return is a missing expected condition"
      (reset-counters)
      (setf *scenario* :sum)
      (let ((result (check-call 'dyad-target (list 1 2))))
        (ok (eq :failed (call-check-result-status result)))
        (ok (eq :missing-condition (trial-observation-reason (observation result))))))
    (testing "a different condition is a condition-spec failure"
      (reset-counters)
      (setf *scenario* :other-error)
      (let ((result (check-call 'dyad-target (list 1 2))))
        (ok (eq :error (call-check-result-status result)))
        (ok (eq :condition-spec (trial-observation-reason (observation result))))))))

(deftest fixed-multiple-values-and-post-values-use-the-shared-classifier
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns (values integer integer))
      (:post-values (first-value second-value)
        (= (+ first-value second-value) (+ a b))))
    (testing "the declared number of values is checked and bound"
      (reset-counters)
      (setf *scenario* :sum)
      ;; DYAD-TARGET returns one value, so the fixed two-value contract fails.
      (let ((result (check-call 'dyad-target (list 1 2))))
        (ok (eq :failed (call-check-result-status result)))
        (ok (eq :return-spec (trial-observation-reason (observation result))))))
    (testing "a multi-value target that satisfies the contract passes"
      (defun two-value-target (a b) (incf *calls*) (values a b))
      (cl-spec:defspec-function two-value-target
        (:args (a integer) (b integer))
        (:returns (values integer integer))
        (:post-values (first-value second-value)
          (= (+ first-value second-value) (+ a b))))
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'two-value-target (list 1 2)))))
      (ok (= 1 *calls*)))))

;;; Argument binding

(deftest a-wrong-arity-or-malformed-call-is-refused-before-the-target
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer))
    (testing "too few arguments is a shape refusal and calls no target"
      (reset-counters)
      (let ((refusal (refusal (lambda () (check-call 'dyad-target (list 1))))))
        (ok (eq :shape (first refusal)))
        (ok (consp (second refusal)))
        (ok (zerop *calls*))))
    (testing "too many arguments is a shape refusal and calls no target"
      (reset-counters)
      (let ((refusal (refusal (lambda () (check-call 'dyad-target (list 1 2 3))))))
        (ok (eq :shape (first refusal)))
        (ok (zerop *calls*))))
    (testing "a non-list is a shape refusal and calls no target"
      (reset-counters)
      (ok (eq :shape (first (refusal (lambda () (check-call 'dyad-target 1))))))
      (ok (zerop *calls*)))
    (testing "a vector of the right length is still not a call list"
      (reset-counters)
      (ok (eq :shape (first (refusal (lambda () (check-call 'dyad-target (vector 1 2)))))))
      (ok (zerop *calls*)))))

(deftest an-argument-outside-its-declared-spec-is-refused-before-the-target
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer))
    (reset-counters)
    (let ((refusal (refusal (lambda () (check-call 'dyad-target (list 1 "x"))))))
      (ok (eq :argument-spec (first refusal)))
      (testing "the structured errors name the failing argument"
        (ok (consp (second refusal)))
        (ok (member :path (first (second refusal)))))
      (ok (zerop *calls*)))))

(deftest optional-arguments-follow-suppliedness
  (with-fresh-registry
    (cl-spec:defspec-function opt-target
      (:args (a integer) &optional (b (or null integer) b-p))
      (:pre (or (not b-p) (integerp b)))
      (:returns list)
      (:post (equal result (list a b))))
    (testing "an omitted optional is bound to NIL and not validated"
      (reset-counters)
      (let ((result (check-call 'opt-target (list 1))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (equal '(1 nil nil) *last-arguments*))))
    (testing "a supplied optional is validated and bound"
      (reset-counters)
      (let ((result (check-call 'opt-target (list 1 5))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (equal '(1 5 t) *last-arguments*))))
    (testing "a supplied optional outside its spec is refused"
      (reset-counters)
      (ok (eq :argument-spec
              (first (refusal (lambda () (check-call 'opt-target (list 1 "x")))))))
      (ok (zerop *calls*)))))

(deftest keyword-arguments-honour-order-and-policy
  (with-fresh-registry
    (cl-spec:defspec-function kw-target
      (:args (a integer) &key ((:b b) (or null integer) b-p))
      (:returns list)
      (:post (if b-p (equal result (list a b)) (equal result (list a nil)))))
    (testing "a keyword pair is accepted in any order"
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'kw-target (list 1 :b 2)))))
      (ok (equal '(1 :b 2) *last-arguments*)))
    (testing "an omitted keyword is bound to NIL and not validated"
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'kw-target (list 1)))))
      (ok (equal '(1 :b nil) *last-arguments*)))
    (testing "an odd keyword tail is a shape refusal"
      (reset-counters)
      (ok (eq :shape (first (refusal (lambda () (check-call 'kw-target (list 1 :b)))))))
      (ok (zerop *calls*)))
    (testing "a non-keyword tail element is a shape refusal"
      (reset-counters)
      (ok (eq :shape (first (refusal (lambda () (check-call 'kw-target (list 1 "x" 2)))))))
      (ok (zerop *calls*)))
    (testing "an unknown key is a shape refusal"
      (reset-counters)
      (ok (eq :shape (first (refusal (lambda () (check-call 'kw-target (list 1 :c 3)))))))
      (ok (zerop *calls*)))))

(deftest allow-other-keys-is-honoured
  (with-fresh-registry
    (cl-spec:defspec-function kw-open-target
      (:args (a integer) &key ((:b b) (or null integer)) &allow-other-keys)
      (:returns list))
    (testing "an undeclared key is admitted when the contract allows others"
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'kw-open-target (list 1 :c 3)))))
      (ok (equal '(1 :b nil) *last-arguments*)))
    (testing "an explicit :allow-other-keys still admits the call"
      (reset-counters)
      (ok (eq :passed
              (call-check-result-status
               (check-call 'kw-open-target (list 1 :allow-other-keys t :c 3))))))))

(deftest rest-arguments-bind-the-whole-remaining-list
  (with-fresh-registry
    (cl-spec:defspec-function rest-target
      (:args (head integer) &rest (tail (list-of integer)))
      (:returns integer)
      (:post (= result (+ head (reduce #'+ tail :initial-value 0)))))
    (testing "the rest binding is the whole tail, exactly as APPLY receives it"
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'rest-target (list 1 2 3 4)))))
      (ok (equal '(1 2 3 4) *last-arguments*)))
    (testing "an empty rest tail is admitted"
      (reset-counters)
      (ok (eq :passed (call-check-result-status (check-call 'rest-target (list 1)))))
      (ok (equal '(1) *last-arguments*)))
    (testing "an element outside the rest spec is refused before the target"
      (reset-counters)
      (ok (eq :argument-spec
              (first (refusal (lambda () (check-call 'rest-target (list 1 "x")))))))
      (ok (zerop *calls*)))))

;;; Cases

(deftest the-selected-case-owns-the-invocation
  (with-fresh-registry
    (cl-spec:defspec-function unary-target
      (:args (n (range integer 1 10)))
      (:cases
       (:small
        "The low branch."
        (:when (progn (incf *guard-runs*) (<= n 5)))
        (:returns integer)
        (:post (= result n)))
       (:large
        "The high branch."
        (:when (progn (incf *guard-runs*) (> n 5)))
        (:returns integer)
        (:post (= result n)))))
    (testing "exactly one matching case is selected and named in the evidence"
      (reset-counters)
      (setf *scenario* :identity)
      (let ((result (check-call 'unary-target (list 3))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (eq :small (trial-observation-case (observation result))))
        (ok (= 1 *calls*))
        (testing "every guard ran, so duplicates would be observed"
          (ok (= 2 *guard-runs*)))))
    (testing "the other branch is selected for the other input"
      (reset-counters)
      (let ((result (check-call 'unary-target (list 8))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (eq :large (trial-observation-case (observation result))))))))

(deftest zero-and-multiple-matches-are-contract-errors-that-call-nothing
  (testing "no matching case"
    (with-fresh-registry
      (cl-spec:defspec-function unary-target
        (:args (n (range integer 1 10)))
        (:cases
         (:impossible (:when (progn (incf *guard-runs*) (> n 100))) (:returns integer))))
      (reset-counters)
      (let ((result (check-call 'unary-target (list 3))))
        (ok (eq :error (call-check-result-status result)))
        (ok (eq :contract-error (trial-observation-reason (observation result))))
        (ok (eq :case-selection (call-check-result-failure-phase result)))
        (ok (zerop *calls*)))))
  (testing "several matching cases"
    (with-fresh-registry
      (cl-spec:defspec-function unary-target
        (:args (n (range integer 1 10)))
        (:cases
         (:first (:when (progn (incf *guard-runs*) (> n 0))) (:returns integer))
         (:second (:when (progn (incf *guard-runs*) (> n 1))) (:returns integer))))
      (reset-counters)
      (let ((result (check-call 'unary-target (list 3))))
        (ok (eq :error (call-check-result-status result)))
        (ok (eq :case-selection (call-check-result-failure-phase result)))
        (ok (zerop *calls*))
        (testing "both guards ran rather than stopping at the first match"
          (ok (= 2 *guard-runs*)))))))

(deftest a-signalling-guard-is-a-contract-error-that-calls-nothing
  (with-fresh-registry
    (cl-spec:defspec-function unary-target
      (:args (n (range integer 1 10)))
      (:cases
       (:broken
        (:when (error 'simple-error :format-control "guard"))
        (:returns integer))))
    (reset-counters)
    (let ((result (check-call 'unary-target (list 3))))
      (ok (eq :error (call-check-result-status result)))
      (ok (eq :case-selection (call-check-result-failure-phase result)))
      (ok (zerop *calls*))
      (testing "the selection identity names the case whose guard signalled"
        (ok (eq :case-selection
                (first (trial-observation-signature (observation result)))))
        (ok (eq :case-guard-error
                (second (trial-observation-signature (observation result)))))
        (ok (eq :broken
                (third (trial-observation-signature (observation result)))))))))

(deftest a-selected-case-stays-in-the-failure-identity
  (with-fresh-registry
    (cl-spec:defspec-function unary-target
      (:args (n (range integer 1 10)))
      (:cases
       (:small
        (:when (progn (incf *guard-runs*) (<= n 5)))
        (:returns integer)
        (:post (= result 999)))
       (:large
        (:when (progn (incf *guard-runs*) (> n 5)))
        (:returns integer)
        (:post (= result n)))))
    (reset-counters)
    (setf *scenario* :identity)
    (let* ((result (check-call 'unary-target (list 3)))
           (signature (trial-observation-signature (observation result))))
      (ok (eq :failed (call-check-result-status result)))
      (ok (eq :postcondition (trial-observation-reason (observation result))))
      (testing "the case wraps the failure identity"
        (ok (eq :case (first signature)))
        (ok (eq :small (second signature))))
      (testing "the case is also recorded on the observation"
        (ok (eq :small (trial-observation-case (observation result))))))))

;;; State observation

(deftest capture-completes-before-the-target
  (with-fresh-registry
    (cl-spec:defspec-function order-target
      (:args (amount (range integer 1 10)))
      (:capture (before (progn (incf *capture-runs*) *balance*)))
      (:returns integer)
      (:post (= result amount)))
    (reset-counters)
    (setf *balance* 30)
    (let* ((result (check-call 'order-target (list 5)))
           (evidence (trial-observation-state (observation result))))
      (ok (eq :passed (call-check-result-status result)))
      (ok (eq :completed (getf (getf evidence :capture) :status)))
      (ok (equal '((before . 30)) (getf (getf evidence :capture) :values)))
      (ok *target-saw-capture*)
      (ok (= 1 *capture-runs*))
      (ok (= 1 *calls*)))))

(deftest a-failing-capture-calls-the-target-zero-times
  (with-fresh-registry
    (cl-spec:defspec-function capture-error-target
      (:args (amount (range integer 1 10)))
      (:capture (before (error 'simple-error :format-control "capture")))
      (:returns integer))
    (reset-counters)
    (let* ((result (check-call 'capture-error-target (list 5)))
           (evidence (trial-observation-state (observation result))))
      (ok (eq :error (call-check-result-status result)))
      (ok (eq :capture (call-check-result-failure-phase result)))
      (ok (eq :error (getf (getf evidence :capture) :status)))
      (ok (zerop *calls*)))))

(deftest state-post-passes-and-fails-after-exactly-one-call
  (with-fresh-registry
    (cl-spec:defspec-function withdraw-target
      (:args (amount (range integer 1 10)))
      (:capture (before *balance*))
      (:returns integer)
      (:post (= result amount))
      (:state-post (= *balance* (- before amount))))
    (testing "a correct withdrawal passes the state-post"
      (reset-counters)
      (setf *balance* 30)
      (let* ((result (check-call 'withdraw-target (list 5)))
             (evidence (trial-observation-state (observation result))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (eql 25 *balance*))
        (ok (eq :passed (getf (getf evidence :state-post) :status)))
        (ok (= 1 *calls*))))
    (testing "a forgotten update is a state-post violation"
      (with-fresh-registry
        (cl-spec:defspec-function forgetful-target
          (:args (amount (range integer 1 10)))
          (:capture (before *balance*))
          (:returns integer)
          (:post (= result amount))
          (:state-post (= *balance* (- before amount))))
        (reset-counters)
        (setf *balance* 30)
        (let* ((result (check-call 'forgetful-target (list 5)))
               (evidence (trial-observation-state (observation result)))
               (state-post (getf evidence :state-post)))
          (ok (eq :failed (call-check-result-status result)))
          (ok (eq :state-post (call-check-result-failure-phase result)))
          (ok (eq :state-postcondition (trial-observation-reason (observation result))))
          (testing "the failure position and form are retained"
            (ok (eql 0 (getf state-post :index)))
            (ok (equal '(= *balance* (- before amount)) (getf state-post :form))))
          (testing "the target was called exactly once"
            (ok (= 1 *calls*))))))))

(deftest an-expected-error-is-followed-by-state-post-validation
  (with-fresh-registry
    (cl-spec:defspec-function withdraw-target
      (:args (amount (range integer 1 10)))
      (:capture (before *balance*))
      (:signals (type insufficient-funds))
      (:state-post (= *balance* before)))
    (testing "an error that leaves the balance alone passes"
      (reset-counters)
      (setf *balance* 3)
      (let ((result (check-call 'withdraw-target (list 5))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (= 1 *calls*))))
    (testing "an error that also mutated the balance fails the state-post"
      (with-fresh-registry
        (cl-spec:defspec-function signals-mutating-target
          (:args (amount (range integer 1 10)))
          (:capture (before *balance*))
          (:signals (type insufficient-funds))
          (:state-post (= *balance* before)))
        (reset-counters)
        (setf *balance* 30)
        (let* ((result (check-call 'signals-mutating-target (list 5)))
               (evidence (trial-observation-state (observation result))))
          (ok (eq :failed (call-check-result-status result)))
          (ok (eq :state-post (call-check-result-failure-phase result)))
          (ok (eq :violation (getf (getf evidence :state-post) :status)))
          (ok (= 1 *calls*)))))))

;;; Execution discipline and API errors

(deftest projection-never-runs-the-target-guards-capture-or-post-forms
  (with-fresh-registry
    (cl-spec:defspec-function unary-target
      (:args (n (range integer 1 10)))
      (:capture (before (progn (incf *capture-runs*) *balance*)))
      (:cases
       (:small
        (:when (progn (incf *guard-runs*) (<= n 5)))
        (:returns integer)
        (:post (progn (incf *post-runs*) (= result n)))
        (:state-post (progn (incf *state-runs*) (= *balance* before))))))
    (reset-counters)
    (setf *balance* 30 *scenario* :identity)
    (let ((result (check-call 'unary-target (list 3))))
      (ok (eq :passed (call-check-result-status result)))
      (let ((calls *calls*) (captures *capture-runs*) (guards *guard-runs*)
            (posts *post-runs*) (states *state-runs*))
        (testing "the invocation ran each form exactly once"
          (ok (= 1 calls)) (ok (= 1 captures)) (ok (= 1 guards))
          (ok (= 1 posts)) (ok (= 1 states)))
        (testing "reading and projecting the result re-runs nothing"
          (call-check-result-status result)
          (call-check-result-name result)
          (call-check-result-arguments result)
          (call-check-result-source-form result)
          (call-check-result-failure-phase result)
          (call-check-result-definition result)
          (observation result)
          (trial-observation-case (observation result))
          (trial-observation-state (observation result))
          (call-check-data result)
          (call-check-data result)
          (ok (= calls *calls*))
          (ok (= captures *capture-runs*))
          (ok (= guards *guard-runs*))
          (ok (= posts *post-runs*))
          (ok (= states *state-runs*)))))))

(deftest a-mutating-target-does-not-change-the-reported-arguments
  (with-fresh-registry
    (cl-spec:defspec-function mutating-target
      (:args (items (list-of integer)))
      (:returns t))
    (reset-counters)
    (let* ((supplied (list 1 2))
           (result (check-call 'mutating-target (list supplied))))
      (ok (eq :passed (call-check-result-status result)))
      (testing "the record reports the pre-call argument list"
        (ok (equal '((1 2)) (call-check-result-arguments result)))
        (ok (equal '((1 2)) (getf (call-check-data result) :arguments))))
      (testing "the observation records that the invocation mutated its input"
        (ok (cl-spec:trial-observation-arguments-mutated-p (observation result))))
      (testing "the caller's own list was the one mutated"
        (ok (equal '(:mutated 2) supplied))))))

(deftest api-misuse-is-signalled-and-findings-are-returned
  (with-fresh-registry
    (cl-spec:defspec-function unary-target
      (:args (n (range integer 1 10)))
      (:pre (> n 5))
      (:returns integer))
    (testing "an unknown function spec signals"
      (signals (check-call 'no-such-function-spec (list 1)) 'unknown-function-spec))
    (testing "a registered contract with no function signals"
      (cl-spec:defspec-function undefined-target-function
        (:args (n integer))
        (:returns integer))
      (signals (check-call 'undefined-target-function (list 1)) 'unbound-target))
    (testing "invalid raw arguments signal with their structured errors"
      (let ((condition
              (handler-case (progn (check-call 'unary-target (list "x")) nil)
                (invalid-call-arguments (condition) condition))))
        (ok condition)
        (ok (eq 'unary-target (invalid-call-arguments-function condition)))
        (ok (equal '("x") (invalid-call-arguments-arguments condition)))
        (ok (eq :argument-spec (invalid-call-arguments-reason condition)))
        (ok (consp (invalid-call-arguments-errors condition)))))
    (testing "a precondition refusal is a result, not a signal"
      (reset-counters)
      (let ((result (check-call 'unary-target (list 1))))
        (ok (eq :rejected (call-check-result-status result)))
        (ok (null (trial-observation-reason (observation result))))
        (ok (null (trial-observation-signature (observation result))))
        (ok (zerop *calls*))))))

(deftest a-contract-object-is-an-accepted-designator
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:returns integer))
    (reset-counters)
    (setf *scenario* :sum)
    (let ((contract (find-function-spec 'dyad-target)))
      (ok (typep contract 'function-spec))
      (ok (eq :passed (call-check-result-status (check-call contract (list 2 3))))))))

(deftest the-record-identifies-the-declaration-not-the-implementation
  (with-fresh-registry
    (cl-spec:defspec-function dyad-target
      "Sum two integers."
      (:args (a integer) (b integer))
      (:returns integer))
    (reset-counters)
    (setf *scenario* :sum)
    (let* ((result (check-call 'dyad-target (list 1 2)))
           (data (call-check-data result))
           (metadata (call-check-result-definition result)))
      (testing "the version 1 envelope is reused"
        (ok (eql 1 (getf data :schema-version)))
        (ok (eq :result (getf data :record-kind)))
        (ok (eq :function-spec (getf data :entity-kind)))
        (ok (eq :declaration-and-registered-dependencies
                (getf data :definition-digest-covers)))
        (ok (eq :target-implementation
                (car (member :target-implementation (getf data :digest-exclusions))))))
      (testing "the digest is the declaration digest and is complete"
        (ok (stringp (getf metadata :definition-digest)))
        (ok (getf metadata :definition-digest-complete))
        (ok (equal (nth-value 0 (definition-digest 'dyad-target :entity-kind :function-spec))
                   (getf metadata :definition-digest))))
      (testing "the projection is data, not prose"
        (ok (eq :passed (getf data :status)))
        (ok (equal '(1 2) (getf data :arguments)))
        (ok (eq :passed (getf (getf data :observation) :status)))
        (ok (eql 3 (getf (getf data :observation) :value)))))))

(deftest a-one-shot-check-works-without-a-generator-backend
  (with-fresh-registry
    ;; A generator that would signal if anything drew from it, so a passing
    ;; check proves the path neither requires nor touches a backend.
    (cl-spec:defgenerator never-drawn-arguments ()
      (error "CHECK-CALL must not draw from a generator"))
    (cl-spec:defspec-function dyad-target
      (:args (a integer) (b integer))
      (:args-generator never-drawn-arguments)
      (:returns integer)
      (:post (= result (+ a b))))
    (reset-counters)
    (setf *scenario* :sum)
    (let ((cl-spec:*generator-backend* nil))
      (ok (null cl-spec:*generator-backend*))
      (let ((result (check-call 'dyad-target (list 4 5))))
        (ok (eq :passed (call-check-result-status result)))
        (ok (= 1 *calls*))
        (testing "the declaration metadata reports without probing a backend"
          (ok (eq :unknown
                  (getf (getf (call-check-result-definition result) :capabilities)
                        :generation))))))))

;;; Agreement with generated checking

(defun generated-status (result)
  (property-result-status result))

(defun generated-failure-key (result)
  (list (property-result-failure-reason result)
        (property-result-failure-signature result)))

(defun direct-failure-key (result)
  (list (trial-observation-reason (call-check-result-observation result))
        (trial-observation-signature (call-check-result-observation result))))

(defun register-exact-arguments-generator ()
  "Register a whole-argument generator that draws *SCRIPTED-ARGUMENTS*."
  (cl-spec:defgenerator exact-arguments ()
    *scripted-arguments*))

(deftest one-shot-and-generated-classification-agree
  ;; The generator supplies exactly the same argument list the one-shot call
  ;; gets, so a disagreement would be a difference between the two entry points
  ;; rather than between two inputs.
  (testing "a passing invocation classifies the same way"
    (with-fresh-registry
      (register-exact-arguments-generator)
      (cl-spec:defspec-function dyad-target
        (:args (a integer) (b integer))
        (:args-generator exact-arguments)
        (:returns integer)
        (:post (= result (+ a b))))
      (reset-counters)
      (setf *scenario* :sum)
      (let ((direct-result (check-call 'dyad-target (list 1 2))))
        (reset-counters)
        (setf *scripted-arguments* (list 1 2))
        (let ((generated-result (check-function 'dyad-target :trials 1 :seed 1)))
          (ok (eq :passed (call-check-result-status direct-result)))
          (ok (eq (generated-status generated-result)
                  (call-check-result-status direct-result)))
          (ok (equal (generated-failure-key generated-result)
                     (direct-failure-key direct-result)))))))
  (testing "a returns failure classifies the same way"
    (with-fresh-registry
      (register-exact-arguments-generator)
      (cl-spec:defspec-function dyad-target
        (:args (a integer) (b integer))
        (:args-generator exact-arguments)
        (:returns integer))
      (reset-counters)
      (setf *scenario* :string)
      (let ((direct-result (check-call 'dyad-target (list 1 2))))
        (reset-counters)
        (setf *scripted-arguments* (list 1 2))
        (let ((generated-result (check-function 'dyad-target :trials 1 :seed 1)))
          (ok (equal (generated-status generated-result)
                     (call-check-result-status direct-result)))
          (ok (equal (generated-failure-key generated-result)
                     (direct-failure-key direct-result)))))))
  (testing "a postcondition failure classifies the same way"
    (with-fresh-registry
      (register-exact-arguments-generator)
      (cl-spec:defspec-function dyad-target
        (:args (a integer) (b integer))
        (:args-generator exact-arguments)
        (:returns integer)
        (:post (= result (+ a b))))
      (reset-counters)
      (setf *scenario* :constant)
      (let ((direct-result (check-call 'dyad-target (list 1 2))))
        (reset-counters)
        (setf *scripted-arguments* (list 1 2))
        (let ((generated-result (check-function 'dyad-target :trials 1 :seed 1)))
          (ok (equal (generated-status generated-result)
                     (call-check-result-status direct-result)))
          (ok (equal (generated-failure-key generated-result)
                     (direct-failure-key direct-result)))))))
  (testing "a case-carrying failure keeps the same case identity"
    (with-fresh-registry
      (register-exact-arguments-generator)
      (cl-spec:defspec-function unary-target
        (:args (n (range integer 1 10)))
        (:args-generator exact-arguments)
        (:cases
         (:small (:when (<= n 5)) (:returns integer) (:post (= result 999)))
         (:large (:when (> n 5)) (:returns integer) (:post (= result n)))))
      (reset-counters)
      (setf *scenario* :identity)
      (let ((direct-result (check-call 'unary-target (list 3))))
        (reset-counters)
        (setf *scripted-arguments* (list 3))
        (let ((generated-result (check-function 'unary-target :trials 1 :seed 1)))
          (ok (equal (generated-status generated-result)
                     (call-check-result-status direct-result)))
          (ok (equal (generated-failure-key generated-result)
                     (direct-failure-key direct-result)))
          (ok (eq :small (trial-observation-case
                          (call-check-result-observation direct-result))))))))
  (testing "a precondition refusal is a rejection for one-shot and a skip for a run"
    (with-fresh-registry
      (register-exact-arguments-generator)
      (cl-spec:defspec-function unary-target
        (:args (n (range integer 1 10)))
        (:args-generator exact-arguments)
        (:pre (> n 5))
        (:returns integer))
      (reset-counters)
      (setf *scenario* :identity)
      (let ((direct-result (check-call 'unary-target (list 1))))
        (reset-counters)
        (setf *scripted-arguments* (list 1))
        (let ((generated-result (check-function 'unary-target :trials 1 :seed 1)))
          (ok (eq :rejected (call-check-result-status direct-result)))
          (ok (zerop *calls*))
          (ok (eq :skipped (generated-status generated-result)))
          (ok (= 1 (property-result-rejected generated-result)))
          (ok (= 1 (property-result-trials generated-result))))))))

