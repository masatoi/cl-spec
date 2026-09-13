;;;; tests/verification-evidence-test.lisp

(defpackage #:cl-spec/tests/verification-evidence-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/property #:property)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/dsl #:defspec #:defspec-function)
  (:import-from #:cl-spec/src/function-spec
                #:check-function #:function-check-result-explanation
                #:function-check-result-failure-reason)
  (:import-from #:cl-spec/src/conditions #:invalid-backend-result)
  (:import-from #:cl-spec/src/execution
                #:observe-trial #:trial-observation-arguments #:trial-observation-value
                #:trial-observation-arguments-mutated-p #:trial-observation-condition
                #:trial-observation-condition-report)
  (:import-from #:cl-spec/src/property-runner
                #:property-result #:property-result-failure-evidence
                #:property-result-shrunk-evidence #:property-result-shrunk-outcome
                #:property-result-entity-kind
                #:run-property #:property-result-status #:property-result-condition
                #:property-result-counterexample #:property-result-shrunk-counterexample)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend* #:backend-default-trials #:run-generated-test)
  (:import-from #:cl-spec/src/introspection
                #:spec-data #:property-data #:function-spec-data)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/verification-evidence-test)

(defun probe-property (function &key (spec '(range integer 0 10)) (shrink t))
  "Build an isolated one-argument property."
  (make-instance 'property :name 'probe
                 :arguments (list (list 'x (normalize-spec-form spec)))
                 :trials '(:normal 10) :metadata (list :shrink shrink)
                 :function function))

(defun reported-x (result)
  "Read the selected counterexample."
  (getf (or (property-result-shrunk-counterexample result)
            (property-result-counterexample result)) 'x))

(deftest property-shrinking-preserves-false-versus-error
  (let ((r (run-property
            (probe-property (lambda (x)
                              (if (zerop x)
                                  (error 'type-error :datum x :expected-type 'string)
                                  nil)))
            :seed 42)))
    (ok (eq :failed (property-result-status r)))
    (ok (= 1 (reported-x r)))
    (ok (eq :used (property-result-shrunk-outcome r)))
    (ok (equal '(x 6) (property-result-counterexample r)))
    (ok (null (property-result-condition r)))))

(deftest property-shrinking-preserves-condition-type
  (let ((r (run-property
            (probe-property (lambda (x)
                              (if (zerop x)
                                  (error 'type-error :datum x :expected-type 'string)
                                  (error "original ~D" x))))
            :seed 42)))
    (ok (eq :error (property-result-status r)))
    (ok (= 1 (reported-x r)))
    (ok (eq :used (property-result-shrunk-outcome r)))
    (ok (equal '(x 6) (property-result-counterexample r)))
    (ok (typep (property-result-condition r) 'simple-error))))

(deftest property-condition-belongs-to-selected-input
  (let ((r (run-property (probe-property (lambda (x) (error "value ~D" x))) :seed 42)))
    (ok (= 0 (reported-x r)))
    (ok (equal (list (reported-x r))
               (simple-condition-format-arguments (property-result-condition r))))))

(defvar *target-calls* 0)
(defvar *predicate-calls* 0)

(defun counted-target ()
  "Return a different value on every invocation."
  (incf *target-calls*))

(defun counted-return-predicate (value)
  "Count validation calls and reject VALUE."
  (declare (ignore value))
  (incf *predicate-calls*)
  nil)

(deftest function-classification-does-not-rerun-user-code
  (let ((*registry* (make-hash-table-registry))
        (*target-calls* 0)
        (*predicate-calls* 0))
    (defspec-function counted-target
      (:returns (satisfies counted-return-predicate)))
    (let ((r (check-function 'counted-target :trials 10 :seed 42)))
      (ok (= 1 *target-calls*))
      (ok (= 1 *predicate-calls*))
      (ok (eq :return-spec (function-check-result-failure-reason r)))
      (ok (= 1 (getf (function-check-result-explanation r) :value))))))

(deftest argument-mutation-does-not-rewrite-evidence
  (let ((r (run-property
            (probe-property (lambda (x) (setf (first x) 99) nil)
                            :spec '(tuple (range integer 1 1)) :shrink nil)
            :seed 42)))
    (ok (equal '(1) (reported-x r)))))

(deftest observing-does-not-change-generated-object-identity
  (let* ((text (copy-seq "abc"))
         (r (run-property
             (probe-property (lambda (x) (eq x text)) :spec (list 'member text))
             :seed 42)))
    (ok (eq :passed (property-result-status r)))))

(defclass incomplete-backend () ())
(defmethod backend-default-trials ((backend incomplete-backend))
  (declare (ignore backend))
  10)
(defmethod run-generated-test ((backend incomplete-backend) property &key options)
  (declare (ignore backend property options))
  (list :status :passed))

(deftest backend-trials-is-required
  (let ((*generator-backend* (make-instance 'incomplete-backend)))
    (ok (handler-case
            (progn (run-property (probe-property (lambda (x) (declare (ignore x)) t)))
                   nil)
          (error () t)))))

(defclass reply-backend ()
  ((reply :initarg :reply :reader backend-reply)))

(defmethod backend-default-trials ((backend reply-backend))
  (declare (ignore backend))
  10)

(defmethod run-generated-test ((backend reply-backend) property &key options)
  (declare (ignore options))
  (let ((reply (backend-reply backend)))
    (if (functionp reply) (funcall reply property) reply)))

(deftest malformed-backend-outcomes-are-not-verdicts
  (dolist (reply '((:status :passed)
                   (:status :passed :trials nil)
                   (:status :passed :trials -1)
                   (:status :passed :trials 1.5)
                   (:status :passed :trials 11)
                   (:status :passed :trials 1)
                   (:status :passed :trials 10 :rejected 11)
                   (:status :skipped :trials 10)
                   (:status :failed :trials 0)
                   (:status :error :trials 1)
                   (:status :unknown :trials 10)
                   (:status :passed :trials 10 :trials 0)
                   (:status :passed :trials)))
    (let ((*generator-backend* (make-instance 'reply-backend :reply reply)))
      (ok (handler-case
              (progn (run-property (probe-property (lambda (x) (declare (ignore x)) t)))
                     nil)
            (invalid-backend-result () t))))))

(deftest backend-cannot-substitute-incompatible-evidence
  (dolist (case '(:identity :status :missing-shrink :passed-failure :unchanged-input))
    (let ((p (probe-property (lambda (x) (if (zerop x) (error "different") nil))))
           (*generator-backend*
             (make-instance
              'reply-backend
              :reply
              (lambda (property)
                ;; Capture inside this invocation so provenance validation passes.
                (let ((original (observe-trial property '(6)))
                      (other (observe-trial property '(0))))
                  (ecase case
                    (:identity
                     (list :status :error :trials 1 :failure original
                           :shrunk-failure other :shrunk-outcome :used))
                    (:status
                     (list :status :error :trials 1 :failure original :shrunk-outcome :none))
                    (:missing-shrink
                     (list :status :failed :trials 1 :failure original :shrunk-outcome :used))
                    (:passed-failure (list :status :passed :trials 10 :failure original))
                    (:unchanged-input
                     (list :status :failed :trials 1 :failure original
                           :shrunk-failure original :shrunk-outcome :used))))))))
      (ok (handler-case (progn (run-property p) nil)
            (invalid-backend-result () t))))))

(deftest executed-trials-is-required-on-results
  (ok (handler-case (progn (make-instance 'property-result) nil)
        (invalid-backend-result () t)))
  (dolist (count '(nil -1 1.5))
    (ok (handler-case (progn (make-instance 'property-result :trials count) nil)
          (invalid-backend-result () t))))
  (ok (make-instance 'property-result :trials 0)))

(deftest direct-backend-calls-require-a-budget
  (let ((p (probe-property (lambda (x) (declare (ignore x)) t))))
    (ok (handler-case
            (progn (run-generated-test *generator-backend* p) nil)
          (type-error () t)))
    (let* ((*generator-backend*
             (make-instance 'reply-backend :reply '(:status :passed :trials 0)))
           (reply (run-generated-test *generator-backend* p :options '(:trials 0))))
      (ok (eql 0 (getf reply :trials))))))

(deftest original-and-selected-observations-remain-distinct
  (let* ((r (run-property (probe-property (lambda (x) (error "value ~D" x))) :seed 42))
         (original (property-result-failure-evidence r))
         (shrunk (property-result-shrunk-evidence r)))
    (ok (equal '(6) (trial-observation-arguments original)))
    (ok (equal '(0) (trial-observation-arguments shrunk)))
    (ok (search "6" (trial-observation-condition-report original)))
    (ok (search "0" (trial-observation-condition-report shrunk)))
    (ok (eq (trial-observation-condition shrunk) (property-result-condition r)))
    (ok (eq :used (property-result-shrunk-outcome r)))
    (ok (eq :property (property-result-entity-kind r)))))

(deftest destructive-trial-keeps-a-snapshot-and-stops-shrinking
  (let ((calls 0))
    (let* ((r (run-property
               (probe-property (lambda (x) (incf calls) (setf (first x) 99) nil)
                               :spec '(tuple (range integer 1 1)))
               :seed 42))
           (original (property-result-failure-evidence r)))
      (ok (= 1 calls))
      (ok (equal '(1) (reported-x r)))
      (ok (trial-observation-arguments-mutated-p original))
      (ok (null (property-result-shrunk-evidence r)))
      (ok (eq :none (property-result-shrunk-outcome r))))))

(deftest counterexample-strings-survive-later-mutation
  (let* ((text (copy-seq "abc"))
         (r (run-property (probe-property (lambda (x) (declare (ignore x)) nil)
                                         :spec (list 'member text) :shrink nil)
                          :seed 42)))
    (setf (aref text 0) #\z)
    (ok (string= "abc" (reported-x r)))))

(deftest function-result-exposes-the-observed-value
  (let ((*registry* (make-hash-table-registry))
        (*target-calls* 0))
    (defspec-function counted-target (:returns integer) (:post (= result 0)))
    (let* ((r (check-function 'counted-target :trials 10 :seed 42))
           (evidence (property-result-failure-evidence r)))
      (ok (= 1 *target-calls*))
      (ok (= 1 (trial-observation-value evidence)))
      (ok (eq :postcondition (function-check-result-failure-reason r)))
      (ok (eq :function-spec (property-result-entity-kind r)))
      (ok (eq :none (property-result-shrunk-outcome r))))))

(define-condition unprintable-failure (error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition stream))
             (error "broken condition printer"))))

(deftest condition-formatting-cannot-destroy-the-observation
  (let ((r (run-property
            (probe-property (lambda (x) (declare (ignore x))
                              (error 'unprintable-failure)))
            :seed 42)))
    (ok (eq :error (property-result-status r)))
    (ok (typep (property-result-condition r) 'unprintable-failure))
    (ok (stringp (trial-observation-condition-report
                  (property-result-failure-evidence r))))))

(deftest malformed-observed-signatures-are-rejected
  (dolist (corruption '(:dotted-arguments :circular-arguments :circular-signature))
    (let ((*generator-backend*
            (make-instance
             'reply-backend
             :reply (lambda (property)
                      (let* ((observation (observe-trial property '(6)))
                             (arguments (trial-observation-arguments observation))
                             (signature
                               (cl-spec/src/execution:trial-observation-signature
                                observation)))
                        (ecase corruption
                          (:dotted-arguments (setf (cdr arguments) 2))
                          (:circular-arguments (setf (cdr arguments) arguments))
                          (:circular-signature (setf (cdr signature) signature)))
                        (list :status :failed :trials 1 :failure observation
                              :shrunk-outcome :none))))))
      (ok (handler-case
              (progn (run-property
                      (probe-property (lambda (x) (declare (ignore x)) nil)))
                     nil)
            (invalid-backend-result () t))))))

(deftest dotted-member-constants-remain-valid-failure-identities
  (let ((*registry* (make-hash-table-registry))
        (*target-calls* 0))
    (defspec-function counted-target (:returns (member (1 . 2))))
    (let ((result (check-function 'counted-target :trials 1 :seed 42)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq :return-spec (function-check-result-failure-reason result))))))

(defun hand-post-target (n)
  "Return values violating different post forms at zero and nonzero inputs."
  (if (zerop n) 20 -1))

(deftest hand-built-postconditions-need-observed-form-identity
  (dolist (index '(nil -1 2))
    (let* ((contract
             (make-instance 'cl-spec/src/function-spec:function-spec
                            :name 'hand-post-target
                            :argument-specs '((n (range integer 0 10)))
                            :postconditions '((>= result 0) (<= result 10))
                            :postcondition-function
                            (lambda (result n)
                              (declare (ignore n))
                              (values (and (>= result 0) (<= result 10))
                                      index
                                      (when index :cl-spec-post-form-failure)))))
           (result (check-function contract :trials 10 :seed 42)))
      (ok (eq :failed (property-result-status result)))
      (ok (equal '(n 6) (property-result-counterexample result)))
      (ok (null (property-result-shrunk-counterexample result)))
      (ok (eq :different-failure (property-result-shrunk-outcome result))))))

(deftest hand-built-tagged-postconditions-preserve-the-failed-form
  (let* ((contract
           (make-instance 'cl-spec/src/function-spec:function-spec
                          :name 'hand-post-target
                          :argument-specs '((n (range integer 0 10)))
                          :postconditions '((>= result 0) (<= result 10))
                          :postcondition-function
                          (lambda (result n)
                            (declare (ignore n))
                            (values nil (if (< result 0) 0 1)
                                    :cl-spec-post-form-failure))))
         (result (check-function contract :trials 10 :seed 42)))
    (ok (equal '(n 1) (property-result-shrunk-counterexample result)))
    (ok (eq :used (property-result-shrunk-outcome result))))
  (let ((unknown '(:return-value :postcondition nil))
        (known '(:return-value :return-spec ((:kind :type)))))
    (ok (not (cl-spec/src/execution:failure-identities-match-p unknown known)))
    (ok (not (cl-spec/src/execution:failure-identities-match-p known unknown)))))

(deftest shrink-counterexamples-stay-in-the-argument-domain
  (dolist (spec '((and integer (satisfies plusp)) string (member 1 100)))
    (let* ((invalid-calls 0)
           (ir (normalize-spec-form spec))
           (result
             (run-property
              (probe-property
               (lambda (x)
                 (unless (cl-spec/src/validator:validp ir x) (incf invalid-calls))
                 nil)
               :spec spec)
              :seed 5)))
      (ok (zerop invalid-calls))
      (ok (cl-spec/src/validator:validp ir (reported-x result)))
      (ok (eq :failed (property-result-status result))))))

(defun domain-target (x)
  "Ignore X and violate the return contract."
  (declare (ignore x))
  5)

(deftest function-shrink-counterexamples-stay-in-the-argument-domain
  (dolist (spec '((and integer (satisfies plusp)) string (member 1 100)))
    (let* ((contract
             (make-instance 'cl-spec/src/function-spec:function-spec
                            :name 'domain-target :argument-specs (list (list 'x spec))
                            :return-spec '(range integer 0 0)))
           (result (check-function contract :trials 30 :seed 5)))
      (ok (cl-spec/src/validator:validp (normalize-spec-form spec) (reported-x result)))
      (ok (eq :return-spec (function-check-result-failure-reason result))))))

(deftest large-snapshots-do-not-use-the-control-stack
  (ok (handler-case
          (let* ((value (make-list 100000 :initial-element 1))
                 (copy (cl-spec/src/execution:snapshot-value value)))
            (and (= 100000 (length copy))
                 (not (eq value copy))
                 (cl-spec/src/execution:same-value-p value copy)))
        (storage-condition () nil))))

(defun long-return-target ()
  "Return a long valid list."
  (make-list 100000 :initial-element 1))

(deftest long-return-values-remain-checkable
  (let ((contract
          (make-instance 'cl-spec/src/function-spec:function-spec
                         :name 'long-return-target
                         :return-spec '(satisfies listp))))
    (ok (handler-case
            (eq :passed (property-result-status (check-function contract :trials 1)))
          (storage-condition () nil)))))

(defclass invalid-status-property (property) ())

(defmethod cl-spec/src/execution:evaluate-trial
    ((property invalid-status-property) arguments &key context)
  "Exercise an invalid evaluator extension."
  (declare (ignore property arguments context))
  (values :typo nil nil nil nil t))

(deftest unknown-trial-status-is-never-a-pass
  (ok (handler-case
          (progn (run-property (make-instance 'invalid-status-property :name 'invalid-status :function (constantly t)
                                               :trials '(:normal 1)))
                 nil)
        (invalid-backend-result () t))))

(defvar *shrink-internal-error-p* nil)

(defmethod check-it:shrink :around ((generator check-it:tuple-generator) test)
  "Inject a shrinker error without replacing the production method."
  (if *shrink-internal-error-p*
      (error "shrinker internals failed")
      (call-next-method)))

(deftest shrinker-errors-preserve-the-original-observation
  (let ((*shrink-internal-error-p* t))
    (let ((result (run-property (probe-property (lambda (x) (declare (ignore x)) nil))
                                :seed 42)))
      (ok (eq :failed (property-result-status result)))
      (ok (equal '(x 6) (property-result-counterexample result)))
      (ok (null (property-result-shrunk-counterexample result))))))

(deftest failure-identity-compares-snapshotted-array-constants
  (let* ((contract
           (make-instance 'cl-spec/src/function-spec:function-spec
                          :name 'domain-target
                          :argument-specs '((x (range integer 0 10)))
                          :return-spec '(member #(1 2))))
         (result (check-function contract :trials 10 :seed 42)))
    (ok (eq :used (property-result-shrunk-outcome result)))
    (ok (equal '(x 0) (property-result-shrunk-counterexample result)))))

(deftest review-evidence-boundaries
  (let* ((p (probe-property (lambda (x)
                              (setf (second x) (copy-list (second x)))
                              nil)))
         (child (list 1))
         (observation (observe-trial p (list (list child child)))))
    (ok (trial-observation-arguments-mutated-p observation)))
  (let* ((p (probe-property (lambda (x) (declare (ignore x)) t)))
         (other (probe-property (lambda (x) (declare (ignore x)) nil)))
         (observation (observe-trial other '(6)))
         (*generator-backend*
           (make-instance 'reply-backend
                          :reply (list :status :failed :trials 1
                                       :failure observation :shrunk-outcome :none))))
    (ok (handler-case (progn (run-property p) nil)
          (invalid-backend-result () t))))
  (let ((circular (list 1)))
    (setf (cdr circular) circular)
    (dolist (arguments (list '(1 . 2) circular))
      (let* ((observation
               (cl-spec/src/execution:make-trial-observation
                :arguments arguments :status :failed :signature '(:property-false)))
             (*generator-backend*
               (make-instance 'reply-backend
                              :reply (list :status :failed :trials 1
                                           :failure observation :shrunk-outcome :none))))
        (ok (handler-case
                (progn (run-property (probe-property (lambda (x) x))) nil)
              (invalid-backend-result () t)
              (type-error () nil)))))))

(deftest entity-discriminator-is-independent-of-kind
  (let ((*registry* (make-hash-table-registry)))
    (defspec probe-spec integer)
    (defspec-function counted-target (:returns integer))
    (let* ((p (make-instance 'property :name 'probe :kind :function-spec
                             :function (lambda () t)))
           (data (property-data p)))
      (ok (eq :property (getf data :entity-kind)))
      (ok (eq :function-spec (getf data :kind))))
    (ok (eq :spec (getf (spec-data 'probe-spec) :entity-kind)))
    (ok (eq :function-spec (getf (function-spec-data 'counted-target) :entity-kind)))))
