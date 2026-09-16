;;;; src/counterexample.lisp

(defpackage #:cl-spec/src/counterexample
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:serialize-artifact-value #:deserialize-artifact-value
                #:encode-artifact-value #:decode-artifact-value
                #:artifact-value-error #:artifact-value-error-reason)
  (:import-from #:cl-spec/src/property-runner
                #:property-result #:property-result-schema-metadata
                #:property-result-entity-kind #:property-result-property
                #:property-result-failure-evidence #:property-result-shrunk-evidence
                #:property-result-seed #:property-result-profile #:property-result-budget
                #:property-result-options #:property-result-provenance
                #:property-result-shrink-report)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-arguments #:trial-observation-arguments-mutated-p
                #:trial-observation-status #:trial-observation-reason
                #:trial-observation-signature #:trial-observation-condition-report
                #:observation-failure-p #:observe-trial #:failure-identities-match-p
                #:observation-failure-phase
                #:snapshot-value #:same-value-p)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/schema #:resolve-definition #:definition-digest
                #:definition-state-constraints)
  (:import-from #:cl-spec/src/property #:property-argument-schema)
  (:import-from #:cl-spec/src/function-spec #:make-function-check-property)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/validator #:validp)
  (:export #:make-counterexample-artifact #:counterexample-artifact-data
           #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
           #:recheck-counterexample #:counterexample-artifact
           #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason))

(in-package #:cl-spec/src/counterexample)

(define-condition invalid-counterexample-artifact (error)
  ((reason :initarg :reason
           :reader invalid-counterexample-artifact-reason
           :documentation "Why the serialized artifact cannot be accepted."))
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

(defun record-p (value keys &optional optional-keys)
  (and (finite-list-p value) (evenp (length value))
       (loop for (key) on value by #'cddr
             always (and (or (member key keys) (member key optional-keys))
                         (not (member key seen)))
             collect key into seen
             finally (return (every (lambda (key) (member key seen)) keys)))))

(defun evidence-data (observation)
  (when observation
    (unless (observation-failure-p observation) (reject-artifact :not-failure-evidence))
    (list :arguments (trial-observation-arguments observation)
          :status (trial-observation-status observation)
          :reason (trial-observation-reason observation)
          :signature (trial-observation-signature observation)
          :mutated-p (trial-observation-arguments-mutated-p observation))))

(defun case-signature-parts (signature)
  "Split SIGNATURE into (values CASE-NAME INNER WRAPPED-P).

A function-spec failure of a selected case wraps the established identity as
(:CASE NAME . INNER).  Anything else is returned unchanged with WRAPPED-P NIL, so
the case-less shapes are read exactly as before."
  (if (and (consp signature) (eq :case (first signature)))
      (values (second signature) (cddr signature) t)
      (values nil signature nil)))

(defun valid-signature-shape-p (signature reason status kind)
  "Recognize one unwrapped failure identity against its reason and status."
  (and (finite-list-p signature)
       (if (eq kind :property)
           (case reason
             (:predicate-false (and (eq status :failed) (equal signature '(:property-false))))
             (:condition (and (eq status :error) (= (length signature) 2)
                              (eq (first signature) :property-condition)
                              (symbolp (second signature)))))
           (case reason
             ((:return-spec :postcondition)
              (and (eq status :failed) (= (length signature) 3)
                   (member (first signature) '(:return-value :return-values))
                    (eq (second signature) reason)))
             (:missing-condition
              (and (eq status :failed) (equal signature '(:missing-condition))))
             (:condition-spec
              (and (eq status :error) (= (length signature) 3)
                   (eq (first signature) :condition-spec) (symbolp (second signature))))
             ((:condition :contract-error)
              (and (eq status :error) (= (length signature) 2)
                   (eq (first signature) (if (eq reason :condition) :target-signal :contract-error))
                   (symbolp (second signature))))))))

(defun valid-signature-p (data kind)
  "Recognize the failure identities this artifact format accepts.

A function-spec case wraps the established identity as (:CASE NAME . INNER); NAME
must be a keyword and INNER must be one of the shapes CASE-SIGNATURE-PARTS
separates.  The wrapper is not a wildcard: evidence that names no case is never
accepted as a case-carrying failure, and the validator is not relaxed to accept
arbitrary signatures.  A case-selection error cannot be persisted at all -- it
never reached the target -- and is refused before this point."
  (multiple-value-bind (case-name inner wrapped-p)
      (case-signature-parts (getf data :signature))
    (and (finite-list-p (getf data :signature))
         (if wrapped-p
             (and (keywordp case-name) (consp inner) (finite-list-p inner))
             t)
         (valid-signature-shape-p inner (getf data :reason) (getf data :status) kind))))

(defun valid-evidence-p (data)
  (and (record-p data '(:arguments :status :reason :signature :mutated-p))
       (finite-list-p (getf data :arguments))
       (member (getf data :status) '(:failed :error))
       (keywordp (getf data :reason))
       (consp (getf data :signature))
       (finite-list-p (getf data :signature))
       (member (getf data :mutated-p) '(nil t))))

(defun validate-artifact-data (data)
  (unless
      (and (record-p data '(:artifact-version :record-kind :entity-kind :name
                           :definition-digest :definition-digest-complete :capabilities
                           :original :shrunk :selection :seed :profile :budget
                           :options :provenance) '(:metadata-omissions
                                                  :digest-omissions :digest-exclusions :shrink-report))
           (finite-list-p (getf data :metadata-omissions))
           (every (lambda (omission)
                    (and (record-p omission '(:field :reason))
                         (member (getf omission :field) '(:options :provenance :capabilities
                                                                        :digest-omissions
                                                                        :digest-exclusions :shrink-report))
                         (keywordp (getf omission :reason))))
                  (getf data :metadata-omissions))
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
  "Return fresh data, marking digest details absent in older artifacts as not collected."
  (check-type artifact counterexample-artifact)
  (let ((data (checked-codec #'deserialize-artifact-value
                             (counterexample-artifact-payload artifact))))
    (dolist (field '(:digest-omissions :digest-exclusions :shrink-report))
      (setf (getf data field) (getf data field :not-collected)))
    data))

(defun serialize-counterexample-artifact (artifact)
  "Return bounded AV1 wire data, never a Lisp reader form."
  (check-type artifact counterexample-artifact)
  (copy-seq (counterexample-artifact-payload artifact)))

(defun deserialize-counterexample-artifact (string)
  "Decode and validate AV1 data without reader evaluation or symbol interning."
  (let ((data (checked-codec #'deserialize-artifact-value string)))
    (validate-artifact-data data)
    (%make-counterexample-artifact (checked-codec #'serialize-artifact-value data))))

(defun persistable-metadata (value field)
  "Copy optional metadata through bounded tags, recording omissions explicitly."
  (handler-case
      (decode-artifact-value (encode-artifact-value value))
    (artifact-value-error (condition)
      (let ((reason (artifact-value-error-reason condition)))
        (values (list :unavailable t :reason reason) (list :field field :reason reason))))))

(defun artifact-record-wire (data)
  "Encode once normally; omit optional metadata if its combined size exhausts the budget."
  (handler-case (serialize-artifact-value data)
    (artifact-value-error (condition)
      (unless (member (artifact-value-error-reason condition)
                      '(:structure-limit :character-limit :text-limit))
        (reject-artifact (artifact-value-error-reason condition)))
      (let ((omissions (getf data :metadata-omissions)))
        (dolist (field '(:options :provenance :capabilities
                          :digest-omissions :digest-exclusions :shrink-report))
          (when (getf data field)
            (setf (getf data field) (list :unavailable t :reason :artifact-budget))
            (setf omissions (remove field omissions :key (lambda (item) (getf item :field))))
            (push (list :field field :reason :artifact-budget) omissions)))
        (setf (getf data :metadata-omissions) omissions)
        ;; Evidence still must fit: this retry never drops arguments or failure identity.
        (checked-codec #'serialize-artifact-value data)))))

(defun make-counterexample-artifact (result &key (selection :selected))
  "Freeze original and accepted shrunk evidence from RESULT.
SELECTION is :SELECTED (prefer shrunk), :ORIGINAL or :SHRUNK. Unsupported
evidence signals INVALID-COUNTEREXAMPLE-ARTIFACT; unsupported optional metadata
is represented by an unavailable placeholder and :METADATA-OMISSIONS.
A case-selection error never reached the target, so it is refused here rather
than persisted as a call that never happened."
  (check-type result property-result)
  (unless (member selection '(:selected :original :shrunk))
    (reject-artifact :invalid-selection))
  (let* ((metadata (property-result-schema-metadata result))
         (original (property-result-failure-evidence result))
         (shrunk (property-result-shrunk-evidence result))
         (choice (if (eq selection :selected) (if shrunk :shrunk :original) selection))
         (omissions nil))
    (unless (and (finite-list-p metadata) (evenp (length metadata)))
      (reject-artifact :invalid-definition-metadata))
    ;; A :CAPTURE / :STATE-POST contract observes state and never restores it, so
    ;; a saved input is not a reproducible artifact.  The answer comes from the
    ;; declaration captured before the run, not from the current registry:
    ;; registering a different definition under the same name must not change it.
    (when (eq :present (getf metadata :state-constraints))
      (reject-artifact :stateful-contract-unsupported))
    (when (or (and original (eq :case-selection (observation-failure-phase original)))
              (and shrunk (eq :case-selection (observation-failure-phase shrunk))))
      (reject-artifact :case-selection-failure))
    (when (and (eq choice :shrunk) (not shrunk)) (reject-artifact :missing-shrunk-evidence))
    (labels ((optional-metadata (value field)
               (multiple-value-bind (copy omission) (persistable-metadata value field)
                 (when omission (push omission omissions))
                 copy)))
      (let ((data
              (list :artifact-version 1 :record-kind :counterexample
                    :entity-kind (property-result-entity-kind result)
                    :name (property-result-property result)
                    :definition-digest (getf metadata :definition-digest)
                    :definition-digest-complete (getf metadata :definition-digest-complete)
                    :digest-omissions
                     (optional-metadata (getf metadata :digest-omissions :not-collected)
                                        :digest-omissions)
                     :digest-exclusions
                     (optional-metadata (getf metadata :digest-exclusions :not-collected)
                                        :digest-exclusions)
                     :capabilities (optional-metadata (getf metadata :capabilities) :capabilities)
                    :original (evidence-data original) :shrunk (evidence-data shrunk)
                    :shrink-report (optional-metadata (property-result-shrink-report result)
                                                       :shrink-report)
                     :selection choice :seed (property-result-seed result)
                    :profile (property-result-profile result)
                    :budget (property-result-budget result)
                    :options (optional-metadata (property-result-options result) :options)
                    :provenance (optional-metadata (property-result-provenance result)
                                                   :provenance))))
        (when omissions (setf (getf data :metadata-omissions) (nreverse omissions)))
        ;; Record checks are cycle-safe; the single wire encoding bounds all nested values.
        (validate-artifact-data data)
        (%make-counterexample-artifact (artifact-record-wire data))))))

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
            ;; Refuse a state-observing contract before the target is called:
            ;; rechecking would reapply the saved input to unrestored state.
            ;; Checked before the digest so a state-observing definition under a
            ;; saved name reports the real reason rather than a mismatch.
            (when (definition-state-constraints definition)
              (return-from recheck-counterexample
                (outcome :unsupported :stateful-contract-unsupported)))
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
                   (property (if (eq kind :property) definition
                                 (make-function-check-property definition)))
                   (schema (property-argument-schema property)))
              (unless (validp schema arguments :registry registry)
                (return-from recheck-counterexample (outcome :input-invalid)))
              (unless (same-value-p before-validation arguments)
                (return-from recheck-counterexample (outcome :unsupported :input-mutated)))
              (let ((observation (observe-trial property arguments
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
