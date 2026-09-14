;;;; tests/field-representations-test.lisp

(defpackage #:cl-spec/tests/field-representations-test
  (:use #:cl)
  (:import-from #:cl-spec/src/field-spec
                #:alist-spec #:hash-table-spec #:field-spec
                #:field-spec-fields #:field-key-test
                #:make-field-definition)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:cl-spec/src/explain #:expected-descriptor #:print-explain-error)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:validp #:explain-data #:spec-data
                #:definition-digest))

(in-package #:cl-spec/tests/field-representations-test)

(defun accepts-p (form value)
  "Check a DSL form, treating an unsupported declaration as a failed expectation."
  (handler-case (validp (normalize-spec-form form) value)
    (invalid-spec-form () nil)))

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(defun first-error (form value)
  "Return the first structured error of VALUE against FORM."
  (first (getf (explain-data (normalize-spec-form form) value) :errors)))

(defun make-table (&key (test 'eql) entries)
  "Build a hash table with TEST holding (KEY . VALUE) ENTRIES."
  (let ((table (make-hash-table :test test)))
    (loop for (key . value) in entries
          do (setf (gethash key table) value))
    table))

(defun alist-key-present-p (alist key)
  "Return true when KEY occurs in ALIST, even when its value is NIL."
  (not (null (assoc key alist :test #'eql))))

(defclass unprintable-key ()
  ()
  (:documentation "A hash-table key whose printer signals, for the no-print test."))

(defmethod print-object ((object unprintable-key) stream)
  (declare (ignore object stream))
  (error "print boom"))

(deftest alist-presence-and-openness
  (let ((form '(alist (:required (:id (nullable integer))) (:optional (:label string)))))
    (ok (accepts-p form '((:id . nil))))
    (ok (accepts-p form '((:label . "a") (:id . 3))))
    (ok (accepts-p form '((:extra . 7) (:id . 3))))
    (ok (not (accepts-p form '((:label . "a")))))
    (ok (not (accepts-p form '((:id . "bad")))))
    (ok (not (accepts-p form '((:id . 3) (:label . nil))))))
  (ok (accepts-p '(alist) nil))
  (ok (accepts-p '(alist) '((:anything . nil))))
  (ok (accepts-p '(alist (:closed t)) nil))
  (ok (not (accepts-p '(alist (:closed t)) '((:anything . nil)))))
  (ok (accepts-p '(alist (:required (:id integer)) (:closed t)) '((:id . 2)))))

(deftest alist-refuses-malformed-values
  (dolist (value '(42 "abc" #(:id 1) (:id . 1) 1
                   ((:id . 1) . 2) ((:id . 1) :atom) ((:id . 1) (:id . 2))))
    (ok (not (accepts-p '(alist) value))
        (format nil "~S is not a well-formed alist" value)))
  (let ((cycle (list (cons :id 1))))
    (setf (cdr cycle) cycle)
    (ok (not (accepts-p '(alist) cycle)))))

(deftest alist-duplicate-keys-are-structural-errors
  (let ((spec (normalize-spec-form '(alist (:test equal) (:required ("id" integer))))))
    (ok (accepts-p '(alist (:test equal) (:required ("id" integer)))
                   (list (cons (copy-seq "id") 1))))
    (let* ((value (list (cons (copy-seq "id") 1) (cons (copy-seq "id") 2)))
           (datum (first (getf (explain-data spec value) :errors))))
      (ok (eq :duplicate-key (getf datum :kind)))
      (ok (equal '("id") (getf datum :path))))))

(deftest key-test-decides-alist-lookup
  (testing "EQUAL finds a copied string key; EQL compares the objects apart"
    (ok (accepts-p '(alist (:test equal) (:required ("id" integer)))
                   (list (cons (copy-seq "id") 1))))
    (ok (not (accepts-p '(alist (:required ("id" integer)))
                        (list (cons (copy-seq "id") 1))))))
  (testing "an omitted :test defaults to EQL and is reported as such"
    (ok (eq :eql (field-key-test (normalize-spec-form '(alist)))))
    (ok (eq :eq (field-key-test (normalize-spec-form '(alist (:test eq))))))
    (ok (eq :eq (field-key-test (normalize-spec-form '(alist (:test :eq))))))))

(deftest hash-table-presence-and-openness
  (let ((form '(hash-table (:required (:id (nullable integer))) (:optional (:label string)))))
    (ok (accepts-p form (make-table :entries '((:id . nil)))))
    (ok (accepts-p form (make-table :entries '((:id . 3) (:label . "a")))))
    (ok (accepts-p form (make-table :entries '((:id . 3) (:extra . 7)))))
    (ok (not (accepts-p form (make-table :entries '((:label . "a"))))))
    (ok (not (accepts-p form (make-table :entries '((:id . "bad"))))))
    (ok (not (accepts-p form (make-table :entries '((:id . 3) (:label . nil)))))))
  (ok (accepts-p '(hash-table) (make-table)))
  (ok (accepts-p '(hash-table) (make-table :entries '((:anything . nil)))))
  (ok (accepts-p '(hash-table (:closed t)) (make-table)))
  (ok (not (accepts-p '(hash-table (:closed t)) (make-table :entries '((:anything . nil)))))))

(deftest hash-table-key-test-must-match
  (let ((spec (normalize-spec-form '(hash-table (:test equal) (:required ("id" integer))))))
    (ok (accepts-p '(hash-table (:test equal) (:required ("id" integer)))
                   (make-table :test 'equal :entries (list (cons (copy-seq "id") 1)))))
    (let* ((value (make-table :test 'eql :entries (list (cons (copy-seq "id") 1))))
           (datum (first (getf (explain-data spec value) :errors))))
      (ok (eq :wrong-key-test (getf datum :kind)))
      (ok (eq 'eql (getf datum :actual-test))))
    (testing "a table whose test does not match is a structure error, not a field error"
      (ok (not (accepts-p '(hash-table (:required (:id integer)))
                          (make-table :test 'equal :entries '((:id . 1)))))))
    (testing "the declared test is part of the expected contract"
      (ok (equal :equal (getf (expected-descriptor spec) :test))))))

(deftest hash-table-refuses-non-tables
  (dolist (value '(42 "abc" nil (:id . 1) #(:id 1) ((:id . 1))))
    (ok (not (accepts-p '(hash-table) value))
        (format nil "~S is not a hash table" value)))
  (ok (eq :not-a-hash-table (getf (first-error '(hash-table) 42) :kind))))

(deftest keyed-refuses-malformed-declarations
  (dolist (form '((alist (:test bogus) (:required (:id integer)))
                  (alist (:test))
                  (alist (:test equal nil))
                  (alist (:test equal) (:test eql))
                  (alist (:unknown t))
                  (alist (:closed yes))
                  (alist (:closed t nil))
                  (alist (:required (:id)))
                  (alist (:required (:id integer extra)))
                  (alist (:required (:id integer) (:id string)))
                  (alist (:test equal) (:required ((1 2) integer) ((1 2) string)))
                  (alist (:optional . :bad))
                  (alist . :bad)
                  (hash-table (:test eql) (:test equal) (:required (:id integer)))
                  (hash-table (:required (:id integer)) (:closed t nil))
                  (plist (:test equal) (:required (:id integer)))))
    (ok (refuses-form-p form) (format nil "~S must be refused" form)))
  (testing "an omitted clause is not an empty clause, and empty clauses are allowed"
    (ok (not (refuses-form-p '(alist (:required)))))
    (ok (accepts-p '(alist (:required)) nil))))

(deftest keyed-absent-key-versus-nil-value
  (let ((spec (normalize-spec-form '(alist (:required (:id (nullable integer)))))))
    (ok (validp spec '((:id . nil))))
    (let ((datum (first (getf (explain-data spec '((:other . nil))) :errors))))
      (ok (eq :missing-key (getf datum :kind)))
      (ok (equal '(:id) (getf datum :path)))))
  (let ((spec (normalize-spec-form '(alist (:required (:id integer))))))
    (ok (eq :type-failed (getf (first (getf (explain-data spec '((:id . nil))) :errors)) :kind))))
  (let ((spec (normalize-spec-form '(hash-table (:required (:id (nullable integer)))))))
    (ok (validp spec (make-table :entries '((:id . nil)))))
    (let ((datum (first (getf (explain-data spec (make-table :entries '((:other . nil)))) :errors))))
      (ok (eq :missing-key (getf datum :kind))))))

(deftest keyed-explains-field-paths
  (let ((spec (normalize-spec-form
               '(alist (:required (:user (alist (:required (:age integer)) (:closed t))))))))
    (let ((errors (getf (explain-data spec '((:user . ((:age . "bad"))))) :errors)))
      (ok (equal '(:user :age) (getf (first errors) :path)))
      (ok (eq :type-failed (getf (first errors) :kind))))
    (let ((missing (first (getf (explain-data spec '((:user . nil))) :errors))))
      (ok (eq :missing-key (getf missing :kind)))
      (ok (equal '(:user :age) (getf missing :path))))
    (let ((unknown (first (getf (explain-data spec '((:user . ((:age . 2) (:extra . t)))))
                                :errors))))
      (ok (eq :unknown-key (getf unknown :kind)))
      (ok (equal '(:user :extra) (getf unknown :path))))
    (let ((duplicate (first (getf (explain-data spec '((:user . nil) (:user . nil))) :errors))))
      (ok (eq :duplicate-key (getf duplicate :kind)))
      (ok (equal '(:user) (getf duplicate :path)))))
  (let ((spec (normalize-spec-form
               '(hash-table (:test equal)
                            (:required (:user (hash-table (:test equal)
                                                          (:required (:age integer))
                                                          (:closed t))))))))
    (let ((errors (getf (explain-data spec
                                      (make-table :test 'equal
                                                  :entries
                                                  (list (cons :user
                                                              (make-table :test 'equal
                                                                          :entries
                                                                          '((:age . "bad")))))))
                       :errors)))
      (ok (equal '(:user :age) (getf (first errors) :path))))
    (let ((missing (first (getf (explain-data spec
                                              (make-table :test 'equal
                                                          :entries
                                                          (list (cons :user
                                                                      (make-table :test 'equal)))))
                                :errors))))
      (ok (eq :missing-key (getf missing :kind)))
      (ok (equal '(:user :age) (getf missing :path))))))

(deftest keyed-introspection-and-digest
  (let* ((form '(alist (:test equal) (:optional (:label string))
                       (:required (:id integer)) (:closed t)))
         (data (spec-data (normalize-spec-form form))))
    (ok (eq :alist (getf data :kind)))
    (ok (eq :equal (getf data :test)))
    (ok (eq t (getf data :closed)))
    (ok (equal '((:key :label :required nil :child-index 0)
                 (:key :id :required t :child-index 1))
               (getf data :fields)))
    (ok (equal form (getf data :source-form)))
    (ok (getf data :definition-digest-complete))
    (let ((digest (getf data :definition-digest)))
      (dolist (other '((alist (:optional (:label string)) (:required (:id integer)) (:closed t))
                       (hash-table (:optional (:label string)) (:required (:id integer)) (:closed t))
                       (alist (:test eql) (:optional (:label string))
                              (:required (:id integer)) (:closed t))))
        (ok (not (equal digest (definition-digest (normalize-spec-form other))))))))
  (let ((data (spec-data (normalize-spec-form '(hash-table (:test equal) (:required (:id integer)))))))
    (ok (eq :hash-table (getf data :kind)))
    (ok (eq :equal (getf data :test)))
    (ok (getf data :definition-digest-complete))))

(deftest programmatic-keyed-digests-cover-fields
  (flet ((digest (class test key)
           (definition-digest
            (make-instance class :key-test test
                           :fields (list (make-field-definition
                                          :key key
                                          :value-spec (normalize-spec-form 'integer)))))))
    (let ((original (digest 'alist-spec :eql :id)))
      (ok (not (equal original (digest 'alist-spec :equal :id))))
      (ok (not (equal original (digest 'alist-spec :eql :other))))
      (ok (not (equal original (digest 'hash-table-spec :eql :id)))))))

(deftest programmatic-keyed-invariants
  (let* ((child (normalize-spec-form 'integer))
         (left (make-field-definition :key "k" :value-spec child))
         (same (make-field-definition :key (copy-seq "k") :value-spec child))
         (other (make-field-definition :key "j" :value-spec child)))
    (ok (handler-case (progn (make-instance 'alist-spec :fields (list left same)
                                            :key-test :equal)
                             nil)
          (invalid-spec-form () t)))
    (ok (eq :ok (handler-case (progn (make-instance 'alist-spec :fields (list left same)
                                                     :key-test :eql)
                                     :ok)
                 (invalid-spec-form () :refused))))
    (ok (handler-case (progn (make-instance 'hash-table-spec :fields (list left)
                                            :key-test :frobnicate)
                             nil)
          (invalid-spec-form () t)))
    (let ((spec (make-instance 'alist-spec :fields (list left other) :key-test :equal)))
      (ok (handler-case (progn (reinitialize-instance spec :fields (list left same)) nil)
            (invalid-spec-form () t)))
      (ok (handler-case (progn (reinitialize-instance spec :key-test :frobnicate) nil)
            (invalid-spec-form () t)))
      (ok (equal (list left other) (field-spec-fields spec)))
      (ok (eq :equal (field-key-test spec))))
    (testing "the base layout still validates through the shared generic"
      (ok (handler-case (progn (make-instance 'field-spec :fields (list left same)) :ok)
            (invalid-spec-form () :refused)))
      (ok (handler-case (progn (make-instance 'field-spec :fields (list left :not-a-field)) nil)
            (invalid-spec-form () t))))))

(deftest keyed-failure-identity-distinguishes-fields
  (let ((spec (normalize-spec-form '(alist (:required (:left integer) (:right integer))))))
    (ok (not (equal
              (failure-signature :return-spec
                                 (explain-data spec '((:left . "bad") (:right . 1))) nil)
              (failure-signature :return-spec
                                 (explain-data spec '((:left . 1) (:right . "bad"))) nil)))))
  (let ((spec (normalize-spec-form '(hash-table (:required (:left integer) (:right integer))))))
    (ok (not (equal
              (failure-signature :return-spec
                                 (explain-data spec (make-table :entries '((:left . "bad") (:right . 1))))
                                 nil)
              (failure-signature :return-spec
                                 (explain-data spec (make-table :entries '((:left . 1) (:right . "bad"))))
                                 nil)))))
  (testing "the same field violation in a different element is one shape"
    (let ((spec (normalize-spec-form '(list-of (alist (:required (:id integer)))))))
      (ok (equal
           (failure-signature :return-spec
                              (explain-data spec '(((:id . "bad")))) nil)
           (failure-signature :return-spec
                              (explain-data spec '(((:id . 1)) ((:id . "bad")))) nil))))))

(deftest keyed-structural-errors-remain-visible-in-conjunctions
  (let ((spec (normalize-spec-form
               '(and (alist (:test equal) (:required ("id" integer)) (:closed t))
                     (satisfies identity)))))
    (dolist (entry (list (list (list (cons (copy-seq "id") 1) (cons "extra" 2)) "unknown key")
                         (list (list (cons (copy-seq "id") 1) (cons (copy-seq "id") 2))
                               "duplicate key")
                         (list nil "missing key")
                         (list 42 "not an alist")))
      (let* ((datum (first (getf (explain-data spec (first entry)) :errors)))
             (printed (with-output-to-string (out) (print-explain-error datum out 0))))
        (ok (search (second entry) printed :test #'char-equal)
            (format nil "~S must stay visible: ~A" (first entry) printed))))))

(deftest programmatic-key-tests-are-canonicalized
  (testing "a plain symbol key test is stored as the canonical keyword"
    (let* ((field (make-field-definition :key "id" :value-spec (normalize-spec-form 'integer)))
           (spec (make-instance 'hash-table-spec :key-test 'equal :fields (list field))))
      (ok (eq :equal (field-key-test spec)))
      (ok (eq :equal (getf (spec-data spec) :test)))
      (ok (validp spec (make-table :test 'equal :entries (list (cons (copy-seq "id") 1)))))
      (ok (not (validp spec (make-table :test 'equal :entries (list (cons "other" 1))))))
      (reinitialize-instance spec :key-test 'eql)
      (ok (eq :eql (field-key-test spec))))))

(deftest hash-table-unknown-keys-never-print
  (testing "ordering unknown-key errors does not invoke a user printer"
    (let ((spec (normalize-spec-form '(hash-table (:closed t))))
          (table (make-hash-table :test 'eql)))
      (setf (gethash (make-instance 'unprintable-key) table) 1)
      (setf (gethash (make-instance 'unprintable-key) table) 2)
      (let ((errors (getf (explain-data spec table) :errors)))
        (ok (= 2 (length errors)))
        (ok (every (lambda (datum) (eq :unknown-key (getf datum :kind))) errors)))
      (ok (not (validp spec table))))))
