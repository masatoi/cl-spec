;;;; tests/explain-test.lisp

(defpackage #:cl-spec/tests/explain-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec))

(in-package #:cl-spec/tests/explain-test)

(defun errors-for (form value)
  "Compile FORM and return the structured errors it reports for VALUE."
  (funcall (compile-explainer (normalize-spec-form form)) value nil))

(deftest valid-values-produce-no-errors
  (testing "a satisfied leaf reports nothing"
    (ok (null (errors-for 'integer 10)))
    (ok (null (errors-for '(satisfies plusp) 10)))
    (ok (null (errors-for '(member :a :b) :a)))
    (ok (null (errors-for '(range 1 100) 50)))
    (ok (null (errors-for '(range 1 *) 10000)))))

(deftest type-failures
  (testing "a failed type check names the expected type"
    (let ((datum (first (errors-for 'integer "foo"))))
      (ok (eq :type-failed (getf datum :kind)))
      (ok (equal '(:type integer) (getf datum :expected)))
      (ok (equal "foo" (getf datum :actual)))
      (ok (null (getf datum :path))))))

(deftest predicate-failures
  (testing "a predicate returning NIL is reported as :PREDICATE-FAILED"
    (let ((datum (first (errors-for '(satisfies plusp) -1))))
      (ok (eq :predicate-failed (getf datum :kind)))
      (ok (eq 'plusp (getf datum :predicate)))
      (ok (equal '(:satisfies plusp) (getf datum :expected)))))
  (testing "a predicate that signals is reported as :PREDICATE-ERRORED, not propagated"
    (let ((datum (first (errors-for '(satisfies plusp) "foo"))))
      (ok (eq :predicate-errored (getf datum :kind)))
      (ok (getf datum :condition-type))
      (ok (stringp (getf datum :condition-report))))))

(deftest member-and-range-failures
  (testing "MEMBER reports the admissible values"
    (let ((datum (first (errors-for '(member :a :b) :c))))
      (ok (eq :not-member (getf datum :kind)))
      (ok (equal '(:member :a :b) (getf datum :expected)))))
  (testing "RANGE says which bound was violated"
    (ok (eq :minimum (getf (first (errors-for '(range 1 100) 0)) :violated-bound)))
    (ok (eq :maximum (getf (first (errors-for '(range 1 100) 101)) :violated-bound))))
  (testing "RANGE rejects a value of the wrong type before comparing"
    (ok (eq :type-failed (getf (first (errors-for '(range 1 100) "x")) :kind)))))

(deftest instance-of-failures
  (testing "an unrelated value is not an instance"
    (let ((datum (first (errors-for '(instance-of standard-object) 10))))
      (ok (eq :not-an-instance (getf datum :kind))))))

(deftest explain-data-shape
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive
                            (normalize-spec-form '(satisfies plusp) :name 'positive))
    (testing "a failing value produces the section 22 shape"
      (let ((data (explain-data 'positive -100 :registry registry)))
        (ok (null (getf data :valid)))
        (ok (eq 'positive (getf data :spec)))
        (ok (eql -100 (getf data :value)))
        (ok (null (getf data :path)))
        (ok (= 1 (length (getf data :errors))))))
    (testing "a passing value reports :VALID T and no errors"
      (let ((data (explain-data 'positive 1 :registry registry)))
        (ok (eq t (getf data :valid)))
        (ok (null (getf data :errors)))))
    (testing "an unregistered name signals UNKNOWN-SPEC"
      (ok (signals (explain-data 'absent 1 :registry registry) 'unknown-spec)))))
