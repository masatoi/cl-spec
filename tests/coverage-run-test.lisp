;;;; tests/coverage-run-test.lisp
(defpackage #:cl-spec/tests/coverage-run-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/coverage #:coverage-data)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/tests/coverage-direct-test #:count-bucket))
(in-package #:cl-spec/tests/coverage-run-test)

(defclass incomplete-backend () ())

(defmethod cl-spec/src/generator:run-generated-test
    ((backend incomplete-backend) property &key options)
  (declare (ignore backend property))
  (list :status :passed :trials (getf options :trials) :rejected 0))

(defmethod cl-spec/src/coverage:backend-coverage-protocol ((backend incomplete-backend))
  :coverage-v1)

(deftest participating-backend-must-complete-coverage
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry))
        (cl-spec:*generator-backend* (make-instance 'incomplete-backend)))
    (cl-spec:defproperty incomplete ((payload (plist (:optional (:memo integer)))))
      (:trials (:normal 1)) t)
    (ok (handler-case
            (progn (cl-spec:run-property 'incomplete :seed 1
                     :options '(:coverage (:mode :observe))) nil)
          (cl-spec:invalid-backend-result () t)))))

(deftest observe-does-not-change-seeded-inputs
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (seen nil))
    (cl-spec:defproperty probe ((payload (plist (:optional (:memo integer)))))
      (:trials (:normal 10)) (push (copy-list payload) seen) t)
    (cl-spec:run-property 'probe :seed 42)
    (let ((baseline seen))
      (setf seen nil)
      (let* ((result (cl-spec:run-property 'probe :seed 42
                        :options '(:coverage (:mode :observe))))
             (report (coverage-data result)))
        (ok (equal baseline seen))
        (ok (= 10 (getf report :trials)))
        (ok (= 10 (+ (count-bucket report :field-presence :checked :present)
                     (count-bucket report :field-presence :checked :absent))))))))

(deftest generated-coverage-excludes-pre-rejections-and-shrinking
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer))))) (:pre nil) (:returns t))
    (let ((report (coverage-data (cl-spec:check-function 'identity :trials 5 :seed 2
                                  :options '(:coverage (:mode :observe))))))
      (ok (= 5 (getf report :trials)))
      (ok (= 0 (count-bucket report :field-presence :checked :present))))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer))))) (:returns integer))
    (let ((report (coverage-data (cl-spec:check-function 'identity :trials 5 :seed 2
                                  :options '(:coverage (:mode :observe))))))
      (ok (= 1 (getf report :trials)))
      (ok (= 1 (+ (count-bucket report :field-presence :checked :present)
                  (count-bucket report :field-presence :checked :absent)))))))

(deftest exercise-plans-basic-plist-buckets
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (seen nil))
    (cl-spec:defproperty planned
      ((payload (plist (:required (:n (range integer 1 3))) (:optional (:memo integer)))))
      (:trials (:normal 7)) (push (copy-list payload) seen) t)
    (let* ((result (cl-spec:run-property 'planned :seed 7
                     :options '(:coverage (:mode :exercise))))
           (report (coverage-data result)))
      (ok (some (lambda (p) (member :coverage-extra p)) seen))
      (ok (plusp (count-bucket report :field-presence :checked :absent)))
      (ok (plusp (count-bucket report :field-presence :checked :present)))
      (ok (plusp (count-bucket report :numeric-boundary :checked :lower)))
      (ok (plusp (count-bucket report :numeric-boundary :checked :upper)))
      (ok (getf report :plan))
      (ok (equal report (coverage-data (cl-spec:run-property 'planned :seed result)))))))

(deftest extra-key-pool-collisions-never-produce-duplicate-keys
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)) (seen nil))
    (cl-spec:defproperty collisions
      ((payload (plist (:required (:coverage-extra integer)) (:optional (:memo integer)))))
      (:trials (:normal 5)) (push payload seen) t)
    (let ((data (coverage-data (cl-spec:run-property 'collisions :seed 4
                                :options '(:coverage (:mode :exercise
                                                      :extra-keys (:coverage-extra)))))))
      (ok (every (lambda (p) (= 1 (count :coverage-extra p))) seen))
      (ok (= 0 (count-bucket data :extra-key-presence :generated :present)))
      (ok (eq :unsupported
              (getf (first (getf (getf data :plan) :entries)) :status))))))

(deftest zero-budget-and-short-plan-report-unattempted-work
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer))))) (:returns t))
    (dolist (budget '(0 1))
      (let* ((result (cl-spec:check-function
                      'identity :trials budget :seed 5
                      :options '(:coverage (:mode :exercise))))
             (data (coverage-data result))
             (entries (getf (getf data :plan) :entries)))
        (ok (= budget (getf data :trials)))
        (ok (some (lambda (e) (eq :pending (getf e :status))) entries))
        (ok (= budget (+ (count-bucket data :field-presence :generated :present)
                         (count-bucket data :field-presence :generated :absent))))))))

(deftest custom-whole-generators-are-observed-but-never-targeted
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defgenerator whole () (list (list :memo 7)))
    (cl-spec:defspec-function identity
      (:args (payload (plist (:optional (:memo integer)))))
      (:args-generator whole) (:returns t))
    (let* ((data (coverage-data (cl-spec:check-function 'identity :trials 2 :seed 1
                                 :options '(:coverage (:mode :exercise)))))
           (capabilities (getf data :capabilities)))
      (ok (= 2 (count-bucket data :field-presence :checked :present)))
      (ok (every (lambda (d)
                   (every (lambda (b) (not (eq :supported (getf b :targeting))))
                          (getf d :buckets))) capabilities)))))

(deftest missing-domain-measurement-does-not-publish-zero
  (let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
    (cl-spec:defproperty plain ((payload (plist (:optional (:memo integer)))))
      (:trials (:normal 1)) t)
    (let* ((data (coverage-data (cl-spec:run-property 'plain :seed 1
                                :options '(:coverage (:mode :observe)))))
           (row (find :domain-valid (getf (first (getf data :dimensions)) :stages)
                      :key (lambda (s) (getf s :stage)))))
      (ok (eq :not-collected (getf row :availability)))
      (ok (not (member :buckets row)))
      (ok (not (member :observed-trials row))))))
