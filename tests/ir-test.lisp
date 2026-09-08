;;;; tests/ir-test.lisp

(defpackage #:cl-spec/tests/ir-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-description
                #:spec-source-form
                #:spec-source-location
                #:spec-metadata
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

(in-package #:cl-spec/tests/ir-test)

(defparameter *leaf-classes*
  '(reference-spec predicate-spec type-spec and-spec or-spec not-spec
    member-spec range-spec collection-spec list-of-spec vector-of-spec
    tuple-spec nullable-spec instance-of-spec custom-spec)
  "Every class the Semantic IR hierarchy defines below SPEC.")

(deftest every-ir-class-is-a-spec
  (testing "all IR classes are subclasses of SPEC"
    (dolist (class-name *leaf-classes*)
      (ok (subtypep class-name 'spec)))))

(deftest collection-classes-share-a-parent
  (testing "LIST-OF, VECTOR-OF and TUPLE specialise COLLECTION-SPEC"
    (ok (subtypep 'list-of-spec 'collection-spec))
    (ok (subtypep 'vector-of-spec 'collection-spec))
    (ok (subtypep 'tuple-spec 'collection-spec))))

(deftest base-slots-are-readable-and-default-to-nil
  (testing "SPEC carries name, description, source form, location and metadata"
    (let ((instance (make-instance 'type-spec :type-specifier 'integer)))
      (ok (null (spec-name instance)))
      (ok (null (spec-description instance)))
      (ok (null (spec-source-form instance)))
      (ok (null (spec-source-location instance)))
      (ok (null (spec-metadata instance)))))
  (testing "base slots accept initargs"
    (let ((instance (make-instance 'type-spec
                                   :type-specifier 'integer
                                   :name 'small-integer
                                   :description "an integer"
                                   :source-form '(type integer)
                                   :source-location '(:file "/tmp/a.lisp")
                                   :metadata '(:tag :numeric))))
      (ok (eq 'small-integer (spec-name instance)))
      (ok (equal "an integer" (spec-description instance)))
      (ok (equal '(type integer) (spec-source-form instance)))
      (ok (equal '(:file "/tmp/a.lisp") (spec-source-location instance)))
      (ok (equal '(:tag :numeric) (spec-metadata instance))))))

(deftest spec-kind-identifies-each-class
  (testing "SPEC-KIND returns the canonical keyword for each IR class"
    (ok (eq :reference (spec-kind (make-instance 'reference-spec :target 'money))))
    (ok (eq :predicate (spec-kind (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (eq :type (spec-kind (make-instance 'type-spec :type-specifier 'integer))))
    (ok (eq :and (spec-kind (make-instance 'and-spec :children '()))))
    (ok (eq :or (spec-kind (make-instance 'or-spec :children '()))))
    (ok (eq :not (spec-kind (make-instance 'not-spec :inner-spec nil))))
    (ok (eq :member (spec-kind (make-instance 'member-spec :values '(:a :b)))))
    (ok (eq :range (spec-kind (make-instance 'range-spec))))
    (ok (eq :list-of (spec-kind (make-instance 'list-of-spec))))
    (ok (eq :vector-of (spec-kind (make-instance 'vector-of-spec))))
    (ok (eq :tuple (spec-kind (make-instance 'tuple-spec))))
    (ok (eq :nullable (spec-kind (make-instance 'nullable-spec :inner-spec nil))))
    (ok (eq :instance-of
            (spec-kind (make-instance 'instance-of-spec :class-name 'account))))
    (ok (eq :custom (spec-kind (make-instance 'custom-spec :handler nil))))))

(deftest spec-children-walks-the-tree
  (testing "leaf specs have no children"
    (ok (null (spec-children (make-instance 'type-spec :type-specifier 'integer))))
    (ok (null (spec-children (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (null (spec-children (make-instance 'reference-spec :target 'money)))))
  (testing "compound specs expose their children in definition order"
    (let* ((first-child (make-instance 'type-spec :type-specifier 'integer))
           (second-child (make-instance 'predicate-spec :predicate 'plusp))
           (conjunction (make-instance 'and-spec
                                       :children (list first-child second-child)))
           (disjunction (make-instance 'or-spec
                                       :children (list first-child second-child))))
      (ok (equal (list first-child second-child) (spec-children conjunction)))
      (ok (equal (list first-child second-child) (spec-children disjunction)))))
  (testing "NOT and NULLABLE expose their single inner spec as a one-element list"
    (let* ((inner (make-instance 'type-spec :type-specifier 'string))
           (negation (make-instance 'not-spec :inner-spec inner))
           (nullable (make-instance 'nullable-spec :inner-spec inner)))
      (ok (equal (list inner) (spec-children negation)))
      (ok (equal (list inner) (spec-children nullable)))))
  (testing "collections expose their element spec, tuples their element specs"
    (let* ((element (make-instance 'type-spec :type-specifier 'integer))
           (list-of (make-instance 'list-of-spec :element-spec element))
           (tuple (make-instance 'tuple-spec :element-specs (list element element))))
      (ok (equal (list element) (spec-children list-of)))
      (ok (equal (list element element) (spec-children tuple)))))
  (testing "a collection without an element spec has no children"
    (ok (null (spec-children (make-instance 'vector-of-spec))))))

(deftest range-bounds-default-to-unbounded
  (testing "RANGE-SPEC bounds default to :UNBOUNDED and accept numbers"
    (let ((open (make-instance 'range-spec))
          (closed (make-instance 'range-spec
                                 :base-type 'integer :minimum 1 :maximum 100)))
      (ok (eq :unbounded (range-spec-minimum open)))
      (ok (eq :unbounded (range-spec-maximum open)))
      (ok (null (range-spec-base-type open)))
      (ok (eq 'integer (range-spec-base-type closed)))
      (ok (eql 1 (range-spec-minimum closed)))
      (ok (eql 100 (range-spec-maximum closed))))))

(deftest class-specific-readers
  (testing "each specialised class exposes its own slot"
    (ok (eq 'money (reference-spec-target
                    (make-instance 'reference-spec :target 'money))))
    (ok (eq 'plusp (predicate-spec-predicate
                    (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (eq 'integer (type-spec-type-specifier
                      (make-instance 'type-spec :type-specifier 'integer))))
    (ok (equal '(:a :b) (member-spec-values
                         (make-instance 'member-spec :values '(:a :b)))))
    (ok (eq 'account (instance-of-spec-class-name
                      (make-instance 'instance-of-spec :class-name 'account))))
    (ok (null (custom-spec-handler (make-instance 'custom-spec :handler nil))))
    (ok (null (and-spec-children (make-instance 'and-spec))))
    (ok (null (or-spec-children (make-instance 'or-spec))))
    (ok (null (not-spec-inner-spec (make-instance 'not-spec))))
    (ok (null (nullable-spec-inner-spec (make-instance 'nullable-spec))))
    (ok (null (collection-spec-element-spec (make-instance 'list-of-spec))))
    (ok (null (tuple-spec-element-specs (make-instance 'tuple-spec))))))
