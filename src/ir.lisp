;;;; src/ir.lisp
;;;;
;;;; Semantic IR for cl-spec (specification §7).  The IR is the stable core of
;;;; the framework: the DSL macros normalize into these objects, and the
;;;; validator, explainer, generator and introspection layers all compile from
;;;; them.  The IR performs no validation itself.

(defpackage #:cl-spec/src/ir
  (:use #:cl)
  (:import-from #:cl-spec/src/definition-validation
                #:definition-validation-slots #:validate-definition)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:export #:spec
           #:spec-name
           #:spec-description
           #:spec-source-form
           #:spec-source-location
           #:spec-metadata
           #:spec-generator-name
           #:spec-kind
           #:spec-children
           #:reference-spec
           #:reference-spec-target
           #:predicate-spec
           #:predicate-spec-predicate
           #:type-spec
           #:type-spec-type-specifier
           #:and-spec
           #:and-spec-children
           #:or-spec
           #:or-spec-children
           #:not-spec
           #:not-spec-inner-spec
           #:member-spec
           #:member-spec-values
           #:range-spec
           #:range-spec-base-type
           #:range-spec-minimum
           #:range-spec-maximum
           #:collection-spec
           #:collection-spec-element-spec
           #:bounded-collection-spec
           #:collection-spec-min-length
           #:collection-spec-max-length
           #:collection-spec-unique-p
           #:collection-constraint-plist
           #:list-of-spec
           #:vector-of-spec
           #:tuple-spec
           #:tuple-spec-element-specs
           #:nullable-spec
           #:nullable-spec-inner-spec
           #:instance-of-spec
           #:instance-of-spec-class-name
           #:custom-spec
           #:custom-spec-handler))

(in-package #:cl-spec/src/ir)

(defclass spec ()
  ((name :initarg :name
         :initform nil
         :reader spec-name
         :documentation "Package-qualified symbol this spec is registered under,
or NIL for an anonymous inline spec.")
   (description :initarg :description
                :initform nil
                :reader spec-description
                :documentation "Human readable description, or NIL.")
   (source-form :initarg :source-form
                :initform nil
                :reader spec-source-form
                :documentation "Original DSL s-expression this spec was
normalized from.  Kept verbatim so introspection can show what the author
wrote rather than what the normalizer produced.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader spec-source-location
                    :documentation "Source location plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION, or NIL.")
   (metadata :initarg :metadata
             :initform nil
             :reader spec-metadata
             :documentation "Arbitrary plist for callers and future extensions.")
   (generator :initarg :generator
              :initform nil
              :reader spec-generator-name
              :documentation "Symbol naming a custom generator, defined with
DEFGENERATOR, that produces this spec's values; or NIL when the backend derives
one from the spec itself (specification §11).

Attached to the top level node only, like NAME and SOURCE-LOCATION: a
(:GENERATOR NAME) clause belongs to the definition, not to each conjunct of it."))
  (:documentation "Base class of every Semantic IR node."))

(defgeneric spec-kind (spec)
  (:documentation "Return the canonical keyword identifying SPEC's node type.

The keyword is part of the public introspection contract: SPEC-DATA and the
MCP/JSON projections use it as the discriminator, so it must stay stable even
if class names change."))

(defgeneric spec-children (spec)
  (:documentation "Return the child specs of SPEC as a list, in definition order.

Leaf nodes return NIL.  Callers use this to walk the IR without knowing which
slot a particular class stores its children in."))

(defmethod spec-children ((spec spec))
  "Leaf nodes have no children."
  nil)

(defclass reference-spec (spec)
  ((target :initarg :target
           :initform nil
           :reader reference-spec-target
           :documentation "Symbol naming another registered spec."))
  (:documentation "A reference to a spec registered under another name."))

(defmethod spec-kind ((spec reference-spec))
  :reference)

(defclass predicate-spec (spec)
  ((predicate :initarg :predicate
              :initform nil
              :reader predicate-spec-predicate
              :documentation "Symbol naming a one-argument predicate function."))
  (:documentation "A SATISFIES-style spec built from a predicate function."))

(defmethod spec-kind ((spec predicate-spec))
  :predicate)

(defclass type-spec (spec)
  ((type-specifier :initarg :type-specifier
                   :initform nil
                   :reader type-spec-type-specifier
                   :documentation "Common Lisp type specifier."))
  (:documentation "A spec delegating to a Common Lisp type specifier."))

(defmethod spec-kind ((spec type-spec))
  :type)

(defclass and-spec (spec)
  ((children :initarg :children
             :initform nil
             :reader and-spec-children
             :documentation "Specs that must all hold."))
  (:documentation "Conjunction of specs."))

(defmethod spec-kind ((spec and-spec))
  :and)

(defmethod spec-children ((spec and-spec))
  (and-spec-children spec))

(defclass or-spec (spec)
  ((children :initarg :children
             :initform nil
             :reader or-spec-children
             :documentation "Specs of which at least one must hold."))
  (:documentation "Disjunction of specs."))

(defmethod spec-kind ((spec or-spec))
  :or)

(defmethod spec-children ((spec or-spec))
  (or-spec-children spec))

(defclass not-spec (spec)
  ((inner-spec :initarg :inner-spec
               :initform nil
               :reader not-spec-inner-spec
               :documentation "Spec that must not hold."))
  (:documentation "Negation of a spec."))

(defmethod spec-kind ((spec not-spec))
  :not)

(defmethod spec-children ((spec not-spec))
  (let ((inner (not-spec-inner-spec spec)))
    (and inner (list inner))))

(defclass member-spec (spec)
  ((admissible-values :initarg :values
                      :initform nil
                      :reader member-spec-values
                      :documentation "Admissible values, compared with EQL."))
  (:documentation "A spec admitting one of an explicit set of values."))

(defmethod spec-kind ((spec member-spec))
  :member)

(defclass range-spec (spec)
  ((base-type :initarg :base-type
              :initform nil
              :reader range-spec-base-type
              :documentation "Type specifier the range is taken over, or NIL.")
   (minimum :initarg :minimum
            :initform :unbounded
            :reader range-spec-minimum
            :documentation "Inclusive lower bound, or :UNBOUNDED.")
   (maximum :initarg :maximum
            :initform :unbounded
            :reader range-spec-maximum
            :documentation "Inclusive upper bound, or :UNBOUNDED."))
  (:documentation "A numeric range.  The DSL writes an open bound as *."))

(defmethod spec-kind ((spec range-spec))
  :range)

(defclass collection-spec (spec)
  ((element-spec :initarg :element-spec
                 :initform nil
                 :reader collection-spec-element-spec
                 :documentation "Spec every element must satisfy."))
  (:documentation "Abstract parent of homogeneous and positional collections."))

(defmethod spec-children ((spec collection-spec))
  (let ((element (collection-spec-element-spec spec)))
    (and element (list element))))

(defclass bounded-collection-spec (collection-spec)
  ((min-length :initarg :min-length
               :initform 0
               :reader collection-spec-min-length
               :documentation "Smallest accepted element count, inclusive.")
   (max-length :initarg :max-length
               :initform :unbounded
               :reader collection-spec-max-length
               :documentation "Largest accepted element count, inclusive, or :UNBOUNDED.")
   (unique-p :initarg :unique
             :initform nil
             :reader collection-spec-unique-p
             :documentation "True when elements must be pairwise distinct under EQL."))
  (:documentation "A homogeneous collection with a declared length range.

The constraints feed validation and generation alike: MIN-LENGTH and MAX-LENGTH
bound the count, and UNIQUE-P requires pairwise distinct elements under EQL."))

(defmethod definition-validation-slots append ((spec bounded-collection-spec))
  '(min-length max-length unique-p))

(defun validate-collection-constraints (spec)
  "Check SPEC's length range and uniqueness flag, returning SPEC.

The DSL refuses the same shapes while normalizing; this covers direct
construction and re-registration, which the registry validates."
  (let ((minimum (collection-spec-min-length spec))
        (maximum (collection-spec-max-length spec))
        (unique (collection-spec-unique-p spec)))
    (unless (and (integerp minimum) (not (minusp minimum)))
      (error 'invalid-spec-form :form spec
                                :reason "MIN-LENGTH must be a nonnegative integer"))
    (unless (or (eq maximum :unbounded)
                (and (integerp maximum) (not (minusp maximum))))
      (error 'invalid-spec-form :form spec
                                :reason "MAX-LENGTH must be a nonnegative integer or :UNBOUNDED"))
    (when (and (integerp maximum) (> minimum maximum))
      (error 'invalid-spec-form :form spec
                                :reason "MIN-LENGTH must not exceed MAX-LENGTH"))
    (unless (member unique '(nil t))
      (error 'invalid-spec-form :form spec :reason "UNIQUE must be boolean"))
    spec))

(defmethod validate-definition ((spec bounded-collection-spec))
  (validate-collection-constraints spec))

(defun collection-constraint-plist (spec)
  "Return SPEC's non-default length and uniqueness constraints as a plist.

A node with no constraints returns NIL, so the constraints' existence does not
change the digest or the introspection record of an unconstrained collection."
  (append (unless (zerop (collection-spec-min-length spec))
            (list :min-length (collection-spec-min-length spec)))
          (unless (eq :unbounded (collection-spec-max-length spec))
            (list :max-length (collection-spec-max-length spec)))
          (when (collection-spec-unique-p spec)
            (list :unique t))))

(defclass list-of-spec (bounded-collection-spec)
  ()
  (:documentation "A list whose elements all satisfy one spec."))

(defmethod spec-kind ((spec list-of-spec))
  :list-of)

(defclass vector-of-spec (bounded-collection-spec)
  ()
  (:documentation "A vector whose elements all satisfy one spec."))

(defmethod spec-kind ((spec vector-of-spec))
  :vector-of)

(defclass tuple-spec (collection-spec)
  ((element-specs :initarg :element-specs
                  :initform nil
                  :reader tuple-spec-element-specs
                  :documentation "One spec per position, in order."))
  (:documentation "A fixed-length sequence with a spec per position."))

(defmethod definition-validation-slots append ((spec tuple-spec))
  '(element-specs))

(defmethod spec-kind ((spec tuple-spec))
  :tuple)

(defmethod spec-children ((spec tuple-spec))
  (tuple-spec-element-specs spec))

(defclass nullable-spec (spec)
  ((inner-spec :initarg :inner-spec
               :initform nil
               :reader nullable-spec-inner-spec
               :documentation "Spec the value satisfies when it is not NIL."))
  (:documentation "A spec that additionally admits NIL."))

(defmethod spec-kind ((spec nullable-spec))
  :nullable)

(defmethod spec-children ((spec nullable-spec))
  (let ((inner (nullable-spec-inner-spec spec)))
    (and inner (list inner))))

(defclass instance-of-spec (spec)
  ((target-class :initarg :class-name
                 :initform nil
                 :reader instance-of-spec-class-name
                 :documentation "Symbol naming a class the value must be an
instance of."))
  (:documentation "A spec asserting CLOS class membership."))

(defmethod spec-kind ((spec instance-of-spec))
  :instance-of)

(defclass custom-spec (spec)
  ((handler :initarg :handler
            :initform nil
            :reader custom-spec-handler
            :documentation "Object supplying user-defined validation,
explanation and generation behaviour."))
  (:documentation "Escape hatch for specs the built-in node types cannot express."))

(defmethod spec-kind ((spec custom-spec))
  :custom)
