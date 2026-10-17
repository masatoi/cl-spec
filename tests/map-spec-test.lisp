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

(defclass unprintable-key ()
  ()
  (:documentation "A hash-table key whose printer signals, for the no-print test."))

(defmethod print-object ((object unprintable-key) stream)
  (declare (ignore object stream))
  (error "print boom"))

(deftest map-validation-accepts-and-refuses
  (ok (validp (normalize-spec-form '(hash-table-of string integer :test equal))
              (make-table 'equal (cons "a" 1) (cons "b" 2))))
  (ok (validp (normalize-spec-form '(alist-of keyword integer)) '((:a . 1) (:b . 2))))
  (ok (validp (normalize-spec-form '(alist-of keyword integer)) nil))
  (ok (not (validp (normalize-spec-form '(alist-of keyword integer)) '((:a . "bad")))))
  (ok (not (validp (normalize-spec-form '(alist-of keyword integer)) '(("a" . 1)))))
  (ok (not (validp (normalize-spec-form '(hash-table-of string integer :test equal))
                   (make-table 'eql (cons "a" 1))))))

(deftest map-structure-errors-reuse-the-keyed-kinds
  (ok (eq :not-a-hash-table (getf (first (errors-of '(hash-table-of t t) 42)) :kind)))
  (let ((datum (first (errors-of '(hash-table-of t t :test equal) (make-table 'eql)))))
    (ok (eq :wrong-key-test (getf datum :kind)))
    (ok (eq 'eql (getf datum :actual-test))))
  (ok (eq :not-an-alist (getf (first (errors-of '(alist-of t t) 42)) :kind)))
  (ok (eq :bad-association
          (getf (first (errors-of '(alist-of t t) '((:a . 1) :atom))) :kind)))
  (let ((errors (errors-of '(alist-of string integer :test equal)
                           (list (cons (copy-seq "a") "bad") (cons (copy-seq "a") 2)))))
    (testing "a structure error stops before any entry is checked"
      (ok (= 1 (length errors)))
      (ok (eq :duplicate-key (getf (first errors) :kind)))
      (ok (equal '("a") (getf (first errors) :path))))))

(deftest map-count-errors-are-structured
  (let ((few (first (errors-of '(alist-of t t :min-count 2) '((:a . 1)))))
        (many (first (errors-of '(hash-table-of t t :max-count 1)
                                (make-table 'eql (cons :a 1) (cons :b 2))))))
    (ok (eq :too-few-entries (getf few :kind)))
    (ok (= 2 (getf few :minimum-count)))
    (ok (= 1 (getf few :actual-count)))
    (ok (eq :too-many-entries (getf many :kind)))
    (ok (= 1 (getf many :maximum-count)))
    (ok (= 2 (getf many :actual-count)))))

(deftest map-entry-errors-name-the-side
  (let ((errors (errors-of '(alist-of keyword integer) '((:ok . 1) ("k" . "v")))))
    (testing "one entry can fail on its key and its value; the key comes first"
      (ok (= 2 (length errors)))
      (ok (equal '(:key) (getf (first errors) :entry-path)))
      (ok (equal '("k") (getf (first errors) :path)))
      (ok (equal '(:value) (getf (second errors) :entry-path)))
      (ok (equal '("k") (getf (second errors) :path)))))
  (testing "nested maps stack the side of each level, outermost first"
    (let ((datum (first (errors-of '(alist-of keyword (alist-of keyword integer))
                                   '((:outer . (("inner" . 1))))))))
      (ok (equal '(:value :key) (getf datum :entry-path)))
      (ok (equal '(:outer "inner") (getf datum :path)))))
  (testing "a hash table reports every key error before any value error"
    (let ((errors (errors-of '(hash-table-of string integer :test equal)
                             (make-table 'equal (cons "ok" "bad") (cons 1 2)))))
      (ok (equal '((:key) (:value))
                 (mapcar (lambda (datum) (getf datum :entry-path)) errors))))))

(deftest map-failure-identity-separates-key-and-value
  (flet ((signature (form value)
           (failure-signature :return-spec
                              (explain-data (normalize-spec-form form) value) nil)))
    (let ((form '(alist-of string string :test equal)))
      (testing "with one spec on both sides, :ENTRY-PATH still tells key from value"
        (ok (not (equal (signature form '((1 . "v"))) (signature form '(("k" . 1)))))))
      (testing "the same violation under a different key is one failure"
        (ok (equal (signature form '(("a" . 1))) (signature form '(("b" . 1)))))))
    (testing "count bounds are part of the shape"
      (ok (not (equal (signature '(alist-of t t :min-count 2) nil)
                      (signature '(alist-of t t :min-count 3) nil)))))))

(deftest map-expected-descriptor-names-both-sides
  (let ((descriptor (expected-descriptor
                     (normalize-spec-form
                      '(hash-table-of string integer :test equal :min-count 1)))))
    (ok (eq :hash-table-of (getf descriptor :kind)))
    (ok (eq :equal (getf descriptor :test)))
    (ok (equal '(:type string) (getf descriptor :key)))
    (ok (equal '(:type integer) (getf descriptor :value)))
    (ok (= 1 (getf descriptor :min-count)))
    (ok (null (getf descriptor :max-count)))))

(deftest map-validation-never-prints-keys
  (let ((table (make-table 'eql (cons (make-instance 'unprintable-key) "bad"))))
    (ok (= 1 (length (errors-of '(hash-table-of t integer) table))))))

(deftest alist-duplicate-detection-follows-the-key-test
  (ok (validp (normalize-spec-form '(alist-of string t :test eq))
              (list (cons (copy-seq "a") 1) (cons (copy-seq "a") 2))))
  (ok (not (validp (normalize-spec-form '(alist-of string t :test equal))
                   (list (cons (copy-seq "a") 1) (cons (copy-seq "a") 2)))))
  (ok (not (validp (normalize-spec-form '(alist-of string t :test equalp))
                   (list (cons "a" 1) (cons "A" 2)))))
  (ok (validp (normalize-spec-form '(alist-of integer integer))
              (loop for key from 0 below 20000 collect (cons key key)))))

(deftest map-introspection-projects-both-children
  (let* ((form '(alist-of keyword integer :test eq :max-count 8))
         (data (spec-data (normalize-spec-form form))))
    (ok (eq :alist-of (getf data :kind)))
    (ok (eq :eq (getf data :test)))
    (ok (null (getf data :min-count)))
    (ok (= 8 (getf data :max-count)))
    (ok (= 0 (getf data :key-child-index)))
    (ok (= 1 (getf data :value-child-index)))
    (ok (equal '(keyword integer)
               (mapcar (lambda (child) (getf child :type)) (getf data :children))))
    (ok (equal form (getf data :source-form)))
    (ok (getf data :definition-digest-complete))))

(deftest map-digests-cover-every-declared-part
  (let ((digest (definition-digest (normalize-spec-form '(hash-table-of string integer)))))
    (dolist (other '((alist-of string integer)
                     (hash-table-of integer string)
                     (hash-table-of string integer :test equal)
                     (hash-table-of string integer :min-count 1)
                     (hash-table-of string integer :max-count 5)))
      (ok (not (equal digest (definition-digest (normalize-spec-form other))))
          (format nil "~S has its own digest" other))))
  (ok (equal '(:test :eql) (definition-constraints (normalize-spec-form '(alist-of t t)))))
  (ok (equal '(:test :equal :min-count 1 :max-count 2)
             (definition-constraints
              (normalize-spec-form '(alist-of t t :test equal :min-count 1 :max-count 2))))))

(deftest map-nodes-are-reported-as-unexpanded-coverage
  (let ((data (plist-coverage-schema
               (list (list 'payload (normalize-spec-form
                                     '(hash-table-of keyword (plist (:optional (:a t)))))))
               *registry* 1024 32)))
    (ok (null (getf data :dimensions)))
    (ok (eq :partial (getf data :discovery)))
    (ok (equal '((:path (payload) :reason :unsupported-composite))
               (getf data :unexpanded)))))

(deftest map-values-meet-the-artifact-codec-as-before
  (testing "an alist of encodable keys and values can be saved"
    (ok (encode-artifact-value (list (cons "a" 1) (cons "b" 2)))))
  (testing "a hash table is refused, exactly as for the keyed HASH-TABLE spec"
    (ok (handler-case (progn (encode-artifact-value (make-table 'equal (cons "a" 1))) nil)
          (artifact-value-error () t)))))
