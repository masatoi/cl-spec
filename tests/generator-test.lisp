;;;; tests/generator-test.lisp

(defpackage #:cl-spec/tests/generator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/generator
                #:generator-for
                #:sample
                #:backend-default-trials
                #:current-generator-backend)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/generator-test)

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
      (ok (generator-for 'positive-integer :registry registry))))
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
