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
    generated-values-satisfy-their-specs retained-counterexamples-stay-valid))

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
the malformed-normalization contract explicitly names its finite input corpus."
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
  (defgenerator valid-arguments-generator ()
    (let* ((value (draw-value))
           (form (typecase value
                   (integer `(range integer ,value ,value))
                   (string 'string)
                   (null 'null)
                   (cons (if (= 1 (length value))
                             '(list-of integer) '(tuple integer string)))
                   (vector '(vector-of integer))
                   (t 'boolean))))
      (list (normalize-spec-form form) value)))
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
  (defspec-function validate
    "Successful validation returns the identical value; refusal is specified by a Property."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:args-generator valid-arguments-generator)
    (:pre (validp contract-spec value))
    (:returns t)
    (:post (eq result value)))
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
           (:metadata t)))))

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
      (:elapsed (nullable number)))))

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
  (values (contract-names) (property-names)))

(register-specifications)
