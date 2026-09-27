;;;; specs.lisp

(defpackage #:cl-spec/specs
  (:use #:cl)
  (:import-from #:cl-spec/src/registry #:registry-find-spec)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/main
                #:compile-explainer
                #:compile-validator
                #:defgenerator
                #:defproperty
                #:defspec
                #:defspec-function
                #:explain-data
                #:find-spec
                #:normalize-spec-form
                #:invalid-spec-form #:invalid-spec-form-reason
                #:properties-for
                #:semantic-data
                #:spec
                #:spec-data
                #:spec-kind
                #:spec-source-form
                #:spec-violation
                #:spec-violation-errors
                #:spec-violation-value
                #:validate
                #:validp)
  (:import-from #:cl-spec/self-spec-fixtures
                #:*function-projection-expectations*
                #:*scripted-state-inputs*
                #:*scripted-validate-inputs*
                #:*state-projection-expectations*
                #:*registry-constructor*
                #:*foreign-duplicate-name*
                #:function-projection-fixtures
                #:make-registry-under-test
                #:next-registration-scenario-kind
                #:registration-index-shape-p
                #:registration-scenario-arguments
                #:registration-scenario-state-p
                #:registration-scenario-tags-p
                #:registration-scenario-targets-p
                #:self-registration-name
                #:self-state-observed-target
                #:*self-state-balance*
                #:*self-state-calls*
                #:*self-state-scenario*
                #:state-projection-fixtures
                #:validate-corpus-entry)
  (:export #:register-instrumentation-specifications #:register-specifications
           #:contract-names #:property-names #:evidence-policy
           #:*registry-constructor* #:registry-implementation-p
           #:registry-conformance-names #:check-registry-implementation))

(in-package #:cl-spec/specs)

(defclass self-object-sample ()
  ((id :initarg :id :reader self-object-sample-id))
  (:documentation "Fixture that the OBJECT-OF normalization laws observe through a reader."))

(defun draw-form ()
  "Draw a finite DSL example spanning scalar and composite specs."
  (let ((bound (1+ (random 20))))
    (case (random 18)
      (0 'integer) (1 'string) (2 `(range integer ,(- bound) ,bound))
      (3 `(and integer (range ,(- bound) ,bound)))
      (4 '(or integer string)) (5 '(not integer))
      (6 '(nullable integer)) (7 '(list-of integer))
      (8 '(tuple integer string))
      (9 '(member 1 "two" :three))
      (10 '(vector-of integer))
      (11 '(plist (:required (:id integer)) (:closed t)))
      (12 '(plist (:required (:id integer))
                  (:optional (:nickname (nullable string)))))
      (13 '(list-of integer :min-length 1 :max-length 3))
      (14 '(alist (:test equal) (:required (:id integer)) (:closed t)))
      (15 '(hash-table (:test eql) (:required (:id integer))
                       (:optional (:nickname (nullable string)))))
      (16 '(object-of self-object-sample (:required (self-object-sample-id integer))))
      (17 '(tagged-by :kind
             (:left (plist (:required (:kind (member :left)) (:value integer)) (:closed t)))
             (:right (plist (:required (:kind (member :right)) (:value string)) (:closed t))))))))

(defparameter *sampled-dsl-forms*
  (append '(integer string (or integer string) (not integer) (nullable integer)
            (list-of integer) (tuple integer string)
            (member 1 "two" :three) (vector-of integer)
            (plist (:required (:id integer)) (:closed t))
            (plist (:required (:id integer))
                   (:optional (:nickname (nullable string))))
            (list-of integer :min-length 1 :max-length 3)
            (alist (:test equal) (:required (:id integer)) (:closed t))
            (hash-table (:test eql) (:required (:id integer))
                        (:optional (:nickname (nullable string))))
            (object-of self-object-sample (:required (self-object-sample-id integer)))
            (tagged-by :kind
              (:left (plist (:required (:kind (member :left)) (:value integer)) (:closed t)))
              (:right (plist (:required (:kind (member :right)) (:value string)) (:closed t)))))
          (loop for bound from 1 to 20
                append (list `(range integer ,(- bound) ,bound)
                             `(and integer (range ,(- bound) ,bound)))))
  "The finite normalization-law corpus, constructed once when the bundle loads.")

(defun sampled-dsl-form-p (form)
  "Recognize exactly the finite DSL subset used by the normalization laws.
Malformed lists must not enter a law that promises normalization succeeds."
  (not (null (member form *sampled-dsl-forms* :test #'equal))))

(defun draw-value ()
  "Draw heterogeneous finite values, including mismatches for generated specs."
  (let ((integer (- (random 61) 30)))
    (case (random 7)
      (0 integer) (1 nil) (2 t) (3 (make-string (random 6) :initial-element #\x))
      (4 (list integer)) (5 (list integer "x")) (6 (vector integer)))))

(defun resolved-designator-p (value)
  "Recognize spec objects and names currently registered as specs."
  (or (typep value 'spec)
      (and (symbolp value) (nth-value 1 (find-spec value)))))

(defun explanation-consistent-p (value)
  "Check the relation between validity and errors after field validation."
  (eq (getf value :valid) (null (getf value :errors))))

(defun invalid-form-condition-p (condition)
  "Require a nonempty diagnostic reason for a malformed DSL form."
  (let ((reason (invalid-spec-form-reason condition)))
    (and (stringp reason) (plusp (length reason)))))

(defun digest-details-consistent-p (data)
  "Check completeness against the digest and collected omission records."
  (if (getf data :definition-digest-complete)
      (and (stringp (getf data :definition-digest)) (null (getf data :digest-omissions)))
      (and (null (getf data :definition-digest)) (consp (getf data :digest-omissions)))))

(defun plist-key-present-p (plist key)
  "True when KEY is an indicator of PLIST, even when its value is NIL.

MEMBER is wrong for this question: it also matches KEY in a value position, so
a record with no :VALUE key could pass merely because some field's value is
:VALUE.  GET-PROPERTIES reports the indicator itself (its first value), which
distinguishes an absent key from one whose value is NIL."
  (multiple-value-bind (indicator value) (get-properties plist (list key))
    (declare (ignore value))
    (not (null indicator))))

(defun diagnostic-type-data-p (value)
  "True for the ordinary-data domain of a capture record's :TYPE.

A named type is a symbol.  An anonymous CLOS class is described by the plist
\(:kind :anonymous-class :metaclass SYMBOL), which never carries the live class
object TYPE-OF may return for an unnamed class."
  (or (symbolp value)
      (and (finite-list-p value)
           (evenp (length value))
           (eq :anonymous-class (getf value :kind))
           (plist-key-present-p value :metaclass)
           (symbolp (getf value :metaclass)))))

(defun capture-value-record-p (record)
  "True for one explicit capture-availability record.

The union is enforced by plist key presence, never by searching values:
:VALUE counts only when it is an indicator, so a record whose :VALUE appears
solely as another field's value is malformed.  :NAME and :AVAILABILITY are
always required.  :COLLECTED requires :VALUE (NIL is a value) and forbids
:REASON and :TYPE.  :UNAVAILABLE forbids :VALUE and requires a keyword :REASON
and a diagnostic :TYPE in DIAGNOSTIC-TYPE-DATA-P's domain."
  (and (finite-list-p record)
       (evenp (length record))
       (plist-key-present-p record :name)
       (symbolp (getf record :name))
       (plist-key-present-p record :availability)
       (case (getf record :availability)
         (:collected (and (plist-key-present-p record :value)
                          (not (plist-key-present-p record :reason))
                          (not (plist-key-present-p record :type))))
         (:unavailable (and (not (plist-key-present-p record :value))
                            (plist-key-present-p record :reason)
                            (keywordp (getf record :reason))
                            (plist-key-present-p record :type)
                            (diagnostic-type-data-p (getf record :type))))
         (t nil))))

(defun capture-values-data-p (values)
  "True when VALUES is an ordered list of explicit capture-value records."
  (and (finite-list-p values) (every #'capture-value-record-p values)))

(defun capture-evidence-consistent-p (evidence)
  "Check a capture report's names, prefix and status against each other.

A completed capture obtained every declared binding; a capture that never ran
obtained none; a failed capture obtained exactly the declared prefix before the
failing binding and names that binding, its position and its condition type."
  (let ((status (getf evidence :status))
        (declared (getf evidence :declared))
        (values (getf evidence :values))
        (error (getf evidence :error)))
    (and (finite-list-p declared)
         (every #'symbolp declared)
         (capture-values-data-p values)
         (let* ((obtained (mapcar (lambda (record) (getf record :name)) values))
                (count (length obtained))
                (prefix (subseq declared 0 (min count (length declared)))))
           (and (equal obtained prefix)
                (case status
                  (:completed (and (= count (length declared)) (null error)))
                  (:not-evaluated (and (zerop count) (null error)))
                  (:error (and (< count (length declared))
                               (consp error)
                               (eql count (getf error :index))
                               (eq (nth count declared) (getf error :binding))
                               (getf error :condition-type)
                               (symbolp (getf error :condition-type))))
                  (t nil)))))))

(defun state-post-evidence-consistent-p (evidence)
  "Check a state-post report's status against its reason and condition.

Every clause key is present, but an unknown position is NIL rather than a guessed
integer, and a form whose value is NIL is still the form that was declared.  A
run that passed carries no reason, position, form or condition type; a run that
never reached the state-post has a reason but no position, form or condition
type; a violation carries no reason or condition type; a signalling form carries
a condition type and no reason.  Only a run that reached the state-post may
report a position or a form, and an unknown position stays NIL.  Unknown keys are
allowed."
  (let ((status (getf evidence :status))
        (reason (getf evidence :reason))
        (case-name (getf evidence :case))
        (index (getf evidence :index))
        (form (getf evidence :form))
        (condition-type (getf evidence :condition-type)))
    (and (or (null case-name) (keywordp case-name))
         (or (null index) (and (integerp index) (not (minusp index))))
         (or (null condition-type) (symbolp condition-type))
         (case status
           (:passed (and (null reason) (null index) (null form) (null condition-type)))
           (:not-evaluated (and reason (keywordp reason)
                                (null index) (null form) (null condition-type)))
           (:violation (and (null reason) (null condition-type)))
           (:error (and (null reason) condition-type (symbolp condition-type)))
           (t nil)))))

(defun registered-function-spec-p (name)
  "Return true when NAME names a function spec in the current registry."
  (and (symbolp name) (nth-value 1 (cl-spec:find-function-spec name))))

(defun registered-property-p (name)
  "Return true when NAME names a property in the current registry."
  (and (symbolp name) (nth-value 1 (cl-spec:find-property name))))

(defun self-instrumentation-target (value)
  "Identity function the instrumentation self-laws wrap and call."
  value)

(defun contract-names ()
  "Return the public functions covered by this executable specification bundle."
  '(cl-spec:coverage-schema cl-spec:coverage-data cl-spec:evidence-summary cl-spec:assess-evidence cl-spec:check-fixture cl-spec:fixture-check-data validp validate explain-data compile-validator
    compile-explainer spec-data semantic-data normalize-spec-form
    cl-spec:deserialize-counterexample-artifact cl-spec:validate-definition
     cl-spec:custom-generator-shrinker cl-spec:trial-observation-outcome
     cl-spec:registry-register-property
     cl-spec:find-spec cl-spec:definition-digest
     cl-spec:schema-info cl-spec:make-hash-table-registry
     cl-spec:function-spec-data cl-spec:property-data cl-spec:definition-description
     cl-spec:property-call-arguments-p cl-spec:property-named-arguments
     cl-spec:property-argument-schema cl-spec:function-spec-argument-schema
     cl-spec:result-data cl-spec:observation-failure-p
     cl-spec:make-counterexample-artifact cl-spec:recheck-counterexample))

(defun property-names ()
  "Return the executable semantic laws in this specification bundle."
  '(normalization-is-idempotent normalization-preserves-source
    validation-and-explanation-agree compiled-validation-agrees
    validation-preserves-values-or-explains-refusal boolean-composition
    introspection-preserves-spec-semantics digest-details-agree-with-metadata
    rest-projection-agrees-with-target
    compiled-explanation-agrees explanation-rendering-projects-explain-data
    registry-round-trips-definitions registry-reverse-indexes-track-redefinition
    registry-clear-empties registry-queries-return-sorted-names
    registry-writes-replace-by-name registry-keys-are-symbols-not-names
    member-admits-exactly-its-values
    collection-validation-is-elementwise plist-error-paths-identify-the-field
    malformed-declarations-are-refused
    run-property-is-reproducible-from-its-seed
    failure-identities-match-reflexively counterexample-artifacts-round-trip
    collection-constraints-are-enforced
    generated-values-satisfy-their-specs retained-counterexamples-stay-valid
    sample-reports-its-generation-request
    validate-cases-classify-admitted-and-refused
    registration-replacement-preserves-unrelated-indexes
    function-spec-projection-retains-declared-state
    result-projection-retains-state-evidence
    one-shot-check-reuses-the-single-trial-classifier
    one-shot-check-observes-a-named-case-and-state-once
    fixture-reconstruction-is-independent))

(defun evidence-policy (trials)
  "Return the evidence policy a run of this bundle is held to for a TRIALS budget.

A :PASSED status says only that the observed trials found no violation.  This
policy is the separate claim, checked with CL-SPEC:ASSESS-EVIDENCE, that the run
completed its budget, that every one of its TRIALS reached a passed or failed
verdict, and that each declared case reached at least one verdict.  It inspects
saved facts only; it neither reruns the check nor proves the domain covered."
  (check-type trials (integer 1))
  (list :policy-version 1
        :requirements (list '(:kind :requested-trials-completed)
                            (list :kind :min-checked-trials :count trials)
                            '(:kind :all-declared-cases :min-checked 1))))

(defparameter *registry-protocol*
  '((cl-spec:registry-find-spec 2) (cl-spec:registry-register-spec 3)
    (cl-spec:registry-list-specs 1)
    (cl-spec:registry-find-function-spec 2) (cl-spec:registry-register-function-spec 3)
    (cl-spec:registry-list-function-specs 1)
    (cl-spec:registry-find-generator 2) (cl-spec:registry-register-generator 3)
    (cl-spec:registry-list-generators 1)
    (cl-spec:registry-find-property 2) (cl-spec:registry-register-property 3)
    (cl-spec:registry-list-properties 1)
    (cl-spec:registry-properties-for 2) (cl-spec:registry-properties-with-tag 2)
    (cl-spec:registry-clear 1))
  "Each REGISTRY-* generic function of the §8 protocol with its required argument count.")

(defun registry-implementation-p (object)
  "True when every REGISTRY-* protocol function has a primary method for OBJECT.

The check dispatches on OBJECT as the registry argument with NIL for the others,
so it describes implementations that specialize only the registry, as the
built-in HASH-TABLE-REGISTRY does.  It inspects method applicability only and
calls none of the methods.  The core's unqualified :AROUND validation methods
apply to every object and are not counted."
  (every (lambda (entry)
           (destructuring-bind (name arity) entry
             (some (lambda (method) (null (method-qualifiers method)))
                   (compute-applicable-methods
                    (fdefinition name)
                    (cons object (make-list (1- arity) :initial-element nil))))))
         *registry-protocol*))

(defun registry-conformance-names ()
  "Return the contracts and laws that describe the REGISTRY-* protocol itself.

Each builds the registry it checks with MAKE-REGISTRY-UNDER-TEST, so
CHECK-REGISTRY-IMPLEMENTATION runs exactly these against another implementation.
The value is a plist of :CONTRACTS and :PROPERTIES name lists."
  (list :contracts '(cl-spec:registry-register-property cl-spec:find-spec
                     cl-spec:definition-digest)
        :properties '(registry-round-trips-definitions
                      registry-reverse-indexes-track-redefinition
                      registry-clear-empties
                      registry-queries-return-sorted-names
                      registry-writes-replace-by-name
                      registry-keys-are-symbols-not-names
                      registration-replacement-preserves-unrelated-indexes)))

(defun check-registry-implementation (constructor &key (seeds '(1 42 2026)) (trials 50))
  "Run the registry-protocol contracts and laws against registries CONSTRUCTOR returns.

CONSTRUCTOR is a function of no arguments returning a fresh, empty registry.  It
is called once before any check to confirm REGISTRY-IMPLEMENTATION-P, and a
TYPE-ERROR is signalled otherwise.  SEEDS must be a nonempty list of nonnegative integers and
TRIALS a positive integer, so a true answer always rests on executed checks.  The bundle is registered in a private
registry, so CL-SPEC:*REGISTRY* is left untouched.  Every contract runs TRIALS
trials and every law its declared :NORMAL budget, once per seed in SEEDS.

Return two values: true when every run passed with :SATISFIED evidence under
EVIDENCE-POLICY, and a list of one plist per run with :KIND, :NAME, :SEED,
:STATUS, :ASSESSMENT and :RESULT.  Executing the checks requires a generator
backend such as CL-SPEC/CHECK-IT to be loaded."
  (check-type constructor function)
  ;; An empty seed list would run nothing, and EVERY over no records is true:
  ;; conformance must always rest on at least one executed check.
  ;; Seeds are validated as the runners require (nonnegative) before any check,
  ;; so a bad later seed cannot surface only after earlier runs have executed.
  (unless (and (consp seeds) (finite-list-p seeds)
               (every (lambda (seed) (typep seed '(integer 0 *))) seeds))
    (error 'type-error :datum seeds :expected-type '(cons (integer 0 *) list)))
  (check-type trials (integer 1))
  (let ((sample (funcall constructor)))
    (unless (registry-implementation-p sample)
      (error 'type-error :datum sample :expected-type '(satisfies registry-implementation-p))))
  (let ((*registry-constructor* constructor)
        (cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (names (registry-conformance-names))
        (records '()))
    (register-specifications)
    (flet ((record (kind name seed result budget)
             (push (list :kind kind :name name :seed seed
                         :status (cl-spec:property-result-status result)
                         :assessment (getf (cl-spec:assess-evidence
                                            result (evidence-policy budget))
                                           :assessment)
                         :result result)
                   records)))
      (dolist (seed seeds)
        (dolist (name (getf names :contracts))
          (record :contract name seed
                  (cl-spec:check-function name :trials trials :seed seed) trials))
        (dolist (name (getf names :properties))
          (record :property name seed (cl-spec:run-property name :seed seed)
                  (getf (cl-spec:property-trials (cl-spec:find-property name)) :normal)))))
    (let ((records (nreverse records)))
      (values (every (lambda (record)
                       (and (eq :passed (getf record :status))
                            (eq :satisfied (getf record :assessment))))
                     records)
              records))))

(defun register-instrumentation-specifications ()
  "Register the optional instrumentation API contracts after CL-SPEC/INSTRUMENT is loaded.
Return the INSTRUMENTATION-STATUS name. This bundle never loads the instrumentation
system itself, so every instrumentation symbol is resolved here by name."
  (let* ((package (find-package "CL-SPEC/INSTRUMENT"))
         (name (and package (find-symbol "INSTRUMENTATION-STATUS" package))))
    (unless (and name (fboundp name))
      (error "Load CL-SPEC/INSTRUMENT before registering its specifications."))
    (flet ((instrumentation-symbol (string)
             (multiple-value-bind (symbol status) (find-symbol string package)
               (unless (and symbol (eq status :external))
                 (error "CL-SPEC/INSTRUMENT does not export ~A." string))
               symbol)))
      (let ((instrument (instrumentation-symbol "INSTRUMENT-FUNCTION"))
            (uninstrument (instrumentation-symbol "UNINSTRUMENT-FUNCTION"))
            (instrumented-p (instrumentation-symbol "INSTRUMENTED-FUNCTION-P"))
            (refresh (instrumentation-symbol "REFRESH-INSTRUMENTATION"))
            (unsupported (instrumentation-symbol "UNSUPPORTED-INSTRUMENTATION-TARGET"))
            (violation (instrumentation-symbol "INSTRUMENTATION-VIOLATION")))
        (cl-spec:register-function-spec
         (make-instance
          'cl-spec:function-spec :name name
          :argument-specs '((name (member uninstalled-self-target)))
          :return-spec
          '(plist (:required
                    (:status (member :not-installed :current :stale :indeterminate))
                    (:reasons (list-of keyword))
                    (:installed-digest-omissions (or (member :not-collected) (list-of t)))
                    (:current-digest-omissions (or (member :not-collected) (list-of t)))
                    (:digest-exclusions (or (member :not-collected) (list-of keyword)))
                    (:dependency-status (member :unchanged :changed :indeterminate))))
          :source-form '(instrumentation-status-shape)
          :documentation
          "Instrumentation status always identifies freshness and comparison limits."))
        (cl-spec:register-function-spec
         (make-instance 'cl-spec:function-spec
                        :name 'self-instrumentation-target
                        :argument-specs '((value integer))
                        :return-spec 'integer
                        :source-form '(self-instrumentation-target)
                        :documentation "Identity contract the instrumentation self-laws wrap."))
        (cl-spec:register-generator
         (make-instance 'cl-spec:custom-generator
                        :name 'instrumentation-target-arguments
                        :function (lambda () (list 'self-instrumentation-target))))
        (cl-spec:register-function-spec
         (make-instance
          'cl-spec:function-spec :name instrumented-p
          :argument-specs '((name symbol))
          :argument-generator 'instrumentation-target-arguments
          :return-spec 'boolean
          :documentation
          "Instrumented-function-p answers a boolean about the wrapped self-target."))
        (cl-spec:register-function-spec
         (make-instance
          'cl-spec:function-spec :name uninstrument
          :argument-specs '((name symbol))
          :argument-generator 'instrumentation-target-arguments
          :return-spec 'boolean
          :documentation
          "Uninstrument-function answers a boolean about the wrapped self-target."))
        (cl-spec:register-property
         (make-instance
          'cl-spec:property
          :name 'instrumentation-round-trips
          :arguments '((value integer))
          :targets (list instrument uninstrument instrumented-p violation)
          :tags '(:cl-spec-self)
          :trials '(:smoke 3 :normal 10)
          :source-form '(instrumentation-round-trips)
          :documentation "Installed checks accept contracted calls and refuse others."
          :function
          (lambda (value)
            (unwind-protect
                 (progn
                   (funcall instrument 'self-instrumentation-target
                            :scopes '(:input :output))
                   (and (funcall instrumented-p 'self-instrumentation-target)
                        (= value (funcall 'self-instrumentation-target value))
                        (handler-case
                            (progn
                              (funcall 'self-instrumentation-target "wrong")
                              nil)
                          (error (condition) (typep condition violation)))
                        (eq t (funcall uninstrument 'self-instrumentation-target))
                        (not (funcall instrumented-p 'self-instrumentation-target))))
              (when (funcall instrumented-p 'self-instrumentation-target)
                (funcall uninstrument 'self-instrumentation-target))))))
        (cl-spec:register-property
         (make-instance
          'cl-spec:property
          :name 'instrumentation-refuses-uncontracted-targets
          :arguments '((value integer))
          :targets (list instrument refresh)
          :tags '(:cl-spec-self)
          :trials '(:smoke 3 :normal 10)
          :source-form '(instrumentation-refuses-uncontracted-targets)
          :documentation "Instrumenting and refreshing uncontracted targets are refused."
          :function
          (lambda (value)
            (declare (ignore value))
            (and (handler-case
                     (progn (funcall instrument 'self-uncontracted-target) nil)
                   (cl-spec:unknown-function-spec () t))
                 (handler-case
                     (progn (funcall refresh 'self-uncontracted-target) nil)
                   (error (condition) (typep condition unsupported)))))))
        name))))

(defparameter *generation-corpus*
  (mapcar #'cl-spec:normalize-spec-form
          '(integer string (range integer -5 5) (member 1 2 3) (member nil)
            (nullable integer) (or integer string)
            (list-of integer :min-length 1 :max-length 3)
            (vector-of (member 1 2 3) :min-length 1 :max-length 2 :unique t)
            (tuple integer string)
            (plist (:required (:id integer)))))
  "Small built-in spec corpus for the generation-soundness law.

Built once at load time.  The entries are anonymous spec objects, so the law
needs no registry beyond the one the runner binds, and it stays independent of
the definitions REGISTER-SPECIFICATIONS installs.")

(defun self-collection-counterexample-target (items)
  "Identity target for the retained-counterexample law's collection contract."
  items)

(defun self-keyword-counterexample-target (&rest raw &key a)
  "Identity target for the retained-counterexample law's keyword contract."
  (declare (ignore a))
  raw)

(defun found-definition-p (expected primary present)
  "True when a REGISTRY-FIND-* answer matches EXPECTED exactly.

A non-NIL EXPECTED requires that definition and a found-p of T; a NIL EXPECTED
requires NIL and NIL, the documented answer for an absent name."
  (and (eq expected primary) (eq (and expected t) present)))

(defun self-sort-contract (&optional (name 'self-contract))
  "Return a fresh, valid function spec named NAME for the registry laws."
  (make-instance 'cl-spec:function-spec :name name
                 :argument-specs '((x integer)) :return-spec 'integer))

(defun self-sort-generator (&optional (name 'self-generator))
  "Return a fresh custom generator named NAME for the registry laws."
  (make-instance 'cl-spec:custom-generator :name name :function (lambda () 1)))

(defun self-sort-property (name)
  "Return a fresh, valid property named NAME for the registry laws."
  (make-instance 'cl-spec:property :name name :arguments '((x integer))
                 :function (lambda (x) (declare (ignore x)) t)))

(defun register-specifications ()
  "Install executable contracts and laws in CL-SPEC:*REGISTRY*.
Loading CL-SPEC/SPECS installs these once. Call this function again after
CLEAR-REGISTRY or with a freshly bound registry. It does not instrument functions.
Generators exercise finite subsets. Most API contracts accept broader domains;
the malformed-normalization contract and the validate cases explicitly name
their finite input corpora, and the registry write contract names its scenarios."
  (defgenerator fresh-fixture-contract-generator ()
    (cl-spec/self-spec-fixtures:fresh-fixture-contract))
  (defspec fresh-fixture-contract-input (instance-of cl-spec:function-spec)
    (:generator fresh-fixture-contract-generator))
  (defspec-function cl-spec:check-fixture
    "A dedicated fresh recipe runs once and releases its fixture."
    (:args (contract fresh-fixture-contract-input) (recipe (range integer 0 30)))
    (:returns (instance-of cl-spec:fixture-check-result))
    (:post (let ((data (cl-spec:fixture-check-data result)))
             (and (eq :passed (getf data :status))
                  (eql recipe (getf data :recipe))
                  (eq :released (getf (getf data :lifecycle) :state))))))
  (defgenerator fresh-fixture-result-generator ()
    (cl-spec:check-fixture (cl-spec/self-spec-fixtures:fresh-fixture-contract) 7))
  (defspec fresh-fixture-result (instance-of cl-spec:fixture-check-result)
    (:generator fresh-fixture-result-generator))
  (defspec-function cl-spec:fixture-check-data
    "Fixture projection distinguishes recipe input from live call arguments."
    (:args (observation fresh-fixture-result))
    (:returns (plist (:required (:schema-version (member 2))
                                (:input-kind (member :fixture-recipe))
                                (:record-kind (member :fixture-check))
                                (:status (member :passed)) (:recipe (member 7)))))
    (:post (eq :completed (getf (getf result :lifecycle) :cleanup))))
  (defspec-function cl-spec:coverage-schema
    "Coverage discovery returns bounded declaration facts without running the target."
    (:args (contract fresh-fixture-contract-input))
    (:returns (plist (:required (:schema-version (member 1))
                                (:record-kind (member :coverage-schema))
                                (:dimensions list) (:unexpanded list))))
    (:post (stringp (getf (getf result :subject) :definition-digest))))
  (defspec-function cl-spec:coverage-data
    "A result saved without coverage reports explicit missing measurement."
    (:args (observation fresh-fixture-result))
    (:returns (plist (:required (:availability (member :not-collected))
                                (:reason (member :disabled))))))
  (defspec-function cl-spec:evidence-summary
    "A saved direct observation is summarized without an implicit policy."
    (:args (observation fresh-fixture-result))
    (:returns (plist (:required (:schema-version (member 1))
                               (:record-kind (member :evidence-summary))
                               (:assessment (member :not-assessed))
                               (:execution-status (member :passed)))))
    (:post (eql 1 (getf (find :checked-trials (getf result :dimensions)
                             :key (lambda (entry) (getf entry :kind))) :value))))
  (defgenerator evidence-policy-generator ()
    (if (zerop (random 2)) nil
        (list :policy-version 1 :requirements
              (list (list :kind :min-checked-trials :count 1)))))
  (defspec evidence-policy-input list (:generator evidence-policy-generator))
  (defspec-function cl-spec:assess-evidence
    "An explicit threshold is assessed; malformed policy data is rejected."
    (:args (observation fresh-fixture-result) (policy evidence-policy-input))
    (:cases
     (:valid (:when (equal policy '(:policy-version 1 :requirements
                                   ((:kind :min-checked-trials :count 1)))))
             (:returns (plist (:required (:schema-version (member 1))
                                         (:record-kind (member :evidence-assessment))
                                         (:assessment (member :satisfied))
                                         (:execution-status (member :passed))))))
     (:invalid (:when (null policy)) (:signals (type cl-spec:invalid-evidence-policy)))))
  (defproperty fixture-reconstruction-is-independent ((recipe (range integer 0 30)))
    "Repeating one recipe starts from the same value and does not overwrite past evidence."
    (:about cl-spec:check-fixture cl-spec:fixture-check-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 2 :normal 10))
    (let* ((contract (cl-spec/self-spec-fixtures:fresh-fixture-contract))
           (first (cl-spec:fixture-check-data (cl-spec:check-fixture contract recipe)))
           (second (cl-spec:fixture-check-data (cl-spec:check-fixture contract recipe))))
      (and (eq :passed (getf first :status)) (eq :passed (getf second :status))
           (= (1+ recipe) (getf (getf (getf first :observation) :value) :value))
           (= (1+ recipe) (getf (getf (getf second :observation) :value) :value))
           (eq :released (getf (getf first :lifecycle) :state))
           (eq :released (getf (getf second :lifecycle) :state)))))
  (defspec-function cl-spec:deserialize-counterexample-artifact
    "Malformed saved artifacts are refused without reader evaluation."
    (:args (wire (member "" "bad" "#.(error \"must not execute\")" "AV1 (999)")))
    (:signals (type cl-spec:invalid-counterexample-artifact)))
  (defspec target-outcome-data
    (or (member :not-collected)
        (plist (:required (:kind (member :returned)) (:values (list-of t))))
        (plist (:required (:kind (member :signaled))
                          (:condition-type t) (:condition-report (nullable string))))))
  (defgenerator observation-generator ()
    (let ((status (case (random 4) (0 :passed) (1 :rejected) (2 :failed) (t :error))))
      (cl-spec:make-trial-observation
       :status status
       :reason (case status (:failed :predicate-false) (:error :condition) (t nil))
       :signature (case status
                    (:failed '(:property-false))
                    (:error '(:property-condition simple-error))
                    (t nil))
       :outcome (case (random 3)
                  (0 :not-collected)
                  (1 (list :kind :returned :values (list (draw-value))))
                  (t (list :kind :signaled :condition-type 'simple-error
                           :condition-report "sample"))))))
  (defspec observed-trial (instance-of cl-spec:trial-observation)
    (:generator observation-generator))
  (defspec-function cl-spec:trial-observation-outcome
    "Observed target data is distinct from the contract classification."
    (:args (observation observed-trial))
    (:returns target-outcome-data))
  (defgenerator custom-generator-definition-generator ()
    (make-instance 'cl-spec:custom-generator :name 'generated-custom-generator
                   :function (lambda () 4)
                   :shrinker (when (zerop (random 2))
                               (lambda (value) (if (zerop value) nil (list 0))))))
  (defspec custom-generator-definition
    (instance-of cl-spec:custom-generator)
    (:generator custom-generator-definition-generator))
  (defspec-function cl-spec:custom-generator-shrinker
    "A custom generator exposes an optional callable shrink strategy."
    (:args (generator custom-generator-definition))
    (:returns (nullable function)))
  (defgenerator definition-generator ()
    (make-instance 'cl-spec:property :name 'generated-definition
                                    :arguments '((x integer)) :function #'identity))
  (defspec generated-definition (instance-of cl-spec:property)
    (:generator definition-generator))
  (defspec-function cl-spec:validate-definition
    "A valid programmatic definition preserves its object identity."
    (:args (definition generated-definition))
    (:returns (instance-of cl-spec:property))
    (:post (eq result definition)))
  (defgenerator form-generator () (draw-form))
  (defgenerator value-generator () (draw-value))
  (defgenerator spec-generator () (normalize-spec-form (draw-form)))
  (defgenerator symbol-generator ()
    (nth (random 4) '(validp unknown-self-name nil :keyword)))
  (defspec malformed-form
    (member 42 "not-a-spec" (range) (tuple . integer) (unknown-primitive)))
  (defspec-function normalize-spec-form
    "Malformed DSL forms are refused with an explanatory invalid-spec-form error."
    (:args (form malformed-form))
    (:signals (and (type invalid-spec-form) (satisfies invalid-form-condition-p))))
  (defspec generated-form (satisfies sampled-dsl-form-p) (:generator form-generator))
  (defspec arbitrary-value t (:generator value-generator))
  (defspec spec-object (instance-of spec) (:generator spec-generator))
  (defspec resolved-designator (satisfies resolved-designator-p)
    (:generator spec-generator))
  (defspec arbitrary-symbol symbol (:generator symbol-generator))
  (defspec explanation-data
    (and (plist (:required (:spec t) (:value t) (:valid boolean)
                           (:errors (list-of t)) (:path (list-of t))))
         (satisfies explanation-consistent-p)))
  (defspec digest-omission-data
    (plist (:required
             (:kind (member :unresolved-reference :opaque-definition :missing-source
                            :opaque-value :uninterned-symbol :resource-limit))
             (:path (list-of t)) (:target symbol) (:reason keyword))))
  (defgenerator digest-definition-generator ()
    (if (zerop (random 2))
        (normalize-spec-form (draw-form))
        (make-instance 'cl-spec:property :name 'source-less-definition
                                        :function (lambda () t))))
  (defspec digest-definition
    (or (instance-of spec) (instance-of cl-spec:property))
    (:generator digest-definition-generator))
  (defspec spec-description-data
    (and
      (plist
        (:required
          (:schema-version (member 1))
          (:record-kind (member :definition))
          (:entity-kind (member :spec))
          (:kind keyword)
          (:source-form t)
          (:definition-digest (nullable string))
          (:digest-omissions (list-of digest-omission-data))
          (:digest-exclusions (list-of keyword))
          (:definition-digest-complete boolean)
          (:definition-digest-covers (member :declaration-and-registered-dependencies))
          (:capabilities
            (plist (:required
                     (:generation (member :available :unavailable :unknown :none))
                     (:shrinking (member :available :unavailable :unknown :none))
                     (:instrumentation (member :available :unavailable :unknown :none)))))))
      (satisfies digest-details-consistent-p)))
  (defgenerator registry-generator () (make-registry-under-test))
  (defspec registry-object (satisfies registry-implementation-p)
    (:generator registry-generator))
  (defspec-function cl-spec:definition-digest
    "A definition digest is a string when complete, otherwise NIL, with an optional registry key."
    (:args (definition digest-definition) &key ((:registry registry) registry-object supplied))
    (:returns (values (nullable string) boolean (list-of digest-omission-data)))
    (:post-values (digest complete omissions)
      (if complete
          (and (stringp digest) (null omissions))
          (and (null digest) (consp omissions)))))
  (defspec-function cl-spec:find-spec
    "Omitted registry uses the current registry; supplied registry is used explicitly."
    (:args (name arbitrary-symbol) &optional (registry registry-object supplied))
    (:returns (values (nullable (instance-of spec)) boolean))
    (:post-values (found-spec found-p)
      (multiple-value-bind (expected present)
          (registry-find-spec
           (if supplied registry cl-spec:*registry*) name)
        (and (eq found-spec expected) (eq found-p present)))))
  (defspec-function validp
    "Validity is a boolean for a resolved spec and an arbitrary value."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:returns boolean))
  (defspec-function explain-data
    "Explanation preserves the checked value and agrees with validity."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:returns explanation-data)
    (:post (eq value (getf result :value))
           (eq (validp contract-spec value) (getf result :valid))))
  (defgenerator validate-corpus-generator ()
    ;; The finite corpus pairs admitted forms with refused values, so a run that
    ;; reaches both pairs reaches both named cases.  This is a sample of the two
    ;; outcomes, not the whole DSL or the whole value domain.
    (destructuring-bind (form value) (validate-corpus-entry)
      (list (normalize-spec-form form) value)))
  (defspec-function validate
    "An admitted value is returned identically; a refused value signals SPEC-VIOLATION.

The generated inputs are a finite admitted/refused corpus; the declared domain is
every resolved designator and value, and the cases classify by the public
validity predicate, so the contract itself is not limited to the corpus."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:args-generator validate-corpus-generator)
    (:cases
     (:conforming
      "The spec admits the value, and validation returns that same object."
      (:when (validp contract-spec value))
      (:returns t)
      (:post (eq result value)))
     (:refused
      "The spec refuses the value, and validation reports SPEC-VIOLATION."
      (:when (not (validp contract-spec value)))
      (:signals (type spec-violation)))))
  (defspec-function compile-validator
    (:args (contract-spec spec-object))
    (:returns function))
  (defspec-function compile-explainer
    (:args (contract-spec spec-object))
    (:returns function))
  (defspec-function spec-data
    (:args (contract-spec resolved-designator))
    (:returns spec-description-data))
  (defspec-function semantic-data
    (:args (name arbitrary-symbol))
    (:returns list)
    (:post (eq name (getf result :symbol))
           (equal (getf result :properties-about) (properties-for name))))
  ;; Kernel round-trip contracts.  These APIs take and return definition
  ;; objects, so their inputs are generated directly rather than reached
  ;; through the DSL; the object specs remain internal to this bundle.

  (defgenerator function-spec-definition-generator ()
    (make-instance 'cl-spec:function-spec :name 'generated-function-spec
                   :argument-specs '((x integer))
                   :return-spec 'integer))

  (defspec function-spec-definition (instance-of cl-spec:function-spec)
    (:generator function-spec-definition-generator))

  (defgenerator registered-function-spec-generator ()
    (let ((name (gensym "SELF-FUNCTION-SPEC")))
      (cl-spec:register-function-spec
       (make-instance 'cl-spec:function-spec :name name
                      :argument-specs '((x integer))
                      :return-spec 'integer))
      name))

  (defspec registered-function-spec (satisfies registered-function-spec-p)
    (:generator registered-function-spec-generator))

  (defgenerator registered-property-generator ()
    (let ((name (gensym "SELF-PROPERTY")))
      (cl-spec:register-property
       (make-instance 'cl-spec:property :name name
                      :arguments '((x integer))
                      :function (lambda (x) (declare (ignore x)) t)))
      name))

  (defspec registered-property (satisfies registered-property-p)
    (:generator registered-property-generator))

  (defspec self-member-values (member 1 "two" :three))
  (defspec self-integer-list (list-of integer))
  (defspec self-integer-vector (vector-of integer))
  (defspec self-record
    (plist (:required (:id integer))
           (:optional (:nickname (nullable string)))
           (:closed t)))

  ;; Runner evidence.  The result and artifact objects are produced by running a
  ;; throwaway property, which is the only way to obtain system-constructed
  ;; evidence; executing these specifications needs a generator backend.
  (defun self-run-result (function)
    "Run a throwaway property over one integer trial with FUNCTION as its body."
    (cl-spec:run-property
     (make-instance 'cl-spec:property :name 'self-result-target
                    :arguments '((x integer))
                    :function function
                    :trials '(:normal 5))
     :seed (random 1000000) :profile :normal))

  (defun self-failing-result ()
    "Register and run a source-backed property whose body always fails.

The body and source form keep the declaration digest complete, which is what
lets RECHECK-COUNTEREXAMPLE resolve the saved name and execute the input."
    (let ((property (make-instance 'cl-spec:property
                                   :name 'self-failing-target
                                   :arguments '((x integer))
                                   :targets '(self-target)
                                   :tags '(:self)
                                   :function (lambda (x) (declare (ignore x)) nil)
                                   :body '(nil)
                                   :source-form '(defproperty self-failing-target
                                                   ((x integer)) nil)
                                   :trials '(:normal 5))))
      (cl-spec:register-property property)
      (cl-spec:run-property property :seed (random 1000000) :profile :normal)))

  (defun self-failing-artifact ()
    "Freeze a throwaway failing run into a saved counterexample artifact."
    (cl-spec:make-counterexample-artifact (self-failing-result)))

  (defgenerator passing-result-generator ()
    (self-run-result (lambda (x) (declare (ignore x)) t)))

  (defspec passing-property-result (instance-of cl-spec:property-result)
    (:generator passing-result-generator))

  (defgenerator failing-result-generator ()
    (self-failing-result))

  (defspec failing-property-result (instance-of cl-spec:property-result)
    (:generator failing-result-generator))

  (defgenerator counterexample-artifact-generator ()
    (self-failing-artifact))

  (defspec counterexample-artifact-object (instance-of cl-spec:counterexample-artifact)
    (:generator counterexample-artifact-generator))

  (defgenerator recheck-arguments-generator ()
    (list (self-failing-artifact) :state-policy :stateless))

  (defspec definition-envelope
    (and
     (plist
      (:required
       (:schema-version (member 1))
       (:record-kind (member :definition))
       (:entity-kind (member :spec :property :function-spec))
       (:definition-digest (nullable string))
       (:definition-digest-complete boolean)
       (:definition-digest-covers (member :declaration-and-registered-dependencies))
       (:digest-omissions (list-of t))
       (:digest-exclusions (list-of keyword))
       (:capabilities
        (plist (:required
                (:generation (member :available :unavailable :unknown :none))
                (:shrinking (member :available :unavailable :unknown :none))
                (:instrumentation (member :available :unavailable :unknown :none)))))))
     (satisfies digest-details-consistent-p)))

  (defspec capture-declaration-data
    (plist (:required (:name symbol) (:form t))))

  (defspec function-case-description-data
    (plist
     (:required
      (:name keyword)
      (:documentation (nullable string))
      (:when t)
      (:outcome (member :returns :signals))
      (:returns t)
      (:signals t)
      (:postconditions (list-of t)))
     (:optional
      (:post-value-variables (or (member :primary) (list-of symbol)))
      (:state-post (list-of t)))))

  (defspec capture-diagnostic-type-data
    (or symbol
        (plist (:required (:kind (member :anonymous-class))
                          (:metaclass symbol)))))

  (defspec capture-value-record-data
    (and
     (plist
      (:required (:name symbol)
                 (:availability (member :collected :unavailable)))
      (:optional (:value t) (:reason keyword)
                 (:type capture-diagnostic-type-data)))
     (satisfies capture-value-record-p)))

  (defspec capture-evidence-data
    (and
     (plist
      (:required
       (:status (member :completed :error :not-evaluated))
       (:declared (list-of symbol))
       (:values (list-of capture-value-record-data)))
      (:optional
       (:error (nullable
                (plist (:required (:binding symbol) (:index (range integer 0 *))
                                  (:condition-type symbol)))))))
     (satisfies capture-evidence-consistent-p)))

  (defspec state-post-evidence-data
    (and
     (plist
      (:required (:status (member :passed :violation :error :not-evaluated))
                 (:reason (nullable keyword))
                 (:case (nullable keyword))
                 (:index (nullable (range integer 0 *)))
                 (:form t)
                 (:condition-type (nullable symbol))))
     (satisfies state-post-evidence-consistent-p)))

  (defspec trial-state-evidence-data
    (plist (:optional (:capture capture-evidence-data)
                      (:state-post state-post-evidence-data))))

  (defspec result-observation-data
    (plist
     (:required
      (:arguments (list-of t))
      (:status (member :passed :failed :error :rejected))
      (:reason t)
      (:signature t)
      (:explanation t)
      (:outcome t)
      (:value t)
      (:case t)
      (:condition-report t))
     (:optional (:state trial-state-evidence-data))))

  (defspec function-spec-description-data
    (and definition-envelope
         (plist
          (:required
           (:name symbol)
           (:kind (member :function-spec))
           (:documentation (nullable string))
           (:arguments (list-of t))
           (:argument-generator (nullable symbol))
           (:argument-schema t)
           (:preconditions (list-of t))
           (:returns (nullable t))
           (:signals (nullable t))
           (:postconditions (list-of t))
           (:source-form t)
           (:source-location t)
           (:metadata t))
          (:optional
           (:capture (list-of capture-declaration-data))
           (:state-post (list-of t))
           (:case-selection (member :exclusive))
           (:cases (list-of function-case-description-data))
           (:post-value-variables (or (member :primary) (list-of symbol)))))))

  (defspec property-description-data
    (and definition-envelope
         (plist
          (:required
           (:name symbol)
           (:kind (nullable keyword))
           (:targets (list-of symbol))
           (:tags (list-of symbol))
           (:documentation (nullable string))
           (:trials (list-of t))
           (:arguments (list-of t))
           (:body (list-of t))
           (:source-form t)
           (:source-location t)
           (:metadata t)))))

  (defspec schema-info-data
    (plist
     (:required
      (:schema-version (member 1))
      (:format (member :lisp-plist))
      (:unknown-keys (member :ignore))
      (:required-metadata (list-of keyword))
      (:optional-metadata (list-of keyword))
      (:digest-omission-kinds (list-of keyword))
      (:entity-kinds (list-of keyword))
      (:record-kinds (list-of keyword))
      (:capture-value-states (list-of keyword))
      (:capture-value-keys (list-of keyword))
      (:capture-value-type-forms (list-of keyword))
      (:digest-algorithm (member :fnv1a64-v1))
      (:digest-covers (member :declaration-and-registered-dependencies))
      (:digest-excludes (list-of keyword))
      (:capability-states (list-of keyword)))))

  (defspec-function cl-spec:schema-info
    "Version 1 schema metadata names its required keys, kinds and capability states."
    (:returns schema-info-data))

  (defspec-function cl-spec:make-hash-table-registry
    "A fresh registry starts empty."
    (:returns (instance-of cl-spec:hash-table-registry))
    (:post (null (cl-spec:list-specs result))
           (null (cl-spec:list-properties result))
           (null (cl-spec:list-function-specs result))
           (null (cl-spec:list-generators result))))

  (defgenerator registration-scenario-kinds ()
    ;; One scenario keyword per draw: a new, replacement or refused write.  No
    ;; shrinker: every keyword selects its own case, and the case name is part of
    ;; the failure identity, so no other keyword could keep the same failure.
    (next-registration-scenario-kind))

  (defspec registration-scenario-kind
      (member :new :replace :refused-targets :refused-tags)
    (:generator registration-scenario-kinds))

  (defspec-function cl-spec:registry-register-property
    "A property write adds, replaces or refuses without leaking stale index entries.

The declared input domain is the whole finite scenario
REGISTRATION-SCENARIO-ARGUMENTS builds: the argument values and, through the
common :PRE, the registry's initial state.  The state-post names the scenario's
fixed index symbols, so a registry with some other history is outside the
contract rather than a counterexample.  Within that domain every expected
after-state is derived from the input and the observed before-state, and every
observation is a fresh list from a public reader, never a captured registry.

The fresh fixture's recipe is the scenario keyword, so each trial rebuilds its
registry from data and a failing keyword persists as a counterexample artifact
that RECHECK-COUNTEREXAMPLE with :STATE-POLICY :FIXTURE reconstructs once."
    (:args (registry registry-object) (name symbol)
           (property (instance-of cl-spec:property))
           &key ((:targets targets) (satisfies registration-scenario-targets-p))
                ((:tags tags) (satisfies registration-scenario-tags-p)))
    (:fixture
      (:isolation :fresh)
      (:version 1)
      (:recipe (scenario registration-scenario-kind))
      (:setup (context)
        (declare (ignore context))
        (registration-scenario-arguments scenario))
      (:cleanup (context)
        (declare (ignore scenario))
        (clrhash context)))
    (:pre (registration-scenario-state-p registry name targets tags))
    (:capture
     (names-before (cl-spec:registry-list-properties registry))
     (old-definition (nth-value 0 (cl-spec:registry-find-property registry name)))
     (shared-target-before
      (cl-spec:registry-properties-for registry (self-registration-name :shared-target)))
     (old-target-before
      (cl-spec:registry-properties-for registry (self-registration-name :old-target)))
     (new-target-before
      (cl-spec:registry-properties-for registry (self-registration-name :new-target)))
     (shared-tag-before
      (cl-spec:registry-properties-with-tag registry (self-registration-name :shared-tag)))
     (old-tag-before
      (cl-spec:registry-properties-with-tag registry (self-registration-name :old-tag)))
     (new-tag-before
      (cl-spec:registry-properties-with-tag registry (self-registration-name :new-tag)))
     (sentinel-before
      (nth-value 0 (cl-spec:registry-find-property registry (self-registration-name :sentinel)))))
    (:cases
     (:refused
      "A malformed index argument is refused before the registry changes."
      (:when (not (registration-index-shape-p targets tags)))
      (:signals (type type-error))
      (:state-post
       (null (set-exclusive-or (cl-spec:registry-list-properties registry) names-before))
       (eq old-definition
           (nth-value 0 (cl-spec:registry-find-property registry name)))
       (eq sentinel-before
           (nth-value 0 (cl-spec:registry-find-property
                         registry (self-registration-name :sentinel))))
       (equal shared-target-before
              (cl-spec:registry-properties-for
               registry (self-registration-name :shared-target)))
       (equal old-target-before
              (cl-spec:registry-properties-for
               registry (self-registration-name :old-target)))
       (equal new-target-before
              (cl-spec:registry-properties-for
               registry (self-registration-name :new-target)))
       (equal shared-tag-before
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :shared-tag)))
       (equal old-tag-before
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :old-tag)))
       (equal new-tag-before
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :new-tag)))))
     (:new-registration
      "A fresh name joins the names and every declared reverse index."
      (:when (and (registration-index-shape-p targets tags) (null old-definition)))
      (:returns (instance-of cl-spec:property))
      (:post (eq result property))
      (:state-post
       (= (1+ (length names-before)) (length (cl-spec:registry-list-properties registry)))
       (member name (cl-spec:registry-list-properties registry))
       ;; The passed definition, not only the return value, is what was stored.
       (eq property (nth-value 0 (cl-spec:registry-find-property registry name)))
       ;; Each index gains exactly this name on top of the observed before-set.
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :new-target))
              (adjoin name new-target-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :new-tag))
              (adjoin name new-tag-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :shared-target))
              (adjoin name shared-target-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :shared-tag))
              (adjoin name shared-tag-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :old-target))
              old-target-before))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :old-tag))
              old-tag-before))
       (eq sentinel-before
           (nth-value 0 (cl-spec:registry-find-property
                         registry (self-registration-name :sentinel))))))
     (:re-registration
      "A same-name write replaces the definition and retracts only its stale keys."
      (:when (and (registration-index-shape-p targets tags) (not (null old-definition))))
      (:returns (instance-of cl-spec:property))
      (:post (eq result property))
      (:state-post
       (= (length names-before) (length (cl-spec:registry-list-properties registry)))
       (null (set-exclusive-or (cl-spec:registry-list-properties registry) names-before))
       (eq property (nth-value 0 (cl-spec:registry-find-property registry name)))
       ;; Old indexes lose exactly this name; new and shared indexes gain it.
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :old-target))
              (remove name old-target-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :old-tag))
              (remove name old-tag-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :new-target))
              (adjoin name new-target-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :new-tag))
              (adjoin name new-tag-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-for
               registry (self-registration-name :shared-target))
              (adjoin name shared-target-before)))
       (null (set-exclusive-or
              (cl-spec:registry-properties-with-tag
               registry (self-registration-name :shared-tag))
              (adjoin name shared-tag-before)))
       (eq sentinel-before
           (nth-value 0 (cl-spec:registry-find-property
                         registry (self-registration-name :sentinel))))))))

  (defspec-function cl-spec:function-spec-data
    "The function-spec projection carries the v1 envelope and the contract's clauses."
    (:args (designator registered-function-spec))
    (:returns function-spec-description-data))

  (defspec-function cl-spec:property-data
    "The property projection carries the v1 envelope and the property's declaration."
    (:args (designator registered-property))
    (:returns property-description-data))

  (defspec-function cl-spec:definition-description
    "A definition describes its declaration, children, registry links and completeness."
    (:args (definition generated-definition))
    (:returns (values
               (plist (:required (:entity-kind (member :property)) (:name symbol)))
               (list-of t) (list-of t) boolean)))

  (defspec-function cl-spec:property-call-arguments-p
    "The raw call-shape predicate matches the binding count without running the property."
    (:args (property generated-definition) (arguments (list-of arbitrary-value)))
    (:returns boolean)
    (:post (eq result (= (length arguments)
                         (length (cl-spec:property-arguments property))))))

  (defspec-function cl-spec:property-named-arguments
    "Raw call arguments project onto the property's variable bindings in order."
    (:args (property generated-definition) (arguments (list-of arbitrary-value)))
    (:returns (list-of t))
    (:post (equal result
                  (loop for (name nil) in (cl-spec:property-arguments property)
                        for value in arguments append (list name value)))))

  (defspec-function cl-spec:property-argument-schema
    "A property's argument schema is a Semantic IR spec object."
    (:args (property generated-definition))
    (:returns (instance-of cl-spec:spec)))

  (defspec-function cl-spec:function-spec-argument-schema
    "A contract's argument schema is a Semantic IR spec object."
    (:args (contract function-spec-definition))
    (:returns (instance-of cl-spec:spec)))

  (defspec result-description-data
    (plist
     (:required
      (:schema-version (member 1))
      (:record-kind (member :result))
      (:entity-kind (member :property :function-spec))
      (:definition-digest (nullable string))
      (:definition-digest-complete boolean)
      (:definition-digest-covers (member :declaration-and-registered-dependencies))
      (:digest-omissions (or (member :not-collected) (list-of t)))
      (:digest-exclusions (or (member :not-collected) (list-of keyword)))
      (:capabilities (plist (:required
                             (:generation (member :available :unavailable :unknown :none))
                             (:shrinking (member :available :unavailable :unknown :none))
                             (:instrumentation (member :available :unavailable :unknown :none)))))
      (:name symbol)
      (:status (member :passed :failed :error :skipped :pending))
      (:trials (range integer 0 *))
      (:budget (nullable (range integer 0 *)))
      (:rejected (range integer 0 *))
      (:seed integer)
      (:profile (member :smoke :normal))
      (:shrunk-outcome (nullable (member :used :none :different-failure)))
      (:elapsed (nullable number)))
     (:optional
      (:failure (nullable result-observation-data))
      (:shrunk-failure (nullable result-observation-data))
      (:failure-phase (nullable keyword))
      (:failure-reason (nullable keyword))
      (:case-report t))))

  (defspec recheck-record-data
    (plist
     (:required
      (:schema-version (member 1))
      (:record-kind (member :recheck))
      (:status (member :same-failure :different-failure :passed :definition-missing
                       :definition-mismatch :incomparable-definition :input-invalid
                       :precondition-rejected :unsupported :contract-error))
      (:name symbol)
      (:entity-kind (member :property :function-spec))
      (:selection (member :original :shrunk))
      (:target-revision t)
      (:failure t))))

  (defspec-function cl-spec:result-data
    "A result record carries the v1 result envelope and the run's evidence."
    (:args (result passing-property-result))
    (:returns result-description-data))

  (defspec-function cl-spec:observation-failure-p
    "Only a failed or signalled observation counts as failure evidence."
    (:args (observation observed-trial))
    (:returns boolean)
    (:post (eq result
               (and (member (cl-spec:trial-observation-status observation)
                            '(:failed :error))
                    t))))

  (defspec-function cl-spec:make-counterexample-artifact
    "A failing result freezes into an artifact carrying its evidence."
    (:args (result failing-property-result))
    (:returns (instance-of cl-spec:counterexample-artifact)))

  (defspec-function cl-spec:recheck-counterexample
    "A saved artifact rechecks into a v1 recheck record."
    (:args (artifact counterexample-artifact-object)
           &key ((:state-policy policy) (member :stateless)))
    (:args-generator recheck-arguments-generator)
    (:returns recheck-record-data)
    (:post (eq :stateless policy)
           (eq :same-failure (getf result :status))))

  (defproperty normalization-is-idempotent ((form generated-form))
    "Normalizing an existing IR object preserves its identity (§9)."
    (:about normalize-spec-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((spec (normalize-spec-form form)))
      (eq spec (normalize-spec-form spec))))
  (defproperty normalization-preserves-source ((form generated-form))
    "Normalization retains the original source form (§9)."
    (:about normalize-spec-form spec-source-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (equal form (spec-source-form (normalize-spec-form form))))
  (defproperty validation-and-explanation-agree
      ((spec spec-object) (value arbitrary-value))
    "VALIDP and structured explanation agree (§10, §21)."
    (:about validp explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (explain-data spec value)))
      (and (eq (validp spec value) (getf data :valid))
           (validp 'explanation-data data))))
  (defproperty compiled-validation-agrees
      ((spec spec-object) (value arbitrary-value))
    "The compiled validator and public validation API agree (§10)."
    (:about compile-validator validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (eq (not (null (funcall (compile-validator spec) value)))
        (validp spec value)))
  (defproperty validation-preserves-values-or-explains-refusal
      ((spec spec-object) (value arbitrary-value))
    "Validation returns its input or reports the same errors as EXPLAIN-DATA (§21)."
    (:about validate explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (explain-data spec value)))
      (handler-case
          (and (eq value (validate spec value)) (getf data :valid))
        (spec-violation (condition)
          (and (not (getf data :valid))
               (eq value (spec-violation-value condition))
               (equal (getf data :errors) (spec-violation-errors condition)))))))
  (defproperty boolean-composition ((value arbitrary-value))
    "AND, OR, and NOT follow boolean semantics for integer and string specs (§9, §68)."
    (:about validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (and (eq (validp
              (normalize-spec-form '(and integer (range -10 10))) value)
             (and (integerp value) (<= -10 value 10)))
         (eq (validp (normalize-spec-form '(or integer string)) value)
             (or (integerp value) (stringp value)))
         (eq (validp (normalize-spec-form '(not integer)) value)
             (not (integerp value)))))
  (defproperty introspection-preserves-spec-semantics ((spec spec-object))
    "SPEC-DATA retains source and kind in its v1 definition envelope (§38.1)."
    (:about spec-data spec-kind spec-source-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (spec-data spec)))
      (and (validp 'spec-description-data data)
           (eq (spec-kind spec) (getf data :kind))
           (equal (spec-source-form spec) (getf data :source-form)))))
  (defproperty digest-details-agree-with-metadata ((definition digest-definition))
    "Digest omissions agree with captured metadata; exclusions do not erase completeness (§38.1)."
    (:about cl-spec:definition-digest cl-spec:definition-metadata)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (multiple-value-bind (digest complete omissions) (cl-spec:definition-digest definition)
      (let ((metadata (cl-spec:definition-metadata definition :capabilities nil)))
        (and (equal digest (getf metadata :definition-digest))
             (eq complete (getf metadata :definition-digest-complete))
             (equal omissions (getf metadata :digest-omissions))
             (digest-details-consistent-p metadata)
             (validp (normalize-spec-form '(list-of digest-omission-data)) omissions)
             (not (null (member :captured-state (getf metadata :digest-exclusions))))))))
  (defproperty rest-projection-agrees-with-target ((seed (range integer 0 1000)))
    "CHECK-FUNCTION binds the whole remaining list exactly as an APPLY target receives it."
    (:about cl-spec:check-function)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((contract
            (make-instance 'cl-spec:function-spec :name 'list
                           :argument-specs '(&rest (tail (list-of integer)))
                           :return-spec 'list
                           :postconditions '((equal result tail))
                           :postcondition-function (lambda (result tail) (equal result tail)))))
      (eq :passed
          (cl-spec:property-result-status
           (cl-spec:check-function contract :trials 5 :seed seed)))))
  (defproperty compiled-explanation-agrees ((spec spec-object) (value arbitrary-value))
    "The compiled explainer reports exactly the errors EXPLAIN-DATA reports (§10, §22)."
    (:about cl-spec:compile-explainer explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let* ((data (explain-data spec value))
           (errors (funcall (compile-explainer spec :context (list :registry cl-spec:*registry*))
                            value nil)))
      (and (eq (getf data :valid) (null errors))
           (equal (getf data :errors) errors))))
  (defproperty explanation-rendering-projects-explain-data
      ((spec spec-object) (value arbitrary-value))
    "EXPLAIN writes the verdict EXPLAIN-DATA computed and returns NIL (§22)."
    (:about cl-spec:explain explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let* ((data (explain-data spec value))
           (returned nil)
           (text (with-output-to-string (stream)
                   (setf returned (cl-spec:explain spec value :stream stream)))))
      (and (null returned)
           (plusp (length text))
           (if (getf data :valid)
               (and (search "satisfies" text) t)
               (and (search "does not satisfy" text)
                    (search "✗" text)
                    t)))))
  (defproperty registry-round-trips-definitions
      ((spec spec-object) (property generated-definition))
    "REGISTER-* then FIND-* returns the object, and LIST-* contains it (§8)."
    (:about cl-spec:register-spec cl-spec:find-spec
            cl-spec:register-property cl-spec:find-property
            cl-spec:register-function-spec cl-spec:find-function-spec
            cl-spec:register-generator cl-spec:find-generator
            cl-spec:list-specs cl-spec:list-properties
            cl-spec:list-function-specs cl-spec:list-generators)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((registry (make-registry-under-test))
          (contract (make-instance 'cl-spec:function-spec :name 'self-contract
                                   :argument-specs '((x integer)) :return-spec 'integer))
          (generator (make-instance 'cl-spec:custom-generator :name 'self-generator
                                    :function (lambda () 1))))
      ;; Each protocol function's documented return value is part of the law:
      ;; a write returns the stored definition, a lookup its definition and T,
      ;; and a lookup of an absent name NIL and NIL.
      (and (eq spec (cl-spec:registry-register-spec registry 'self-spec spec))
           (eq property (cl-spec:registry-register-property registry 'self-property property))
           (eq contract (cl-spec:registry-register-function-spec
                         registry 'self-contract contract))
           (eq generator (cl-spec:registry-register-generator
                          registry 'self-generator generator))
           (multiple-value-call #'found-definition-p
             spec (cl-spec:registry-find-spec registry 'self-spec))
           (multiple-value-call #'found-definition-p
             property (cl-spec:registry-find-property registry 'self-property))
           (multiple-value-call #'found-definition-p
             contract (cl-spec:registry-find-function-spec registry 'self-contract))
           (multiple-value-call #'found-definition-p
             generator (cl-spec:registry-find-generator registry 'self-generator))
           (multiple-value-call #'found-definition-p
             nil (cl-spec:registry-find-spec registry 'self-absent))
           (multiple-value-call #'found-definition-p
             nil (cl-spec:registry-find-property registry 'self-absent))
           (multiple-value-call #'found-definition-p
             nil (cl-spec:registry-find-function-spec registry 'self-absent))
           (multiple-value-call #'found-definition-p
             nil (cl-spec:registry-find-generator registry 'self-absent))
           (member 'self-spec (cl-spec:registry-list-specs registry))
           (member 'self-property (cl-spec:registry-list-properties registry))
           (member 'self-contract (cl-spec:registry-list-function-specs registry))
           (member 'self-generator (cl-spec:registry-list-generators registry)))))
  (defproperty registry-reverse-indexes-track-redefinition ()
    "Re-registering a property retracts its previous target and tag index entries (§8)."
    (:about cl-spec:properties-for cl-spec:properties-with-tag cl-spec:register-property)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let* ((registry (make-registry-under-test))
           (first (make-instance 'cl-spec:property
                                 :name 'self-property
                                 :arguments '((x integer))
                                 :targets '(self-target-a)
                                 :tags '(self-tag-a)
                                 :function (lambda (x) (declare (ignore x)) t)))
           (second (make-instance 'cl-spec:property
                                  :name 'self-property
                                  :arguments '((x integer))
                                  :targets '(self-target-b)
                                  :tags '(self-tag-b)
                                  :function (lambda (x) (declare (ignore x)) t))))
      (cl-spec:register-property first registry)
      (let ((indexed (and (member 'self-property
                                  (cl-spec:properties-for 'self-target-a registry))
                          (member 'self-property
                                  (cl-spec:properties-with-tag 'self-tag-a registry)))))
        (cl-spec:register-property second registry)
        (and indexed
             (null (cl-spec:properties-for 'self-target-a registry))
             (null (cl-spec:properties-with-tag 'self-tag-a registry))
             (member 'self-property (cl-spec:properties-for 'self-target-b registry))
             (member 'self-property
                     (cl-spec:properties-with-tag 'self-tag-b registry))))))
  (defproperty registry-clear-empties ((spec spec-object) (property generated-definition))
    "CLEAR-REGISTRY leaves every index and lookup empty (§8)."
    (:about cl-spec:clear-registry cl-spec:list-specs cl-spec:list-properties
            cl-spec:properties-for cl-spec:properties-with-tag)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((registry (make-registry-under-test)))
      ;; Every definition kind is stored before the clear, so a store the clear
      ;; forgets is observed rather than trivially empty.
      (cl-spec:registry-register-spec registry 'self-spec spec)
      (cl-spec:registry-register-property registry 'self-property property
                                          :targets '(self-target) :tags '(self-tag))
      (cl-spec:registry-register-function-spec registry 'self-contract (self-sort-contract))
      (cl-spec:registry-register-generator registry 'self-generator (self-sort-generator))
      (and (eq registry (cl-spec:registry-clear registry))
           (null (cl-spec:registry-list-specs registry))
           (null (cl-spec:registry-list-properties registry))
           (null (cl-spec:registry-list-function-specs registry))
           (null (cl-spec:registry-list-generators registry))
           (null (cl-spec:registry-properties-for registry 'self-target))
           (null (cl-spec:registry-properties-with-tag registry 'self-tag))
           (not (nth-value 1 (cl-spec:registry-find-spec registry 'self-spec)))
           (not (nth-value 1 (cl-spec:registry-find-property registry 'self-property)))
           (not (nth-value 1 (cl-spec:registry-find-function-spec registry 'self-contract)))
           (not (nth-value 1 (cl-spec:registry-find-generator registry 'self-generator))))))
  (defproperty registry-queries-return-sorted-names ()
    "Every REGISTRY-* list and reverse-index query returns names sorted (§8).

The names are registered out of order, so an implementation answering in
insertion order or its reverse is observed.  They share one home package, so the
expected order is by symbol name alone and is computed here, not by the registry."
    (:about cl-spec:list-specs cl-spec:list-properties cl-spec:list-function-specs
            cl-spec:list-generators cl-spec:properties-for cl-spec:properties-with-tag)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let* ((registry (make-registry-under-test))
           (names '(self-sort-c self-sort-a self-sort-b))
           (expected (sort (copy-list names) #'string< :key #'symbol-name)))
      (dolist (name names)
        (cl-spec:registry-register-spec registry name (normalize-spec-form 'integer))
        (cl-spec:registry-register-function-spec registry name (self-sort-contract name))
        (cl-spec:registry-register-generator registry name (self-sort-generator name))
        (cl-spec:registry-register-property registry name (self-sort-property name)
                                            :targets '(self-sort-target)
                                            :tags '(self-sort-tag)))
      (every (lambda (observed) (equal expected observed))
             (list (cl-spec:registry-list-specs registry)
                   (cl-spec:registry-list-function-specs registry)
                   (cl-spec:registry-list-generators registry)
                   (cl-spec:registry-list-properties registry)
                   (cl-spec:registry-properties-for registry 'self-sort-target)
                   (cl-spec:registry-properties-with-tag registry 'self-sort-tag)))))
  (defproperty registry-writes-replace-by-name ()
    "A second write under a name replaces the first for every definition kind (§8)."
    (:about cl-spec:register-spec cl-spec:register-function-spec cl-spec:register-generator
            cl-spec:find-spec cl-spec:find-function-spec cl-spec:find-generator)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let ((registry (make-registry-under-test))
          (first-spec (normalize-spec-form 'integer))
          (second-spec (normalize-spec-form 'string))
          (first-contract (self-sort-contract))
          (second-contract (self-sort-contract))
          (first-generator (self-sort-generator))
          (second-generator (self-sort-generator)))
      (cl-spec:registry-register-spec registry 'self-spec first-spec)
      (cl-spec:registry-register-function-spec registry 'self-contract first-contract)
      (cl-spec:registry-register-generator registry 'self-generator first-generator)
      (and (eq second-spec (cl-spec:registry-register-spec registry 'self-spec second-spec))
           (eq second-contract (cl-spec:registry-register-function-spec
                                registry 'self-contract second-contract))
           (eq second-generator (cl-spec:registry-register-generator
                                 registry 'self-generator second-generator))
           (multiple-value-call #'found-definition-p
             second-spec (cl-spec:registry-find-spec registry 'self-spec))
           (multiple-value-call #'found-definition-p
             second-contract (cl-spec:registry-find-function-spec registry 'self-contract))
           (multiple-value-call #'found-definition-p
             second-generator (cl-spec:registry-find-generator registry 'self-generator))
           (equal '(self-spec) (cl-spec:registry-list-specs registry))
           (equal '(self-contract) (cl-spec:registry-list-function-specs registry))
           (equal '(self-generator) (cl-spec:registry-list-generators registry)))))
  (defproperty registry-keys-are-symbols-not-names ()
    "Same-named symbols of two packages are distinct entries, listed in package order (§8).

Both names are registered for every definition kind and indexed under one
target and tag.  Each must stay independently findable, and every list and
reverse-index query must order them by name and then by home package name."
    (:about cl-spec:find-spec cl-spec:find-property cl-spec:find-function-spec
            cl-spec:find-generator cl-spec:list-specs cl-spec:list-properties
            cl-spec:list-function-specs cl-spec:list-generators
            cl-spec:properties-for cl-spec:properties-with-tag)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let* ((registry (make-registry-under-test))
           (local 'self-duplicate-item)
           (foreign *foreign-duplicate-name*)
           (expected (sort (list local foreign) #'string<
                           :key (lambda (name)
                                  (package-name (symbol-package name)))))
           (definitions
             (loop for name in (list local foreign)
                   collect (list name
                                 (normalize-spec-form (if (eq name local) 'integer 'string))
                                 (self-sort-contract name)
                                 (self-sort-generator name)
                                 (self-sort-property name)))))
      (dolist (entry definitions)
        (destructuring-bind (name spec contract generator property) entry
          (cl-spec:registry-register-spec registry name spec)
          (cl-spec:registry-register-function-spec registry name contract)
          (cl-spec:registry-register-generator registry name generator)
          (cl-spec:registry-register-property registry name property
                                              :targets '(self-sort-target)
                                              :tags '(self-sort-tag))))
      (and (string= (symbol-name local) (symbol-name foreign))
           (not (eq local foreign))
           (every (lambda (entry)
                    (destructuring-bind (name spec contract generator property) entry
                      (and (multiple-value-call #'found-definition-p
                             spec (cl-spec:registry-find-spec registry name))
                           (multiple-value-call #'found-definition-p
                             contract (cl-spec:registry-find-function-spec registry name))
                           (multiple-value-call #'found-definition-p
                             generator (cl-spec:registry-find-generator registry name))
                           (multiple-value-call #'found-definition-p
                             property (cl-spec:registry-find-property registry name)))))
                  definitions)
           (every (lambda (observed) (equal expected observed))
                  (list (cl-spec:registry-list-specs registry)
                        (cl-spec:registry-list-function-specs registry)
                        (cl-spec:registry-list-generators registry)
                        (cl-spec:registry-list-properties registry)
                        (cl-spec:registry-properties-for registry 'self-sort-target)
                        (cl-spec:registry-properties-with-tag registry 'self-sort-tag))))))
  (defproperty member-admits-exactly-its-values ((value arbitrary-value))
    "A MEMBER spec admits exactly the values EQL to one of its members (§9)."
    (:about validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (eq (validp 'self-member-values value)
        (and (member value '(1 "two" :three) :test #'eql) t)))
  (defproperty collection-validation-is-elementwise ((value arbitrary-value))
    "LIST-OF and VECTOR-OF accept exactly collections of admitted elements (§9)."
    (:about validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (and (eq (validp 'self-integer-list value)
             (and (listp value) (every #'integerp value)))
         (eq (validp 'self-integer-vector value)
             (and (vectorp value) (every #'integerp value)))))
  (defproperty plist-error-paths-identify-the-field ((seed (range integer 0 2)))
    "PLIST field errors name the offending key, and closed records reject unknown keys (§9.2)."
    (:about validp explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (case seed
      (0 (let ((errors (getf (explain-data 'self-record '(:nickname "x")) :errors)))
           (and (not (validp 'self-record '(:nickname "x")))
                (some (lambda (datum) (eq :missing-key (getf datum :kind))) errors)
                (some (lambda (datum) (member :id (getf datum :path))) errors))))
      (1 (let ((errors (getf (explain-data 'self-record '(:id 1 :extra 2)) :errors)))
           (and (some (lambda (datum) (eq :unknown-key (getf datum :kind))) errors)
                (some (lambda (datum) (member :extra (getf datum :path))) errors))))
      (t (and (validp 'self-record '(:id 1 :nickname nil))
              (not (validp 'self-record '(:id "bad")))
              (not (validp 'self-record '(:id 1 :id 2)))))))
  (defproperty malformed-declarations-are-refused ((index (range integer 0 3)))
    "The surface macros refuse malformed declarations at macroexpansion (§17, §37)."
    (:about cl-spec:defspec cl-spec:defspec-function cl-spec:defproperty cl-spec:defgenerator)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((form (nth index '((cl-spec:defproperty self-bad ((x integer) extra) t)
                             (cl-spec:defspec-function self-bad (:unknown-clause 1))
                             (cl-spec:defgenerator self-bad (x) 1)
                             (cl-spec:defproperty self-bad ((x integer)))))))
      (handler-case
          (progn (macroexpand-1 form) nil)
        (cl-spec:invalid-property-form () (member index '(0 3)))
        (cl-spec:invalid-function-spec-form () (= index 1))
        (cl-spec:invalid-generator-form () (= index 2))
        (error () nil))))
  (defproperty run-property-is-reproducible-from-its-seed ((seed (range integer 0 100000)))
    "A run records the seed and profile that replay it to the same status and trials (§15)."
    (:about cl-spec:run-property cl-spec:replay-property)
    (:tags :cl-spec-self)
    (:trials (:smoke 5 :normal 50))
    (let* ((property (make-instance 'cl-spec:property :name 'self-replay-target
                                    :arguments '((x integer))
                                    :function (lambda (x) (declare (ignore x)) t)
                                    :trials '(:normal 10)))
           (first-run (cl-spec:run-property property :seed seed :profile :normal))
           (replay (cl-spec:replay-property property first-run)))
      (and (eq (cl-spec:property-result-status first-run)
               (cl-spec:property-result-status replay))
           (= (cl-spec:property-result-trials first-run)
              (cl-spec:property-result-trials replay))
           (eql (cl-spec:property-result-seed first-run)
                (cl-spec:property-result-seed replay)))))
  (defproperty failure-identities-match-reflexively ((observation observed-trial))
    "An observed failure identity matches itself (§14)."
    (:about cl-spec:failure-identities-match-p)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((signature (cl-spec:trial-observation-signature observation)))
      (or (null signature)
          (cl-spec:failure-identities-match-p signature signature))))
  (defproperty counterexample-artifacts-round-trip ((seed (range integer 0 1000)))
    "A saved artifact serializes, deserializes and preserves its recorded evidence (§73.4)."
    (:about cl-spec:make-counterexample-artifact cl-spec:serialize-counterexample-artifact
            cl-spec:deserialize-counterexample-artifact cl-spec:counterexample-artifact-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 5 :normal 50))
    (let* ((property (make-instance 'cl-spec:property :name 'self-failing-target
                                    :arguments '((x integer))
                                    :function (lambda (x) (declare (ignore x)) nil)
                                    :trials '(:normal 5)))
           (result (cl-spec:run-property property :seed seed :profile :normal))
           (artifact (cl-spec:make-counterexample-artifact result))
           (wire (cl-spec:serialize-counterexample-artifact artifact))
           (restored (cl-spec:deserialize-counterexample-artifact wire)))
      (equal (cl-spec:counterexample-artifact-data artifact)
             (cl-spec:counterexample-artifact-data restored))))
  (defproperty collection-constraints-are-enforced ()
    "LIST-OF length and uniqueness constraints are enforced as declared (§9)."
    (:about validp explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((bounded (normalize-spec-form '(list-of integer :min-length 2 :max-length 3)))
          (distinct (normalize-spec-form '(list-of integer :unique t))))
      (and (not (validp bounded '(1)))
           (validp bounded '(1 2))
           (validp bounded '(1 2 3))
           (not (validp bounded '(1 2 3 4)))
           (not (validp distinct '(1 1)))
           (validp distinct '(1 2))
           (eq :too-short (getf (first (getf (explain-data bounded '(1)) :errors)) :kind))
           (eq :duplicate-element
               (getf (first (getf (explain-data distinct '(1 1)) :errors)) :kind)))))
  (defproperty generated-values-satisfy-their-specs ()
    "Every value a built-in generator draws satisfies the spec it came from (§9, §12)."
    (:about cl-spec:sample cl-spec:generator-for)
    (:tags :cl-spec-self)
    (:trials (:smoke 5 :normal 50))
    (every (lambda (spec)
             (every (lambda (value) (validp spec value))
                    (cl-spec:sample spec :count 10)))
           *generation-corpus*))
  (defproperty sample-reports-its-generation-request ()
    "SAMPLE returns values plus one coherent report for a shared request (§12, §14)."
    (:about cl-spec:sample)
    (:tags :cl-spec-self)
    (:trials (:smoke 5 :normal 20))
    (let ((spec (normalize-spec-form '(and (plist (:required (:v integer)))
                                           (satisfies identity)))))
      (multiple-value-bind (values report) (cl-spec:sample spec :count 8 :seed 11)
        (and (= 8 (length values))
             (every (lambda (value) (validp spec value)) values)
             (eq :request (getf report :scope))
             (eq :bounded-filter-source-call (getf report :unit))
             (eq :completed (getf report :termination))
             (= 8 (getf report :generated-values))
             (= 8 (getf report :requested-values))
             (<= (getf report :rejections) (getf report :attempts))
             (<= (getf report :attempts) (getf report :budget))))))
  (defproperty retained-counterexamples-stay-valid ((seed (range integer 0 1000)))
    "A retained shrunk counterexample is schema-valid and still fails identically (§14, §15)."
    (:about cl-spec:make-counterexample-artifact cl-spec:recheck-counterexample)
    (:tags :cl-spec-self)
    (:trials (:smoke 5 :normal 50))
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec:defspec-function self-collection-counterexample-target
        (:args (items (list-of (member 1 2 3) :min-length 2 :max-length 3 :unique t)))
        (:returns list)
        (:post (and result (not result))))
      (cl-spec:defspec-function self-keyword-counterexample-target
        (:args &rest (raw (list-of t :min-length 2 :max-length 2))
               &key ((:a a) null))
        (:returns list)
        (:post (and result (not result))))
      (every (lambda (name)
               (let* ((contract (cl-spec:find-function-spec name))
                      (result (cl-spec:check-function name :trials 5 :seed seed))
                      (arguments
                        (cl-spec:trial-observation-arguments
                         (or (cl-spec:property-result-shrunk-evidence result)
                             (cl-spec:property-result-failure-evidence result)))))
                 (and (eq :failed (cl-spec:property-result-status result))
                      (cl-spec:validp (cl-spec:function-spec-argument-schema contract)
                                      arguments)
                      (eq :same-failure
                          (getf (cl-spec:recheck-counterexample
                                 (cl-spec:make-counterexample-artifact result)
                                 :registry cl-spec:*registry*
                                 :state-policy :stateless)
                                :status)))))
             '(self-collection-counterexample-target
               self-keyword-counterexample-target))))
  (defproperty validate-cases-classify-admitted-and-refused ()
    "The named cases run an explicit admitted/refused sequence through VALIDATE."
    (:about validate)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let ((*scripted-validate-inputs*
            '((integer 0) (integer "refused") (string "ok") (string 3)
              (integer 1) (integer :refused) (boolean t) (boolean 42))))
      (let* ((result (cl-spec:check-function 'validate :trials 4 :seed 1))
             (report (cl-spec:function-check-result-case-report result)))
        (and (eq :passed (cl-spec:property-result-status result))
             (= 4 (cl-spec:property-result-trials result))
             (zerop (cl-spec:property-result-rejected result))
             (equal '(:conforming :refused) (getf report :declared-cases))
             (null (getf report :never-called))
             (zerop (getf report :case-selection-errors))
             (zerop (getf report :capture-errors))
             (equal '(2 2)
                    (mapcar (lambda (case) (getf case :called)) (getf report :cases)))
             (equal '(2 2)
                    (mapcar (lambda (case) (getf case :passed))
                            (getf report :cases)))))))
  (defproperty registration-replacement-preserves-unrelated-indexes ()
    "A same-name write retracts only the subject's stale keys and keeps the sentinel's."
    (:about cl-spec:registry-register-property cl-spec:properties-for
            cl-spec:properties-with-tag)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let* ((registry (make-registry-under-test))
           (subject (self-registration-name :subject))
           (sentinel (self-registration-name :sentinel))
           (shared-target (self-registration-name :shared-target))
           (old-target (self-registration-name :old-target))
           (new-target (self-registration-name :new-target))
           (shared-tag (self-registration-name :shared-tag))
           (old-tag (self-registration-name :old-tag))
           (new-tag (self-registration-name :new-tag))
           (first (make-instance 'cl-spec:property :name subject
                                 :arguments '((x integer))
                                 :function (lambda (x) (declare (ignore x)) t)))
           (second (make-instance 'cl-spec:property :name subject
                                  :arguments '((x integer))
                                  :function (lambda (x) (declare (ignore x)) t))))
      (cl-spec:registry-register-property registry sentinel
        (make-instance 'cl-spec:property :name sentinel :arguments '((x integer))
                       :function (lambda (x) (declare (ignore x)) t))
        :targets (list shared-target) :tags (list shared-tag))
      (cl-spec:registry-register-property registry subject first
        :targets (list shared-target old-target)
        :tags (list shared-tag old-tag))
      (let ((before (cl-spec:registry-list-properties registry)))
        (cl-spec:registry-register-property registry subject second
          :targets (list new-target shared-target)
          :tags (list new-tag shared-tag))
        (and (eq second (nth-value 0 (cl-spec:registry-find-property registry subject)))
             (= (length before) (length (cl-spec:registry-list-properties registry)))
             (null (set-exclusive-or before (cl-spec:registry-list-properties registry)))
             (null (cl-spec:properties-for old-target registry))
             (member subject (cl-spec:properties-for new-target registry))
             (member subject (cl-spec:properties-for shared-target registry))
             (member sentinel (cl-spec:properties-for shared-target registry))
             (null (cl-spec:properties-with-tag old-tag registry))
             (member subject (cl-spec:properties-with-tag new-tag registry))
             (member sentinel (cl-spec:properties-with-tag shared-tag registry))))))
  (defproperty function-spec-projection-retains-declared-state ()
    "FUNCTION-SPEC-DATA keeps declared cases, guards, capture and per-case state-post."
    (:about cl-spec:function-spec-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let* ((fixtures (function-projection-fixtures))
           (registry (getf fixtures :registry))
           (expected *function-projection-expectations*)
           (plain (cl-spec:function-spec-data (getf fixtures :plain) :registry registry))
           (cases (cl-spec:function-spec-data (getf fixtures :cases) :registry registry))
           (state (cl-spec:function-spec-data (getf fixtures :state) :registry registry))
           (declared (getf cases :cases))
           (declared-state (getf state :cases)))
      (and
       ;; A contract that declares none of the clauses invents none of the keys.
       (null (getf plain :capture))
       (null (getf plain :state-post))
       (null (getf plain :cases))
       (null (getf plain :case-selection))
       ;; Case names, order, guards and outcomes survive the projection.  The
       ;; expectations carry the fixture's own symbols, so EQUAL checks symbol
       ;; identity; a same-named symbol from another package is rejected.
       (eq (getf expected :case-selection) (getf cases :case-selection))
       (equal (getf expected :case-names)
              (mapcar (lambda (case) (getf case :name)) declared))
       (equal (getf expected :case-outcomes)
              (mapcar (lambda (case) (getf case :outcome)) declared))
       (equal (getf expected :admitted-when) (getf (first declared) :when))
       (equal (getf expected :refused-when) (getf (second declared) :when))
       (equal (getf expected :admitted-postconditions)
              (getf (first declared) :postconditions))
       (null (getf (first declared) :state-post))
       ;; Capture names, order and source form survive, on the contract not the case.
       (equal (getf expected :state-capture) (getf state :capture))
       (null (getf state :state-post))
       ;; The case state-post stays attached to the case that declared it.
       (equal (getf expected :state-case-state-post)
              (getf (first declared-state) :state-post))
       (null (getf (second declared-state) :state-post)))))
  (defproperty result-projection-retains-state-evidence ()
    "RESULT-DATA keeps a state-post violation, a capture error and a stopped case."
    (:about cl-spec:result-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let* ((fixtures (state-projection-fixtures))
           (registry (getf fixtures :registry))
           (expected *state-projection-expectations*)
           (*self-state-balance* 10)
           (*self-state-calls* 0)
           (*self-state-scenario* :correct)
           (*scripted-state-inputs* nil))
      (flet ((run (name scenario amount)
               (setf *self-state-balance* 10 *self-state-calls* 0
                     *self-state-scenario* scenario
                     *scripted-state-inputs* (list amount))
               (values (cl-spec:check-function name :trials 1 :seed 1 :registry registry)
                       *self-state-calls*)))
        (multiple-value-bind (violation violation-calls)
            (run (getf fixtures :observed) :forget 3)
          (multiple-value-bind (capture capture-calls)
              (run (getf fixtures :capture) :correct 3)
            (multiple-value-bind (selection selection-calls)
                (run (getf fixtures :uncalled) :correct 3)
              (let* ((violation-data (cl-spec:result-data violation))
                     (violation-state (getf (getf violation-data :failure) :state))
                     (capture-data (cl-spec:result-data capture))
                     (capture-state (getf (getf capture-data :failure) :state))
                     (selection-data (cl-spec:result-data selection))
                     (selection-state (getf (getf selection-data :failure) :state)))
                (and
                 ;; A violated state-post is retained, with its binding and form position.
                 (eq :failed (getf violation-data :status))
                 (eq :state-post (getf violation-data :failure-phase))
                 (eq :state-postcondition (getf violation-data :failure-reason))
                 (eq :violation (getf (getf violation-state :state-post) :status))
                 (eq 0 (getf (getf violation-state :state-post) :index))
                 ;; A captured NIL is present with a NIL value; a binding whose
                 ;; form never ran is declared but absent from :VALUES.  The
                 ;; expectation holds the fixture's own symbols, so EQUAL checks
                 ;; symbol identity, not just the printed name.
                 (equal (getf expected :values)
                        (getf (getf violation-state :capture) :values))
                 (equal (getf expected :declared)
                        (getf (getf violation-state :capture) :declared))
                 (= 1 violation-calls)
                 ;; A capture error keeps the failure, names the binding, calls no target.
                 (eq :error (getf capture-data :status))
                 (eq :capture (getf capture-data :failure-phase))
                 (eq :error (getf (getf capture-state :capture) :status))
                 (equal (getf expected :declared)
                        (getf (getf capture-state :capture) :declared))
                 (null (getf (getf capture-state :capture) :values))
                 (equal (getf expected :capture-error-binding)
                        (getf (getf (getf capture-state :capture) :error) :binding))
                 (null (getf capture-state :state-post))
                 (zerop capture-calls)
                 ;; A stopped case is not a pass: the declared state-post says so.
                 (eq :error (getf selection-data :status))
                 (eq :case-selection (getf selection-data :failure-phase))
                 (eq :not-evaluated (getf (getf selection-state :state-post) :status))
                 (eq :case-selection-failed (getf (getf selection-state :state-post) :reason))
                 (zerop selection-calls)
                 ;; The strengthened evidence schema accepts the real records the
                 ;; evaluator produced, not only hand-written lookalikes.
                 (let ((result-spec
                         (cl-spec:function-spec-return-spec
                          (cl-spec:find-function-spec 'cl-spec:result-data))))
                   (and (cl-spec:validp result-spec violation-data)
                        (cl-spec:validp result-spec capture-data)
                        (cl-spec:validp result-spec selection-data)))))))))))
  (defproperty one-shot-check-reuses-the-single-trial-classifier ()
    "CHECK-CALL classifies one concrete invocation with the shared trial path."
    (:about cl-spec:check-call cl-spec:call-check-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    ;; Anonymous contracts are accepted directly as designators, so the law
    ;; needs no registration and cannot collide with another definition.
    (let* ((passing-contract
             (make-instance 'cl-spec:function-spec :name 'list
                            :argument-specs '((x integer))
                            :return-spec 'list
                            :postconditions '((equal result (list x)))
                            :postcondition-function (lambda (result x)
                                                      (equal result (list x)))))
           (failing-contract
             (make-instance 'cl-spec:function-spec :name 'list
                            :argument-specs '((x integer))
                            :return-spec 'string))
           (refusing-contract
             (make-instance 'cl-spec:function-spec :name 'list
                            :argument-specs '((x integer))
                            :return-spec 'list
                            :preconditions '((> x 100))
                            :precondition-function (lambda (x) (> x 100))))
           (passing (cl-spec:check-call passing-contract (list 5)))
           (failing (cl-spec:check-call failing-contract (list 5)))
           (rejected (cl-spec:check-call refusing-contract (list 5)))
           (data (cl-spec:call-check-data passing)))
      (and (eq :passed (cl-spec:call-check-result-status passing))
           (equal '(5) (cl-spec:trial-observation-value
                        (cl-spec:call-check-result-observation passing)))
           (equal '(5) (cl-spec:call-check-result-arguments passing))
           (eq :result (getf data :record-kind))
           (eq :function-spec (getf data :entity-kind))
           (eq :passed (getf data :status))
           (equal '(5) (getf data :arguments))
           (eq :passed (getf (getf data :observation) :status))
           (member (getf data :definition-digest-complete) '(t nil))
           (eq :failed (cl-spec:call-check-result-status failing))
           (eq :return-spec (cl-spec:trial-observation-reason
                             (cl-spec:call-check-result-observation failing)))
           (eq :rejected (cl-spec:call-check-result-status rejected))
           (null (cl-spec:trial-observation-reason
                  (cl-spec:call-check-result-observation rejected))))))
  (defproperty one-shot-check-observes-a-named-case-and-state-once
      ((amount (range integer 1 10)))
    "CHECK-CALL selects one case and checks captured state after one call."
    (:about cl-spec:check-call cl-spec:call-check-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 1 :normal 2))
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      ;; The target is the counting fixture; the contract is declared here so
      ;; the law reads a named case and a state-post it wrote itself.
      (cl-spec:defspec-function self-state-observed-target
        (:args (amount (range integer 1 10)))
        (:capture (before *self-state-balance*))
        (:cases
         (:observed
          (:when (>= amount 1))
          (:returns integer)
          (:post (= result amount))
          (:state-post (= *self-state-balance* (- before amount))))))
      (let ((*self-state-balance* 30)
            (*self-state-calls* 0)
            (*self-state-scenario* :correct))
        (let* ((passing (cl-spec:check-call 'self-state-observed-target (list amount)))
               (observation (cl-spec:call-check-result-observation passing))
               (state (cl-spec:trial-observation-state observation)))
          (and (eq :passed (cl-spec:call-check-result-status passing))
               (eq :observed (cl-spec:trial-observation-case observation))
               (= 1 *self-state-calls*)
               (eq :completed (getf (getf state :capture) :status))
               (eq :passed (getf (getf state :state-post) :status))
               (let ((*self-state-balance* 30)
                     (*self-state-calls* 0)
                     (*self-state-scenario* :forget))
                 (let* ((failing (cl-spec:check-call 'self-state-observed-target
                                                     (list amount)))
                        (failing-observation (cl-spec:call-check-result-observation failing))
                        (failing-state (cl-spec:trial-observation-state failing-observation))
                        (data (cl-spec:call-check-data failing)))
                   (and (eq :failed (cl-spec:call-check-result-status failing))
                        (eq :state-post (cl-spec:call-check-result-failure-phase failing))
                        (eq :state-postcondition (cl-spec:trial-observation-reason
                                                  failing-observation))
                        (eq :violation (getf (getf failing-state :state-post) :status))
                        (= 1 *self-state-calls*)
                        (eq :failed (getf data :status))
                        (eq :state-post (getf data :failure-phase))
                        (eq :failed (getf (getf data :observation) :status))))))))))
  (values (contract-names) (property-names)))

(register-specifications)
