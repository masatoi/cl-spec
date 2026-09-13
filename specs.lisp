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
  (:export #:register-specifications #:contract-names #:property-names))

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

(defun sampled-dsl-form-p (form)
  "Recognize exactly the finite DSL subset used by the normalization laws.
Malformed lists must not enter a law that promises normalization succeeds."
  (or (member form '(integer string))
      (member form '((or integer string) (not integer) (nullable integer)
                     (list-of integer) (tuple integer string))
              :test #'equal)
      (loop for bound from 1 to 20
            thereis (or (equal form `(range integer ,(- bound) ,bound))
                        (equal form `(and integer (range ,(- bound) ,bound)))))))

(defun draw-value ()
  "Draw heterogeneous finite values, including mismatches for generated specs."
  (let ((integer (- (random 61) 30)))
    (case (random 7)
      (0 integer) (1 nil) (2 t) (3 (make-string (random 6) :initial-element #\x))
      (4 (list integer)) (5 (list integer "x")) (6 (vector integer)))))

(defun resolved-designator-p (value)
  "Recognize spec objects and names currently registered as specs."
  (or (typep value 'cl-spec:spec)
      (and (symbolp value) (nth-value 1 (cl-spec:find-spec value)))))

(defun explanation-consistent-p (value)
  "Check the relation between validity and errors after field validation."
  (eq (getf value :valid) (null (getf value :errors))))

(defun contract-names ()
  "Return the public functions covered by this executable specification bundle."
  '(cl-spec:validp cl-spec:validate cl-spec:explain-data cl-spec:compile-validator
    cl-spec:compile-explainer cl-spec:spec-data cl-spec:semantic-data))

(defun property-names ()
  "Return the executable semantic laws in this specification bundle."
  '(normalization-is-idempotent normalization-preserves-source
    validation-and-explanation-agree compiled-validation-agrees
    validation-preserves-values-or-explains-refusal boolean-composition
    introspection-preserves-spec-semantics))

(defun register-specifications ()
  "Install executable contracts and laws in CL-SPEC:*REGISTRY*.
Loading CL-SPEC/SPECS installs these once. Call this function again after
CLEAR-REGISTRY or with a freshly bound registry. It does not instrument functions.
Generators exercise a finite subset; the API contracts accept broader domains."
  (cl-spec:defgenerator form-generator () (draw-form))
  (cl-spec:defgenerator value-generator () (draw-value))
  (cl-spec:defgenerator spec-generator () (cl-spec:normalize-spec-form (draw-form)))
  (cl-spec:defgenerator symbol-generator ()
    (nth (random 4) '(cl-spec:validp unknown-self-name nil :keyword)))
  (cl-spec:defgenerator valid-arguments-generator ()
    (let* ((value (draw-value))
           (form (typecase value
                   (integer `(range integer ,value ,value))
                   (string 'string)
                   (null 'null)
                   (cons (if (= 1 (length value))
                             '(list-of integer) '(tuple integer string)))
                   (vector '(vector-of integer))
                   (t 'boolean))))
      (list (cl-spec:normalize-spec-form form) value)))
  (cl-spec:defspec generated-form (satisfies sampled-dsl-form-p) (:generator form-generator))
  (cl-spec:defspec arbitrary-value t (:generator value-generator))
  (cl-spec:defspec spec-object (instance-of cl-spec:spec) (:generator spec-generator))
  (cl-spec:defspec resolved-designator (satisfies resolved-designator-p)
    (:generator spec-generator))
  (cl-spec:defspec arbitrary-symbol symbol (:generator symbol-generator))
  (cl-spec:defspec explanation-data
    (and (plist (:required (:spec t) (:value t) (:valid boolean)
                           (:errors (list-of t)) (:path (list-of t))))
         (satisfies explanation-consistent-p)))
  (cl-spec:defspec spec-description-data
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
  (cl-spec:defspec-function cl-spec:validp
    "Validity is a boolean for a resolved spec and an arbitrary value."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:returns boolean))
  (cl-spec:defspec-function cl-spec:explain-data
    "Explanation preserves the checked value and agrees with validity."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:returns explanation-data)
    (:post (eq value (getf result :value))
           (eq (cl-spec:validp contract-spec value) (getf result :valid))))
  (cl-spec:defspec-function cl-spec:validate
    "Successful validation returns the identical value; refusal is specified by a Property."
    (:args (contract-spec resolved-designator) (value arbitrary-value))
    (:args-generator valid-arguments-generator)
    (:pre (cl-spec:validp contract-spec value))
    (:returns t)
    (:post (eq result value)))
  (cl-spec:defspec-function cl-spec:compile-validator
    (:args (contract-spec spec-object))
    (:returns function))
  (cl-spec:defspec-function cl-spec:compile-explainer
    (:args (contract-spec spec-object))
    (:returns function))
  (cl-spec:defspec-function cl-spec:spec-data
    (:args (contract-spec resolved-designator))
    (:returns spec-description-data))
  (cl-spec:defspec-function cl-spec:semantic-data
    (:args (name arbitrary-symbol))
    (:returns list)
    (:post (eq name (getf result :symbol))
           (equal (getf result :properties-about) (cl-spec:properties-for name))))
  (cl-spec:defproperty normalization-is-idempotent ((form generated-form))
    "Normalizing an existing IR object preserves its identity (§9)."
    (:about cl-spec:normalize-spec-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((spec (cl-spec:normalize-spec-form form)))
      (eq spec (cl-spec:normalize-spec-form spec))))
  (cl-spec:defproperty normalization-preserves-source ((form generated-form))
    "Normalization retains the original source form (§9)."
    (:about cl-spec:normalize-spec-form cl-spec:spec-source-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (equal form (cl-spec:spec-source-form (cl-spec:normalize-spec-form form))))
  (cl-spec:defproperty validation-and-explanation-agree
      ((spec spec-object) (value arbitrary-value))
    "VALIDP and structured explanation agree (§10, §21)."
    (:about cl-spec:validp cl-spec:explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (cl-spec:explain-data spec value)))
      (and (eq (cl-spec:validp spec value) (getf data :valid))
           (cl-spec:validp 'explanation-data data))))
  (cl-spec:defproperty compiled-validation-agrees
      ((spec spec-object) (value arbitrary-value))
    "The compiled validator and public validation API agree (§10)."
    (:about cl-spec:compile-validator cl-spec:validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (eq (not (null (funcall (cl-spec:compile-validator spec) value)))
        (cl-spec:validp spec value)))
  (cl-spec:defproperty validation-preserves-values-or-explains-refusal
      ((spec spec-object) (value arbitrary-value))
    "Validation returns its input or reports the same errors as EXPLAIN-DATA (§21)."
    (:about cl-spec:validate cl-spec:explain-data)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (cl-spec:explain-data spec value)))
      (handler-case
          (and (eq value (cl-spec:validate spec value)) (getf data :valid))
        (cl-spec:spec-violation (condition)
          (and (not (getf data :valid))
               (eq value (cl-spec:spec-violation-value condition))
               (equal (getf data :errors) (cl-spec:spec-violation-errors condition)))))))
  (cl-spec:defproperty boolean-composition ((value arbitrary-value))
    "AND, OR, and NOT follow boolean semantics for integer and string specs (§9, §68)."
    (:about cl-spec:validp)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (and (eq (cl-spec:validp
              (cl-spec:normalize-spec-form '(and integer (range -10 10))) value)
             (and (integerp value) (<= -10 value 10)))
         (eq (cl-spec:validp (cl-spec:normalize-spec-form '(or integer string)) value)
             (or (integerp value) (stringp value)))
         (eq (cl-spec:validp (cl-spec:normalize-spec-form '(not integer)) value)
             (not (integerp value)))))
  (cl-spec:defproperty introspection-preserves-spec-semantics ((spec spec-object))
    "SPEC-DATA retains source and kind in its v1 definition envelope (§38.1)."
    (:about cl-spec:spec-data cl-spec:spec-kind cl-spec:spec-source-form)
    (:tags :cl-spec-self)
    (:trials (:smoke 10 :normal 50))
    (let ((data (cl-spec:spec-data spec)))
      (and (cl-spec:validp 'spec-description-data data)
           (eq (cl-spec:spec-kind spec) (getf data :kind))
           (equal (cl-spec:spec-source-form spec) (getf data :source-form)))))
  (values (contract-names) (property-names)))

(register-specifications)
