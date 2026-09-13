;;;; tests/normalize-test.lisp

(defpackage #:cl-spec/tests/normalize-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir
                #:spec-name #:spec-source-form #:spec-source-location #:spec-kind
                #:spec-children
                #:type-spec-type-specifier #:reference-spec-target
                #:predicate-spec-predicate #:member-spec-values
                #:range-spec-base-type #:range-spec-minimum #:range-spec-maximum
                #:instance-of-spec-class-name)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form
                #:*spec-primitives*))

(in-package #:cl-spec/tests/normalize-test)

(deftest malformed-compound-spines-signal-invalid-spec-form
  (dolist (form '((tuple . integer) (and integer . string) (member . integer)
                  (type integer . extra)))
    (ok (handler-case (progn (normalize-spec-form form) nil)
          (invalid-spec-form () t)
          (type-error () nil)))))

(deftest mvp-primitives-are-declared
  (testing "*SPEC-PRIMITIVES* lists exactly the MVP spec head names"
    (ok (equal '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
                 "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "PLIST" "INSTANCE-OF")
               *spec-primitives*)))
  (testing "CONS-OF is gone, matching the MVP spec list in section 52"
    (ok (not (member "CONS-OF" *spec-primitives* :test #'string=)))))

(deftest bare-symbols-split-into-types-and-references
  (testing "a COMMON-LISP type name becomes a TYPE-SPEC"
    (let ((spec (normalize-spec-form 'integer)))
      (ok (eq :type (spec-kind spec)))
      (ok (eq 'integer (type-spec-type-specifier spec)))))
  (testing "NULL is a type, not a reference"
    (ok (eq :type (spec-kind (normalize-spec-form 'null)))))
  (testing "any other symbol becomes a REFERENCE-SPEC"
    (let ((spec (normalize-spec-form 'positive-integer)))
      (ok (eq :reference (spec-kind spec)))
      (ok (eq 'positive-integer (reference-spec-target spec)))))
  (testing "a symbol in another package is a reference even if it names a class"
    (ok (eq :reference (spec-kind (normalize-spec-form 'cl-user::my-class))))))

(deftest explicit-leaf-heads
  (testing "(TYPE ...) wraps a type specifier"
    (ok (equal '(vector fixnum)
               (type-spec-type-specifier (normalize-spec-form '(type (vector fixnum)))))))
  (testing "(SATISFIES ...) records the predicate"
    (ok (eq 'plusp (predicate-spec-predicate (normalize-spec-form '(satisfies plusp))))))
  (testing "(MEMBER ...) keeps its values unnormalized"
    (ok (equal '(:a :b :c) (member-spec-values (normalize-spec-form '(member :a :b :c))))))
  (testing "(INSTANCE-OF ...) records the class name"
    (ok (eq 'my-class
            (instance-of-spec-class-name (normalize-spec-form '(instance-of my-class)))))))

(deftest range-accepts-both-arities
  (testing "two arguments leave the base type unspecified"
    (let ((spec (normalize-spec-form '(range 1 100))))
      (ok (null (range-spec-base-type spec)))
      (ok (eql 1 (range-spec-minimum spec)))
      (ok (eql 100 (range-spec-maximum spec)))))
  (testing "three arguments name the base type"
    (let ((spec (normalize-spec-form '(range integer 1 100))))
      (ok (eq 'integer (range-spec-base-type spec)))))
  (testing "* becomes :UNBOUNDED"
    (let ((spec (normalize-spec-form '(range 1 *))))
      (ok (eql 1 (range-spec-minimum spec)))
      (ok (eq :unbounded (range-spec-maximum spec)))))
  (testing "a non numeric base type is rejected"
    (ok (signals (normalize-spec-form '(range character 1 2)) 'invalid-spec-form)))
  (testing "(range integer *) is rejected rather than treating INTEGER as a bound"
    ;; The natural mis-write for "any integer": with only two arguments this
    ;; matches the (range lo hi) grammar and MINIMUM would otherwise become
    ;; the symbol INTEGER, which used to survive normalization and only fail
    ;; later, inside VALIDP, with an unrelated TYPE-ERROR.
    (ok (signals (normalize-spec-form '(range integer *)) 'invalid-spec-form)))
  (testing "a non numeric, non * bound is rejected in the three argument form too"
    (ok (signals (normalize-spec-form '(range integer 1 something)) 'invalid-spec-form))))

(deftest heads-are-matched-by-name-not-identity
  (testing "a head interned in another package still normalizes"
    (let ((head (intern "SATISFIES" (or (find-package "CL-USER") *package*))))
      (ok (eq :predicate (spec-kind (normalize-spec-form (list head 'plusp))))))))

(deftest normalization-records-provenance
  (testing "the top level spec keeps name, source form and location"
    (let ((spec (normalize-spec-form '(satisfies plusp)
                                     :name 'positive
                                     :source-location '(:file "x.lisp" :package "CL-USER"))))
      (ok (eq 'positive (spec-name spec)))
      (ok (equal '(satisfies plusp) (spec-source-form spec)))
      (ok (equal '(:file "x.lisp" :package "CL-USER") (spec-source-location spec))))))

(deftest rejected-forms
  (testing "CONS-OF is reported as post-MVP rather than as an unknown head"
    (let ((condition (handler-case (progn (normalize-spec-form '(cons-of integer integer)) nil)
                       (invalid-spec-form (c) c))))
      (ok condition)
      (ok (search "post-MVP" (princ-to-string condition)))))
  (testing "an unknown head is rejected"
    (ok (signals (normalize-spec-form '(vector-or-list integer)) 'invalid-spec-form)))
  (testing "a non symbol head is rejected"
    (ok (signals (normalize-spec-form '((1 2) 3)) 'invalid-spec-form)))
  (testing "a bare literal is rejected"
    (ok (signals (normalize-spec-form 42) 'invalid-spec-form)))
  (testing "wrong arity is rejected"
    (ok (signals (normalize-spec-form '(satisfies plusp oddp)) 'invalid-spec-form))))

(deftest spec-objects-pass-through
  (testing "an already normalized spec is returned unchanged"
    (let ((spec (normalize-spec-form 'integer)))
      (ok (eq spec (normalize-spec-form spec)))))
  (testing "NAME is not attached to an already normalized spec, even when supplied"
    ;; SPEC's NAME slot has no writer and the object may be shared or already
    ;; registered elsewhere, so NORMALIZE-SPEC-FORM cannot safely rename it in
    ;; place; see the docstring for why this is documented rather than fixed.
    (let ((spec (normalize-spec-form 'integer)))
      (ok (eq spec (normalize-spec-form spec :name 'renamed)))
      (ok (null (spec-name (normalize-spec-form spec :name 'renamed)))))))

(deftest composite-heads
  (testing "AND collects normalized children in order"
    (let ((spec (normalize-spec-form '(and integer (range 1 *)))))
      (ok (eq :and (spec-kind spec)))
      (ok (equal '(:type :range) (mapcar #'spec-kind (spec-children spec))))))
  (testing "OR collects normalized children"
    (ok (equal '(:type :reference)
               (mapcar #'spec-kind (spec-children (normalize-spec-form '(or null user)))))))
  (testing "NOT takes exactly one child"
    (ok (equal '(:type) (mapcar #'spec-kind (spec-children (normalize-spec-form '(not integer))))))
    (ok (signals (normalize-spec-form '(not integer string)) 'invalid-spec-form)))
  (testing "LIST-OF and VECTOR-OF take one element spec"
    (ok (eq :list-of (spec-kind (normalize-spec-form '(list-of integer)))))
    (ok (eq :vector-of (spec-kind (normalize-spec-form '(vector-of integer))))))
  (testing "TUPLE keeps one spec per position"
    (let ((spec (normalize-spec-form '(tuple integer string))))
      (ok (eq :tuple (spec-kind spec)))
      (ok (equal '(:type :type) (mapcar #'spec-kind (spec-children spec))))))
  (testing "NULLABLE takes exactly one child"
    (ok (eq :nullable (spec-kind (normalize-spec-form '(nullable integer))))))
  (testing "the empty AND and OR are accepted"
    (ok (null (spec-children (normalize-spec-form '(and)))))
    (ok (null (spec-children (normalize-spec-form '(or)))))))

(deftest children-do-not-inherit-the-name
  (testing "only the top level node carries NAME"
    (let ((spec (normalize-spec-form '(and integer) :name 'positive)))
      (ok (eq 'positive (spec-name spec)))
      (ok (null (spec-name (first (spec-children spec)))))))
  (testing "children keep their own source form"
    (let ((spec (normalize-spec-form '(and (range 1 *)))))
      (ok (equal '(range 1 *) (spec-source-form (first (spec-children spec))))))))
