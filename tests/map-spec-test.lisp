;;;; tests/map-spec-test.lisp

(defpackage #:cl-spec/tests/map-spec-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/map-spec
                #:hash-table-of-spec #:alist-of-spec
                #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
                #:map-spec-min-count #:map-spec-max-count)
  (:import-from #:cl-spec/src/ir #:type-spec)
  (:import-from #:cl-spec/src/definition-validation #:validate-definition)
  (:import-from #:cl-spec/src/explain #:expected-descriptor)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:cl-spec/src/schema #:definition-constraints)
  (:import-from #:cl-spec/src/coverage-plist #:plist-coverage-schema)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:encode-artifact-value #:artifact-value-error)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:invalid-spec-form #:validp #:explain-data
                #:spec-data #:definition-digest #:*registry*))

(in-package #:cl-spec/tests/map-spec-test)

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(defun make-table (test &rest entries)
  "Build a hash table with TEST holding (KEY . VALUE) ENTRIES in order."
  (let ((table (make-hash-table :test test)))
    (loop for (key . value) in entries
          do (setf (gethash key table) value))
    table))

(defun errors-of (form value)
  "Return the structured errors of VALUE against the DSL FORM."
  (getf (explain-data (normalize-spec-form form) value) :errors))

(deftest map-forms-normalize-into-the-ir
  (let ((table (normalize-spec-form '(hash-table-of string integer)))
        (alist (normalize-spec-form '(alist-of keyword (list-of string)
                                      :test equal :min-count 1 :max-count 4))))
    (testing "a map without options uses EQL and no count bounds"
      (ok (typep table 'hash-table-of-spec))
      (ok (typep (map-spec-key-spec table) 'type-spec))
      (ok (typep (map-spec-value-spec table) 'type-spec))
      (ok (eq :eql (map-spec-key-test table)))
      (ok (zerop (map-spec-min-count table)))
      (ok (eq :unbounded (map-spec-max-count table))))
    (testing "declared options reach the IR"
      (ok (typep alist 'alist-of-spec))
      (ok (eq :equal (map-spec-key-test alist)))
      (ok (= 1 (map-spec-min-count alist)))
      (ok (= 4 (map-spec-max-count alist))))
    (testing "a keyword and a plain symbol name the same test; * is unbounded"
      (ok (eq :equalp (map-spec-key-test (normalize-spec-form '(hash-table-of t t :test :equalp)))))
      (ok (eq :unbounded
              (map-spec-max-count (normalize-spec-form '(alist-of t t :max-count *))))))))

(deftest malformed-map-declarations-are-refused
  (dolist (form '((hash-table-of)
                  (hash-table-of string)
                  (alist-of string integer :test)
                  (alist-of string integer :test bogus)
                  (alist-of string integer :test equal :test eql)
                  (alist-of string integer :min-count -1)
                  (alist-of string integer :min-count 1.5)
                  (alist-of string integer :max-count -1)
                  (alist-of string integer :max-count many)
                  (alist-of string integer :min-count 3 :max-count 2)
                  (hash-table-of string integer :unique t)
                  (hash-table-of string integer extra)))
    (ok (refuses-form-p form) (format nil "~S is refused" form))))

(deftest programmatic-map-specs-are-validated
  (let ((child (normalize-spec-form 'integer)))
    (flet ((refused-p (&rest initargs)
             (handler-case (progn (apply #'make-instance 'hash-table-of-spec initargs) nil)
               (invalid-spec-form () t))))
      (ok (refused-p :key-spec child))
      (ok (refused-p :key-spec child :value-spec :not-a-spec))
      (ok (refused-p :key-spec child :value-spec child :key-test :frobnicate))
      (ok (refused-p :key-spec child :value-spec child :min-count -1))
      (ok (refused-p :key-spec child :value-spec child :max-count 'many))
      (ok (refused-p :key-spec child :value-spec child :min-count 2 :max-count 1)))
    (testing "a plain symbol key test is stored as the canonical keyword"
      (let ((spec (make-instance 'alist-of-spec :key-spec child :value-spec child
                                                :key-test 'equal)))
        (ok (eq :equal (map-spec-key-test spec)))
        (ok (eq spec (validate-definition spec)))))
    (testing "a refused reinitialization leaves the slots unchanged"
      (let ((spec (make-instance 'alist-of-spec :key-spec child :value-spec child
                                                :max-count 3)))
        (ok (handler-case (progn (reinitialize-instance spec :min-count 4) nil)
              (invalid-spec-form () t)))
        (ok (zerop (map-spec-min-count spec)))
        (ok (= 3 (map-spec-max-count spec)))))))
