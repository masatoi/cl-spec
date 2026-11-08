;;;; tests/conditions-test.lisp

(defpackage #:cl-spec/tests/conditions-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:not-implemented
                #:not-implemented-operator
                #:spec-violation
                #:spec-violation-spec
                #:spec-violation-value
                #:spec-violation-path
                #:spec-violation-errors
                #:unknown-spec
                #:unknown-spec-name
                #:unknown-property
                #:unknown-property-name
                #:no-generator-backend
                #:invalid-spec-form
                #:invalid-spec-form-form
                #:invalid-spec-form-reason
                #:generator-unavailable
                #:generator-unavailable-spec
                #:unsupported-seed
                #:invalid-argument
                #:invalid-argument-argument
                #:unknown-function-spec
                #:invalid-generated-arguments
                #:generation-budget-exhausted
                #:generator-unavailable-kind
                #:generator-unavailable-argument)
  (:import-from #:cl-spec/src/property-runner
                #:run-property
                #:property-result-condition)
  (:import-from #:cl-spec/src/coverage)
  (:import-from #:cl-spec/src/execution)
  (:import-from #:cl-spec/src/introspection)
  (:import-from #:cl-spec/src/evidence)
  (:import-from #:cl-spec/src/function-spec)
  (:import-from #:cl-spec/src/counterexample))

(in-package #:cl-spec/tests/conditions-test)

(deftest malformed-form-reports-handle-cycles
  (let ((form (list :bad)))
    (setf (cdr form) form)
    (dolist (type '(cl-spec/src/conditions:invalid-spec-form
                    cl-spec/src/conditions:invalid-property-form
                    cl-spec/src/conditions:invalid-function-spec-form
                    cl-spec/src/conditions:invalid-generator-form))
      ;; The length limit keeps this regression safe even before the fix.
      (let* ((*print-circle* nil)
             (*print-length* 20)
             (condition (make-condition type :form form :reason "finite list required"))
             (report (princ-to-string condition)))
        (ok (search "#1=" report))
        (ok (search "finite list required" report))))))

(deftest condition-hierarchy
  (testing "every framework condition inherits from CL-SPEC-ERROR"
    (ok (subtypep 'cl-spec-error 'error))
    (ok (subtypep 'not-implemented 'cl-spec-error))
    (ok (subtypep 'spec-violation 'cl-spec-error))
    (ok (subtypep 'unknown-spec 'cl-spec-error))
    (ok (subtypep 'unknown-property 'cl-spec-error))
    (ok (subtypep 'no-generator-backend 'cl-spec-error))))

(defun error-class-name-p (symbol package)
  "Return true when SYMBOL is PACKAGE's own symbol and names a subclass of ERROR."
  (let ((class (and (eq (symbol-package symbol) package) (find-class symbol nil))))
    (and class (subtypep class 'error))))

(defun cl-spec-error-classes ()
  "Return the names of every error class defined by a loaded cl-spec source package."
  (let ((names nil))
    (dolist (package (list-all-packages) names)
      (when (eql 0 (search "CL-SPEC/SRC/" (package-name package)))
        (do-symbols (symbol package)
          (when (error-class-name-p symbol package)
            (pushnew symbol names)))))))

(deftest every-cl-spec-error-inherits-from-the-root
  (testing "the enumeration reaches the subsystems as well as the core"
    (ok (member "INVALID-COVERAGE-OPTIONS" (cl-spec-error-classes) :test #'string=))
    (ok (member "INSTRUMENTATION-VIOLATION" (cl-spec-error-classes) :test #'string=)))
  (testing "a handler for CL-SPEC-ERROR catches every error cl-spec defines"
    (dolist (name (cl-spec-error-classes))
      (ok (subtypep name 'cl-spec-error)
          (format nil "~S inherits from CL-SPEC-ERROR" name)))))

(defun refusal-of (thunk)
  "Return the condition THUNK signals, or NIL when it returns."
  (handler-case (progn (funcall thunk) nil)
    (error (condition) condition)))

(defun bad-argument-cases ()
  "Return (ARGUMENT THUNK) pairs, each calling a public operator with a bad ARGUMENT."
  (list (list :seed (lambda ()
                      (cl-spec/src/property-runner:run-property
                       'argument-check-property :seed -1)))
        (list :seed (lambda ()
                      (cl-spec/src/property-runner:run-property
                       'argument-check-property :seed "abc")))
        (list :seed (lambda ()
                      (cl-spec/src/property-runner:replay-property
                       'argument-check-property 1.5)))
        (list :trials (lambda ()
                        (cl-spec/src/function-spec:check-function
                         'argument-check-target :trials -5 :seed 1)))
        (list :scopes (lambda ()
                        (cl-spec/src/instrument:instrument-function
                         'argument-check-target :scopes '(:bogus))))
        (list :count (lambda ()
                       (cl-spec/src/generator:sample
                        (cl-spec/src/normalize:normalize-spec-form 'integer) :count -1)))
        (list :seed (lambda ()
                      (cl-spec/src/generator:sample
                       (cl-spec/src/normalize:normalize-spec-form 'integer) :seed -1)))))

(defun refused-argument (condition)
  "Return the parameter CONDITION names when it is an INVALID-ARGUMENT, else NIL."
  (and (typep condition 'invalid-argument)
       (invalid-argument-argument condition)))

(deftest a-bad-argument-to-a-public-entry-point-is-a-cl-spec-error
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty argument-check-property ((value integer))
            (integerp value)))
    (eval '(cl-spec/src/dsl:defspec-function argument-check-target
            (:args (value integer))
            (:returns integer)))
    (loop for (argument thunk) in (bad-argument-cases)
          for condition = (refusal-of thunk)
          do (testing (format nil "the ~S refusal is both kinds of error" argument)
               (ok (typep condition 'cl-spec-error))
               (ok (typep condition 'type-error))
               (ok (eq argument (refused-argument condition)))))))

(defun more-bad-argument-cases ()
  "Return (ARGUMENT THUNK) pairs for the entry points issue #79 found unchecked."
  (let ((integer-spec (cl-spec/src/normalize:normalize-spec-form 'integer)))
    (list (list :options (lambda ()
                           (run-property 'argument-check-property :seed 1 :options 42)))
          (list :options (lambda ()
                           (run-property 'argument-check-property :seed 1
                                         :options '(:generation-budget))))
          (list :options (lambda ()
                           (run-property 'argument-check-property :seed 1
                                         :options '(:trials 5))))
          (list :generation-budget (lambda ()
                                     (run-property 'argument-check-property :seed 1
                                                   :options '(:generation-budget -3))))
          (list :shrink-budget (lambda ()
                                 (run-property 'argument-check-property :seed 1
                                               :options '(:shrink-budget -3))))
          (list :generation-budget (lambda ()
                                     (cl-spec/src/function-spec:check-function
                                      'argument-check-target :seed 1
                                      :options '(:generation-budget "x"))))
          (list :options (lambda ()
                           (cl-spec/src/property-runner:run-properties
                            '(argument-check-property) :options 42)))
          (list :options (lambda ()
                           (cl-spec/src/property-runner:replay-property
                            'argument-check-property 1 :options 42)))
          (list :property-designator (lambda () (funcall 'run-property 3 :seed 1)))
          (list :property-designators (lambda ()
                                        (cl-spec/src/property-runner:run-properties 42)))
          (list :registry (lambda () (run-property 'argument-check-property :seed 1
                                                   :registry 42)))
          (list :registry (lambda () (cl-spec/src/validator:validp integer-spec 1
                                                                   :registry 42)))
          (list :registry (lambda () (cl-spec/src/generator:sample 'argument-check-spec :seed 1
                                                                   :registry 42)))
          (list :registry (lambda () (cl-spec/src/function-spec:check-call
                                      'argument-check-target '(1) :registry 42)))
          (list :result (lambda () (cl-spec/src/property-runner:result-data 3)))
          (list :result (lambda () (cl-spec/src/evidence:evidence-summary 3)))
          (list :result (lambda () (cl-spec/src/function-spec:call-check-data 3)))
          (list :result (lambda () (cl-spec/src/counterexample:make-counterexample-artifact 3)))
          (list :artifact (lambda ()
                            (cl-spec/src/counterexample:serialize-counterexample-artifact 3)))
          (list :artifact (lambda () (cl-spec/src/counterexample:recheck-counterexample 3)))
          (list :entity-kind (lambda () (cl-spec/src/schema:definition-digest 'no-such-name)))
          (list :options (lambda ()
                           (cl-spec/src/instrument:instrument-function
                            'argument-check-target :scope '(:input)))))))

(deftest more-public-entry-points-check-their-arguments
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty argument-check-property ((value integer))
            (integerp value)))
    (eval '(cl-spec/src/dsl:defspec-function argument-check-target
            (:args (value integer))
            (:returns integer)))
    (setf (symbol-function 'argument-check-target) #'identity)
    (loop for (argument thunk) in (more-bad-argument-cases)
          for condition = (refusal-of thunk)
          do (testing (format nil "a bad ~S is refused as an INVALID-ARGUMENT" argument)
               (ok (typep condition 'cl-spec-error))
               (ok (eq argument (refused-argument condition))
                   (format nil "~S refused ~S" (type-of condition) argument))))))

(declaim (notinline bogus-keyword-arguments))

(defun bogus-keyword-arguments ()
  "Return a keyword tail no entry point accepts, built at run time.

A literal list passed to APPLY is checked by the compiler, which would refuse to
compile this file rather than let the call reach the entry point."
  (list :bogus 1))

(defun remaining-bad-argument-cases ()
  "Return (ARGUMENT OPERATOR THUNK) triples for entry points #79 left unchecked."
  (let ((policy '(:policy-version 1
                  :requirements ((:kind :min-checked-trials :count 1)))))
    (list (list :result 'cl-spec/src/function-spec:fixture-check-data
                (lambda () (cl-spec/src/function-spec:fixture-check-data 3)))
          (list :result 'cl-spec/src/coverage:coverage-data
                (lambda () (cl-spec/src/coverage:coverage-data 3)))
          (list :definition 'cl-spec/src/coverage:coverage-schema
                (lambda () (cl-spec/src/coverage:coverage-schema 3)))
          (list :artifact 'cl-spec/src/counterexample:counterexample-artifact-data
                (lambda () (cl-spec/src/counterexample:counterexample-artifact-data 3)))
          (list :symbol 'cl-spec/src/introspection:semantic-data
                (lambda () (cl-spec/src/introspection:semantic-data 3)))
          (list :original 'cl-spec/src/execution:failure-identities-match-p
                (lambda () (cl-spec/src/execution:failure-identities-match-p 1 '(:x))))
          (list :candidate 'cl-spec/src/execution:failure-identities-match-p
                (lambda () (cl-spec/src/execution:failure-identities-match-p '(:x) 2)))
          (list :property 'cl-spec/src/execution:evaluate-trial
                (lambda () (cl-spec/src/execution:evaluate-trial 42 nil)))
          (list :property 'cl-spec/src/execution:observe-trial
                (lambda () (cl-spec/src/execution:observe-trial 42 nil)))
          (list :result 'cl-spec/src/evidence:assess-evidence
                (lambda () (cl-spec/src/evidence:assess-evidence 5 policy)))
          (list :registry 'cl-spec/src/function-spec:check-fixture
                (lambda () (cl-spec/src/function-spec:check-fixture
                            'argument-check-target 1 :registry 42)))
          (list :registry 'cl-spec/src/introspection:function-spec-data
                (lambda () (cl-spec/src/introspection:function-spec-data
                            'argument-check-target :registry 42)))
          (list :bogus 'cl-spec/src/function-spec:check-function
                (lambda () (apply #'cl-spec/src/function-spec:check-function
                                  'argument-check-target (bogus-keyword-arguments))))
          (list :bogus 'cl-spec/src/function-spec:check-call
                (lambda () (apply #'cl-spec/src/function-spec:check-call
                                  'argument-check-target '(1) (bogus-keyword-arguments))))
          (list :bogus 'cl-spec/src/function-spec:check-fixture
                (lambda () (apply #'cl-spec/src/function-spec:check-fixture
                                  'argument-check-target 1 (bogus-keyword-arguments))))
          (list :bogus 'run-property
                (lambda () (apply #'run-property 'argument-check-property
                                  (bogus-keyword-arguments))))
          (list :bogus 'cl-spec/src/property-runner:replay-property
                (lambda () (apply #'cl-spec/src/property-runner:replay-property
                                  'argument-check-property 1 (bogus-keyword-arguments))))
          (list :bogus 'cl-spec/src/property-runner:run-properties
                (lambda () (apply #'cl-spec/src/property-runner:run-properties
                                  '(argument-check-property) (bogus-keyword-arguments)))))))

(deftest remaining-public-entry-points-check-their-arguments
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty argument-check-property ((value integer))
            (integerp value)))
    (eval '(cl-spec/src/dsl:defspec-function argument-check-target
            (:args (value integer))
            (:returns integer)))
    (setf (symbol-function 'argument-check-target) #'identity)
    (loop for (argument operator thunk) in (remaining-bad-argument-cases)
          for condition = (refusal-of thunk)
          do (testing (format nil "~S refuses a bad ~S as an INVALID-ARGUMENT" operator argument)
               (ok (typep condition 'cl-spec-error)
                   (format nil "~S signalled ~S" operator (type-of condition)))
               (ok (eq argument (refused-argument condition)))
               (ok (and (typep condition 'cl-spec/src/conditions:invalid-argument)
                        (eq operator (cl-spec/src/conditions:invalid-argument-operator
                                      condition))))))))

(deftest recheck-refuses-its-own-bad-arguments-before-running
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defspec-function argument-check-target
            (:args (value integer))
            (:returns (range integer 1000 *))))
    (setf (symbol-function 'argument-check-target) #'identity)
    (let ((artifact (cl-spec/src/counterexample:make-counterexample-artifact
                     (cl-spec/src/function-spec:check-function 'argument-check-target
                                                               :seed 1 :trials 20))))
      (testing "a non-registry is refused, not reported as a contract error"
        (ok (eq :registry (refused-argument
                           (refusal-of (lambda ()
                                         (cl-spec/src/counterexample:recheck-counterexample
                                          artifact :registry 42)))))))
      (testing "an unknown state policy is refused"
        (ok (eq :state-policy (refused-argument
                               (refusal-of (lambda ()
                                             (cl-spec/src/counterexample:recheck-counterexample
                                              artifact :state-policy :bogus))))))))))

(deftest a-result-replays-only-the-run-it-came-from
  ;; Issue #84: a result handed to another property donated its seed, profile and
  ;; options, and a failed run could then look fixed.
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty replay-source ((x (range integer 0 100))) (< x 50)))
    (eval '(cl-spec/src/dsl:defproperty replay-other ((x (range integer 0 100))) t))
    (eval '(cl-spec/src/dsl:defspec-function argument-check-target
            (:args (value integer))
            (:returns integer)))
    (setf (symbol-function 'argument-check-target) #'identity)
    (let ((source (run-property 'replay-source :seed 3 :profile :smoke))
          (contract (cl-spec/src/function-spec:check-function 'argument-check-target
                                                              :seed 1 :trials 5)))
      (testing "the property that produced a result can still replay it"
        (ok (eq :failed (cl-spec/src/property-runner:property-result-status
                         (cl-spec/src/property-runner:replay-property 'replay-source source)))))
      (testing "another property refuses it"
        (ok (eq :seed (refused-argument
                       (refusal-of (lambda ()
                                     (cl-spec/src/property-runner:replay-property
                                      'replay-other source)))))))
      (testing "RUN-PROPERTY refuses a function check's result"
        (ok (eq :seed (refused-argument
                       (refusal-of (lambda () (run-property 'replay-other :seed contract)))))))
      (testing "CHECK-FUNCTION refuses a property's result"
        (ok (eq :seed (refused-argument
                       (refusal-of (lambda ()
                                     (cl-spec/src/function-spec:check-function
                                      'argument-check-target :seed source)))))))
      (testing "an integer seed still starts a new run of any property"
        (ok (cl-spec/src/property-runner:property-result-status
             (run-property 'replay-other
                           :seed (cl-spec/src/property-runner:property-result-seed source))))))))

(defun report-within-seconds (condition seconds)
  "Return CONDITION's report printed with *PRINT-CIRCLE* NIL, or :TIMED-OUT."
  #+sbcl
  (handler-case (sb-ext:with-timeout seconds
                  (let ((*print-circle* nil)) (princ-to-string condition)))
    (sb-ext:timeout () :timed-out))
  #-sbcl
  (progn seconds (let ((*print-circle* nil)) (princ-to-string condition))))

(defun circular-designator ()
  "Return a circular list, a designator no registry can hold."
  (let ((list (list 1 2 3)))
    (setf (cdr (last list)) list)
    list))

(defun conditions-carrying (datum)
  "Return a condition of every report-bearing class that prints DATUM."
  (list (make-condition 'unknown-spec :name datum)
        (make-condition 'unknown-property :name datum)
        (make-condition 'unknown-function-spec :name datum)
        (make-condition 'not-implemented :operator datum)
        (make-condition 'invalid-generated-arguments
                        :generator datum :value datum :reason "bad")
        (make-condition 'generation-budget-exhausted
                        :report (list :attempts 1 :budget 1 :rejections 0
                                      :exhausted-at datum))))

(deftest every-condition-report-is-bounded
  (testing "a circular datum prints in finite time when *PRINT-CIRCLE* is NIL"
    (dolist (condition (conditions-carrying (circular-designator)))
      (ok (stringp (report-within-seconds condition 2))
          (format nil "~S prints a circular datum" (type-of condition)))))
  (testing "a very long datum prints a short report"
    (dolist (condition (conditions-carrying (make-list 100000 :initial-element 7)))
      (let ((report (report-within-seconds condition 2)))
        (ok (and (stringp report) (< (length report) 2000))
            (format nil "~S keeps a long datum short" (type-of condition)))))))

(deftest an-invalid-argument-report-is-one-line
  (let ((condition (refusal-of (lambda ()
                                 (cl-spec/src/generator:sample
                                  (cl-spec/src/normalize:normalize-spec-form 'integer)
                                  :count -1)))))
    (ok (typep condition 'invalid-argument))
    (ok (not (find #\Newline (princ-to-string condition))))))

(deftest budget-exhaustion-has-its-own-kind-and-names-the-argument
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty exhausting-property
            ((items (list-of (and (range integer 0 1000000) (satisfies zerop))
                             :min-length 1)))
            t))
    (let ((condition (property-result-condition
                      (run-property 'exhausting-property
                                    :seed 1 :options '(:generation-budget 20)))))
      (ok (typep condition 'generation-budget-exhausted))
      (ok (eq :budget-exhausted (generator-unavailable-kind condition)))
      (ok (eq 'items (generator-unavailable-argument condition))))
    (testing "SAMPLE names no argument"
      (let ((condition (refusal-of
                        (lambda ()
                          (cl-spec/src/generator:sample
                           (cl-spec/src/normalize:normalize-spec-form
                            '(and (range integer 0 1000000) (satisfies zerop)))
                           :count 1 :seed 1 :generation-budget 2)))))
        (ok (eq :budget-exhausted (generator-unavailable-kind condition)))
        (ok (null (generator-unavailable-argument condition)))))))

(deftest not-implemented-reports-operator
  (testing "NOT-IMPLEMENTED carries and prints the stubbed operator"
    (let ((condition (make-condition 'not-implemented :operator 'normalize-spec-form)))
      (ok (eq 'normalize-spec-form (not-implemented-operator condition)))
      (ok (search "NORMALIZE-SPEC-FORM" (princ-to-string condition))))))

(deftest spec-violation-carries-context
  (testing "SPEC-VIOLATION keeps spec, value, path and structured errors"
    (let ((condition (make-condition 'spec-violation
                                     :spec 'positive-money
                                     :value -100
                                     :path '(transfer amount)
                                     :errors '((:kind :predicate-failed
                                                :predicate plusp)))))
      (ok (eq 'positive-money (spec-violation-spec condition)))
      (ok (eql -100 (spec-violation-value condition)))
      (ok (equal '(transfer amount) (spec-violation-path condition)))
      (ok (equal '((:kind :predicate-failed :predicate plusp))
                 (spec-violation-errors condition))))))

(deftest spec-violation-defaults
  (testing "PATH and ERRORS default to NIL"
    (let ((condition (make-condition 'spec-violation :spec 'money :value 1)))
      (ok (null (spec-violation-path condition)))
      (ok (null (spec-violation-errors condition))))))

(deftest lookup-conditions-name-the-missing-entry
  (testing "UNKNOWN-SPEC and UNKNOWN-PROPERTY report the name that was not found"
    (let ((spec-condition (make-condition 'unknown-spec :name 'missing-spec))
          (property-condition (make-condition 'unknown-property :name 'missing-property)))
      (ok (eq 'missing-spec (unknown-spec-name spec-condition)))
      (ok (eq 'missing-property (unknown-property-name property-condition)))
      (ok (search "MISSING-SPEC" (princ-to-string spec-condition)))
      (ok (search "MISSING-PROPERTY" (princ-to-string property-condition))))))

(define-condition hint-condition (error)
  ()
  (:documentation "A condition class outside COMMON-LISP, which a bare name cannot denote."))

(deftest unknown-spec-suggests-the-type-form-for-a-class-name
  (flet ((report (name)
           (princ-to-string (make-condition 'unknown-spec :name name))))
    (testing "a bare name that names a class is offered as (TYPE NAME)"
      (let ((report (report 'hint-condition)))
        (ok (search "HINT-CONDITION" report))
        (ok (search (format nil "(~S ~S)" 'type 'hint-condition) report))))
    (testing "the suggestion follows the printer settings"
      (let ((*print-case* :downcase))
        (ok (search (format nil "(~S ~S)" 'type 'hint-condition)
                    (report 'hint-condition)))))
    (testing "a name with no class gets no suggestion"
      (ok (null (search "names a class" (report 'missing-spec)))))
    (testing "a COMMON-LISP class name gets no suggestion"
      (ok (null (search "names a class" (report 'integer)))))))

(deftest no-generator-backend-points-at-check-it
  (testing "the report tells the user which system installs a backend"
    (ok (search "CL-SPEC/CHECK-IT"
                (princ-to-string (make-condition 'no-generator-backend))))))

(deftest normalization-failures-carry-the-form
  (testing "INVALID-SPEC-FORM keeps the form and the reason"
    (let ((condition (make-condition 'invalid-spec-form
                                     :form '(cons-of a b)
                                     :reason "post-MVP")))
      (ok (equal '(cons-of a b) (invalid-spec-form-form condition)))
      (ok (equal "post-MVP" (invalid-spec-form-reason condition)))
      (ok (typep condition 'cl-spec-error))
      (ok (search "post-MVP" (princ-to-string condition)))))
  (testing "FORM defaults to NIL rather than leaving the slot unbound"
    ;; An unbound slot would fail inside the :REPORT lambda itself the first
    ;; time INVALID-SPEC-FORM is signalled without a :FORM initarg, masking
    ;; whatever the real problem was.
    (let ((condition (make-condition 'invalid-spec-form :reason "no form given")))
      (ok (null (invalid-spec-form-form condition)))
      (ok (stringp (princ-to-string condition))))))

(deftest generator-failures-name-the-spec
  (testing "GENERATOR-UNAVAILABLE keeps the spec and the reason"
    (let ((condition (make-condition 'generator-unavailable
                                     :spec :placeholder
                                     :reason "NOT has no generation strategy")))
      (ok (eq :placeholder (generator-unavailable-spec condition)))
      (ok (typep condition 'cl-spec-error))
      (ok (search "NOT has no generation strategy" (princ-to-string condition)))))
  (testing "SPEC defaults to NIL rather than leaving the slot unbound"
    (let ((condition (make-condition 'generator-unavailable :reason "no spec given")))
      (ok (null (generator-unavailable-spec condition)))
      (ok (stringp (princ-to-string condition))))))

(deftest unsupported-seed-names-the-implementation
  (testing "UNSUPPORTED-SEED reports which implementation is missing support"
    (let ((condition (make-condition 'unsupported-seed)))
      (ok (typep condition 'cl-spec-error))
      (ok (search (lisp-implementation-type) (princ-to-string condition))))))
