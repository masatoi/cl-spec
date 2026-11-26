;;;; tests/self-specs-test.lisp

(defpackage #:cl-spec/tests/self-specs-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/specs)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec-cases #:function-case-name #:function-case-outcome-spec)
  (:import-from #:cl-spec/main
                #:*registry*
                #:check-contracts
                #:check-function
                #:clear-registry
                #:defproperty
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
                #:property-result-status
                #:property-targets
                #:property-trials
                #:result-data
                #:run-property
                #:spec-data
                #:validp)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/self-specs-test)

(deftest generation-law-covers-structured-spec-kinds
  (let ((kinds (mapcar #'cl-spec:spec-kind cl-spec/specs::*generation-corpus*)))
    (dolist (kind '(:alist :hash-table :alist-of :hash-table-of :tagged-union :and))
      (ok (member kind kinds) (format nil "Generation law exercises ~S" kind)))))

(deftest structured-generation-laws-are-registered-and-executable
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (name '(cl-spec/specs::structured-retained-counterexamples-stay-valid
                    cl-spec/specs::generation-exhaustion-preserves-budget-evidence
                    cl-spec/specs::tagged-generation-reaches-each-declared-branch))
      (ok (member name (list-properties)))
      (when (member name (list-properties))
        (let ((result (run-property name :profile :smoke :seed 42)))
          (ok (eq :passed (property-result-status result))
              (prin1-to-string (result-data result))))))))

(deftest coverage-apis-have-executable-contracts
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (name '(cl-spec:coverage-schema cl-spec:coverage-data))
      (ok (find-function-spec name))
      (ok (eq :passed (property-result-status (check-function name :trials 5 :seed 42)))))))

(deftest evidence-apis-have-executable-contracts
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (name '(cl-spec:evidence-summary cl-spec:assess-evidence))
      (ok (find-function-spec name))
      (ok (eq :passed (property-result-status (check-function name :trials 20 :seed 42)))))
    (let ((observation (cl-spec:check-fixture
                        (cl-spec/self-spec-fixtures:fresh-fixture-contract) 7)))
      (dolist (policy '(nil (:policy-version 1 :requirements
                            ((:kind :min-checked-trials :count 1)))))
        (ok (eq :passed
                (getf (cl-spec:call-check-data
                       (cl-spec:check-call 'cl-spec:assess-evidence (list observation policy)))
                      :status)))))))

(deftest fixture-apis-have-executable-contracts
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (name '(cl-spec:check-fixture cl-spec:fixture-check-data))
      (ok (find-function-spec name))
      (ok (eq :passed (property-result-status
                       (check-function name :trials 5 :seed 42)))))
    (ok (eq :passed
            (property-result-status
             (run-property 'cl-spec/specs::fixture-reconstruction-is-independent :seed 42))))))

(deftest command-sequence-checker-has-an-executable-contract
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (find-function-spec 'cl-spec:check-state-machine))
    (when (find-function-spec 'cl-spec:check-state-machine)
      (ok (eq :passed (property-result-status
                       (check-function 'cl-spec:check-state-machine :trials 20 :seed 2)))))))

(deftest state-machine-self-contract-describes-foreign-machines
  (let ((*registry* (make-hash-table-registry)) (target-calls 0))
    (cl-spec/specs:register-specifications)
    (cl-spec:defspec accepted-command (or (member :drop) (tuple (member :add) integer)))
    (let ((machine (cl-spec:defstate-machine agreeing (commands accepted-command :max-length 3)
                     :model 0 :target 0
                     :model-step (lambda (model command)
                                   (declare (ignore command)) (values (1+ model) model))
                     :target-step (lambda (target command)
                                    (declare (ignore command)) (incf target-calls)
                                    (values (1+ target) target)))))
      (flet ((check (commands)
               (getf (cl-spec:call-check-data
                      (cl-spec:check-call 'cl-spec:check-state-machine (list machine commands)))
                     :status)))
        (ok (eq :passed (check '(:drop))))
        (ok (eq :passed (check '((:add 2) :drop))))
        (ok (= 3 target-calls))
        (ok (eq :rejected (check '(:tick))))
        (ok (= 3 target-calls))))
    (let ((ordinary (cl-spec:defproperty impostor ((commands list))
                      (:kind :state-machine) (listp commands))))
      (ok (handler-case
              (progn (cl-spec:check-call 'cl-spec:check-state-machine (list ordinary nil)) nil)
            (cl-spec:invalid-call-arguments () t))))))

(deftest counter-machine-semantic-law-checks-the-first-divergence
  (let ((*registry* (make-hash-table-registry))
        (name 'cl-spec/specs::counter-machine-reports-first-dropped-increment))
    (cl-spec/specs:register-specifications)
    (ok (member name (cl-spec/specs:property-names)))
    (ok (member name (properties-for 'cl-spec:check-state-machine)))
    (let ((property (find-property name)))
      (when property
        (dolist (commands '(() (:tick :tick) (:drop) (:tick :drop :drop)))
          (ok (funcall (cl-spec:property-function property) commands)))
        (ok (eq :passed (property-result-status (run-property name :profile :smoke :seed 2))))))))

(deftest rest-projection-has-an-executable-law
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (eq :passed
            (property-result-status
             (run-property 'cl-spec/specs::rest-projection-agrees-with-target
                           :seed 42))))))

(deftest keyword-registry-is-covered-by-self-specification
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (find-function-spec 'cl-spec:definition-digest))
    (ok (eq :passed
            (property-result-status
             (check-function 'cl-spec:definition-digest :trials 50 :seed 42))))))

(deftest optional-registry-is-covered-by-self-specification
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (find-function-spec 'cl-spec:find-spec))
    (ok (eq :passed
            (property-result-status
             (check-function 'cl-spec:find-spec :trials 50 :seed 42))))))

(deftest multiple-values-are-covered-by-self-specifications
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (dolist (entry '((cl-spec:find-spec 2) (cl-spec:definition-digest 3)))
      (let* ((contract (find-function-spec (first entry)))
             (schema (cl-spec:function-spec-return-spec contract)))
        (ok (eq :values (cl-spec:spec-kind schema)))
        (ok (= (second entry) (length (cl-spec:spec-children schema))))
        (ok (= (second entry) (length (cl-spec:function-spec-post-value-variables contract))))
        (ok (eq :passed (property-result-status
                         (check-function contract :trials 50 :seed 42))))))))

(deftest target-outcome-has-an-executable-data-contract
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (find-function-spec 'cl-spec:trial-observation-outcome))
    (ok (eq :passed
            (property-result-status
             (check-function 'cl-spec:trial-observation-outcome :trials 20 :seed 42))))))

(deftest custom-shrinker-reader-has-an-executable-contract
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (ok (find-function-spec 'cl-spec:custom-generator-shrinker))
    (ok (eq :passed
            (property-result-status
             (check-function 'cl-spec:custom-generator-shrinker :trials 20 :seed 42))))))

(deftest malformed-dsl-has-an-executable-error-contract
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let ((contract (find-function-spec 'cl-spec:normalize-spec-form)))
      (ok contract)
      (when contract
        (ok (getf (function-spec-data 'cl-spec:normalize-spec-form) :signals))
        (ok (null (function-spec-return-spec contract)))
        (ok (eq :passed
                (property-result-status
                 (check-function 'cl-spec:normalize-spec-form :trials 50 :seed 42))))))))

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
    ;; Re-registration must not duplicate an index or a registered name: the
    ;; bundle's declared lists are exactly what the registry holds, twice over.
    (cl-spec:clear-registry)
    (cl-spec/specs:register-specifications)
    (let ((contracts (cl-spec:list-function-specs))
          (properties (cl-spec:list-properties)))
      (ok (plusp (length contracts)))
      (ok (plusp (length properties)))
      (ok (null (set-exclusive-or contracts (cl-spec/specs:contract-names))))
      (ok (null (set-exclusive-or properties (cl-spec/specs:property-names))))
      (ok (= (length contracts) (length (remove-duplicates contracts))))
      (ok (= (length properties) (length (remove-duplicates properties)))))))

(deftest executable-specifications-use-the-current-registry
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (original-validp (fdefinition 'cl-spec:validp)))
    (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
      (cl-spec/specs:register-specifications)
      (ok (null (set-exclusive-or (cl-spec:list-function-specs)
                                  (cl-spec/specs:contract-names))))
      (ok (null (set-exclusive-or (cl-spec:list-properties)
                                  (cl-spec/specs:property-names))))
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
                 (cl-spec/specs::member 1 "two" :three)
                 (cl-spec/specs::vector-of integer)
                 (cl-spec/specs::plist (:required (:id integer)) (:closed t))
                 (cl-spec/specs::plist (:required (:id integer))
                                       (:optional (:nickname (cl-spec/specs::nullable string))))
                 (cl-spec/specs::list-of integer :min-length 1 :max-length 3)
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

(defun checked-explanation-spec ()
  "Return EXPLAIN-DATA's return spec for a completed validation."
  (let ((contract (find-function-spec 'explain-data)))
    (function-case-outcome-spec
     (find :checked (function-spec-cases contract) :key #'function-case-name))))

(deftest executable-data-specs-refuse-inconsistent-evidence
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let* ((spec (cl-spec:normalize-spec-form 'integer))
           (return-spec (checked-explanation-spec))
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
    (let ((spec (checked-explanation-spec))
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
           (fields (getf (first (getf data :children)) :fields)))
      (ok (eq :and (getf data :kind)))
      (ok (find :schema-version fields :key (lambda (field) (getf field :key)))))))

(deftest result-self-spec-checks-trial-profiles
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (defproperty profile-result-property ((value (member 1)))
      (:trials (:smoke 1 :normal 1 :extended 1 :stress 1))
      (= value 1))
    (let ((return-spec (function-spec-return-spec (find-function-spec 'result-data))))
      (dolist (profile '(:smoke :normal :extended :stress))
        (testing (format nil "Result for profile ~S" profile)
          (let ((data (result-data (run-property 'profile-result-property
                                                 :seed 1 :profile profile))))
            (ok (eq profile (getf data :profile)))
            (ok (eq :passed (getf data :status)))
            (ok (validp return-spec data))
            (setf (getf data :profile) :unknown)
            (ok (not (validp return-spec data)) "An unknown profile is rejected")))))))

(deftest executable-digest-details-refuse-inconsistent-metadata
  (let ((*registry* (make-hash-table-registry)))
    (cl-spec/specs:register-specifications)
    (let* ((contract (find-function-spec 'cl-spec:spec-data))
           (spec (function-spec-return-spec contract))
           (data (spec-data (normalize-spec-form 'integer))))
      (setf (getf data :digest-omissions)
            '((:kind :opaque-value :path (:declarations 0) :target nil :reason :function-object)))
      (ok (not (validp spec data))))
    (let* ((contract (find-function-spec 'cl-spec:spec-data))
           (spec (function-spec-return-spec contract))
           (data (spec-data (normalize-spec-form 'integer))))
      (setf (getf data :digest-exclusions) :unknown)
      (ok (not (validp spec data))))))

(deftest executable-specifications-pass-generated-checks
  (let ((*registry* (make-hash-table-registry))
        (seeds '(1 42 2026))
        (contract-budget 50))
    (cl-spec/specs:register-specifications)
    (flet ((check-suite (names budget)
             (let* ((report (check-contracts :names names :seeds seeds :trials budget
                              :policy (cl-spec/specs:evidence-policy budget)))
                    (entries (getf report :entries)))
               (ok (eq :passed (getf report :status))
                   (prin1-to-string (getf report :problems)))
               (ok (= (* (length names) (length seeds)) (length entries)))
               (dolist (entry entries)
                 (let ((result (getf entry :result)))
                   (testing (format nil "~S ~S, seed ~A"
                                    (getf entry :kind) (getf entry :name) (getf entry :seed))
                     (ok (eq :passed (getf entry :verdict)) (prin1-to-string entry))
                     (ok (eql budget (getf result :trials)))
                     (ok (eql 0 (getf result :rejected)))))))))
      (check-suite (mapcar (lambda (name) (list :function-spec name))
                           (cl-spec/specs:contract-names))
                   contract-budget)
      (dolist (name (cl-spec/specs:property-names))
        (let ((budget (getf (property-trials (find-property name)) :normal)))
          (ok (typep budget '(integer 1 *))
              (format nil "~S declares no positive :normal budget" name))
          (when (typep budget '(integer 1 *))
            (check-suite (list (list :property name)) budget)))))))
