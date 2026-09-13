;;;; specs.lisp

(defpackage #:cl-spec/specs
  (:use #:cl)
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

(defun draw-form ()
  "Draw a finite DSL example spanning scalar and composite specs."
  (let ((bound (1+ (random 20))))
    (case (random 9)
      (0 'integer) (1 'string) (2 `(range integer ,(- bound) ,bound))
      (3 `(and integer (range ,(- bound) ,bound)))
      (4 '(or integer string)) (5 '(not integer))
      (6 '(nullable integer)) (7 '(list-of integer))
      (8 '(tuple integer string)))))

(defparameter *sampled-dsl-forms*
  (append '(integer string (or integer string) (not integer) (nullable integer)
            (list-of integer) (tuple integer string))
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

(defun contract-names ()
  "Return the public functions covered by this executable specification bundle."
  '(validp validate explain-data compile-validator
    compile-explainer spec-data semantic-data normalize-spec-form
    cl-spec:deserialize-counterexample-artifact cl-spec:validate-definition))

(defun property-names ()
  "Return the executable semantic laws in this specification bundle."
  '(normalization-is-idempotent normalization-preserves-source
    validation-and-explanation-agree compiled-validation-agrees
    validation-preserves-values-or-explains-refusal boolean-composition
    introspection-preserves-spec-semantics))

(defun register-instrumentation-specifications ()
  "Register the optional status API contract after CL-SPEC/INSTRUMENT is loaded.
Return its name. This bundle never loads the instrumentation system itself."
  (let* ((package (find-package "CL-SPEC/INSTRUMENT"))
         (name (and package (find-symbol "INSTRUMENTATION-STATUS" package))))
    (unless (and name (fboundp name))
      (error "Load CL-SPEC/INSTRUMENT before registering its specifications."))
    (cl-spec:register-function-spec
     (make-instance
      'cl-spec:function-spec :name name
      :argument-specs '((name (member uninstalled-self-target)))
      :return-spec
      '(plist (:required
                (:status (member :not-installed :current :stale :indeterminate))
                (:reasons (list-of keyword))
                (:dependency-status (member :unchanged :changed :indeterminate))))
      :source-form '(instrumentation-status-shape)
      :documentation "Instrumentation status always identifies freshness and comparison limits."))
    name))

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
  (defspec spec-description-data
    (plist
      (:required
        (:schema-version (member 1))
        (:record-kind (member :definition))
        (:entity-kind (member :spec))
        (:kind keyword)
        (:source-form t)
        (:definition-digest string)
        (:definition-digest-complete boolean)
        (:definition-digest-covers (member :declaration-and-registered-dependencies))
        (:capabilities
          (plist (:required
                   (:generation (member :available :unavailable :unknown :none))
                   (:shrinking (member :available :unavailable :unknown :none))
                   (:instrumentation (member :available :unavailable :unknown :none))))))))
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
  (values (contract-names) (property-names)))

(register-specifications)
