;;;; tests/generator-test.lisp

(defpackage #:cl-spec/tests/generator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:no-generator-backend
                #:generator-unavailable)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:generator-for
                #:sample
                #:backend-default-trials)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec
                #:registry-register-generator)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/generator-test)

(deftest backend-protocol-is-generic
  (testing "the three backend operations are generic functions"
    (ok (typep #'compile-generator 'generic-function))
    (ok (typep #'generate-value 'generic-function))
    (ok (typep #'run-generated-test 'generic-function))))

(deftest missing-backend-is-reported
  (testing "CURRENT-GENERATOR-BACKEND signals when no backend is installed"
    (let ((*generator-backend* nil))
      (ok (signals (current-generator-backend) 'no-generator-backend)))))

(deftest installed-backend-is-returned
  (testing "CURRENT-GENERATOR-BACKEND returns whatever is bound"
    (let ((*generator-backend* :fake-backend))
      (ok (eq :fake-backend (current-generator-backend))))))

(deftest sample-produces-values-the-spec-admits
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "SAMPLE returns COUNT values"
      (ok (= 10 (length (sample 'positive-integer :registry registry))))
      (ok (= 3 (length (sample 'positive-integer :count 3 :registry registry)))))
    (testing "every sampled value satisfies the spec"
      (ok (every (lambda (value) (validp 'positive-integer value :registry registry))
                 (sample 'positive-integer :count 50 :registry registry))))
    (testing "the same seed reproduces the same sample"
      (ok (equal (sample 'positive-integer :count 20 :seed 4242 :registry registry)
                 (sample 'positive-integer :count 20 :seed 4242 :registry registry))))
    (testing "GENERATOR-FOR returns something GENERATE-VALUE accepts"
      (let ((generator (generator-for 'positive-integer :registry registry)))
        (ok (validp 'positive-integer
                    (generate-value (current-generator-backend) generator)
                    :registry registry)))))
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'wide
                            (normalize-spec-form '(range integer 20 100) :name 'wide))
    (testing "a range wider than check-it's default size is still respected"
      (ok (every (lambda (value) (<= 20 value 100))
                 (sample 'wide :count 50 :registry registry))))))

(deftest the-backend-supplies-a-default-trial-count
  (testing "BACKEND-DEFAULT-TRIALS is a positive integer read from check-it"
    (let ((trials (backend-default-trials (current-generator-backend))))
      (ok (integerp trials))
      (ok (plusp trials))))
  (testing "it is read live rather than snapshotted at load time"
    (ok (= 7 (let ((check-it:*num-trials* 7))
               (backend-default-trials (current-generator-backend)))))))

(deftest a-custom-generator-is-what-the-backend-draws-from
  (let ((registry (make-hash-table-registry)))
    (registry-register-generator
     registry 'even-only
     (make-instance 'custom-generator
                    :name 'even-only
                    :function (lambda () (* 2 (random 5)))))
    (registry-register-spec registry 'even-number
                            (normalize-spec-form '(and integer (range 0 8))
                                                 :name 'even-number
                                                 :generator 'even-only))
    (testing "the values come from the generator rather than from the DSL"
      ;; The spec admits odd numbers too, so twenty even values in a row is the
      ;; generator's doing: at 1/2 each, the DSL would need about a million runs
      ;; to produce that by chance.
      (let ((values (sample 'even-number :count 20 :seed 11 :registry registry)))
        (ok (every #'evenp values))))
    (testing "a spec naming a generator that is not registered says so"
      (registry-register-spec registry 'orphan
                              (normalize-spec-form 'integer :name 'orphan
                                                   :generator 'not-registered))
      (ok (signals (sample 'orphan :count 1 :registry registry)
                   'generator-unavailable)))))
