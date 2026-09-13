;;;; tests/self-specs-test.lisp

(defpackage #:cl-spec/tests/self-specs-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/specs)
  (:import-from #:cl-spec/main
                #:*registry*
                #:check-function
                #:clear-registry
                #:explain-data
                #:find-function-spec
                #:find-property
                #:function-spec-data
                #:function-spec-return-spec
                #:list-function-specs
                #:list-properties
                #:make-hash-table-registry
                #:normalize-spec-form
                #:properties-for
                #:property-data
                #:property-result-rejected
                #:property-result-status
                #:property-result-trials
                #:property-targets
                #:result-data
                #:run-property
                #:spec-data
                #:validp)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/self-specs-test)

(deftest executable-specifications-are-discoverable
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (name (cl-spec/specs:contract-names))
      (ok (eq name (getf (cl-spec:function-spec-data name) :name)))
      (ok (eq :function-spec (getf (cl-spec:function-spec-data name) :entity-kind))))
    (dolist (name (cl-spec/specs:property-names))
      (let ((data (cl-spec:property-data name)))
        (ok (getf data :body))
        (dolist (target (cl-spec:property-targets (cl-spec:find-property name)))
          (ok (member name (cl-spec:properties-for target))))))
    (cl-spec:clear-registry)
    (cl-spec/specs:register-specifications)
    (ok (= 7 (length (cl-spec:list-function-specs))))
    (ok (= 7 (length (cl-spec:list-properties))))))

(deftest executable-specifications-use-the-current-registry
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (original-validp (fdefinition 'cl-spec:validp)))
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec/specs:register-specifications)
      (ok (= 7 (length (cl-spec:list-function-specs))))
      (ok (= 7 (length (cl-spec:list-properties))))
      (ok (eq original-validp (fdefinition 'cl-spec:validp))))
    (ok (null (cl-spec:list-function-specs)))
    (ok (null (cl-spec:list-properties)))))

(deftest normalization-laws-declare-their-finite-domain
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let* ((property (cl-spec:find-property (first (cl-spec/specs:property-names))))
           (domain (second (first (cl-spec:property-arguments property)))))
      (ok (cl-spec:validp domain 'integer))
      (ok (not (cl-spec:validp domain '(range)))))
    (let ((contract (cl-spec:find-function-spec 'cl-spec:validp)))
      ;; API contracts remain broader than the bounded generation corpus.
      (ok (cl-spec:validp
           (second (first (cl-spec:function-spec-argument-specs contract)))
           (cl-spec:normalize-spec-form '(member :outside :the :sample)))))))

(deftest sampled-dsl-domain-boundaries
  (dolist (form '(integer string (or integer string) (not integer)
                 (cl-spec/specs::nullable integer)
                 (cl-spec/specs::list-of integer)
                 (cl-spec/specs::tuple integer string)
                 (cl-spec/specs::range integer -1 1)
                 (cl-spec/specs::range integer -20 20)
                 (and integer (cl-spec/specs::range -1 1))
                 (and integer (cl-spec/specs::range -20 20))))
    (ok (cl-spec/specs::sampled-dsl-form-p form)))
  (dolist (form '(nil 42 "integer" :integer (integer) (cl-spec/specs::range)
                 (cl-spec/specs::range integer 0 0)
                 (cl-spec/specs::range integer -21 21)
                 (cl-spec/specs::range integer -1 2)
                 (cl-spec/specs::range integer -1.0 1.0)
                 (cl-spec/specs::range integer -1 1 extra)
                 (cl-spec/specs::range integer -1 . 1)
                 (and integer (cl-spec/specs::range -21 21))
                 (and integer (cl-spec/specs::range -1 . 1))
                 (or string integer) (cl-spec/specs::tuple integer string extra)))
    (ok (not (cl-spec/specs::sampled-dsl-form-p form))))
  (let ((circular (list 'cl-spec/specs::range 'integer -1 1)))
    (setf (cdr (last circular)) circular)
    (ok (not (cl-spec/specs::sampled-dsl-form-p circular)))))

(deftest executable-data-specs-refuse-inconsistent-evidence
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let* ((spec (cl-spec:normalize-spec-form 'integer))
           (contract (cl-spec:find-function-spec 'cl-spec:explain-data))
           (return-spec (cl-spec:function-spec-return-spec contract))
           (good (cl-spec:explain-data spec 1)))
      (ok (cl-spec:validp return-spec good))
      (let ((bad (copy-list good)))
        (setf (getf bad :valid) nil)
        (ok (not (cl-spec:validp return-spec bad))))
      (let ((bad (copy-list good)))
        (remf bad :errors)
        (setf (getf bad :value) :errors)
        (ok (not (cl-spec:validp return-spec bad)))))
    (let* ((contract (cl-spec:find-function-spec 'cl-spec:spec-data))
           (return-spec (cl-spec:function-spec-return-spec contract))
           (data (cl-spec:spec-data (cl-spec:normalize-spec-form 'integer))))
      (setf (getf data :entity-kind) :property)
      (ok (not (cl-spec:validp return-spec data))))))

(deftest executable-data-specs-check-field-structure
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let* ((contract (cl-spec:find-function-spec 'cl-spec:explain-data))
           (spec (cl-spec:function-spec-return-spec contract))
           (data (cl-spec:explain-data (cl-spec:normalize-spec-form 'integer) "bad")))
      (ok (not (cl-spec:validp spec (append data '(:valid nil)))))
      (setf (getf data :errors) '(broken . errors))
      (ok (not (cl-spec:validp spec data))))
    (let* ((contract (cl-spec:find-function-spec 'cl-spec:spec-data))
           (spec (cl-spec:function-spec-return-spec contract))
           (data (cl-spec:spec-data (cl-spec:normalize-spec-form 'integer))))
      (setf (getf data :definition-digest-complete) :yes)
      (ok (not (cl-spec:validp spec data))))
    (let* ((data (cl-spec:spec-data 'cl-spec/specs::spec-description-data))
           (fields (getf data :fields)))
      (ok (eq :plist (getf data :kind)))
      (ok (find :schema-version fields :key (lambda (field) (getf field :key)))))))

(deftest executable-specifications-pass-generated-checks
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (seed '(1 42 2026))
      (dolist (name (cl-spec/specs:contract-names))
        (testing (format nil "contract ~S, seed ~D" name seed)
          (let ((result (cl-spec:check-function name :trials 50 :seed seed)))
            (ok (eq :passed (cl-spec:property-result-status result))
                (prin1-to-string (cl-spec:result-data result)))
            (ok (= 50 (cl-spec:property-result-trials result)))
            (ok (zerop (cl-spec:property-result-rejected result))))))
      (dolist (name (cl-spec/specs:property-names))
        (testing (format nil "property ~S, seed ~D" name seed)
          (let ((result (cl-spec:run-property name :seed seed)))
            (ok (eq :passed (cl-spec:property-result-status result))
                (prin1-to-string (cl-spec:result-data result)))
            (ok (= 50 (cl-spec:property-result-trials result)))))))))
