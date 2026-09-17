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
                #:property-names
                #:register-specifications)
  (:import-from #:cl-spec/main
                #:*registry*
                #:check-function
                #:defproperty
                #:find-function-spec
                #:find-property
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
                #:property-result-status
                #:property-result-trials
                #:property-targets
                #:registry-register-property
                #:result-data
                #:run-property
                #:spec-violation
                #:validate
                #:validp)
  (:import-from #:cl-spec/self-spec-fixtures
                #:*scripted-registration-scenarios*
                #:*scripted-state-inputs*
                #:*scripted-validate-inputs*
                #:*self-state-balance*
                #:*self-state-calls*
                #:*self-state-scenario*
                #:function-projection-fixtures
                #:self-registration-name
                #:state-projection-fixtures)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/self-api-contracts-test)

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

(deftest registry-contract-declares-its-finite-domain
  (let ((*registry* (make-hash-table-registry)))
    (register-specifications)
    (let* ((contract (find-function-spec 'cl-spec:registry-register-property))
           (schema (function-spec-argument-schema contract))
           (subject (self-registration-name :subject))
           (property (make-instance 'cl-spec:property :name subject
                                    :arguments '((x integer))
                                    :function (lambda (x) (declare (ignore x)) t)))
           (in-domain (list (make-hash-table-registry) subject property
                            :targets (list (self-registration-name :new-target)
                                           (self-registration-name :shared-target))
                            :tags (list (self-registration-name :new-tag)
                                        (self-registration-name :shared-tag))))
           (refused-in-domain (list (make-hash-table-registry) subject property
                                    :targets 42
                                    :tags (list (self-registration-name :new-tag)
                                                (self-registration-name :shared-tag))))
           (outside-domain (list (make-hash-table-registry) subject property
                                 :targets (list 'some-other-target)
                                 :tags (list (self-registration-name :new-tag)
                                             (self-registration-name :shared-tag)))))
      (testing "the scenario inputs, including the refused one, are in the domain"
        (ok (validp schema in-domain))
        (ok (validp schema refused-in-domain)))
      (testing "a valid but out-of-scenario target list is outside the declared domain"
        (ok (not (validp schema outside-domain)))))))
