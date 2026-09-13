;;;; tests/function-spec-test.lisp

(defpackage #:cl-spec/tests/function-spec-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:invalid-function-spec-form
                #:unknown-function-spec)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-status
                #:property-result-trials
                #:property-result-seed
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:run-property)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-kind
                #:reference-spec-target)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator
                #:validate)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/introspection
                #:function-spec-data)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:registry-register-spec
                #:registry-register-generator
                #:find-function-spec
                #:list-function-specs)
  (:import-from #:cl-spec/src/property
                #:property
                #:register-property)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty)
  ;; CHECK-FUNCTION generates arguments, so this suite needs a backend installed.
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name #:function-spec-call-layout
                #:function-spec-argument-specs #:function-spec-argument-schema
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
                #:function-check-result-budget
                #:function-check-result-rejected
                #:function-check-result-failure-reason
                #:function-check-result-explanation
                #:function-check-result-shrunk-outcome
                #:check-function))

(defpackage #:cl-spec/tests/function-spec-test/stash
  (:use #:cl)
  (:export #:result #:record)
  (:documentation "A package that happens to export a variable named RESULT.

Exists so a contract can refer to another package's RESULT and have it stay
that package's: the return-value binding is whatever RESULT denotes in the
package the form is read in, and a symbol of the same name from anywhere else
is data the author meant literally."))

(defvar cl-spec/tests/function-spec-test/stash:result nil
  "A global in another package that happens to be named RESULT.

A postcondition reading it means this variable.  Binding it as the return value
instead turned a claim that is false for every input into a tautology.")

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
    ;; silently ignoring the claim, and report :PASSED for it.
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
  (testing "and a compiled predicate with no forms is refused too"
    ;; The other direction, which matters just as much: the predicate runs, so
    ;; inputs are refused and results are judged by a claim FUNCTION-SPEC-DATA
    ;; then reports as absent.  An agent is told the contract has no :PRE while
    ;; half its generated inputs never reach the function.
    (ok (handler-case
            (progn (make-instance 'function-spec
                                  :name 'transfer
                                  :precondition-function (lambda (n) (plusp n)))
                   nil)
          (invalid-function-spec-form () t)))
    (ok (handler-case
            (progn (make-instance 'function-spec
                                  :name 'transfer
                                  :postcondition-function (lambda (result n)
                                                            (> result n)))
                   nil)
          (invalid-function-spec-form () t))))
  (testing "the refusal does not blame a macro that was never involved"
    (ok (not (search "DEFSPEC-FUNCTION"
                     (handler-case
                         (progn (make-instance 'function-spec
                                               :name 'transfer
                                               :preconditions '((plusp n)))
                                "")
                       (invalid-function-spec-form (condition)
                         (princ-to-string condition)))))))
  (testing "and a contract with neither forms nor functions is fine"
    (ok (typep (make-instance 'function-spec :name 'transfer) 'function-spec))))

(deftest function-spec-invariants-survive-every-construction-path
  ;; MAKE-INSTANCE is not the only standard way to fill these slots.  With the
  ;; checks in INITIALIZE-INSTANCE only, these two paths put back exactly the
  ;; states the checks exist to refuse: an un-normalized argument spec, which
  ;; reaches the generator as a bare symbol, and :PRECONDITIONS with no
  ;; predicate to run.
  ;;
  ;; Each case gets its own contract.  A refused REINITIALIZE-INSTANCE has
  ;; already written the slots by the time the :AFTER method runs, so the
  ;; object is left holding what was refused -- standard CLOS, and the reason
  ;; the caller must discard it rather than reuse it.
  (testing "REINITIALIZE-INSTANCE is checked like MAKE-INSTANCE"
    (let ((contract (make-instance 'function-spec
                                   :name 'half
                                   :argument-specs '((n integer)))))
      (ok (handler-case
              (progn (reinitialize-instance contract :preconditions '((plusp n)))
                     nil)
            (invalid-function-spec-form () t)))))
  (testing "and normalizes like it"
    (let ((contract (make-instance 'function-spec :name 'half)))
      (reinitialize-instance contract :argument-specs '((n integer)))
      (ok (typep (second (first (function-spec-argument-specs contract))) 'spec))))
  (testing "CHANGE-CLASS is too"
    (let ((contract (make-instance 'function-spec
                                   :name 'half
                                   :argument-specs '((n integer)))))
      (change-class contract 'function-spec)
      (ok (typep (second (first (function-spec-argument-specs contract))) 'spec)))))

(deftest function-spec-refused-edit-leaves-the-contract-as-it-was
  (testing "a refused REINITIALIZE-INSTANCE does not write what it refused"
    ;; The :AFTER method validated after the standard method had already
    ;; written the slots, so catching the refusal left the object holding
    ;; exactly the state the check exists to refuse.  Discarding it is not
    ;; open to the caller: REGISTER-FUNCTION-SPEC stores the object by
    ;; identity, so the registry, FIND-FUNCTION-SPEC, FUNCTION-SPEC-DATA and
    ;; CHECK-FUNCTION are all aliased to the poisoned instance.
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-halve
        (:args (value small-integer))
        (:returns small-integer))
      (let ((contract (find-function-spec 'demo-halve)))
        (ok (handler-case
                (progn (reinitialize-instance contract :preconditions '((evenp value)))
                       nil)
              (invalid-function-spec-form () t)))
        (testing "the registry still holds the contract that was there before"
          (ok (null (function-spec-preconditions contract)))
          (ok (null (getf (function-spec-data 'demo-halve) :preconditions))))
        (testing "and a refused spec form does not destroy the one that worked"
          (ok (handler-case
                  (progn (reinitialize-instance contract :return-spec '(cons-of integer))
                         nil)
                (error () t)))
          (ok (typep (function-spec-return-spec contract) 'spec))
          (ok (getf (function-spec-data 'demo-halve) :returns)))))))

(deftest function-spec-refuses-a-parameter-named-twice
  (testing "the class refuses what the DSL already refuses"
    ;; A counterexample is a {name value} plist (§14).  With A bound twice it
    ;; comes out as (A -3 A -4), which is not one: GETF returns the first value
    ;; and the second is unrecoverable, so the reported counterexample cannot
    ;; reproduce the failure it was reported for.
    (ok (handler-case
            (progn (make-instance 'function-spec
                                  :name 'pair
                                  :argument-specs '((a integer) (a integer)))
                   nil)
          (invalid-function-spec-form () t)))))

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
                                  (:args (a integer) &key (b integer))))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (a integer) &rest more)))
                 'invalid-function-spec-form)))
  (testing "an unsupported clause is refused rather than ignored"
    ;; Unsupported clauses must never register unchecked claims.
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer))
                                  (:restarts continue)))
                 'invalid-function-spec-form)))
  (testing "(:returns nil) is refused, because nothing satisfies the empty type"
    ;; NIL as a type specifier is the type with no members, so a contract
    ;; written this way reports every return value as a violation -- including
    ;; the NIL its author meant.  NULL is the type they wanted, and the
    ;; refusal names it.
    (ok (signals (macroexpand-1 '(defspec-function f (:returns nil)))
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
  (testing "a lambda list keyword in the parameter position is refused too"
    ;; The bare-symbol spelling above was refused; this one was not, and the
    ;; keyword became the parameter's NAME.  The contract registered with
    ;; parameters (X &OPTIONAL) and CHECK-FUNCTION reported :PASSED over 25
    ;; trials for a signature nothing had checked.
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer) (&optional integer))))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (a integer) (&rest integer))))
                 'invalid-function-spec-form)))
  (testing "a parameter that cannot be bound is refused"
    ;; Both of these were emitted into a lambda list the expander knew was
    ;; illegal, and the author was handed an SBCL error about a form they
    ;; never wrote: (LAMBDA (RESULT RESULT) ...) for the first, and "T names a
    ;; defined constant" for the second.
    (ok (signals (macroexpand-1 '(defspec-function f
                                  (:args (result integer))
                                  (:post (> result 0))))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (t integer))))
                 'invalid-function-spec-form)))
  (testing "a dotted clause is refused rather than escaping the parser"
    ;; (:args . x) gave a bare TYPE-ERROR out of DOLIST, and (:pre . y)
    ;; expanded into (AND . Y), which is not a form at all.
    (ok (signals (macroexpand-1 '(defspec-function f (:args . a)))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (a integer)) (:pre . b)))
                 'invalid-function-spec-form)))
  (testing "a malformed :ARGS entry is refused"
    (ok (signals (macroexpand-1 '(defspec-function f (:args a)))
                 'invalid-function-spec-form))
    (ok (signals (macroexpand-1 '(defspec-function f (:args (a integer) (a string))))
                 'invalid-function-spec-form))))

(deftest defspec-function-does-not-mistake-a-keyword-for-the-return-value
  (testing ":RESULT as data and RESULT as the binding coexist in one :POST"
    ;; The return-value binding is found by looking for a symbol named RESULT
    ;; in the :POST forms.  Matching on the name alone caught the keyword
    ;; :RESULT, an ordinary plist key: the expander emitted
    ;; (LAMBDA (:RESULT PLIST) ...), which SBCL refuses, and a form using both
    ;; spellings was rejected with a message claiming the contract named the
    ;; return value twice.  DEFPROPERTY accepts the same expression.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-plist-contract
        (:args (entries list))
        (:post (eql result (getf entries :result))))
      (let ((predicate (function-spec-postcondition-function
                        (find-function-spec 'demo-plist-contract))))
        (ok (functionp predicate))
        (ok (funcall predicate 5 '(:result 5)))
        (ok (not (funcall predicate 5 '(:result 6))))))))

(deftest defspec-function-binds-only-the-result-of-the-reading-package
  (testing "another package's RESULT is refused, not guessed at"
    ;; Binding it made a postcondition false for every input compile into a
    ;; tautology; not binding it left the author's RESULT reading a global they
    ;; may or may not have meant.  Both readings are defensible from the text,
    ;; which is the reason to refuse rather than pick one: neither mistake is
    ;; visible in the result, and introspection shows the written form either
    ;; way.
    (ok (signals (macroexpand-1
                  '(defspec-function demo-record-broken
                    (:args (value small-integer))
                    (:post (eql cl-spec/tests/function-spec-test/stash:result value))))
                 'invalid-function-spec-form)))
  (testing "a quoted type name of the same name is data, not a second binding"
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-halve
        (:args (value small-integer))
        (:post (typep result 'cl-spec/tests/function-spec-test/stash:result)))
      (ok (find-function-spec 'demo-halve))))
  (testing "a parameter the contract itself named RESULT is usable in :PRE"
    ;; :PRE was checked for the name without consulting the parameter list, so
    ;; a precondition about a parameter called RESULT was refused with a
    ;; sentence about the return value that the form does not do.
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-format-result
        (:args (result small-integer))
        (:pre (>= result 0))
        (:returns small-integer))
      (let ((predicate (function-spec-precondition-function
                        (find-function-spec 'demo-format-result))))
        (ok (funcall predicate 1))
        (ok (not (funcall predicate -1)))))))

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

(defun demo-halve (value)
  "Return half of VALUE."
  (/ value 2))

(defun demo-record-broken (value)
  "Return VALUE without recording it anywhere.

Its contract claims the stash holds VALUE afterwards, which is false for every
input -- unless the stash's RESULT is captured as the return-value binding, in
which case the postcondition compiles into a tautology."
  value)

(defun demo-format-result (result)
  "Render RESULT, whose parameter name is deliberately the awkward one."
  (format nil "~D" result))

(defun demo-upcase-unless-a (text)
  "Return TEXT upcased, or NIL when it contains an #\\a.

Written for the shrinker: CHECK-IT hands a string generator's shrink candidates
to the test as the cached character LIST, which STRING-UPCASE signals on, and
the backend counts a signalled condition as \"still fails\".  So shrinking walks
out of the failing region and lands on a value the contract satisfies."
  (if (find #\a text) nil (string-upcase text)))

(defun demo-odd-signals (value)
  "Signal on an odd VALUE, and return a string on an even one.

Both halves break the same contract, in the two different ways CHECK-FUNCTION
distinguishes, so the first failing trial and the shrunk counterexample can
land on opposite sides of it."
  (if (oddp value)
      (error "DEMO-ODD-SIGNALS was called with ~S" value)
      (format nil "~D" value)))

(defun demo-even-signals (value)
  "Signal on an even VALUE, and return a string on an odd one.

The mirror of DEMO-ODD-SIGNALS: whichever of the two the generator reaches
first, shrinking towards zero crosses into the other."
  (if (evenp value)
      (error "DEMO-EVEN-SIGNALS was called with ~S" value)
      (format nil "~D" value)))

(defun demo-identity (value)
  "Return VALUE. Correct for every input, so any failure reported against it
comes from the contract rather than from here."
  value)

(defun demo-coin (value)
  "Break the contract one way or the other, depending on a coin.

Reading mutable state is what makes the verdict depend on where the random
state stands when the reproduction re-run happens, rather than only on the
seed the run was given."
  (declare (ignore value))
  (if (zerop (random 2))
      (error "DEMO-COIN signalled")
      "not an integer"))

(defun result-is-self-consistent-p (result violates-p)
  "Return true when RESULT's status, reason, condition and counterexample agree.

The four are derived from different moments -- the status from the first
failing trial, the shrunk counterexample and the reason from shrinking
afterwards -- and nothing reconciled them.  A report whose parts describe
different inputs is one an agent cannot act on, so they are asserted together
rather than one at a time.

VIOLATES-P is called on the reported argument list and answers whether the
contract really is broken there."
  (let ((status (property-result-status result))
        (reason (function-check-result-failure-reason result))
        (condition (property-result-condition result))
        (shrunk (loop for (nil value) on (property-result-shrunk-counterexample result)
                      by #'cddr
                      collect value)))
    (and
     ;; A reported minimal counterexample has to be one: its own docstring
     ;; calls it "the value an agent should be shown first".
     (or (null shrunk) (funcall violates-p shrunk))
     ;; The named half and the status tell the same story.
     (case (or reason :none)
       (:condition (and (eq :error status) condition t))
       ((:return-spec :postcondition) (eq :failed status))
       ;; :PRECONDITION cannot be a real finding: the trial predicate answers
       ;; true for every input :PRE refuses, so one can never be a
       ;; counterexample.
       (:precondition nil)
       (:none t)
       (t nil)))))

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

(deftest check-function-reports-a-counterexample-that-really-fails
  (testing "a shrunk value the contract satisfies is not put forward as one"
    ;; CHECK-IT hands a string generator's shrink candidates to the test as the
    ;; cached character list, and the backend counts a signalled condition as
    ;; "still fails", so shrinking walks out of the failing region.  The result
    ;; reported (S "1") -- for which the contract holds -- as the value to show
    ;; first, and named NIL as the broken half, which the slot documents as
    ;; "the function is not deterministic".  It is.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-upcase-unless-a
        (:args (text string))
        (:returns string))
      (let ((result (check-function 'demo-upcase-unless-a :trials 300 :seed 12345)))
        (ok (eq :failed (property-result-status result)))
        (ok (result-is-self-consistent-p
             result
             (lambda (arguments)
               (not (stringp (handler-case (apply #'demo-upcase-unless-a arguments)
                               (error () nil)))))))
        (testing "and the half that broke is named, because it is knowable"
          (ok (eq :return-spec (function-check-result-failure-reason result)))))))
  (testing "a run that signals and a run that returns badly stay consistent"
    ;; Both functions break the same contract in the two ways CHECK-FUNCTION
    ;; distinguishes, and shrinking towards zero crosses from one to the other.
    ;; Before, one reported :ERROR with a condition from an input the reported
    ;; counterexample does not signal on, and the other reported :FAILED with
    ;; :CONDITION as the broken half and no condition to look at.
    (flet ((bounded-violation-p (target)
             (lambda (arguments)
               (handler-case
                   (not (typep (apply target arguments) '(integer -100 100)))
                 (error () t)))))
      (let ((*registry* (make-hash-table-registry)))
        (defspec bounded-integer (range integer -100 100))
        (defspec-function demo-odd-signals
          (:args (value bounded-integer))
          (:returns bounded-integer))
        (let ((result (check-function 'demo-odd-signals :trials 20 :seed 1)))
          (ok (member (property-result-status result) '(:failed :error)))
          (ok (result-is-self-consistent-p
               result (bounded-violation-p #'demo-odd-signals)))))
      (let ((*registry* (make-hash-table-registry)))
        (defspec bounded-integer (range integer -100 100))
        (defspec-function demo-even-signals
          (:args (value bounded-integer))
          (:returns bounded-integer))
        (let ((result (check-function 'demo-even-signals :trials 20 :seed 1)))
          (ok (member (property-result-status result) '(:failed :error)))
          (ok (result-is-self-consistent-p
               result (bounded-violation-p #'demo-even-signals))))))))

(deftest check-function-does-not-blame-the-function-for-a-broken-contract
  (testing "a contract that cannot be evaluated signals, rather than reporting a failure"
    ;; The re-verification wrapped the target call, the :PRE and :POST
    ;; predicates and the :RETURNS check in one handler, and turned any
    ;; condition into "the function signalled".  A contract naming a predicate
    ;; that does not exist came back as :ERROR / :CONDITION with a shrunk
    ;; counterexample of (VALUE 0) -- for a function correct on 0, in a run
    ;; where every input produced the identical error, so the minimal
    ;; counterexample was noise.  SRC/EXPLAIN.LISP already re-signals authoring
    ;; bugs on purpose, so the reader is pointed at the broken spec rather than
    ;; told the value is bad; this now agrees with it.
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-identity
        (:args (value small-integer))
        (:returns (satisfies demo-no-such-predicate-p)))
      (ok (handler-case (progn (check-function 'demo-identity :trials 20) nil)
            (undefined-function () t)))))
  (testing "but a postcondition that signals on a value keeps the finding"
    ;; The other half of the same rule.  A condition from :POST is not
    ;; structural -- it is about the value the function returned -- so the
    ;; fault may be either side's, and destroying the result to point at the
    ;; contract loses a real counterexample.  Reported as :CONTRACT-ERROR,
    ;; which says exactly that much and no more.
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-identity
        (:args (value small-integer))
        (:returns small-integer)
        ;; Divides by a literal zero, so it signals on every generated input:
        ;; dividing by RESULT needed the generator to draw exactly 0, which it
        ;; does about one run in five.
        (:post (< (/ result 0) 1000)))
      (let ((result (check-function 'demo-identity :trials 5)))
        (ok (eq :contract-error (function-check-result-failure-reason result)))
        (ok (eq :error (property-result-status result)))
        (ok (property-result-condition result))))))

(deftest check-function-gives-the-same-verdict-for-the-same-seed
  (testing "the verdict is decided under the seed, not after it"
    ;; The re-run that decides the status happens after RUN-PROPERTY has
    ;; returned, outside the *RANDOM-STATE* binding the seed installs.  For a
    ;; target that reads mutable state, ten identical calls at one seed gave
    ;; :ERROR seven times and :FAILED three -- the same counterexample and the
    ;; same shrunk value each time, and a different verdict.
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-coin
        (:args (value small-integer))
        (:returns small-integer))
      (let ((verdicts (loop repeat 8
                            collect (let ((result (check-function 'demo-coin
                                                                  :trials 20
                                                                  :seed 42)))
                                      (list (property-result-status result)
                                            (function-check-result-failure-reason
                                             result))))))
        (ok (= 1 (length (remove-duplicates verdicts :test #'equal))))))))

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
            (undefined-function () t)))
      (testing "and it is trappable as a cl-spec condition like everything else"
        ;; §21 promises a caller can trap the framework as a whole, and
        ;; CL-SPEC-ERROR's docstring calls itself the root of every condition
        ;; cl-spec signals.  A plain UNDEFINED-FUNCTION escaped that handler,
        ;; so one unadopted function lost a whole batch of checks -- and a
        ;; property run never signals for a broken target, so the habit the
        ;; older family teaches is exactly the one that breaks here.
        (ok (handler-case (progn (check-function 'demo-function-that-does-not-exist) nil)
              (cl-spec-error () t)))))))

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
                   (property-result-shrunk-counterexample second-run))))))
  (testing "and the result itself is accepted where the seed goes"
    ;; FUNCTION-CHECK-RESULT is advertised as a PROPERTY-RESULT so one reader
    ;; set covers both, and REPLAY-PROPERTY takes a result in place of a seed.
    ;; Digging the integer out of the result was the only spelling that worked
    ;; here.
    (with-clamp-contract (demo-clamp-swapped)
      (let* ((first-run (check-function 'demo-clamp-swapped :trials 200))
             (second-run (check-function 'demo-clamp-swapped :trials 200
                                                             :seed first-run)))
        (ok (equal (property-result-counterexample first-run)
                   (property-result-counterexample second-run))))))
  (testing "the result carries its budget, so replaying it replays the run"
    ;; REPLAY-PROPERTY reuses the seed and the profile, because the profile is
    ;; what fixes the trial count and TRIALS records only where the run
    ;; stopped.  Digging out the seed alone reset the budget to the backend
    ;; default, so a run of 2 trials replayed as a run of 100 -- same seed,
    ;; opposite verdict, and nothing on either result saying why.
    (with-clamp-contract (demo-clamp-swapped)
      (let* ((first-run (check-function 'demo-clamp-swapped :trials 7))
             (replay (check-function 'demo-clamp-swapped :seed first-run)))
        (ok (= 7 (function-check-result-budget first-run)))
        (ok (= (function-check-result-budget first-run)
               (function-check-result-budget replay)))
        (ok (eq (property-result-status first-run)
                (property-result-status replay)))
        (ok (equal (property-result-counterexample first-run)
                   (property-result-counterexample replay))))))
  (testing "a seed that cannot be honoured is refused, not passed on"
    ;; An unusable seed reached SEED->RANDOM-STATE and leaked a condition
    ;; naming an internal symbol; TRIALS was already guarded here and SEED was
    ;; not.
    (with-clamp-contract (demo-clamp)
      (ok (handler-case (progn (check-function 'demo-clamp :trials 5 :seed -1) nil)
            (type-error () t)))
      (ok (handler-case (progn (check-function 'demo-clamp :trials 5 :seed "1") nil)
            (type-error () t))))))

(defun demo-wide-clamp (value)
  "Return VALUE, or a string once it is far from zero.

The failing region starts well outside the size CHECK-IT generates at by
default, so whether a run finds it depends on the generation size in effect --
which is what makes it a probe for size leaking between nested runs."
  (if (> (abs value) 200) "not an integer" value))

(deftest check-function-generates-the-same-inputs-inside-another-run
  (testing "a check nested in a property run generates what it would alone"
    ;; The backend seeds CHECK-IT:*SIZE* from its own ambient value, raising
    ;; rather than setting it, so a run inside another inherited the outer
    ;; run's size.  Generation stopped being a function of the contract, the
    ;; seed and the backend: the same call reported :FAILED nested and :PASSED
    ;; standalone, and replaying the nested result reported :PASSED -- the
    ;; documented replay contradicting the result it was handed (§72.3).
    (let ((*registry* (make-hash-table-registry))
          (nested nil))
      (defspec small-integer (range integer -100 100))
      (defspec-function demo-wide-clamp
        (:args (value integer))
        (:returns integer))
      (defproperty demo-wide-property ((k (range integer 5000 6000)))
        (:trials (:normal 1))
        (setf nested (check-function 'demo-wide-clamp :seed 7 :trials 50))
        (integerp k))
      (run-property 'demo-wide-property :seed 1)
      (let ((alone (check-function 'demo-wide-clamp :seed 7 :trials 50)))
        (ok (eq (property-result-status nested) (property-result-status alone)))
        (ok (equal (property-result-counterexample nested)
                   (property-result-counterexample alone)))))))

(defun demo-explodes-near-zero (value)
  "Signal just below zero, return a string further down, and behave otherwise.

Two different failures of one contract, adjacent, so shrinking from the second
towards zero walks into the first."
  (cond ((<= -5 value -1) (error "DEMO-EXPLODES-NEAR-ZERO at ~S" value))
        ((<= value -6) "not an integer")
        (t value)))

(deftest check-function-does-not-swap-one-failure-for-another-while-shrinking
  (testing "the shrunk counterexample fails the way the run's own failure did"
    ;; The backend counts a signalled condition as \"still fails\" while
    ;; shrinking, so the shrinker walks from a :RETURNS violation into an
    ;; unrelated exception.  The run's finding was a return-spec violation at
    ;; -10; it was reported as :ERROR / :CONDITION with a condition that -10
    ;; does not produce.  §72.4 forbids exactly that substitution.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-explodes-near-zero
        (:args (value integer))
        (:returns integer))
      (let ((result (check-function 'demo-explodes-near-zero :trials 50 :seed 0)))
        (ok (member (property-result-status result) '(:failed :error)))
        (testing "so the counterexample and the reason describe one failure mode"
          (let ((values (loop for (nil value) on
                              (property-result-counterexample result) by #'cddr
                              collect value)))
            (ok (eq (eq :condition (function-check-result-failure-reason result))
                    (handler-case (progn (apply #'demo-explodes-near-zero values) nil)
                      (error () t))))))))))

(defun demo-calls-a-missing-helper (value)
  "Call a function that does not exist, but only for a large VALUE.

Structural conditions are the ones CLASSIFY-FUNCTION-FAILURE lets propagate,
on the grounds that they would signal for every input.  A target can signal
them on one branch, where they are an ordinary bug with an ordinary
counterexample."
  (if (> value 20)
      (funcall (symbol-function 'demo-no-such-helper) value)
      (* 2 value)))

(deftest check-function-keeps-the-finding-when-the-target-signals-structurally
  (testing "a target that calls a missing function on one branch is reported"
    ;; The carve-out for UNDEFINED-FUNCTION and PROGRAM-ERROR belongs to the
    ;; contract's own evaluation.  Applied to the target call as well, it made
    ;; CHECK-FUNCTION signal rather than return: the counterexample, the seed
    ;; and the status all went with it, for a bug the backend had already
    ;; found and shrunk.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-calls-a-missing-helper
        (:args (value (range integer 0 1000)))
        (:returns (range integer 0 *)))
      (let ((result (check-function 'demo-calls-a-missing-helper :trials 50 :seed 7)))
        (ok (eq :error (property-result-status result)))
        (ok (eq :condition (function-check-result-failure-reason result)))
        (ok (property-result-counterexample result))
        (ok (typep (property-result-condition result) 'undefined-function))))))

(defun demo-clause-crossing (value)
  "Break :POST everywhere but at the generator's floor, which breaks :RETURNS.

CHECK-IT shrinks towards that floor, so the candidate the backend keeps fails a
different clause of the same contract than the trial the run found."
  (if (= value 20) -1 (1+ value)))

(deftest check-function-keeps-a-shrink-that-breaks-another-clause
  (testing "a shrunk value that breaks another clause of the same contract is kept"
    ;; CLASSIFY-FUNCTION-FAILURE tests :RETURNS before :POST, so a candidate that
    ;; breaks both is classified :RETURN-SPEC while the trial broke :POST alone.
    ;; Comparing the two by keyword discarded the reduction and reported no
    ;; shrunk counterexample for a run that had one (§73.4 #3).
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-clause-crossing
        (:args (value (range integer 20 30)))
        (:returns (range integer 0 *))
        (:post (= result (* 2 value))))
      (let* ((result (check-function 'demo-clause-crossing :trials 50 :seed 1))
             (original (loop for (nil value) on
                             (property-result-counterexample result)
                             by #'cddr collect value))
             (shrunk (loop for (nil value) on
                           (property-result-shrunk-counterexample result)
                           by #'cddr collect value)))
        (ok (eq :failed (property-result-status result)))
        (testing "the trial the run found broke :POST and not :RETURNS"
          (ok (plusp (apply #'demo-clause-crossing original)))
          (ok (not (= (apply #'demo-clause-crossing original)
                      (* 2 (first original))))))
        (testing "the reduction is put forward rather than discarded"
          (ok shrunk)
          (ok (< (first shrunk) (first original)))
          (ok (eq :used (function-check-result-shrunk-outcome result))))
        (testing "and the half named is the one the reported value breaks"
          (ok (eq :return-spec (function-check-result-failure-reason result)))
          (ok (minusp (apply #'demo-clause-crossing shrunk))))))))

(defun demo-signal-varies (value)
  "Signal SIMPLE-ERROR above the generator's floor and SIMPLE-TYPE-ERROR at it.

Both are :CONDITION, so the reason keyword cannot tell the run's own failure from
the one shrinking walks into; the condition's type can."
  (if (> value 20)
      (error "above twenty")
      (error 'simple-type-error :datum value :expected-type 'null)))

(deftest check-function-compares-a-condition-by-its-type-not-its-keyword
  (testing "the reported condition is the one the reported counterexample raises"
    ;; Every candidate is :CONDITION, so (EQ SHRUNK-REASON REASON) accepted the
    ;; shrinker's unrelated exception and put it forward as the run's finding
    ;; (§73.4 #2).  Two conditions are compared on their type now.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-signal-varies
        (:args (value (range integer 20 60)))
        (:returns integer))
      (let* ((result (check-function 'demo-signal-varies :trials 50 :seed 1))
             (values (loop for (nil value) on
                           (property-result-counterexample result)
                           by #'cddr collect value))
             (raised (handler-case (progn (apply #'demo-signal-varies values) nil)
                       (error (condition) (type-of condition)))))
        (ok (eq :error (property-result-status result)))
        (ok (eq :condition (function-check-result-failure-reason result)))
        (testing "so the counterexample and the condition describe one failure"
          (ok (eq (type-of (property-result-condition result)) raised)))
        (testing "shrinking stops above the different exception at twenty"
          (ok (equal '(21) (loop for (nil value) on
                                 (property-result-shrunk-counterexample result)
                                 by #'cddr collect value)))
          (ok (eq :used (function-check-result-shrunk-outcome result))))))))

(defun demo-zero-argument-contract ()
  "Return a string.  Its contract asks for an integer and names no :ARGS."
  "not an integer")

(deftest check-function-distinguishes-a-discarded-shrink-from-no-shrink
  (testing "a contract with nothing to shrink reports :NONE rather than a discard"
    ;; SHRUNK-COUNTEREXAMPLE is NIL here and in the test above, and the two mean
    ;; opposite things: this contract has no argument to reduce, that one had a
    ;; candidate the checker refused.  §73.4 #4 is that the slot could not say
    ;; which of the two had happened.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-zero-argument-contract
        (:returns integer))
      (let ((result (check-function 'demo-zero-argument-contract :trials 5 :seed 1)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (ok (null (property-result-shrunk-counterexample result)))
        (ok (eq :none (function-check-result-shrunk-outcome result)))))))

(defun demo-doubles-a-count (count)
  "Return twice COUNT.

Its parameter is named by a COMMON-LISP symbol, which is where the
return-value binding used to be lost: COMMON-LISP has no RESULT, so the lookup
found nothing and the author's RESULT was left free."
  (* 2 count))

(deftest defspec-function-refuses-a-result-it-cannot-place
  (testing "a parameter named by a CL symbol is refused, not silently unbound"
    ;; COUNT, LIST, TYPE, STRING, FIRST, MAP -- ordinary parameter names, all
    ;; homed in COMMON-LISP.  The postcondition never ran, could not tell a
    ;; correct function from a broken one, and FUNCTION-SPEC-DATA went on
    ;; reporting the claim.  Refusing says which symbol it could not place.
    (ok (signals (macroexpand-1 '(defspec-function demo-doubles-a-count
                                  (:args (count integer))
                                  (:post (= result (* 2 count)))))
                 'invalid-function-spec-form)))
  (testing "and the same contract is accepted once the parameter is local"
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-doubles-a-count
        (:args (n integer))
        (:post (= result (* 2 n))))
      (let ((predicate (function-spec-postcondition-function
                        (find-function-spec 'demo-doubles-a-count))))
        (ok (funcall predicate 4 2))
        (ok (not (funcall predicate 5 2)))))))

(defun demo-adds (a b)
  "Return the sum of A and B."
  (+ a b))

(deftest check-function-treats-a-validating-precondition-as-a-refusal
  (testing "a :PRE written with VALIDATE refuses an input instead of erroring"
    ;; VALIDATE's job is to judge that a value misses a spec, so the
    ;; SPEC-VIOLATION it signals is a refusal.  Reaching the trial loop's error
    ;; handler made it :CONTRACT-ERROR and turned a run that passes on every
    ;; input it accepts into a report about the function (§73.4 #1).
    (let ((*registry* (make-hash-table-registry)))
      (defspec small-integer (range integer 0 100))
      (defspec admissible-low (range integer 0 50))
      (defspec-function demo-adds
        (:args (a small-integer) (b small-integer))
        (:pre (validate 'admissible-low a))
        (:returns (range integer 0 *)))
      (let ((result (check-function 'demo-adds :trials 50 :seed 5)))
        (ok (eq :passed (property-result-status result)))
        (testing "and the refused inputs are counted rather than reported"
          ;; About half the generated A values are above 50, so a run reporting
          ;; no refusals would have quietly checked a different domain.
          (ok (plusp (function-check-result-rejected result))))))))

(defun demo-breaks-one-return-spec-two-ways (value)
  "Miss the return spec's RANGE for a nonzero VALUE and its TYPE at zero.

Both failures are :RETURN-SPEC, and CHECK-IT shrinks towards zero, so the
candidate crosses from one conjunct of :RETURNS to the other."
  (if (zerop value) "not an integer" -1))

(defun demo-always-below-range (value)
  "Return -1 for every VALUE, so the same conjunct fails on every input."
  (declare (ignore value))
  -1)

(deftest check-function-does-not-swap-one-return-spec-failure-for-another
  (testing "a shrink that crosses to another conjunct of :RETURNS is not a reduction"
    ;; EXPLAIN-DATA's top level has no :KIND and its :PATH is always NIL: the
    ;; kinds and paths live inside :ERRORS.  Reading those two keys gave every
    ;; return-spec failure the same signature, so a candidate that moved from one
    ;; conjunct to another compared equal and was put forward as the reduction.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-breaks-one-return-spec-two-ways
        (:args (value (range integer 0 10)))
        (:returns (and integer (range 0 10))))
      (let* ((result (check-function 'demo-breaks-one-return-spec-two-ways
                                     :trials 100 :seed 42))
             (original (loop for (nil value) on
                             (property-result-counterexample result)
                             by #'cddr collect value))
             (explanation (function-check-result-explanation result))
             (top (first (getf explanation :errors)))
             (nested (first (getf top :errors))))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (testing "the trial the run found missed the range conjunct"
          (ok (plusp (first original)))
          (ok (eq :out-of-range (getf nested :kind))))
        (testing "the type violation at zero is refused while one remains a range violation"
          (ok (equal '(1) (loop for (nil value) on
                                (property-result-shrunk-counterexample result)
                                by #'cddr collect value)))
          (ok (eq :used (function-check-result-shrunk-outcome result)))))))
  (testing "and two failures of the same conjunct are still a reduction"
    ;; The signature has to tell the conjuncts apart and no more: a target that
    ;; misses one conjunct on every input still has its counterexample reduced.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-always-below-range
        (:args (value (range integer 0 10)))
        (:returns (and integer (range 0 10))))
      (let ((result (check-function 'demo-always-below-range :trials 100 :seed 42)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :used (function-check-result-shrunk-outcome result)))
        (ok (property-result-shrunk-counterexample result))))))

(defun demo-fails-both-branches-of-or (value)
  "Return an integer below the first branch's range, so both branches fail.

Every VALUE from the generator gives the same kind of failure, so a reduction is
legitimate however far the shrinker moves."
  (- -1 value))

(deftest check-function-keeps-a-reduction-that-fails-an-or-the-same-way
  (testing "an OR's branch errors are compared without the values in them"
    ;; An OR reports each branch's own errors under :BRANCHES, and a shape that
    ;; walked only :ERRORS left every branch's :ACTUAL in the signature.  Two
    ;; inputs that fail the same branches then looked like two different
    ;; findings and the reduction was thrown away (PR review).
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-fails-both-branches-of-or
        (:args (value (range integer 0 10)))
        (:returns (or (range integer 0 10) string)))
      (let* ((result (check-function 'demo-fails-both-branches-of-or
                                     :trials 100 :seed 42))
             (original (loop for (nil value) on
                             (property-result-counterexample result)
                             by #'cddr collect value))
             (shrunk (loop for (nil value) on
                           (property-result-shrunk-counterexample result)
                           by #'cddr collect value)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (testing "the candidate misses the same branches, so it is kept"
          (ok (plusp (first original)))
          (ok shrunk)
          (ok (< (first shrunk) (first original)))
          (ok (eq :used (function-check-result-shrunk-outcome result))))))))

(defun demo-returns-its-argument (value)
  "Return VALUE."
  value)

(defun demo-noisy-predicate (value)
  "Report VALUE in the message, so the report text follows the value."
  (error "bad value ~S" value))

(defun demo-list-longer-than-its-tuple (n)
  "Return a list longer than the one-element tuple the contract asks for.

Every input misses the same arity; only how far it misses it by changes, and that
is the value's length rather than the spec's."
  (make-list (1+ n) :initial-element 1))

(defun demo-string-at-the-end (n)
  "Return N integers followed by a string, so the failing index follows N."
  (append (make-list n :initial-element 1) (list "x")))

(deftest check-function-keeps-a-reduction-that-misses-the-same-clause
  (testing "a tuple's ACTUAL length does not make two identical failures differ"
    ;; The wrong-length datum carries the value's length, so a shape that kept it
    ;; rejected every candidate for the same arity violation (PR review).
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-list-longer-than-its-tuple
        (:args (n (range integer 1 4)))
        (:returns (tuple integer)))
      (dolist (seed '(1 3 7 42))
        (let ((result (check-function 'demo-list-longer-than-its-tuple
                                      :trials 50 :seed seed)))
          (testing (format nil "seed ~D keeps its reduction" seed)
            (ok (eq :failed (property-result-status result)))
            (ok (eq :return-spec (function-check-result-failure-reason result)))
            (ok (property-result-shrunk-counterexample result))
            (ok (eq :used (function-check-result-shrunk-outcome result))))))))
  (testing "nor does the PATH of the failing element"
    ;; A LIST-OF reports the position inside the value, and that follows the input.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-string-at-the-end
        (:args (n (range integer 0 5)))
        (:returns (list-of integer)))
      (dolist (seed '(1 3 7))
        (let ((result (check-function 'demo-string-at-the-end :trials 50 :seed seed)))
          (testing (format nil "seed ~D keeps its reduction" seed)
            (ok (eq :failed (property-result-status result)))
            (ok (property-result-shrunk-counterexample result))
            (ok (eq :used (function-check-result-shrunk-outcome result))))))))
  (testing "nor does a condition report that embeds the value"
    ;; :CONDITION-REPORT is the predicate's own text, and a predicate that quotes
    ;; the value made every candidate look like a different failure.
    (let ((*registry* (make-hash-table-registry)))
      (defspec-function demo-returns-its-argument
        (:args (value (range integer 0 20)))
        (:returns (satisfies demo-noisy-predicate)))
      (dolist (seed '(1 7 42))
        (let ((result (check-function 'demo-returns-its-argument :trials 50 :seed seed)))
          (testing (format nil "seed ~D keeps its reduction" seed)
            (ok (eq :failed (property-result-status result)))
            (ok (property-result-shrunk-counterexample result))
            (ok (eq :used (function-check-result-shrunk-outcome result)))))))))

(defun install-always-one (registry)
  "Register a custom generator drawing 1, and a spec that names it, in REGISTRY.

The objects are built directly rather than through the DSL: the DSL's own
registration is tests/dsl-test.lisp's subject, and a test here that evaluated
macro expansions would need the lint exemption that file carries."
  (registry-register-generator
   registry 'always-one
   (make-instance 'custom-generator :name 'always-one
                                    :function (lambda () 1)))
  (registry-register-spec registry 'always-one-spec
                          (normalize-spec-form 'integer :name 'always-one-spec
                                                       :generator 'always-one)))

(deftest a-custom-generator-survives-shrinking
  (testing "a failing contract over a custom generator returns a result"
    ;; The draw was built from a MAPPED-GENERATOR over a constant, and check-it's
    ;; shrink method reads its sub-generators' cached values -- a constant is not a
    ;; generator, so every FAILING run signalled NO-APPLICABLE-METHOD-ERROR instead
    ;; of reporting the failure.  A sample and a passing run never shrink, which is
    ;; why the first test for this feature missed it (PR review).
    (let ((*registry* (make-hash-table-registry)))
      (install-always-one *registry*)
      (register-function-spec
       (make-instance 'function-spec
                      :name 'demo-returns-its-argument
                      :argument-specs '((value always-one-spec))
                      :return-spec '(range integer 0 0)))
      (let ((result (check-function 'demo-returns-its-argument :trials 5 :seed 3)))
        (ok (eq :failed (property-result-status result)))
        (ok (eq :return-spec (function-check-result-failure-reason result)))
        (testing "the value the generator drew is the counterexample"
          (ok (equal '(1) (loop for (nil value) on
                                (property-result-counterexample result)
                                by #'cddr collect value)))))))
  (testing "and a failing property over one returns a result too"
    ;; RUN-PROPERTIES is a bare MAPCAR, so one such property aborted a whole batch.
    (let ((*registry* (make-hash-table-registry)))
      (install-always-one *registry*)
      (register-property
       (make-instance 'property
                      :name 'four-is-the-answer
                      :arguments (list (list 'x (normalize-spec-form 'always-one-spec)))
                      :trials '(:normal 5)
                      :function (lambda (x) (= x 4))))
      (let ((result (run-property 'four-is-the-answer :seed 3)))
        (ok (eq :failed (property-result-status result)))
        (ok (property-result-counterexample result))
        (ok (null (property-result-shrunk-counterexample result)))))))

(defun explained-error-keys (datum keys)
  "Return KEYS with every key of the error data under DATUM added."
  (when (listp datum)
    (loop for (key value) on datum by #'cddr
          do (pushnew key keys)
             (when (and (member key '(:errors :branches :conjuncts)) (listp value))
               (dolist (nested value)
                 (setf keys (explained-error-keys nested keys))))))
  keys)

(defun demo-post-switch (value)
  "Violate the lower bound except at zero, where the upper bound fails."
  (if (zerop value) 20 -1))

(defun demo-tuple-switch (value)
  "Move the type failure between fixed tuple elements."
  (if (zerop value) '(1 "bad") '("bad" 1)))

(deftest check-function-preserves-post-form
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function demo-post-switch
      (:args (value (range integer 0 10)))
      (:post (>= result 0) (<= result 10)))
    (let ((r (check-function 'demo-post-switch :trials 100 :seed 42)))
      (ok (equal '(6) (loop for (nil v) on (property-result-counterexample r)
                            by #'cddr collect v)))
      (ok (eq :used (function-check-result-shrunk-outcome r)))
      (ok (equal '(1) (loop for (nil value) on
                            (property-result-shrunk-counterexample r)
                            by #'cddr collect value)))
      (ok (null (function-check-result-explanation r))))))

(deftest check-function-preserves-tuple-element
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function demo-tuple-switch
      (:args (value (range integer 0 10)))
      (:returns (tuple integer integer)))
    (let ((r (check-function 'demo-tuple-switch :trials 100 :seed 42)))
      (ok (eq :used (function-check-result-shrunk-outcome r)))
      (ok (equal '(1) (loop for (nil value) on
                            (property-result-shrunk-counterexample r)
                            by #'cddr collect value)))
      (ok (equal '(0) (getf (first (getf (function-check-result-explanation r)
                                       :errors)) :path))))))

(deftest and-refuses-conjunct-generators
  (let ((*registry* (make-hash-table-registry)))
    (install-always-one *registry*)
    (defspec alias-for-one always-one-spec)
    (dolist (form '( (and always-one-spec integer)
                    (and integer (and alias-for-one integer))))
      (ok (handler-case
              (progn (cl-spec/src/generator:generator-for
                       (normalize-spec-form form)) nil)
            (cl-spec/src/conditions:generator-unavailable () t))))
    (ok (equal '(1 1 1)
               (cl-spec/src/generator:sample 'always-one-spec :count 3 :seed 42)))
    (defspec whole-and (and always-one-spec integer) (:generator always-one))
    (ok (equal '(1 1 1)
               (cl-spec/src/generator:sample 'whole-and :count 3 :seed 42)))))

(deftest postcondition-evaluates-each-form-once
  (let ((*registry* (make-hash-table-registry))
        (calls nil))
    (defspec-function demo-post-switch
      (:args (value integer))
      (:post (progn (push :first calls) (>= result 0))
             (progn (push :second calls) (<= result 10))))
    (let ((predicate (function-spec-postcondition-function
                      (find-function-spec 'demo-post-switch))))
      (ok (null (funcall predicate -1 0)))
      (ok (equal '(:first) calls))
      (setf calls nil)
      (ok (null (funcall predicate 20 0)))
      (ok (equal '(:second :first) calls))
      (setf calls nil)
      (ok (funcall predicate 5 0))
      (ok (equal '(:second :first) calls)))))

(deftest postcondition-keeps-the-same-form-reduction
  (let ((*registry* (make-hash-table-registry)))
    (defspec-function demo-always-below-range
      (:args (value (range integer 0 10)))
      (:post (integerp result) (>= result 0) (error "must short-circuit")))
    (let ((r (check-function 'demo-always-below-range :trials 100 :seed 42)))
      (ok (eq :postcondition (function-check-result-failure-reason r)))
      (ok (eq :used (function-check-result-shrunk-outcome r)))
      (ok (equal '(0) (loop for (nil v) on (property-result-shrunk-counterexample r)
                            by #'cddr collect v))))))

(deftest tuple-shapes-preserve-nesting-but-ignore-collection-indices
  (flet ((signature (form value)
           (cl-spec/src/function-spec::failure-signature
            :return-spec (explain-data (normalize-spec-form form) value) nil)))
    (let ((form '(tuple (tuple integer integer) (tuple integer integer))))
      (ok (not (cl-spec/src/function-spec::same-failure-p
                (signature form '(("bad" 1) (1 1)))
                (signature form '((1 "bad") (1 1))))))
      (ok (not (cl-spec/src/function-spec::same-failure-p
                (signature form '(("bad" 1) (1 1)))
                (signature form '((1 1) ("bad" 1)))))))
    (let ((form '(list-of (tuple integer integer))))
      (ok (cl-spec/src/function-spec::same-failure-p
           (signature form '((1 1) ("bad" 1)))
           (signature form '(("bad" 1)))))
      (ok (not (cl-spec/src/function-spec::same-failure-p
                (signature form '(("bad" 1)))
                (signature form '((1 "bad")))))))))

(deftest every-explained-error-key-is-classified
  (testing "a new EXPLAIN-DATA key cannot slip past the failure shape unclassified"
    ;; FAILURE-SHAPE keeps a whitelist, so a key nobody has classified is dropped --
    ;; and if it came from the spec, two different failures would compare equal.
    ;; This enumerates the keys the explainer produces and fails when one is neither
    ;; kept by the shape nor known to be value-derived, so the decision is made here
    ;; rather than in review.
    (let ((seen '())
          (kept (append cl-spec/src/function-spec::*failure-shape-keys*
                        cl-spec/src/function-spec::*failure-shape-containers*))
          (value-derived '(:actual :actual-length :path :condition-report :key)))
      (dolist (form '((type integer) (range 0 10) (member 1 2) (satisfies oddp)
                      (satisfies demo-noisy-predicate) (list-of integer)
                      (vector-of integer) (tuple integer string) (not integer)
                      (nullable integer) (or integer string)
                      (and integer (range 0 10)) (instance-of standard-object)
                      (plist (:required (:a integer)) (:optional (:b string)) (:closed t))
                      (plist (:required (:a (plist (:required (:b integer))))))))
        (let ((spec (normalize-spec-form form)))
          (dolist (value (list 1 -1 3.5 "s" nil #\a '(1 "a") '(1) #(1) '(:a 1)
                              '(:a "bad") '(:a 1 :a 2) '(:a 1 :extra nil)
                              '(:a (:b "bad"))))
            (dolist (datum (getf (explain-data spec value) :errors))
              (setf seen (explained-error-keys datum seen))))))
      (let ((spec (function-spec-argument-schema
                   (make-instance 'function-spec :name 'demo-adds
                                  :argument-specs '((a integer) &optional (b string b-p))))))
        (dolist (value '(nil (1 "valid" :extra) (1 2)))
          (dolist (datum (getf (explain-data spec value) :errors))
            (setf seen (explained-error-keys datum seen)))))
      (let ((spec (function-spec-argument-schema
                   (make-instance 'function-spec :name 'demo-adds
                                  :argument-specs '(&key ((:size amount) integer))))))
        (dolist (value '((:unknown 1) (:size) (3 4) (:size "bad")))
          (dolist (datum (getf (explain-data spec value) :errors))
            (setf seen (explained-error-keys datum seen)))))
      (let ((spec (function-spec-argument-schema
                   (make-instance 'function-spec :name 'demo-adds
                                  :argument-specs
                                  '((head integer) &rest (tail (list-of string)))))))
        (dolist (value '(nil (1 2) (1 "valid" 3)))
          (dolist (datum (getf (explain-data spec value) :errors))
            (setf seen (explained-error-keys datum seen)))))
      (let ((spec (function-spec-return-spec
                   (make-instance 'function-spec :name 'demo-adds
                                  :return-spec '(values integer string)))))
        (dolist (value '(nil (1) (1 "valid" :extra) ("bad" "valid")))
          (dolist (datum (getf (explain-data spec value) :errors))
            (setf seen (explained-error-keys datum seen)))))
      (testing "the audit itself saw the keys it is meant to check"
        (ok (member :kind seen))
        (ok (member :actual seen))
        (ok (member :field-path seen))
        (ok (member :minimum-length seen))
        (ok (member :maximum-length seen))
        (ok (member :key seen)))
      (testing "and every key it saw is either kept or known to be value-derived"
        (ok (null (set-difference seen (append kept value-derived))))))))

(deftest call-layout-cache-tracks-current-declarations
  (let* ((contract (make-instance 'function-spec :name 'demo-adds
                                  :argument-specs '((a integer))))
         (first (function-spec-call-layout contract))
         (spec (second (first (function-spec-argument-specs contract)))))
    (ok (eq first (function-spec-call-layout contract)))
    (reinitialize-instance contract)
    (ok (not (eq first (function-spec-call-layout contract))))
    (setf first (function-spec-call-layout contract))
    (ok (eq spec (cl-spec/src/call-schema:argument-binding-spec
                  (first (cl-spec/src/call-schema:call-layout-bindings first)))))
    (setf (caar (function-spec-argument-specs contract)) 'renamed)
    (let ((changed (function-spec-call-layout contract)))
      (ok (not (eq first changed)))
      (ok (eq 'renamed (cl-spec/src/call-schema:argument-binding-name
                        (first (cl-spec/src/call-schema:call-layout-bindings changed)))))
      (ok (eq changed (function-spec-call-layout contract)))
      ;; The public layout reader also exposes mutable list storage.
      (setf (car (cl-spec/src/call-schema:call-layout-bindings changed)) nil)
      (ok (not (eq changed (function-spec-call-layout contract)))))
    (reinitialize-instance contract :argument-specs '(&key ((:value b) string)))
    (let ((updated (function-spec-call-layout contract)))
      (ok (cl-spec/src/call-schema:call-layout-key-p updated))
      (ok (eq updated (function-spec-call-layout contract)))
      (ok (handler-case
              (progn (reinitialize-instance contract :argument-specs '((t integer))) nil)
            (invalid-function-spec-form () t)))
      (ok (eq updated (function-spec-call-layout contract)))
      (setf (caar (cdr (function-spec-argument-specs contract))) '(:other b))
      (ok (cl-spec/src/call-schema:call-layout-accepts-p
           (function-spec-call-layout contract) '(:other "value")))
      (let ((declarations (function-spec-argument-specs contract)))
        (setf (cdr (last declarations)) declarations)
        (ok (handler-case (progn (function-spec-call-layout contract) nil)
              (program-error () t)))))))
