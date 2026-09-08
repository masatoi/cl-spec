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
                #:generator-unavailable-reason
                #:unsupported-seed))

(in-package #:cl-spec/tests/conditions-test)

(deftest condition-hierarchy
  (testing "every framework condition inherits from CL-SPEC-ERROR"
    (ok (subtypep 'cl-spec-error 'error))
    (ok (subtypep 'not-implemented 'cl-spec-error))
    (ok (subtypep 'spec-violation 'cl-spec-error))
    (ok (subtypep 'unknown-spec 'cl-spec-error))
    (ok (subtypep 'unknown-property 'cl-spec-error))
    (ok (subtypep 'no-generator-backend 'cl-spec-error))))

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
      (ok (search "post-MVP" (princ-to-string condition))))))

(deftest generator-failures-name-the-spec
  (testing "GENERATOR-UNAVAILABLE keeps the spec and the reason"
    (let ((condition (make-condition 'generator-unavailable
                                     :spec :placeholder
                                     :reason "NOT has no generation strategy")))
      (ok (eq :placeholder (generator-unavailable-spec condition)))
      (ok (typep condition 'cl-spec-error))
      (ok (search "NOT has no generation strategy" (princ-to-string condition))))))

(deftest unsupported-seed-names-the-implementation
  (testing "UNSUPPORTED-SEED reports which implementation is missing support"
    (let ((condition (make-condition 'unsupported-seed)))
      (ok (typep condition 'cl-spec-error))
      (ok (search (lisp-implementation-type) (princ-to-string condition))))))
