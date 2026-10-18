;;;; tests/self-api-contracts-test.lisp
;;;;
;;;; Direct checks around the self-specification bundle: that registration,
;;;; discovery and execution agree, that the named cases really run the inputs
;;;; they claim, and that the projection specs refuse a record with a required
;;;; field removed or changed.  These are concrete expectations and boundary
;;;; inputs; specs.lisp holds the general laws.

(defpackage #:cl-spec/tests/self-api-contracts-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/specs
                #:contract-names
                #:evidence-policy
                #:property-names
                #:register-specifications)
  (:import-from #:cl-spec/main
                #:*registry*
                #:assess-evidence
                #:check-fixture
                #:check-function
                #:deserialize-counterexample-artifact
                #:fixture-check-data
                #:hash-table-registry
                #:make-counterexample-artifact
                #:recheck-counterexample
                #:serialize-counterexample-artifact
                #:defproperty
                #:find-function-spec
                #:find-property
                #:find-spec
                #:function-check-result-case-report
                #:function-spec-argument-schema
                #:function-spec-data
                #:function-spec-return-spec
                #:list-function-specs
                #:list-properties
                #:make-hash-table-registry
                #:normalize-spec-form
                #:properties-for
                #:properties-with-tag
                #:property-result-rejected
                #:property-result-status
                #:property-result-trials
                #:property-targets
                #:registry-register-property
                #:result-data
                #:run-property
                #:spec-violation
                #:validate
                #:validp)
  (:import-from #:cl-spec/self-generation-fixtures
                #:structured-generation-forms #:structured-counterexample-contracts
                #:retained-counterexample-valid-p #:generation-exhaustion-observations)
  (:import-from #:cl-spec/self-spec-fixtures
                #:*registry-constructor*
                #:*scripted-registration-scenarios*
                #:*scripted-state-inputs*
                #:*scripted-validate-inputs*
                #:*self-state-balance*
                #:*self-state-calls*
                #:*self-state-scenario*
                #:function-projection-fixtures
                #:registration-scenario
                #:registration-scenario-state-p
                #:self-registration-name
                #:state-projection-fixtures)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/self-api-contracts-test)

(deftest structured-generation-has-independent-map-oracles
  ;; The first eight fixtures deliberately saturate a two-key domain under
  ;; each comparison. Check with CL operations, independently of VALIDP.
  (loop for form in (subseq (structured-generation-forms) 0 8)
        for index from 0
        for test = (nth (mod index 4) '(eq eql equal equalp))
        for samples = (cl-spec:sample (normalize-spec-form form) :count 10 :seed 42)
        do (ok (= 10 (length samples)))
           (dolist (value samples)
             (let ((keys (if (hash-table-p value)
                             (loop for key being the hash-keys of value collect key)
                             (mapcar #'car value)))
                   (values (if (hash-table-p value)
                               (loop for item being the hash-values of value collect item)
                               (mapcar #'cdr value))))
               (ok (= 2 (length keys)))
               (ok (= 2 (length (remove-duplicates keys :test test))))
               (when (eq test 'eql)
                 (ok (= 1 (length (remove-duplicates keys :test #'equalp)))))
               (ok (every (lambda (item) (and (integerp item) (<= 10 item 30))) values)))
             (when (hash-table-p value)
               (ok (eq test (hash-table-test value)))))))

(deftest structured-retention-exercises-real-shrinks-and-empty-domains
  (loop for contract in (structured-counterexample-contracts)
        for form in (structured-generation-forms :recheck-p t)
        for index from 0
        for result = (check-function contract :trials 1 :seed 1)
        do (testing (format nil "~S" form)
             (ok (retained-counterexample-valid-p
                  contract result :require-reduction (not (<= 10 index 13))))
             (if (<= 10 index 13)
                 (progn
                   (ok (eq :none (cl-spec:property-result-shrunk-outcome result)))
                   (ok (null (cl-spec:property-result-shrunk-evidence result))))
                 (progn
                   ;; Merely falling back to the original must not make this
                   ;; acceptance check pass: these seed-1 fixtures do shrink.
                   (ok (eq :used (cl-spec:property-result-shrunk-outcome result)))
                   (ok (cl-spec:property-result-shrunk-evidence result)))))))

(deftest retained-evidence-law-refuses-invalid-or-different-failures
  (let* ((contract (first (structured-counterexample-contracts)))
         (result (check-function contract :trials 1 :seed 42))
         (original (cl-spec:property-result-failure-evidence result))
         (signature (cl-spec:trial-observation-signature original)))
    (flet ((saved (shrunk &key (failure original) (outcome :used))
             (make-instance 'cl-spec:property-result :status :failed :trials 1
                            :failure-evidence failure :shrunk-evidence shrunk
                            :shrunk-outcome outcome))
           (observation (arguments identity &optional (status :failed))
             (cl-spec:make-trial-observation :arguments arguments :signature identity
                                             :status status :reason :return-spec)))
      (ok (not (retained-counterexample-valid-p contract (saved nil))))
      (ok (not (retained-counterexample-valid-p
                contract (saved original) :require-reduction t)))
      (ok (not (retained-counterexample-valid-p
                contract
                (saved (observation
                        (copy-tree (cl-spec:trial-observation-arguments original)) signature))
                :require-reduction t)))
      (ok (not (retained-counterexample-valid-p
                contract (saved nil :failure nil :outcome :none))))
      (dolist (arguments '((nil) (((:a . 10))) (((:a . 10) (:a . 11)))
                           (((:a . 9) (:b . 10)))))
        (ok (not (retained-counterexample-valid-p
                  contract (saved (observation arguments signature))))))
      (ok (not (retained-counterexample-valid-p
                contract (saved (observation '(((:a . 10) (:b . 11))) '(:property-false))))))
      (ok (not (retained-counterexample-valid-p
                contract (saved (observation '(((:a . 10) (:b . 11))) signature :passed))))))
      ;; Even matching saved signatures are insufficient if CHECK-CALL now
      ;; passes: recheck the target, not just the evidence record.
      (let ((passing (make-instance 'cl-spec:function-spec
                                    :name (cl-spec:function-spec-name contract)
                                    :argument-specs (cl-spec:function-spec-argument-specs contract)
                                    :return-spec t)))
        (ok (not (retained-counterexample-valid-p passing result))))))

(deftest a-copied-table-is-not-evidence-of-reduction
  (let* ((contract (fifth (structured-counterexample-contracts)))
         (result (check-function contract :trials 1 :seed 1))
         (original (cl-spec:property-result-failure-evidence result))
         (table (first (cl-spec:trial-observation-arguments original)))
         (copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value) (setf (gethash key copy) value)) table)
    (let* ((candidate
             (cl-spec:make-trial-observation
              :arguments (list copy) :status :failed :reason :return-spec
              :signature (cl-spec:trial-observation-signature original)))
           (saved (make-instance 'cl-spec:property-result
                                 :status :failed :trials 1 :failure-evidence original
                                 :shrunk-evidence candidate :shrunk-outcome :used)))
      (ok (not (eq table copy)))
      (ok (retained-counterexample-valid-p contract saved))
      (ok (not (retained-counterexample-valid-p contract saved :require-reduction t))))))

(deftest identity-sensitive-string-members-are-not-recheck-domains
  (let* ((form (third (structured-generation-forms)))
         (contract (make-instance 'cl-spec:function-spec
                                 :name 'identity :argument-specs (list (list 'value form))
                                 :return-spec '(member :impossible-return)))
         (result (check-function contract :trials 1 :seed 42)))
    ;; MEMBER uses EQL even when the map uses EQUAL. Copying a string while
    ;; saving cons/array evidence loses membership identity. Do not call this
    ;; a successful recheck or change MEMBER semantics to make it pass.
    (ok (not (retained-counterexample-valid-p contract result)))
    (ok (not (validp (function-spec-argument-schema contract)
                     (cl-spec:trial-observation-arguments
                      (cl-spec:property-result-failure-evidence result)))))))

(deftest generation-budget-boundaries-keep-paths-and-registry-isolation
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let ((before (list-properties))
          (generators (cl-spec:list-generators)))
      (dolist (budget '(0 1 5))
        (let ((reports (generation-exhaustion-observations budget)))
          (ok (= 3 (length reports)))
          (loop for report in reports
                for path in '((0) (:map-key) (:map-key))
                do (ok (eq :budget-exhausted (getf report :termination)))
                   (ok (eq :generation (getf report :exhaustion-phase)))
                   (ok (equal path (getf report :exhausted-at)))
                   (ok (= budget (getf report :attempts)))
                   (ok (= budget (getf report :rejections)))
                   (ok (zerop (getf report :generated-values))))))
      (ok (equal before (list-properties)))
      (ok (equal generators (cl-spec:list-generators))))))

(deftest self-specification-lists-are-internally-consistent
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let ((contracts (contract-names))
          (properties (property-names)))
      (testing "the declared lists are non-empty and carry no duplicate name"
        (ok (plusp (length contracts)))
        (ok (plusp (length properties)))
        (ok (= (length contracts) (length (remove-duplicates contracts))))
        (ok (= (length properties) (length (remove-duplicates properties)))))
      (testing "every declared contract is registered and projects its own name"
        (dolist (name contracts)
          (ok (find-function-spec name))
          (ok (eq name (getf (function-spec-data name) :name)))))
      (testing "every declared property is registered and reachable from each :about"
        (dolist (name properties)
          (let ((property (find-property name)))
            (ok property)
            (dolist (target (property-targets property))
              (ok (member name (properties-for target)))))))
      (testing "the execution set is exactly the declared set"
        (ok (null (set-exclusive-or contracts (list-function-specs))))
        (ok (null (set-exclusive-or properties (list-properties)))))
      (testing "a target nothing is registered about is not reported as covered"
        (ok (null (properties-for 'self-target-nothing-registers-about))))
      (testing "re-running the bundle adds no name and duplicates no index entry"
        (register-specifications)
        (ok (null (set-exclusive-or (contract-names) (list-function-specs))))
        (ok (null (set-exclusive-or (property-names) (list-properties))))
        (dolist (name (property-names))
          (dolist (target (property-targets (find-property name)))
            (let ((found (properties-for target)))
              (ok (= (length found) (length (remove-duplicates found)))))))))))

(deftest introspection-runs-no-guard-capture-or-target
  (let* ((fixtures (state-projection-fixtures))
         (registry (getf fixtures :registry))
         (*self-state-balance* 10)
         (*self-state-calls* 0)
         (*self-state-scenario* :correct)
         (*scripted-state-inputs* nil))
    (function-spec-data (getf fixtures :observed) :registry registry)
    (function-spec-data (getf fixtures :capture) :registry registry)
    (function-spec-data (getf fixtures :uncalled) :registry registry)
    (ok (zerop *self-state-calls*))
    (ok (= 10 *self-state-balance*))))

(deftest small-domain-oracle-is-independent-of-the-checker
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    ;; The expected verdicts are hand-written from INTEGERP, STRINGP, EQL and
    ;; MEMBER, so the check does not assume VALIDP is the authority.
    (dolist (entry (list (list 'integer 0 t)
                         (list 'integer "x" nil)
                         (list 'string "ok" t)
                         (list 'string 3 nil)
                         (list 'null nil t)
                         (list 'null t nil)
                         (list '(member 1 2 3) 2 t)
                         (list '(member 1 2 3) 4 nil)
                         (list '(or integer string) "text" t)
                         (list '(or integer string) :keyword nil)))
      (destructuring-bind (form value admittedp) entry
        (let ((spec (normalize-spec-form form)))
          (testing (format nil "~S admits ~S is ~S" form value admittedp)
            (ok (eq admittedp (and (validp spec value) t)))
            (if admittedp
                (ok (eq value (validate spec value)))
                (ok (handler-case (progn (validate spec value) nil)
                      (spec-violation () t))))))))))

(deftest validate-cases-cover-admitted-and-refused-inputs
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    ;; The sequence is explicit, so both named cases are reached by the input
    ;; list itself rather than by what a seed happens to draw.
    (let ((*scripted-validate-inputs*
            '((integer 0) (integer "x") (string "ok") (string 7)
              (integer 1) (integer :x) (null nil) (null t))))
      (let* ((result (check-function 'cl-spec:validate :trials 4 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 4 (property-result-trials result)))
        (ok (equal '(:conforming :refused) (getf report :declared-cases)))
        (ok (equal '(2 2)
                   (mapcar (lambda (case) (getf case :called)) (getf report :cases))))
        (ok (equal '(2 2)
                   (mapcar (lambda (case) (getf case :passed)) (getf report :cases))))
        (ok (null (getf report :never-called)))
        (ok (zerop (getf report :case-selection-errors)))))))

(deftest evidence-policy-flags-an-unreached-case
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (testing "the policy names every requirement the bundle's runs are held to"
      (ok (equal '(:policy-version 1
                   :requirements ((:kind :requested-trials-completed)
                                  (:kind :min-checked-trials :count 4)
                                  (:kind :all-declared-cases :min-checked 1)))
                 (evidence-policy 4))))
    ;; Only admitted pairs: the run passes, yet never reaches the :REFUSED case.
    (let ((*scripted-validate-inputs*
            '((integer 0) (string "ok") (integer 1) (null nil)
              (integer 2) (string "yes") (integer 3) (boolean t))))
      (let* ((result (check-function 'cl-spec:validate :trials 4 :seed 1))
             (assessment (assess-evidence result (evidence-policy 4))))
        (testing "a passing run that misses a declared case is insufficient evidence"
          (ok (eq :passed (property-result-status result)))
          (ok (eq :insufficient (getf assessment :assessment)))
          (ok (equal '(:refused)
                     (mapcar (lambda (gap) (getf gap :case)) (getf assessment :gaps)))))))))

(deftest registry-registration-cases-cover-each-write
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let ((*scripted-registration-scenarios*
            '(:new :replace :refused-targets :refused-tags)))
      (let* ((result (check-function 'cl-spec:registry-register-property
                                     :trials 4 :seed 1))
             (report (function-check-result-case-report result)))
        (ok (eq :passed (property-result-status result)))
        (ok (= 4 (property-result-trials result)))
        (ok (equal '(:refused :new-registration :re-registration)
                   (getf report :declared-cases)))
        ;; Two refusals, one new registration, one replacement, and every case ran.
        (ok (equal '(2 1 1)
                   (mapcar (lambda (case) (getf case :passed)) (getf report :cases))))
        (ok (null (getf report :never-called)))
        (ok (zerop (getf report :capture-errors)))))))

(deftest registry-registration-keeps-unrelated-indexes
  (let* ((registry (make-hash-table-registry))
         (subject 'self-contract-subject)
         (sentinel 'self-contract-sentinel)
         (shared-target 'self-contract-shared-target)
         (old-target 'self-contract-old-target)
         (new-target 'self-contract-new-target)
         (shared-tag 'self-contract-shared-tag)
         (old-tag 'self-contract-old-tag)
         (new-tag 'self-contract-new-tag)
         (first (make-instance 'cl-spec:property :name subject
                               :arguments '((x integer))
                               :function (lambda (x) (declare (ignore x)) t)))
         (second (make-instance 'cl-spec:property :name subject
                                :arguments '((x integer))
                                :function (lambda (x) (declare (ignore x)) t))))
    (registry-register-property registry sentinel
      (make-instance 'cl-spec:property :name sentinel :arguments '((x integer))
                     :function (lambda (x) (declare (ignore x)) t))
      :targets (list shared-target) :tags (list shared-tag))
    (registry-register-property registry subject first
      :targets (list shared-target old-target) :tags (list shared-tag old-tag))
    (let ((names-before (cl-spec:list-properties registry)))
      (registry-register-property registry subject second
        :targets (list new-target shared-target) :tags (list new-tag shared-tag))
      (testing "the same name is replaced, not duplicated"
        (ok (eq second (nth-value 0 (cl-spec:registry-find-property registry subject))))
        (ok (= (length names-before) (length (cl-spec:list-properties registry))))
        (ok (null (set-exclusive-or names-before
                                    (cl-spec:list-properties registry)))))
      (testing "the subject's stale keys are retracted"
        (ok (null (properties-for old-target registry)))
        (ok (null (properties-with-tag old-tag registry))))
      (testing "new keys and keys shared with the sentinel are kept"
        (ok (member subject (properties-for new-target registry)))
        (ok (member subject (properties-for shared-target registry)))
        (ok (member sentinel (properties-for shared-target registry)))
        (ok (member subject (properties-with-tag new-tag registry)))
        (ok (member subject (properties-with-tag shared-tag registry)))
        (ok (member sentinel (properties-with-tag shared-tag registry)))))))

(deftest case-selection-error-calls-no-target
  (let* ((fixtures (state-projection-fixtures))
         (registry (getf fixtures :registry))
         (*self-state-balance* 10)
         (*self-state-calls* 0)
         (*self-state-scenario* :correct)
         (*scripted-state-inputs* '(3)))
    (let ((result (check-function (getf fixtures :uncalled)
                                  :trials 1 :seed 1 :registry registry)))
      (ok (eq :error (property-result-status result)))
      (ok (eq :case-selection (cl-spec:property-result-failure-phase result)))
      (ok (zerop *self-state-calls*)))))

(deftest projection-specs-refuse-inconsistent-records
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (testing "function-spec-data refuses a changed kind, a missing name and a broken case"
      (let* ((fixtures (function-projection-fixtures))
             (registry (getf fixtures :registry))
             (contract (find-function-spec 'cl-spec:function-spec-data))
             (spec (function-spec-return-spec contract))
             (good (function-spec-data (getf fixtures :state) :registry registry)))
        (ok (validp spec good))
        (let ((bad (copy-list good)))
          (setf (getf bad :kind) :property)
          (ok (not (validp spec bad))))
        (let ((bad (copy-list good)))
          (remf bad :name)
          (ok (not (validp spec bad))))
        (let ((bad (copy-list good)))
          (setf (getf bad :cases) (list (list :name :admitted)))
          (ok (not (validp spec bad))))))
    (testing "result-data refuses a state record whose required evidence was removed"
      (let* ((fixtures (state-projection-fixtures))
             (registry (getf fixtures :registry))
             (*self-state-balance* 10)
             (*self-state-calls* 0)
             (*self-state-scenario* :forget)
             (*scripted-state-inputs* '(3))
             (result (check-function (getf fixtures :observed)
                                     :trials 1 :seed 1 :registry registry))
             (contract (find-function-spec 'cl-spec:result-data))
             (spec (function-spec-return-spec contract))
             (good (result-data result)))
        (ok (validp spec good))
        (let ((failure (copy-list (getf good :failure)))
              (bad (copy-list good)))
          (remf failure :status)
          (setf (getf bad :failure) failure)
          (ok (not (validp spec bad))))
        (let* ((failure (copy-list (getf good :failure)))
               (state (copy-list (getf failure :state)))
               (capture (copy-list (getf state :capture)))
               (bad (copy-list good)))
          (setf (getf capture :status) :bogus
                (getf state :capture) capture
                (getf failure :state) state
                (getf bad :failure) failure)
          (ok (not (validp spec bad))))))))

(deftest a-deliberately-false-property-is-reported-as-failed
  (let ((*registry* (make-hash-table-registry)))
    (defproperty self-deliberately-false-law ((x (range integer 0 10)))
      "Always false, so the runner cannot report it as passed."
      (:trials (:smoke 3 :normal 5))
      (and (integerp x) (not (integerp x))))
    (let ((result (run-property 'self-deliberately-false-law :seed 1)))
      (ok (eq :failed (property-result-status result)))
      (ok (plusp (property-result-trials result))))))

(deftest projection-comparison-keeps-symbol-identity
  ;; The projection keeps the fixture's own symbols while the property lives in
  ;; CL-SPEC/SPECS.  Comparing whole forms with EQUAL is symbol-sensitive: a
  ;; same-named symbol from another package must not compare equal.
  (let* ((fixtures (function-projection-fixtures))
         (registry (getf fixtures :registry))
         (data (function-spec-data (getf fixtures :cases) :registry registry))
         (declared (getf data :cases))
         (expected cl-spec/self-spec-fixtures:*function-projection-expectations*)
         (actual (getf (first declared) :when))
         (fixture-n (intern "N" '#:cl-spec/self-spec-fixtures))
         (foreign (make-symbol "N"))
         (mutated (subst foreign fixture-n actual)))
    (testing "the declared form matches with EQUAL and its own symbols"
      (ok (equal (getf expected :admitted-when) actual)))
    (testing "a same-named symbol from another package is rejected, not ignored"
      (ok (not (eq fixture-n foreign)))
      (ok (string= (symbol-name fixture-n) (symbol-name foreign)))
      (ok (not (equal (getf expected :admitted-when) mutated))))))

(deftest registry-contract-declares-its-whole-scenario
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let* ((contract (find-function-spec 'cl-spec:registry-register-property))
           (schema (function-spec-argument-schema contract))
           (subject (self-registration-name :subject))
           (property (make-instance 'cl-spec:property :name subject
                                    :arguments '((x integer))
                                    :function (lambda (x) (declare (ignore x)) t)))
           (scenario-values (list (make-hash-table-registry) subject property
                                  :targets (list (self-registration-name :new-target)
                                                 (self-registration-name :shared-target))
                                  :tags (list (self-registration-name :new-tag)
                                              (self-registration-name :shared-tag))))
           (refused-values (list (make-hash-table-registry) subject property
                                 :targets 42
                                 :tags (list (self-registration-name :new-tag)
                                             (self-registration-name :shared-tag))))
           (outside-values (list (make-hash-table-registry) subject property
                                 :targets (list 'some-other-target)
                                 :tags (list (self-registration-name :new-tag)
                                             (self-registration-name :shared-tag)))))
      (testing "the argument schema admits the scenario values, including the refused one"
        (ok (validp schema scenario-values))
        (ok (validp schema refused-values)))
      (testing "an out-of-scenario target value is rejected by the argument schema"
        (ok (not (validp schema outside-values)))))
    (testing "the precondition admits the fixture's registry and rejects an unprepared one"
      (let ((*scripted-registration-scenarios* '(:replace)))
        (destructuring-bind (registry name property &key targets tags)
            (registration-scenario)
          (declare (ignore property))
          (ok (registration-scenario-state-p registry name targets tags))
          (ok (not (registration-scenario-state-p (make-hash-table-registry)
                                                  name targets tags))))))
    (testing "every scenario runs through the contract to a pass with no rejected trial"
      (let ((*scripted-registration-scenarios* '(:new :replace :refused-targets :refused-tags)))
        (let ((result (check-function 'cl-spec:registry-register-property :trials 4 :seed 1)))
          (ok (eq :passed (property-result-status result)))
          (ok (zerop (property-result-rejected result))))))))

(defclass tag-dropping-registry (hash-table-registry) ()
  (:documentation "A deliberately faulty registry that stores the registration subject without its tags."))

(defmethod registry-register-property ((registry tag-dropping-registry) name property
                                       &key targets tags)
  ;; Only the subject's writes lose their tags: the scenario's sentinel keeps its
  ;; entries, so the fixture still builds the initial state the :PRE admits.
  (call-next-method registry name property
                    :targets targets
                    :tags (unless (eq name (self-registration-name :subject)) tags)))

(defun make-tag-dropping-registry ()
  "Return a fresh registry whose writes lose their tag index entries."
  (make-instance 'tag-dropping-registry))

(deftest registry-contract-reconstructs-scenarios-from-recipes
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (testing "the contract declares a fresh fixture instead of an argument generator"
      (let ((data (function-spec-data 'cl-spec:registry-register-property)))
        (ok (getf data :fixture))
        (ok (null (getf data :argument-generator)))))
    (testing "each scenario keyword is a recipe one fixture check runs to a pass"
      (dolist (scenario '(:new :replace :refused-targets :refused-tags))
        (ok (eq :passed
                (getf (fixture-check-data
                       (check-fixture 'cl-spec:registry-register-property scenario))
                      :status))
            (prin1-to-string scenario))))
    (testing "a past result replays onto the fixture instead of being refused"
      (let ((first (check-function 'cl-spec:registry-register-property :trials 8 :seed 42)))
        (ok (eq :passed (property-result-status first)))
        (ok (eq :passed (property-result-status
                         (check-function 'cl-spec:registry-register-property
                                         :seed first))))))))

(deftest registry-contract-failure-is-saved-and-rechecked
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let* ((result (let ((*registry-constructor* #'make-tag-dropping-registry)
                         (*scripted-registration-scenarios* '(:new)))
                     (check-function 'cl-spec:registry-register-property
                                     :trials 1 :seed 1)))
           (artifact (deserialize-counterexample-artifact
                      (serialize-counterexample-artifact
                       (make-counterexample-artifact result)))))
      (testing "the faulty registry fails the new-registration state-post"
        (ok (eq :failed (property-result-status result)))
        (ok (eq :state-post (cl-spec:property-result-failure-phase result))))
      (testing "the saved recipe reproduces the failure against the same fault"
        (let ((*registry-constructor* #'make-tag-dropping-registry))
          (ok (eq :same-failure
                  (getf (recheck-counterexample artifact :state-policy :fixture) :status)))))
      (testing "the saved recipe passes once the fault is gone"
        (ok (eq :passed
                (getf (recheck-counterexample artifact :state-policy :fixture) :status)))))))

(deftest every-contract-is-named-in-the-coverage-section
  (let* ((path (asdf:system-relative-pathname
                "cl-spec" "docs/cl-spec-specification-v0.2-draft.md"))
         (text (with-open-file (in path :external-format :utf-8)
                 (let* ((buffer (make-string (file-length in)))
                        (end (read-sequence buffer in)))
                   (subseq buffer 0 end))))
         (start (search "## 68.1 " text))
         (section (string-downcase
                   (subseq text start (search (format nil "~%# 69.") text :start2 start)))))
    ;; The section states no count to drift; instead each contract the bundle
    ;; registers must have its own row, named in backquotes.
    (let ((missing (remove-if (lambda (name)
                                (search (format nil "`~(~A~)`" (symbol-name name)) section))
                              (contract-names))))
      (ok (null missing)
          (format nil "specification §68.1 names no row for ~S" missing)))))

(deftest diagnostic-evidence-specs-refuse-malformed-records
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let ((capture-spec (find-spec 'cl-spec/specs::capture-evidence-data))
          (state-spec (find-spec 'cl-spec/specs::state-post-evidence-data)))
      (testing "capture values are explicit availability records"
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :collected :value 1))
                      :error nil)))
        (ok (not (validp capture-spec '(:status :completed :declared (x)
                                        :values (123) :error nil))))
        ;; The pre-release ((NAME . VALUE) ...) alist is not the v1 shape and
        ;; is not accepted as a compatibility form.
        (ok (not (validp capture-spec '(:status :completed :declared (x)
                                        :values ((x . 1)) :error nil))))
        (ok (not (validp capture-spec '(:status :completed :declared (x)
                                        :values nil :error nil)))))
      (testing "availability separates metadata from an application value"
        ;; A collected application value may equal the old marker plist; it is
        ;; still a value because :AVAILABILITY says so, never because of shape.
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :collected
                                :value (:unavailable :reason :opaque-value
                                        :type :hash-table)))
                      :error nil))))
      (testing "the union is enforced by plist key presence, not by searching values"
        ;; A present :VALUE whose value is NIL is a collected value.
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :collected :value nil))
                      :error nil)))
        ;; No :VALUE indicator at all.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :collected))
                           :error nil))))
        ;; :VALUE appears only as the value of :NAME, never as an indicator.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name :value :availability :collected))
                           :error nil))))
        ;; A symbol in a value position does not stand in for a missing :NAME.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:availability :collected :value 1))
                           :error nil))))
        ;; An unavailable record claims no value.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :unavailable
                                     :reason :opaque-value :type hash-table
                                     :value 1))
                           :error nil))))
        ;; An unavailable record requires both :REASON and :TYPE.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :unavailable
                                     :type hash-table))
                           :error nil))))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :unavailable
                                     :reason :opaque-value))
                           :error nil))))
        ;; A collected record carries no unavailable-only metadata, NIL or not.
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :collected :value 1
                                     :reason :opaque-value))
                           :error nil))))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :collected :value 1
                                     :type hash-table))
                           :error nil))))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :collected :value 1
                                     :reason nil))
                           :error nil)))))
      (testing "the diagnostic :TYPE is ordinary data, never a live class object"
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :unavailable
                                :reason :opaque-value :type hash-table))
                      :error nil)))
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :unavailable
                                :reason :opaque-value
                                :type (:kind :anonymous-class
                                       :metaclass standard-class)))
                      :error nil)))
        ;; The :UNKNOWN fallback is a symbol and part of the documented domain.
        (ok (validp capture-spec
                    '(:status :completed :declared (x)
                      :values ((:name x :availability :unavailable
                                :reason :opaque-value :type :unknown))
                      :error nil)))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :unavailable
                                     :reason :opaque-value
                                     :type (:kind :named :name hash-table)))
                           :error nil))))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (x)
                           :values ((:name x :availability :unavailable
                                     :reason :opaque-value :type 42))
                           :error nil))))
        (let ((class (make-instance 'standard-class)))
          (ok (not (validp capture-spec
                           (list :status :completed :declared '(x)
                                 :values (list (list :name 'x
                                                     :availability :unavailable
                                                     :reason :opaque-value
                                                     :type class))
                                 :error nil))))))
      (testing "a failed capture names the binding at the failure position"
        (ok (validp capture-spec '(:status :error :declared (x) :values nil
                                   :error (:binding x :index 0
                                           :condition-type simple-error))))
        (ok (validp capture-spec
                    '(:status :error :declared (a b)
                      :values ((:name a :availability :collected :value 10))
                      :error (:binding b :index 1 :condition-type simple-error))))
        (ok (not (validp capture-spec
                         '(:status :error :declared (a b)
                           :values ((:name a :availability :collected :value 10))
                           :error (:binding unrelated :index 1
                                   :condition-type simple-error)))))
        (ok (not (validp capture-spec '(:status :error :declared (x)
                                        :values nil :error nil))))
        (ok (not (validp capture-spec
                         '(:status :error :declared (a)
                           :values ((:name a :availability :collected :value 1))
                           :error (:binding a :index 1
                                   :condition-type simple-error)))))
        (ok (not (validp capture-spec
                         '(:status :completed :declared (a)
                           :values ((:name a :availability :collected :value 1))
                           :error (:binding a :index 1
                                   :condition-type simple-error))))))
      (testing "an uncollected capture obtained nothing"
        (ok (validp capture-spec '(:status :not-evaluated :declared (x)
                                   :values nil :error nil))))
      (testing "state-post evidence requires the keys its status implies"
        (ok (not (validp state-spec '(:status :not-evaluated :reason nil :case nil
                                      :index nil :form nil :condition-type nil))))
        (ok (validp state-spec '(:status :not-evaluated :reason :not-declared :case nil
                                 :index nil :form nil :condition-type nil)))
        ;; A missing clause key is refused, but a NIL form is a form and an
        ;; unknown position is NIL rather than a guessed integer.
        (ok (not (validp state-spec '(:status :violation :reason nil :case nil
                                      :index 0 :condition-type nil))))
        (ok (validp state-spec '(:status :violation :reason nil :case nil
                                 :index 0 :form nil :condition-type nil)))
        (ok (validp state-spec '(:status :violation :reason nil :case nil
                                 :index nil :form nil :condition-type nil)))
        (ok (validp state-spec '(:status :error :reason nil :case nil
                                 :index nil :form nil :condition-type simple-error)))
        (ok (not (validp state-spec '(:status :error :reason nil :case nil :index 0
                                      :form (= x 1) :condition-type nil))))
        (ok (not (validp state-spec '(:status :passed :reason :why :case nil
                                      :index nil :form nil :condition-type nil)))))
      (testing "a status that never reached the state-post carries no failure data"
        (ok (not (validp state-spec '(:status :passed :reason nil :case nil
                                      :index 0 :form (= x 1) :condition-type nil))))
        (ok (not (validp state-spec '(:status :passed :reason nil :case nil
                                      :index nil :form nil :condition-type simple-error))))
        (ok (not (validp state-spec '(:status :not-evaluated :reason :outcome-failed
                                      :case nil :index 0 :form (= x 1)
                                      :condition-type simple-error))))
        (ok (not (validp state-spec '(:status :violation :reason :outcome-failed
                                      :case nil :index 0 :form (= x 1)
                                      :condition-type nil))))
        (ok (not (validp state-spec '(:status :error :reason :outcome-failed
                                      :case nil :index 0 :form (= x 1)
                                      :condition-type simple-error)))))
      (testing "unknown keys stay allowed, as the open schema requires"
        (ok (validp state-spec '(:status :passed :reason nil :case nil :index nil
                                 :form nil :condition-type nil :future t)))))))

(deftest real-state-evidence-satisfies-its-schema
  ;; Evidence the core actually builds, not a hand-written lookalike: a state-post
  ;; whose form is NIL, and a programmatic predicate that reports no position.
  (let* ((fixtures (state-projection-fixtures))
         (registry (getf fixtures :registry)))
    (flet ((state-evidence (name)
             (let ((cl-spec/self-spec-fixtures:*self-state-balance* 10)
                   (cl-spec/self-spec-fixtures:*self-state-scenario* :correct)
                   (cl-spec/self-spec-fixtures:*scripted-state-inputs* '(3)))
               (let ((result (check-function name :trials 1 :seed 1 :registry registry)))
                 (getf (getf (result-data result) :failure) :state)))))
      (let ((state-spec (find-spec 'cl-spec/specs::state-post-evidence-data))
            (nil-form (state-evidence (getf fixtures :nil-post)))
            (programmatic (state-evidence (getf fixtures :programmatic))))
        (testing "a state-post whose only form is NIL is accepted"
          (let ((evidence (getf nil-form :state-post)))
            (ok (eq :violation (getf evidence :status)))
            (ok (eql 0 (getf evidence :index)))
            (ok (null (getf evidence :form)))
            (ok (validp state-spec evidence))))
        (testing "a programmatic predicate without a position is accepted"
          (let ((evidence (getf programmatic :state-post)))
            (ok (eq :violation (getf evidence :status)))
            (ok (null (getf evidence :index)))
            (ok (null (getf evidence :form)))
            (ok (validp state-spec evidence))))))))
