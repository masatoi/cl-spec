;;;; tests/counterexample-test.lisp

(defpackage #:cl-spec/tests/counterexample-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/counterexample
                #:make-counterexample-artifact #:counterexample-artifact-data
                #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
                #:recheck-counterexample #:invalid-counterexample-artifact
                #:invalid-counterexample-artifact-reason)
  (:import-from #:cl-spec/src/property #:property #:register-property #:property-argument-schema)
  (:import-from #:cl-spec/src/property-runner #:property-result)
  (:import-from #:cl-spec/src/execution #:observe-trial)
  (:import-from #:cl-spec/src/schema #:definition-metadata #:definition-description)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form))

(in-package #:cl-spec/tests/counterexample-test)

(defun make-registry () (make-hash-table-registry))

(deftest invalid-selection-is-specific
  (multiple-value-bind (result property) (fixture (make-registry))
    (declare (ignore property))
    (ok (eq :invalid-selection
            (handler-case (make-counterexample-artifact result :selection :typo)
              (invalid-counterexample-artifact (condition)
                (invalid-counterexample-artifact-reason condition)))))))

(deftest opaque-metadata-does-not-discard-evidence
  (let ((registry (make-registry)))
    (multiple-value-bind (result property) (fixture registry)
      (declare (ignore property))
      (reinitialize-instance result :options (list :registry registry)
                                    :provenance (list :extension (lambda () t)))
      (let* ((artifact (make-counterexample-artifact result))
             (data (counterexample-artifact-data artifact)))
        (ok (getf (getf data :options) :unavailable))
        (ok (getf (getf data :provenance) :unavailable))
        (ok (find :options (getf data :metadata-omissions)
                  :key (lambda (omission) (getf omission :field))))
        (ok (eq :same-failure
                (getf (recheck-counterexample artifact :registry registry
                                             :state-policy :stateless) :status)))))))

(deftest optional-metadata-cannot-exhaust-the-artifact-budget
  (multiple-value-bind (result property) (fixture (make-registry))
    (declare (ignore property))
    (reinitialize-instance result :options (make-array 6000 :initial-element nil)
                                  :provenance (make-array 6000 :initial-element nil))
    (let* ((artifact (make-counterexample-artifact result))
           (data (counterexample-artifact-data artifact)))
      (ok (equal '(4) (getf (getf data :original) :arguments)))
      (ok (getf (getf data :options) :unavailable))
      (ok (getf (getf data :provenance) :unavailable)))))

(deftest malformed-captured-metadata-is-rejected-before-lookup
  (dolist (metadata (list '(:other . 3)
                         (let ((cycle (list :other nil)))
                           (setf (cddr cycle) cycle) cycle)))
    (let ((result (make-instance 'property-result :trials 1 :schema-metadata metadata)))
      (ok (handler-case (progn (make-counterexample-artifact result) nil)
            (invalid-counterexample-artifact (condition)
              (eq :invalid-definition-metadata
                  (invalid-counterexample-artifact-reason condition))))))))

(defclass custom-schema-property (property) ())

(defmethod property-argument-schema ((property custom-schema-property))
  (normalize-spec-form '(tuple string)))

(defmethod definition-description ((property custom-schema-property))
  (multiple-value-bind (data children links complete) (call-next-method)
    (declare (ignore complete))
    (values data children links t)))

(deftest recheck-honors-whole-argument-schema
  (let* ((registry (make-registry))
         (calls 0)
         (property (make-instance 'custom-schema-property :name 'custom-schema
                                  :arguments '((x integer))
                                  :source-form '(custom-schema)
                                  :function (lambda (x) (declare (ignore x)) (incf calls) nil))))
    (register-property property registry)
    (let* ((evidence (observe-trial property (list "accepted-by-override")))
           (metadata (definition-metadata property :registry registry :capabilities nil))
           (artifact (make-counterexample-artifact
                      (make-instance 'property-result :property 'custom-schema :trials 1
                                     :schema-metadata metadata :failure-evidence evidence))))
      (ok (eq :same-failure
              (getf (recheck-counterexample artifact :registry registry
                                           :state-policy :stateless) :status)))
      (ok (= 2 calls)))))

(defun fixture (registry &key (function (lambda (x) (declare (ignore x)) nil))
                              (arguments '(4)) (spec 'integer))
  (let* ((property
           (make-instance 'property :name 'example
                          :arguments (list (list 'x (normalize-spec-form spec)))
                          :body '(nil) :source-form '(property example) :function function))
         (metadata (definition-metadata property :registry registry
                                        :capabilities '(:generation :unknown)))
         (evidence (observe-trial property arguments)))
    (register-property property registry)
    (values (make-instance 'property-result :property 'example :trials 1
                          :schema-metadata metadata :failure-evidence evidence
                          :status :failed :seed 42 :profile :normal :budget 20)
            property)))

(deftest nonfinite-evidence-preserves-public-error-contract
  #+sbcl
  (dolist (bits '(#x7ff00000 -1048576 #x7ff80000))
    (multiple-value-bind (result property)
        (fixture (make-registry)
                 :arguments (list (funcall (symbol-function 'sb-kernel:make-double-float) bits 0))
                 :spec t)
      (declare (ignore property))
      (ok (handler-case (progn (make-counterexample-artifact result) nil)
            (invalid-counterexample-artifact (condition)
              (eq :unsupported-float (invalid-counterexample-artifact-reason condition))))))))

(deftest long-list-counterexample-survives-persistence-and-recheck
  (let ((registry (make-registry))
        (input (loop for i below 500 collect i)))
    (multiple-value-bind (result property)
        (fixture registry :arguments (list input) :spec '(list-of integer))
      (declare (ignore property))
      (let* ((artifact (make-counterexample-artifact result))
             (restored (deserialize-counterexample-artifact
                        (serialize-counterexample-artifact artifact))))
        (ok (equal input
                   (first (getf (getf (counterexample-artifact-data restored) :original)
                                :arguments))))
        (ok (eq :same-failure
                (getf (recheck-counterexample restored :registry registry
                                             :state-policy :stateless) :status)))))))

(deftest immutable-roundtrip-and-direct-recheck
  (let ((registry (make-registry)) (calls 0) (fixed nil))
    (multiple-value-bind (result property)
        (fixture registry :function (lambda (x) (incf calls) (and fixed (= x 4))))
      (declare (ignore property))
      (let* ((artifact (make-counterexample-artifact result))
             (wire (serialize-counterexample-artifact artifact))
             (restored (deserialize-counterexample-artifact wire)))
        (ok (= calls 1))
        (ok (eq :same-failure
                (getf (recheck-counterexample restored :registry registry
                                             :state-policy :stateless) :status)))
        (ok (= calls 2))
        (setf fixed t)
        (ok (eq :passed (getf (recheck-counterexample artifact :registry registry
                                                    :state-policy :stateless) :status)))
        (ok (= calls 3))
        (let ((copy (counterexample-artifact-data restored)))
          (setf (getf copy :selection) :corrupt))
        (ok (eq :original (getf (counterexample-artifact-data restored) :selection)))
        (ok (string= wire (serialize-counterexample-artifact artifact)))))))

(deftest refuse-before-execution
  (let ((registry (make-registry)) (calls 0))
    (multiple-value-bind (result property)
        (fixture registry :function (lambda (x) (declare (ignore x)) (incf calls) nil))
      (let ((artifact (make-counterexample-artifact result)))
        (ok (eq :unsupported
                (getf (recheck-counterexample artifact :registry registry) :status)))
        (ok (eq :definition-missing
                (getf (recheck-counterexample artifact :registry (make-registry)
                                             :state-policy :stateless) :status)))
        (reinitialize-instance property :body '(different) :function #'identity)
        (ok (eq :definition-mismatch
                (getf (recheck-counterexample artifact :registry registry
                                             :state-policy :stateless) :status)))
        (ok (= calls 1))))))

(deftest malformed-and-missing-evidence
  (ok (signals (make-counterexample-artifact
                (make-instance 'property-result :trials 1 :status :passed))
               'invalid-counterexample-artifact))
  (dolist (wire '("" "#.(error \"reader evaluated\")" "AV1 (999)"))
    (ok (signals (deserialize-counterexample-artifact wire)
                 'invalid-counterexample-artifact))))

(deftest reject-record-tampering
  (let ((registry (make-registry)))
    (multiple-value-bind (result property) (fixture registry)
      (declare (ignore property))
      (let* ((artifact (make-counterexample-artifact result))
             (data (counterexample-artifact-data artifact)))
        (setf (getf data :artifact-version) 99)
        (ok (signals
             (deserialize-counterexample-artifact
              (cl-spec/src/utils/artifact-values:serialize-artifact-value data))
             'invalid-counterexample-artifact))
        (ok (signals (make-counterexample-artifact result :selection :shrunk)
                     'invalid-counterexample-artifact))))))

(deftest reject-unknown-failure-identity
  (multiple-value-bind (result property) (fixture (make-registry))
    (declare (ignore property))
    (let ((data (counterexample-artifact-data (make-counterexample-artifact result))))
      (setf (getf (getf data :original) :signature) '(:return-value :bogus))
      (ok (signals
           (deserialize-counterexample-artifact
            (cl-spec/src/utils/artifact-values:serialize-artifact-value data))
           'invalid-counterexample-artifact)))))

(deftest incomplete-and-mutating-evidence
  (let ((registry (make-registry)))
    (multiple-value-bind (result property) (fixture registry)
      (declare (ignore result))
      (reinitialize-instance property :source-form nil)
      (let* ((metadata (definition-metadata property :registry registry :capabilities nil))
             (artifact (make-counterexample-artifact
                        (make-instance 'property-result :property 'example :trials 1
                                       :schema-metadata metadata
                                       :failure-evidence (observe-trial property '(4))))))
        (ok (eq :incomparable-definition
                (getf (recheck-counterexample artifact :registry registry
                                             :state-policy :stateless) :status))))))
  (let* ((registry (make-registry))
         (property (make-instance 'property :name 'mutator :source-form '(mutator)
                                  :arguments (list (list 'x (normalize-spec-form '(list-of integer))))
                                  :function (lambda (x) (setf (car x) 0) nil)))
         (metadata (definition-metadata property :registry registry :capabilities nil))
         (observation (observe-trial property (list (list 4)))))
    (register-property property registry)
    (let ((artifact (make-counterexample-artifact
                     (make-instance 'property-result :property 'mutator :trials 1
                                    :schema-metadata metadata :failure-evidence observation))))
      (ok (eq :recorded-input-mutation
              (getf (recheck-counterexample artifact :registry registry
                                           :state-policy :stateless) :detail))))))
