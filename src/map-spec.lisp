;;;; src/map-spec.lisp
;;;;
;;;; Homogeneous maps (specification §9.6).  A map spec constrains every key with
;;;; one spec and every value with another under a declared key test, instead of
;;;; naming fields the way the keyed field specs of src/field-spec.lisp do.

(defpackage #:cl-spec/src/map-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:import-from #:cl-spec/src/field-spec #:key-test-designator)
  (:export #:map-of-spec #:hash-table-of-spec #:alist-of-spec
           #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
           #:map-spec-min-count #:map-spec-max-count
           #:map-count-constraint-plist))

(in-package #:cl-spec/src/map-spec)

(defclass map-of-spec (spec)
  ((key-spec :initarg :key-spec
             :initform nil
             :reader map-spec-key-spec
             :documentation "Spec every key must satisfy.")
   (value-spec :initarg :value-spec
               :initform nil
               :reader map-spec-value-spec
               :documentation "Spec every value must satisfy.")
   (key-test :initarg :key-test
             :initform :eql
             :reader map-spec-key-test
             :documentation "Canonical keyword naming the comparison used for keys.")
   (min-count :initarg :min-count
              :initform 0
              :reader map-spec-min-count
              :documentation "Smallest accepted entry count, inclusive.")
   (max-count :initarg :max-count
              :initform :unbounded
              :reader map-spec-max-count
              :documentation "Largest accepted entry count, inclusive, or :UNBOUNDED."))
  (:documentation "Abstract parent of maps whose keys and values each satisfy one spec.

Keys are compared with the declared test, so they are distinct under it.  No key
is named: a map key is data, which is the difference from the keyed field specs."))

(defmethod spec-children ((spec map-of-spec))
  (list (map-spec-key-spec spec) (map-spec-value-spec spec)))

(defclass hash-table-of-spec (map-of-spec)
  ()
  (:documentation "A hash table using the declared test whose entries all satisfy one key spec
and one value spec."))

(defmethod spec-kind ((spec hash-table-of-spec))
  :hash-table-of)

(defclass alist-of-spec (map-of-spec)
  ()
  (:documentation "An association list of (KEY . VALUE) conses, keys unique under the declared
test, whose entries all satisfy one key spec and one value spec."))

(defmethod spec-kind ((spec alist-of-spec))
  :alist-of)

(defun validate-map-layout (key-spec value-spec key-test min-count max-count)
  "Check one map spec's candidate slot values and return the canonical key test.

The values are passed in rather than read from a spec because reinitialization
validates before the slots change."
  (unless (and (typep key-spec 'spec) (typep value-spec 'spec))
    (error 'invalid-spec-form
           :form (list :key-spec key-spec :value-spec value-spec)
           :reason "A map spec needs a key spec and a value spec."))
  (let ((canonical (key-test-designator key-test)))
    (unless canonical
      (error 'invalid-spec-form
             :form (list :key-test key-test)
             :reason "The key test must name EQ, EQL, EQUAL or EQUALP."))
    (unless (and (integerp min-count) (not (minusp min-count)))
      (error 'invalid-spec-form
             :form (list :min-count min-count)
             :reason "MIN-COUNT must be a nonnegative integer"))
    (unless (or (eq max-count :unbounded)
                (and (integerp max-count) (not (minusp max-count))))
      (error 'invalid-spec-form
             :form (list :max-count max-count)
             :reason "MAX-COUNT must be a nonnegative integer or :UNBOUNDED"))
    (when (and (integerp max-count) (> min-count max-count))
      (error 'invalid-spec-form
             :form (list :min-count min-count :max-count max-count)
             :reason "MIN-COUNT must not exceed MAX-COUNT"))
    canonical))

(defmethod validate-definition ((spec map-of-spec))
  (validate-map-layout (map-spec-key-spec spec) (map-spec-value-spec spec)
                       (map-spec-key-test spec) (map-spec-min-count spec)
                       (map-spec-max-count spec))
  spec)

(defmethod definition-validation-slots append ((spec map-of-spec))
  '(key-spec value-spec key-test min-count max-count))

(defmethod shared-initialize :around
    ((spec map-of-spec) slot-names &rest initargs
     &key (key-spec nil key-spec-p) (value-spec nil value-spec-p)
          (key-test nil key-test-p) (min-count nil min-count-p)
          (max-count nil max-count-p))
  "Validate the candidate slot values before changing SPEC, then store the canonical test.

A caller may write the key test as a plain symbol; every later consumer --
introspection, digest, explainer and generator -- sees one keyword."
  (declare (ignore slot-names initargs))
  (flet ((candidate (supplied-p value slot default)
           (cond (supplied-p value)
                 ((slot-boundp spec slot) (slot-value spec slot))
                 (t default))))
    (let ((canonical
            (validate-map-layout (candidate key-spec-p key-spec 'key-spec nil)
                                 (candidate value-spec-p value-spec 'value-spec nil)
                                 (candidate key-test-p key-test 'key-test :eql)
                                 (candidate min-count-p min-count 'min-count 0)
                                 (candidate max-count-p max-count 'max-count :unbounded))))
      (prog1 (call-next-method)
        (setf (slot-value spec 'key-test) canonical)))))

(defun map-count-constraint-plist (spec)
  "Return SPEC's non-default entry count bounds as a plist.

A map with neither bound returns NIL, so the bounds' existence does not change
the digest or the introspection record of an unbounded map."
  (append (unless (zerop (map-spec-min-count spec))
            (list :min-count (map-spec-min-count spec)))
          (unless (eq :unbounded (map-spec-max-count spec))
            (list :max-count (map-spec-max-count spec)))))
