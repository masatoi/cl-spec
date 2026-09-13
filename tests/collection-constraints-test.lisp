;;;; tests/collection-constraints-test.lisp

(defpackage #:cl-spec/tests/collection-constraints-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/ir
                #:list-of-spec #:vector-of-spec
                #:collection-spec-min-length #:collection-spec-max-length
                #:collection-spec-unique-p)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/schema #:definition-constraints)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:validp #:explain-data #:spec-data #:sample
                #:definition-digest #:invalid-spec-form #:generator-unavailable
                #:defspec #:defproperty #:run-property
                #:property-result-status #:property-result-shrunk-outcome
                #:property-result-shrunk-counterexample))

(in-package #:cl-spec/tests/collection-constraints-test)

(deftest collection-options-normalize-into-the-ir
  (let ((plain (normalize-spec-form '(list-of integer)))
        (bounded (normalize-spec-form '(list-of integer :min-length 2 :max-length 4 :unique t)))
        (vector (normalize-spec-form '(vector-of string :max-length 3))))
    (testing "a collection without options stays unconstrained"
      (ok (typep plain 'list-of-spec))
      (ok (zerop (collection-spec-min-length plain)))
      (ok (eq :unbounded (collection-spec-max-length plain)))
      (ok (null (collection-spec-unique-p plain))))
    (testing "declared options reach the IR"
      (ok (= 2 (collection-spec-min-length bounded)))
      (ok (= 4 (collection-spec-max-length bounded)))
      (ok (collection-spec-unique-p bounded)))
    (testing "vector-of shares the same options"
      (ok (typep vector 'vector-of-spec))
      (ok (= 3 (collection-spec-max-length vector))))))

(deftest malformed-collection-options-are-refused
  (dolist (form '((list-of integer :min-length -1)
                  (list-of integer :max-length -1)
                  (list-of integer :unique :yes)
                  (list-of integer :min-length 5 :max-length 2)
                  (list-of integer :min-length 1 :min-length 2)
                  (list-of integer :unknown 1)
                  (list-of integer :min-length)))
    (testing (format nil "~S is refused before an IR object exists" form)
      (ok (signals (normalize-spec-form form) 'invalid-spec-form)))))

(deftest length-violations-are-structured
  (let* ((short (normalize-spec-form '(list-of integer :min-length 2)))
         (long (normalize-spec-form '(list-of integer :max-length 1)))
         (short-error (first (getf (explain-data short '(1)) :errors)))
         (long-error (first (getf (explain-data long '(1 2)) :errors))))
    (ok (not (validp short '(1))))
    (ok (eq :too-short (getf short-error :kind)))
    (ok (= 2 (getf short-error :minimum-length)))
    (ok (= 1 (getf short-error :actual-length)))
    (ok (eq :too-long (getf long-error :kind)))
    (ok (= 1 (getf long-error :maximum-length)))
    (ok (= 2 (getf long-error :actual-length)))
    (testing "a collection inside the range is admitted"
      (ok (validp short '(1 2)))
      (ok (validp long '(1))))))

(deftest uniqueness-errors-name-the-repeat
  (let* ((spec (normalize-spec-form '(vector-of integer :unique t)))
         (data (explain-data spec (vector 1 2 1 1)))
         (errors (getf data :errors)))
    (ok (not (getf data :valid)))
    (ok (= 2 (length errors)))
    (ok (every (lambda (datum) (eq :duplicate-element (getf datum :kind))) errors))
    (ok (equal '(2) (getf (first errors) :path)))
    (ok (= 0 (getf (first errors) :first-index)))
    (ok (equal '(3) (getf (second errors) :path)))
    (ok (validp spec (vector 1 2 3)))))

(deftest constraints-appear-in-introspection-only-when-set
  (let ((plain (spec-data (normalize-spec-form '(list-of integer))))
        (bounded (spec-data (normalize-spec-form '(list-of integer :min-length 1 :unique t)))))
    (ok (null (getf plain :min-length)))
    (ok (null (getf plain :max-length)))
    (ok (null (getf plain :unique)))
    (ok (= 1 (getf bounded :min-length)))
    (ok (eq t (getf bounded :unique)))))

(deftest digests-cover-constraints
  (let ((plain (normalize-spec-form '(list-of integer)))
        (bounded (normalize-spec-form '(list-of integer :min-length 1))))
    (testing "an unconstrained collection declares no constraint fields"
      (ok (null (definition-constraints plain))))
    (testing "a declared constraint changes the digest"
      (ok (not (equal (definition-digest plain) (definition-digest bounded)))))))

(deftest generation-honors-length-and-uniqueness
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (defspec bounded (list-of (range integer 0 20) :min-length 2 :max-length 5))
    (defspec distinct (vector-of (member 1 2 3 4) :min-length 2 :unique t))
    (let ((lists (sample 'bounded :count 50 :seed 7))
          (vectors (sample 'distinct :count 50 :seed 7)))
      (testing "generated lengths stay inside the declared range"
        (ok (every (lambda (items) (<= 2 (length items) 5)) lists)))
      (testing "unique collections draw distinct elements"
        (ok (every (lambda (items)
                     (= (length items) (length (remove-duplicates items :test #'eql))))
                   vectors))
        (ok (every (lambda (items) (<= 2 (length items) 4)) vectors))))))

(deftest generation-refuses-unique-without-a-finite-domain
  (testing "UNIQUE on an unbounded element spec is refused, not retried forever"
    (ok (signals (sample (normalize-spec-form '(list-of integer :unique t)) :count 1)
                 'generator-unavailable))))

(deftest shrinking-keeps-the-minimum-length
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (defproperty keeps-two ((xs (list-of (range integer 0 10) :min-length 2 :max-length 5)))
      (:tags :collection-constraint)
      (:trials (:normal 200))
      (not (eql 0 (first xs))))
    (let* ((result (run-property 'keeps-two :seed 1 :profile :normal))
           (shrunk (getf (property-result-shrunk-counterexample result) 'xs)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :used (property-result-shrunk-outcome result)))
      (ok (<= 2 (length shrunk) 5))
      (ok (eql 0 (first shrunk))))))

(deftest shrinking-keeps-uniqueness
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (defproperty keeps-distinct
        ((xs (list-of (member 1 2 3 4) :min-length 2 :unique t)))
      (:tags :collection-constraint)
      (:trials (:normal 200))
      (not (member 1 xs)))
    (let* ((result (run-property 'keeps-distinct :seed 3 :profile :normal))
           (shrunk (getf (property-result-shrunk-counterexample result) 'xs)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :used (property-result-shrunk-outcome result)))
      (ok (>= (length shrunk) 2))
      (ok (= (length shrunk) (length (remove-duplicates shrunk :test #'eql)))))))

(deftest unique-nullable-domains-are-deduplicated
  (let ((spec (normalize-spec-form '(list-of (nullable boolean) :min-length 2 :unique t)))
        (too-large (normalize-spec-form
                    '(list-of (nullable boolean) :min-length 3 :unique t))))
    (let ((samples (sample spec :count 20 :seed 5)))
      (ok (every (lambda (items)
                   (= (length items) (length (remove-duplicates items :test #'eql))))
                 samples)))
    (testing "NIL is one value of the nullable-boolean domain, not two"
      (ok (signals (sample too-large :count 1) 'generator-unavailable)))))

(deftest unique-resolves-named-finite-domains
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (defspec finite-id (member 1 2 3))
    (defspec named-distinct (list-of finite-id :min-length 2 :max-length 3 :unique t))
    (let ((samples (sample 'named-distinct :count 20 :seed 5)))
      (ok (every (lambda (items)
                   (and (<= 2 (length items) 3)
                        (= (length items) (length (remove-duplicates items :test #'eql)))))
                 samples)))))
