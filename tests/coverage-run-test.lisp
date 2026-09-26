;;;; tests/coverage-run-test.lisp
(defpackage #:cl-spec/tests/coverage-run-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/src/coverage #:coverage-data)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/tests/coverage-direct-test #:count-bucket))
(in-package #:cl-spec/tests/coverage-run-test)

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
