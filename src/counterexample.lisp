;;;; src/counterexample.lisp

(defpackage #:cl-spec/src/counterexample
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:serialize-artifact-value #:deserialize-artifact-value
                #:artifact-value-error #:artifact-value-error-reason)
  (:import-from #:cl-spec/src/property-runner
                #:property-result #:property-result-schema-metadata
                #:property-result-entity-kind #:property-result-property
                #:property-result-failure-evidence #:property-result-shrunk-evidence
                #:property-result-seed #:property-result-profile #:property-result-budget
                #:property-result-options #:property-result-provenance)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-arguments #:trial-observation-arguments-mutated-p
                #:trial-observation-status #:trial-observation-reason
                #:trial-observation-signature #:trial-observation-condition-report
                #:observation-failure-p #:observe-trial #:failure-identities-match-p
                #:snapshot-value #:same-value-p)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/schema #:resolve-definition #:definition-digest)
  (:import-from #:cl-spec/src/property #:property-arguments)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec-argument-specs #:make-function-check-property)
  (:import-from #:cl-spec/src/ir #:tuple-spec)
  (:import-from #:cl-spec/src/validator #:validp)
  (:export #:make-counterexample-artifact #:counterexample-artifact-data
           #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
           #:recheck-counterexample #:counterexample-artifact
           #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason))

(in-package #:cl-spec/src/counterexample)

(define-condition invalid-counterexample-artifact (error)
  ((reason :initarg :reason :reader invalid-counterexample-artifact-reason))
  (:documentation "Malformed, unsupported or excessive persisted counterexample data.")
  (:report (lambda (condition stream)
             (format stream "Invalid counterexample artifact: ~A"
                     (invalid-counterexample-artifact-reason condition)))))

(defstruct (counterexample-artifact (:constructor %make-counterexample-artifact (payload))
                                   (:copier nil))
  "Immutable serialized evidence for one concrete counterexample."
  (payload "" :type string :read-only t))

(defun reject-artifact (reason)
  (error 'invalid-counterexample-artifact :reason reason))

(defun checked-codec (function value)
  (handler-case (funcall function value)
    (artifact-value-error (condition)
      (reject-artifact (artifact-value-error-reason condition)))))

(defun record-p (value keys)
  ;; Values reaching this function have already passed the bounded tree codec.
  (and (listp value)
       (loop for tail = value then (cddr tail)
             while tail
             always (and (consp tail) (consp (cdr tail))
                         (member (car tail) keys)
                         (not (member (car tail) seen)))
             collect (car tail) into seen
             finally (return (= (length seen) (length keys))))))

(defun evidence-data (observation)
  (when observation
    (unless (observation-failure-p observation) (reject-artifact :not-failure-evidence))
    (list :arguments (trial-observation-arguments observation)
          :status (trial-observation-status observation)
          :reason (trial-observation-reason observation)
          :signature (trial-observation-signature observation)
          :mutated-p (trial-observation-arguments-mutated-p observation))))

(defun proper-list-p (value)
  (loop for tail = value then (cdr tail)
        while (consp tail)
        finally (return (null tail))))

(defun valid-signature-p (data kind)
  (let ((signature (getf data :signature))
        (reason (getf data :reason))
        (status (getf data :status)))
    (and (proper-list-p signature)
         (if (eq kind :property)
             (case reason
               (:predicate-false (and (eq status :failed) (equal signature '(:property-false))))
               (:condition (and (eq status :error) (= (length signature) 2)
                                (eq (first signature) :property-condition)
                                (symbolp (second signature)))))
             (case reason
               ((:return-spec :postcondition)
                (and (eq status :failed) (= (length signature) 3)
                     (eq (first signature) :return-value) (eq (second signature) reason)))
               (:missing-condition
                (and (eq status :failed) (equal signature '(:missing-condition))))
               (:condition-spec
                (and (eq status :error) (= (length signature) 3)
                     (eq (first signature) :condition-spec) (symbolp (second signature))))
               ((:condition :contract-error)
                (and (eq status :error) (= (length signature) 2)
                     (eq (first signature) (if (eq reason :condition) :target-signal :contract-error))
                     (symbolp (second signature)))))))))

(defun valid-evidence-p (data)
  (and (record-p data '(:arguments :status :reason :signature :mutated-p))
       (proper-list-p (getf data :arguments))
       (member (getf data :status) '(:failed :error))
       (keywordp (getf data :reason))
       (consp (getf data :signature))
       (proper-list-p (getf data :signature))
       (member (getf data :mutated-p) '(nil t))))

(defun validate-artifact-data (data)
  (unless
      (and (record-p data '(:artifact-version :record-kind :entity-kind :name
                           :definition-digest :definition-digest-complete :capabilities
                           :original :shrunk :selection :seed :profile :budget
                           :options :provenance))
           (eql (getf data :artifact-version) 1)
           (eq (getf data :record-kind) :counterexample)
           (member (getf data :entity-kind) '(:property :function-spec))
           (getf data :name) (symbolp (getf data :name))
           (member (getf data :definition-digest-complete) '(nil t))
           (if (getf data :definition-digest-complete)
               (stringp (getf data :definition-digest))
               (null (getf data :definition-digest)))
           (valid-evidence-p (getf data :original))
           (valid-signature-p (getf data :original) (getf data :entity-kind))
           (or (null (getf data :shrunk))
               (and (valid-evidence-p (getf data :shrunk))
                    (valid-signature-p (getf data :shrunk) (getf data :entity-kind))
                    (failure-identities-match-p (getf (getf data :original) :signature)
                                                (getf (getf data :shrunk) :signature))))
           (member (getf data :selection) '(:original :shrunk))
           (getf data (getf data :selection))
           (typep (getf data :seed) '(or null (integer 0 *)))
           (typep (getf data :budget) '(or null (integer 0 *))))
    (reject-artifact :invalid-record))
  data)

(defun counterexample-artifact-data (artifact)
  "Return a fresh versioned data record; modifying it cannot change ARTIFACT."
  (check-type artifact counterexample-artifact)
  (checked-codec #'deserialize-artifact-value (counterexample-artifact-payload artifact)))

(defun serialize-counterexample-artifact (artifact)
  "Return bounded AV1 wire data, never a Lisp reader form."
  (check-type artifact counterexample-artifact)
  (copy-seq (counterexample-artifact-payload artifact)))

(defun deserialize-counterexample-artifact (string)
  "Decode and validate AV1 data without reader evaluation or symbol interning."
  (let ((data (checked-codec #'deserialize-artifact-value string)))
    (validate-artifact-data data)
    (%make-counterexample-artifact (checked-codec #'serialize-artifact-value data))))

(defun bounded-copy (value)
  (checked-codec #'deserialize-artifact-value
                 (checked-codec #'serialize-artifact-value value)))

(defun make-counterexample-artifact (result &key (selection :selected))
  "Freeze original and accepted shrunk evidence from RESULT.
SELECTION is :SELECTED (prefer shrunk), :ORIGINAL or :SHRUNK. Unsupported
values, sharing and cycles signal INVALID-COUNTEREXAMPLE-ARTIFACT."
  (check-type result property-result)
  (let* ((metadata (property-result-schema-metadata result))
         (original (property-result-failure-evidence result))
         (shrunk (property-result-shrunk-evidence result))
         (choice (if (eq selection :selected) (if shrunk :shrunk :original) selection))
         (data
           (list :artifact-version 1 :record-kind :counterexample
                 :entity-kind (property-result-entity-kind result)
                 :name (property-result-property result)
                 :definition-digest (getf metadata :definition-digest)
                 :definition-digest-complete (getf metadata :definition-digest-complete)
                 :capabilities (bounded-copy (getf metadata :capabilities))
                 :original (evidence-data original) :shrunk (evidence-data shrunk)
                 :selection choice :seed (property-result-seed result)
                 :profile (property-result-profile result) :budget (property-result-budget result)
                 :options (bounded-copy (property-result-options result))
                 :provenance (bounded-copy (property-result-provenance result))))
         ;; Validate bounded decoded data, so malformed/cyclic manually built results
         ;; cannot make the record validator loop indefinitely.
         (wire (checked-codec #'serialize-artifact-value data)))
    (validate-artifact-data (checked-codec #'deserialize-artifact-value wire))
    (%make-counterexample-artifact wire)))

(defun recheck-counterexample (artifact &key (registry *registry*)
                                           (state-policy :unconfirmed)
                                           (target-revision :unknown))
  "Recheck saved input once without generation or shrinking.
Execution requires :STATE-POLICY :STATELESS, a caller assertion that external
state needs no restoration. Definition identity must be complete and unchanged.
Returns a :RECHECK record; never mutates the saved artifact or original result."
  (let* ((data (counterexample-artifact-data artifact))
         (kind (getf data :entity-kind))
         (saved (getf data (getf data :selection))))
    (labels ((outcome (status &optional detail observation)
               (list :schema-version 1 :record-kind :recheck :status status
                     :name (getf data :name) :entity-kind kind
                     :selection (getf data :selection) :detail detail
                     :target-revision target-revision
                     :failure (when observation (evidence-data observation)))))
      (handler-case
          (let ((definition (resolve-definition (getf data :name) kind registry)))
            (unless definition (return-from recheck-counterexample
                                 (outcome :definition-missing)))
            (multiple-value-bind (digest complete) (definition-digest definition :registry registry)
              (unless (and complete (getf data :definition-digest-complete))
                (return-from recheck-counterexample (outcome :incomparable-definition)))
              (unless (equal digest (getf data :definition-digest))
                (return-from recheck-counterexample (outcome :definition-mismatch))))
            (unless (eq state-policy :stateless)
              (return-from recheck-counterexample (outcome :unsupported :state-unconfirmed)))
            (when (getf saved :mutated-p)
              (return-from recheck-counterexample (outcome :unsupported :recorded-input-mutation)))
            (let* ((*registry* registry)
                   (arguments (getf saved :arguments))
                   (before-validation (snapshot-value arguments))
                   (bindings (if (eq kind :property)
                                 (property-arguments definition)
                                 (function-spec-argument-specs definition)))
                   (schema (make-instance 'tuple-spec :element-specs (mapcar #'second bindings))))
              (unless (validp schema arguments :registry registry)
                (return-from recheck-counterexample (outcome :input-invalid)))
              (unless (same-value-p before-validation arguments)
                (return-from recheck-counterexample (outcome :unsupported :input-mutated)))
              (let* ((property (if (eq kind :property) definition
                                   (make-function-check-property definition)))
                     (observation (observe-trial property arguments
                                                 :context (list :registry registry))))
                (cond
                  ((trial-observation-arguments-mutated-p observation)
                   (outcome :unsupported :input-mutated))
                  ((eq (trial-observation-status observation) :rejected)
                   (outcome :precondition-rejected))
                  ((eq (trial-observation-status observation) :passed) (outcome :passed))
                  ((eq (trial-observation-reason observation) :contract-error)
                   (outcome :contract-error (trial-observation-condition-report observation)))
                  (t (outcome (if (failure-identities-match-p
                                   (getf saved :signature)
                                   (trial-observation-signature observation))
                                  :same-failure :different-failure)
                              nil observation))))))
        (error (condition)
          (outcome :contract-error (type-of condition)))))))
