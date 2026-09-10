;;;; tests/function-spec-test.lisp

(defpackage #:cl-spec/tests/function-spec-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:invalid-function-spec-form
                #:unknown-function-spec)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-status
                #:property-result-trials
                #:property-result-seed
                #:property-result-counterexample
                #:property-result-shrunk-counterexample)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-kind
                #:reference-spec-target)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-function-spec
                #:list-function-specs)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function)
  ;; CHECK-FUNCTION generates arguments, so this suite needs a backend installed.
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name
                #:function-spec-argument-specs
                #:function-spec-return-spec
                #:function-spec-preconditions
                #:function-spec-postconditions
                #:function-spec-precondition-function
                #:function-spec-postcondition-function
                #:function-spec-documentation
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata
                #:register-function-spec
                #:function-check-result
                #:function-check-result-rejected
                #:function-check-result-failure-reason
                #:function-check-result-explanation
                #:check-function))

(in-package #:cl-spec/tests/function-spec-test)

(deftest function-spec-slots-round-trip
  (testing "every documented slot is readable"
    (let ((instance (make-instance 'function-spec
                                   :name 'transfer
                                   :argument-specs '((from account)
                                                     (to account)
                                                     (amount positive-money))
                                   :return-spec 'transaction
                                   :preconditions '((distinct-accounts-p from to))
                                   :precondition-function (lambda (from to amount)
                                                            (declare (ignore amount))
                                                            (not (eq from to)))
                                   :postconditions '((balance-preserved-p))
                                   :postcondition-function (lambda (result from to amount)
                                                             (declare (ignore result from
                                                                               to amount))
                                                             t)
                                   :documentation "Move money between accounts."
                                   :source-form '(defspec-function transfer)
                                   :source-location '(:file "/tmp/bank.lisp")
                                   :metadata '(:owner "bank-team"))))
      (ok (eq 'transfer (function-spec-name instance)))
      (ok (equal '((distinct-accounts-p from to))
                 (function-spec-preconditions instance)))
      (ok (equal '((balance-preserved-p)) (function-spec-postconditions instance)))
      (ok (functionp (function-spec-precondition-function instance)))
      (ok (functionp (function-spec-postcondition-function instance)))
      (ok (equal "Move money between accounts." (function-spec-documentation instance)))
      (ok (equal '(defspec-function transfer) (function-spec-source-form instance)))
      (ok (equal '(:file "/tmp/bank.lisp") (function-spec-source-location instance)))
      (ok (equal '(:owner "bank-team") (function-spec-metadata instance))))))

(deftest function-spec-refuses-a-claim-it-could-not-check
  (testing "clause forms without their compiled predicate are refused"
    ;; The class and REGISTER-FUNCTION-SPEC are both public, so a contract can
    ;; be built without the DSL.  A compiled predicate cannot be recovered from
    ;; the stored forms -- §60 forbids runtime EVAL -- so an object carrying
    ;; :PRE forms and no function is one CHECK-FUNCTION would run while
    ;; silently ignoring the claim, and report :PASSED for it.  There is no
    ;; repair, only refusal.
    (ok (handler-case
            (progn (make-instance 'function-spec
                                  :name 'transfer
                                  :preconditions '((distinct-accounts-p from to)))
                   nil)
          (invalid-function-spec-form () t)))
    (ok (handler-case
            (progn (make-instance 'function-spec
                                  :name 'transfer
                                  :postconditions '((balance-preserved-p)))
                   nil)
          (invalid-function-spec-form () t))))
  (testing "and a contract with neither forms nor functions is fine"
    (ok (typep (make-instance 'function-spec :name 'transfer) 'function-spec))))

(deftest function-spec-normalizes-argument-specs-it-is-handed
  (testing "a spec designator becomes IR, so every consumer reads one shape"
    ;; Unlike a missing predicate, this one can be repaired: NORMALIZE-SPEC-FORM
    ;; is pure and returns an already-normalized spec unchanged.  Left alone,
    ;; the backend dispatched SPEC-GENERATOR on the bare symbol and signalled
    ;; NO-APPLICABLE-METHOD out of both CHECK-FUNCTION and FUNCTION-SPEC-DATA.
    (let ((instance (make-instance 'function-spec
                                   :name 'transfer
                                   :argument-specs '((amount integer))
                                   :return-spec 'integer)))
      (ok (typep (second (first (function-spec-argument-specs instance))) 'spec))
      (ok (typep (function-spec-return-spec instance) 'spec))
      (testing "and the parameter name is left alone"
        (ok (eq 'amount (first (first (function-spec-argument-specs instance))))))))
  (testing "an already normalized spec is not rebuilt"
    (let* ((normalized (normalize-spec-form 'integer))
           (instance (make-instance 'function-spec
                                    :name 'transfer
                                    :argument-specs (list (list 'amount normalized)))))
      (ok (eq normalized (second (first (function-spec-argument-specs instance))))))))

(deftest function-spec-registration
  (testing "REGISTER-FUNCTION-SPEC uses the function spec's own name"
    (let ((*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (ok (eq instance (register-function-spec instance)))
      (ok (eq instance (find-function-spec 'transfer)))
      (ok (equal '(transfer) (list-function-specs)))))
  (testing "an explicit registry argument is honoured"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (register-function-spec instance other)
      (ok (null (find-function-spec 'transfer)))
      (ok (eq instance (find-function-spec 'transfer other))))))

(deftest defspec-function-normalizes-its-clauses
  (testing ":ARGS and :RETURNS become Semantic IR while :PRE and :POST keep their forms"
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (and integer (range -1000 1000)))
      (defspec-function demo-clamp
        "Limit a value to an interval."
        (:args (value small-integer) (low small-integer) (high small-integer))
        (:pre (<= low high))
        (:returns small-integer)
        (:post (and (<= low result) (<= result high))))
      (let ((contract (find-function-spec 'demo-clamp)))
        (ok (eq 'demo-clamp (function-spec-name contract)))
        (ok (equal '(demo-clamp) (list-function-specs)))
        (ok (equal '(value low high)
                   (mapcar #'first (function-spec-argument-specs contract))))
        (ok (every (lambda (pair) (typep (second pair) 'spec))
                   (function-spec-argument-specs contract)))
        (ok (eq 'small-integer
                (reference-spec-target
                 (second (first (function-spec-argument-specs contract))))))
        (ok (eq :reference (spec-kind (function-spec-return-spec contract))))
        (ok (equal '((<= low high)) (function-spec-preconditions contract)))
        (ok (equal '((and (<= low result) (<= result high)))
                   (function-spec-postconditions contract)))
        (ok (equal "Limit a value to an interval."
                   (function-spec-documentation contract)))
        (ok (eq 'defspec-function (first (function-spec-source-form contract))))
        (ok (function-spec-source-location contract)))))
  (testing "a docstring is documentation even when it is the only clause"
    ;; DEFPROPERTY guards this case because a lone string there is the
    ;; predicate body.  DEFSPEC-FUNCTION has no body forms, so a leading
    ;; string can only ever be documentation -- and refusing it while
    ;; accepting both no clauses at all and a docstring plus a clause is an
    ;; inconsistency, not a check.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-undocumented-contract)
      (defspec-function demo-documented-contract "All it has is prose.")
      (ok (null (function-spec-documentation
                 (find-function-spec 'demo-undocumented-contract))))
      (ok (equal "All it has is prose."
                 (function-spec-documentation
                  (find-function-spec 'demo-documented-contract)))))))

(deftest defspec-function-refuses-what-the-checker-cannot-honour
  (testing "a lambda list keyword in :ARGS is named in the refusal, not dropped"
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer) &optional (b integer))))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer) &key (b integer))))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (a integer) &rest more)))
                 'invalid-function-spec-form)))
  (testing "an unsupported clause is refused rather than ignored"
    ;; §17 lists SIGNALS as part of a function spec, and the MVP checker cannot
    ;; honour it; accepting the clause would report a verified result for a
    ;; claim nothing checked.
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer))
                                  (:signals division-by-zero)))
                 'invalid-function-spec-form)))
  (testing "multiple values are refused, because :RETURNS checks one value"
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer))
                                  (:returns (values integer integer))))
                 'invalid-function-spec-form)))
  (testing "a repeated clause is refused rather than silently taking one of them"
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer))
                                  (:returns integer)
                                  (:returns string)))
                 'invalid-function-spec-form)))
  (testing ":PRE cannot refer to RESULT, which does not exist before the call"
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer))
                                  (:pre (integerp result))))
                 'invalid-function-spec-form)))
  (testing "a malformed :ARGS entry is refused"
    (ok (signals (macroexpand-1 '(defspec-function f (:args a)))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (a integer) (a string))))
                 'invalid-function-spec-form))))

(defun demo-clamp (value low high)
  "Return VALUE limited to the closed interval [LOW, HIGH]."
  (cond ((< value low) low)
        ((> value high) high)
        (t value)))

(defun demo-clamp-swapped (value low high)
  "A CLAMP whose MIN and MAX are the wrong way round.

Returns LOW for every non-empty interval, so it satisfies \"the result is
inside the bounds\" and breaks \"a value already inside is left alone\"."
  (min low (max high value)))

(defun demo-negate (value)
  "Return the negation of VALUE printed, in violation of an integer :RETURNS."
  (format nil "~D" (- value)))

(defun demo-always-signals (value bound)
  "Signal whenever called, so a contract check over it ends in :ERROR."
  (declare (ignore bound))
  (error "DEMO-ALWAYS-SIGNALS was called with ~S" value))

(defmacro with-clamp-contract ((function-name &key (pre '(<= low high))) &body body)
  "Register the CLAMP contract about FUNCTION-NAME in a private registry.

The contract is the whole of it: the result stays inside the interval, and a
value already inside is returned untouched.  Half of it -- bounds alone -- is
satisfied by a CLAMP that always returns LOW, which is exactly the defect
DEMO-CLAMP-SWAPPED has."
  `(let ((*registry* (make-hash-table-registry)))
     (defspec small-integer (range integer -100 100))
     (defspec-function ,function-name
       "Limit a value to a closed interval."
       (:args (value small-integer) (low small-integer) (high small-integer))
       (:pre ,pre)
       (:returns small-integer)
       (:post (and (<= low result)
                   (<= result high)
                   (if (<= low value high) (= result value) t))))
     ,@body))

(deftest check-function-verifies-a-function-that-honours-its-contract
  (with-clamp-contract (demo-clamp)
    (let ((result (check-function 'demo-clamp :trials 50)))
      (testing "the result is a property result, so one reader set covers both"
        (ok (typep result 'function-check-result))
        (ok (eq :passed (property-result-status result)))
        (ok (= 50 (property-result-trials result)))
        (ok (integerp (property-result-seed result))))
      (testing "nothing is reported as a counterexample"
        (ok (null (property-result-counterexample result)))
        (ok (null (function-check-result-failure-reason result))))
      (testing "inputs the precondition refused are counted rather than hidden"
        ;; Half the generated (LOW HIGH) pairs are the wrong way round, so a
        ;; run that reported 50 checked trials would be overstating its work.
        (ok (integerp (function-check-result-rejected result)))
        (ok (plusp (function-check-result-rejected result)))
        (ok (< (function-check-result-rejected result) 50))))))

(deftest check-function-names-which-half-of-the-contract-broke
  (testing "a postcondition failure is reported as one, with a shrunk counterexample"
    (with-clamp-contract (demo-clamp-swapped)
      (let ((result (check-function 'demo-clamp-swapped :trials 200)))
        (ok (eq :failed (property-result-status result)))
        (ok (property-result-counterexample result))
        (ok (property-result-shrunk-counterexample result))
        (ok (eq :postcondition (function-check-result-failure-reason result)))
        (testing "the shrunk counterexample still satisfies the precondition"
          ;; The shrinker does not know about :PRE; a smaller input that :PRE
          ;; refuses is not a counterexample, and reporting one would send an
          ;; agent to fix a call the contract never admitted.
          (let ((values (loop for (nil value) on
                              (property-result-shrunk-counterexample result) by #'cddr
                              collect value)))
            (ok (<= (second values) (third values))))))))
  (testing "a return spec violation is reported as one, with the explanation"
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-negate
        (:args (value small-integer))
        (:returns small-integer))
      (let ((result (check-function 'demo-negate :trials 10)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (let ((explanation (function-check-result-explanation result)))
          (ok explanation)
          (ok (null (getf explanation :valid)))
          (ok (getf explanation :errors)))))))

(deftest check-function-does-not-report-a-vacuous-run-as-verified
  (testing "a precondition nothing can satisfy is SKIPPED, never PASSED"
    ;; SMALL-INTEGER admits -100..100, so (> low 1000) rejects every generated
    ;; argument list.  Counting those as passing trials is the zero-count
    ;; success §73.3 measures for: the run would claim a verified contract
    ;; while having executed the function no times at all.
    (with-clamp-contract (demo-clamp :pre (> low 1000))
      (let ((result (check-function 'demo-clamp :trials 20)))
        (ok (eq :skipped (property-result-status result)))
        (ok (not (eq :passed (property-result-status result))))
        (ok (= 20 (function-check-result-rejected result)))))))

(deftest check-function-stops-counting-rejections-when-the-trial-loop-ends
  (testing "an erroring contract never reports more rejections than trials"
    ;; A signalled condition ends the trial loop, but it leaves the counter
    ;; running: everything the backend does afterwards is shrinking, and every
    ;; shrink candidate :PRE refuses was being counted as a rejected trial.
    ;; REJECTED then exceeds TRIALS and the call count it implies -- TRIALS
    ;; minus REJECTED -- comes out negative.
    (let ((*registry* (make-hash-table-registry)))
      (defspec wide-integer (range integer -500 500))
      (defspec-function demo-always-signals
        (:args (value wide-integer) (bound wide-integer))
        (:pre (and (< value bound) (> value 400)))
        (:returns wide-integer))
      (let* ((result (check-function 'demo-always-signals :trials 3000))
             (trials (property-result-trials result))
             (rejected (function-check-result-rejected result)))
        (testing "the run reached the function, so this is not a vacuous check"
          (ok (eq :error (property-result-status result))))
        (ok (<= rejected trials))
        (testing "so the call count it implies is a count of calls that happened"
          (ok (plusp (- trials rejected))))))))

(deftest check-function-refuses-a-trial-count-that-runs-nothing
  (testing "a negative TRIALS is refused rather than reported as verified"
    ;; The backend's trial loop simply does not run for a negative count and
    ;; reports :PASSED with that count.  EXECUTED then came out negative rather
    ;; than zero, so the vacuous-run guard did not fire and the contract was
    ;; reported verified without the function ever being called.
    (with-clamp-contract (demo-clamp)
      (ok (handler-case (progn (check-function 'demo-clamp :trials -5) nil)
            (type-error () t)))
      (ok (handler-case (progn (check-function 'demo-clamp :trials 1.5) nil)
            (type-error () t)))))
  (testing "zero is a legal budget, and reports that nothing was checked"
    (with-clamp-contract (demo-clamp)
      (let ((result (check-function 'demo-clamp :trials 0)))
        (ok (eq :skipped (property-result-status result)))
        (ok (not (eq :passed (property-result-status result))))))))

(deftest check-function-refuses-a-name-it-cannot-check
  (testing "a symbol with no registered contract signals UNKNOWN-FUNCTION-SPEC"
    (let ((*registry* (make-hash-table-registry)))
      (ok (handler-case (progn (check-function 'demo-clamp) nil)
            (unknown-function-spec () t)))))
  (testing "a contract whose function is not defined signals UNDEFINED-FUNCTION"
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-function-that-does-not-exist
        (:args (value small-integer))
        (:returns small-integer))
      (ok (handler-case (progn (check-function 'demo-function-that-does-not-exist) nil)
            (undefined-function () t))))))

(deftest check-function-reproduces-a-failure-from-its-seed
  (testing "the same seed regenerates the same counterexample"
    (with-clamp-contract (demo-clamp-swapped)
      (let* ((first-run (check-function 'demo-clamp-swapped :trials 200))
             (seed (property-result-seed first-run))
             (second-run (check-function 'demo-clamp-swapped :trials 200 :seed seed)))
        (ok (eq :failed (property-result-status second-run)))
        (ok (equal (property-result-counterexample first-run)
                   (property-result-counterexample second-run)))
        (ok (equal (property-result-shrunk-counterexample first-run)
                   (property-result-shrunk-counterexample second-run)))))))
