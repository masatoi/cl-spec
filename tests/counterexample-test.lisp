;;;; tests/counterexample-test.lisp

(defpackage #:cl-spec/tests/counterexample-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/counterexample
                #:make-counterexample-artifact #:counterexample-artifact-data
                #:serialize-counterexample-artifact #:deserialize-counterexample-artifact
                #:recheck-counterexample #:invalid-counterexample-artifact)
  (:import-from #:cl-spec/src/property #:property #:register-property)
  (:import-from #:cl-spec/src/property-runner #:property-result)
  (:import-from #:cl-spec/src/execution #:observe-trial)
  (:import-from #:cl-spec/src/schema #:definition-metadata)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form))

(in-package #:cl-spec/tests/counterexample-test)

(defun make-registry () (make-hash-table-registry))

(defun fixture (registry &key (function (lambda (x) (declare (ignore x)) nil))
                              (arguments '(4)))
  (let* ((property
           (make-instance 'property :name 'example
                          :arguments (list (list 'x (normalize-spec-form 'integer)))
                          :body '(nil) :source-form '(property example) :function function))
         (metadata (definition-metadata property :registry registry
                                        :capabilities '(:generation :unknown)))
         (evidence (observe-trial property arguments)))
    (register-property property registry)
    (values (make-instance 'property-result :property 'example :trials 1
                          :schema-metadata metadata :failure-evidence evidence
                          :status :failed :seed 42 :profile :normal :budget 20)
            property)))

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
