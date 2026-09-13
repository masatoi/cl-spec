;;;; tests/plist-test.lisp

(defpackage #:cl-spec/tests/plist-test
  (:use #:cl)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:field-spec #:field-spec-fields #:field-spec-closed-p
                #:field-key #:make-field-definition)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:validp #:explain-data #:spec-data
                #:definition-digest #:invalid-spec-form))

(in-package #:cl-spec/tests/plist-test)

(defvar *plist-predicate-calls* 0
  "Number of child predicate calls during plist structural validation tests.")

(defun counted-plist-field-p (value)
  "Record a child predicate call and accept VALUE."
  (declare (ignore value))
  (incf *plist-predicate-calls*)
  t)

(defun accepts-p (form value)
  "Check a DSL form, treating unsupported syntax as a failed expectation."
  (handler-case (validp (normalize-spec-form form) value)
    (invalid-spec-form () nil)))

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(deftest plist-presence-and-openness
  (let ((form '(plist (:required (:id (nullable integer))) (:optional (:label string)))))
    (ok (accepts-p form '(:id nil)))
    (ok (accepts-p form '(:label "a" :id 3)))
    (ok (accepts-p form '(:extra 7 :id 3)))
    (ok (not (accepts-p form '(:label "a"))))
    (ok (not (accepts-p form '(:id "bad"))))
    (ok (not (accepts-p form '(:id 3 :label nil)))))
  (ok (accepts-p '(plist) nil))
  (ok (accepts-p '(plist) '(:anything nil)))
  (ok (accepts-p '(plist (:closed t)) nil))
  (ok (not (accepts-p '(plist (:closed t)) '(:anything nil))))
  (ok (accepts-p '(plist (:required (:id integer)) (:closed t)) '(:id 2))))

(deftest plist-refuses-malformed-values
  (dolist (value '(42 "abc" #(:id 1) (:id) (:id 1 :tail)
                  (:id . 1) (:id 1 . 2) (id 1) (:id 1 :id 2)))
    (ok (not (accepts-p '(plist) value))))
  (let ((cycle (list :id 1)))
    (setf (cddr cycle) cycle)
    (ok (not (accepts-p '(plist) cycle)))))

(deftest malformed-plists-do-not-call-child-predicates
  (let ((spec (normalize-spec-form
                '(plist (:required (:id (satisfies counted-plist-field-p))))))
         (cycle (list :id 1)))
    (setf (cddr cycle) cycle)
    (dolist (value (list '(:id 1 :id 2) '(:id 1 :tail)
                        '(:id 1 . :tail) cycle '(:id 1 foreign 2)))
      (let ((*plist-predicate-calls* 0))
        (ok (not (validp spec value)))
        (ok (zerop *plist-predicate-calls*))
        (ok (getf (explain-data spec value) :errors))
        (ok (zerop *plist-predicate-calls*))))))

(deftest plist-refuses-malformed-declarations
  (dolist (form '((plist (:unknown t))
                  (plist (:closed))
                  (plist (:closed yes))
                  (plist (:closed t nil))
                  (plist (:closed nil) (:closed t))
                  (plist (:required (:id integer)) (:required))
                  (plist (:required (id integer)))
                  (plist (:required (:id)))
                  (plist (:required (:id integer extra)))
                  (plist (:required (:id integer) (:id string)))
                  (plist (:required (:id integer)) (:optional (:id string)))
                  (plist (:optional . :bad))
                  (plist . :bad)))
    (ok (refuses-form-p form)))
  (let ((form (list 'plist (list :required (list :id 'integer)))))
    (setf (cddr form) form)
    (ok (refuses-form-p form))))

(deftest plist-explains-field-paths
  (handler-case
      (let* ((spec (normalize-spec-form
                    '(plist (:required
                              (:user (plist (:required (:age integer)) (:closed t)))))))
             (errors (getf (explain-data spec '(:user (:age "bad"))) :errors)))
        (ok (equal '(:user :age) (getf (first errors) :path)))
        (ok (eq :type-failed (getf (first errors) :kind)))
        (let ((missing (first (getf (explain-data spec '(:user nil)) :errors))))
          (ok (eq :missing-key (getf missing :kind)))
          (ok (equal '(:user :age) (getf missing :path))))
        (let ((unknown (first (getf (explain-data spec '(:user (:age 2 :extra t)))
                                    :errors))))
          (ok (eq :unknown-key (getf unknown :kind)))
          (ok (equal '(:user :extra) (getf unknown :path))))
        (let ((duplicate (first (getf (explain-data spec '(:user nil :user nil))
                                      :errors))))
          (ok (eq :duplicate-key (getf duplicate :kind)))
          (ok (equal '(:user) (getf duplicate :path)))))
    (invalid-spec-form () (ok nil "PLIST must normalize before explaining fields"))))

(deftest plist-introspection-retains-field-associations
  (handler-case
      (let* ((form '(plist (:optional (:label string)) (:required (:id integer))
                          (:closed t)))
             (data (spec-data (normalize-spec-form form))))
        (ok (eq :plist (getf data :kind)))
        (ok (eq t (getf data :closed)))
        (ok (equal '((:key :label :required nil :child-index 0)
                     (:key :id :required t :child-index 1))
                   (getf data :fields)))
        (ok (equal '(string integer) (mapcar (lambda (child) (getf child :type))
                                            (getf data :children))))
        (ok (equal form (getf data :source-form)))
        (ok (getf data :definition-digest-complete))
        (let ((digest (getf data :definition-digest)))
          (dolist (other '((plist (:required (:id string)))
                           (plist (:required (:other integer)))
                           (plist (:optional (:id integer)))
                           (plist (:required (:id integer)) (:closed nil))))
            (ok (not (equal digest (definition-digest (normalize-spec-form other))))))))
    (invalid-spec-form () (ok nil "PLIST must expose field semantics"))))

(deftest programmatic-plist-digests-cover-fields
  (flet ((digest (key required-p closed-p child)
           (definition-digest
            (make-instance 'plist-spec :closed-p closed-p
                           :fields (list (make-field-definition
                                          :key key :required-p required-p
                                          :value-spec (normalize-spec-form child)))))))
    (let ((original (digest :id t nil 'integer)))
      (ok (not (equal original (digest :other t nil 'integer))))
      (ok (not (equal original (digest :id nil nil 'integer))))
      (ok (not (equal original (digest :id t t 'integer))))
      (ok (not (equal original (digest :id t nil 'string)))))))

(deftest programmatic-plist-invariants
  (let* ((*print-circle* t)
         (child (normalize-spec-form 'integer))
         (field (make-field-definition :key :id :value-spec child))
         (foreign (make-field-definition :key 'id :value-spec child))
         (cycle (list field)))
    (setf (cdr cycle) cycle)
    (dolist (fields (list (list foreign) (list field field) (list :id)
                         (cons field :tail) cycle :not-a-list))
      (ok (handler-case (progn (make-instance 'plist-spec :fields fields) nil)
            (invalid-spec-form () t))))
    (ok (handler-case (progn (make-instance 'plist-spec :closed-p :yes) nil)
          (invalid-spec-form () t)))
    (let ((spec (make-instance 'plist-spec :fields (list field))))
      (dolist (initargs (list (list :fields (list foreign) :closed-p t)
                             (list :fields (list field field))
                             (list :fields cycle)
                             (list :fields nil :closed-p :yes)))
        (ok (handler-case (progn (apply #'reinitialize-instance spec initargs) nil)
              (invalid-spec-form () t)))
        (ok (equal (list field) (field-spec-fields spec)))
        (ok (null (field-spec-closed-p spec))))
      (reinitialize-instance spec :fields nil :closed-p t)
      (ok (null (field-spec-fields spec)))
      (ok (eq t (field-spec-closed-p spec))))
    (ok (eq 'id (field-key
                 (first (field-spec-fields
                         (make-instance 'field-spec :fields (list foreign)))))))))

(deftest plist-failure-identity-distinguishes-fields
  (let ((spec (normalize-spec-form
               '(plist (:required (:left integer) (:right integer))))))
    (ok (not (equal
              (failure-signature :return-spec
                                 (explain-data spec '(:left "bad" :right 1)) nil)
              (failure-signature :return-spec
                                 (explain-data spec '(:left 1 :right "bad")) nil)))))
  (let ((spec (normalize-spec-form '(list-of (plist (:required (:id integer)))))))
    (ok (equal
         (failure-signature :return-spec (explain-data spec '((:id "bad"))) nil)
         (failure-signature :return-spec
                            (explain-data spec '((:id 1) (:id "bad"))) nil)))))
