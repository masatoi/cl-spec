;;;; specs.lisp

(defpackage #:cl-spec/specs
  (:use #:cl)
  (:import-from #:cl-spec/src/registry #:hash-table-registry #:registry-find-spec)
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
                #:function-projection-fixtures
                #:registration-index-shape-p
                #:registration-scenario
                #:registration-scenario-tags-p
                #:registration-scenario-targets-p
                #:self-registration-name
                #:*self-state-balance*
                #:*self-state-calls*
                #:*self-state-scenario*
                #:state-projection-fixtures
                #:validate-corpus-entry)
  (:export #:register-instrumentation-specifications #:register-specifications
           #:contract-names #:property-names))

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
  '(validp validate explain-data compile-validator
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
    registry-clear-empties member-admits-exactly-its-values
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
    result-projection-retains-state-evidence))

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

(defun register-specifications ()
  "Install executable contracts and laws in CL-SPEC:*REGISTRY*.
Loading CL-SPEC/SPECS installs these once. Call this function again after
CLEAR-REGISTRY or with a freshly bound registry. It does not instrument functions.
Generators exercise finite subsets. Most API contracts accept broader domains;
the malformed-normalization contract and the validate cases explicitly name
their finite input corpora, and the registry write contract names its scenarios."
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
  (defgenerator registry-generator () (cl-spec:make-hash-table-registry))
  (defspec registry-object (instance-of hash-table-registry)
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

  (defspec capture-evidence-data
    (plist
     (:required
      (:status (member :completed :error :not-evaluated))
      (:declared (list-of symbol))
      (:values (nullable (list-of t))))
     (:optional
      (:error (nullable
               (plist (:required (:binding symbol) (:index (range integer 0 *))
                                 (:condition-type symbol))))))))

  (defspec state-post-evidence-data
    (plist
     (:required (:status (member :passed :violation :error :not-evaluated)))
     (:optional (:reason t) (:case t) (:index t) (:form t) (:condition-type t))))

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

  (defgenerator registry-registration-arguments ()
    ;; A fresh scenario per draw: a new registry, a sentinel property sharing a
    ;; target and a tag with the subject, and a new, replacement or refused write.
    (registration-scenario))

  (defspec-function cl-spec:registry-register-property
    "A property write adds, replaces or refuses without leaking stale index entries.

The declared input domain is the finite scenario set REGISTRATION-SCENARIO
produces, not every index list: the state-post names the scenario's fixed target
and tag symbols, so a different valid list is outside this contract rather than a
counterexample.  Within that domain the expected after-state follows from the
input and the observed before-state, and every observation is a fresh list from a
public reader, never a captured registry."
    (:args (registry (instance-of cl-spec:hash-table-registry)) (name symbol)
           (property (instance-of cl-spec:property))
           &key ((:targets targets) (satisfies registration-scenario-targets-p))
                ((:tags tags) (satisfies registration-scenario-tags-p)))
    (:args-generator registry-registration-arguments)
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
       (eq sentinel-before
           (nth-value 0 (cl-spec:registry-find-property
                         registry (self-registration-name :sentinel))))
       (equal old-target-before
              (cl-spec:registry-properties-for
               registry (self-registration-name :old-target)))
       (equal new-target-before
              (cl-spec:registry-properties-for
               registry (self-registration-name :new-target)))
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
       (member name
               (cl-spec:registry-properties-for
                registry (self-registration-name :new-target)))
       (member name
               (cl-spec:registry-properties-for
                registry (self-registration-name :shared-target)))
       (member (self-registration-name :sentinel)
               (cl-spec:registry-properties-for
                registry (self-registration-name :shared-target)))
       (null new-target-before)
       (member name
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :new-tag)))
       (member name
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :shared-tag)))
       (member (self-registration-name :sentinel)
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :shared-tag)))
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
       (null (cl-spec:registry-properties-for
              registry (self-registration-name :old-target)))
       (null (cl-spec:registry-properties-with-tag
              registry (self-registration-name :old-tag)))
       (member name
               (cl-spec:registry-properties-for
                registry (self-registration-name :new-target)))
       (member name
               (cl-spec:registry-properties-for
                registry (self-registration-name :shared-target)))
       (member (self-registration-name :sentinel)
               (cl-spec:registry-properties-for
                registry (self-registration-name :shared-target)))
       (member name
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :new-tag)))
       (member name
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :shared-tag)))
       (member (self-registration-name :sentinel)
               (cl-spec:registry-properties-with-tag
                registry (self-registration-name :shared-tag)))
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
    (let ((registry (cl-spec:make-hash-table-registry))
          (contract (make-instance 'cl-spec:function-spec :name 'self-contract
                                   :argument-specs '((x integer)) :return-spec 'integer))
          (generator (make-instance 'cl-spec:custom-generator :name 'self-generator
                                    :function (lambda () 1))))
      (cl-spec:registry-register-spec registry 'self-spec spec)
      (cl-spec:registry-register-property registry 'self-property property)
      (cl-spec:registry-register-function-spec registry 'self-contract contract)
      (cl-spec:registry-register-generator registry 'self-generator generator)
      (and (eq spec (nth-value 0 (cl-spec:registry-find-spec registry 'self-spec)))
           (nth-value 1 (cl-spec:registry-find-spec registry 'self-spec))
           (eq property (nth-value 0 (cl-spec:registry-find-property registry 'self-property)))
           (eq contract (nth-value 0 (cl-spec:registry-find-function-spec registry 'self-contract)))
           (eq generator (nth-value 0 (cl-spec:registry-find-generator registry 'self-generator)))
           (member 'self-spec (cl-spec:registry-list-specs registry))
           (member 'self-property (cl-spec:registry-list-properties registry))
           (member 'self-contract (cl-spec:registry-list-function-specs registry))
           (member 'self-generator (cl-spec:registry-list-generators registry)))))
  (defproperty registry-reverse-indexes-track-redefinition ()
    "Re-registering a property retracts its previous target and tag index entries (§8)."
    (:about cl-spec:properties-for cl-spec:properties-with-tag cl-spec:register-property)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let* ((registry (cl-spec:make-hash-table-registry))
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
    (let ((registry (cl-spec:make-hash-table-registry)))
      (cl-spec:registry-register-spec registry 'self-spec spec)
      (cl-spec:registry-register-property registry 'self-property property
                                          :targets '(self-target) :tags '(self-tag))
      (cl-spec:registry-clear registry)
      (and (null (cl-spec:registry-list-specs registry))
           (null (cl-spec:registry-list-properties registry))
           (null (cl-spec:registry-properties-for registry 'self-target))
           (null (cl-spec:registry-properties-with-tag registry 'self-tag))
           (not (nth-value 1 (cl-spec:registry-find-spec registry 'self-spec)))
           (not (nth-value 1 (cl-spec:registry-find-property registry 'self-property))))))
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
    (let* ((registry (cl-spec:make-hash-table-registry))
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
                 (zerop selection-calls)))))))))
  (values (contract-names) (property-names)))

(register-specifications)
