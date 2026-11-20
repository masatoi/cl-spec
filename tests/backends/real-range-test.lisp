;;;; tests/backends/real-range-test.lisp

(defpackage #:cl-spec/tests/backends/real-range-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/main #:sample #:normalize-spec-form #:validp)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/backends/real-range-test)

(deftest draw-format-follows-the-range-operands
  (dolist (case '(((range real -2.0f38 2.0f38) double-float)
                  ((range real -1d200 1d200) double-float)
                  ((range real -1l250 1l250) long-float)
                  ((range real -2.0f0 1d200) double-float)
                  ((range real 0 1d-200) double-float)
                  ((range real 2.0f38 *) double-float)
                  ((range real * -1d200) double-float)
                  ((range real 1.0f0 *) single-float)
                  ((range real 1/4 3/4) single-float)
                  ((range real 1d0 2d0) double-float)))
    (destructuring-bind (form type) case
      (testing (format nil "~S produces admitted ~S draws" form type)
        (let* ((spec (normalize-spec-form form))
               (values (sample spec :count 32)))
          (ok (= 32 (length values)))
          (ok (every (lambda (value) (and (typep value type) (validp spec value))) values)))))))

(deftest draws-near-the-smallest-double
  ;; CLISP has no subnormals. On implementations with gradual underflow the
  ;; nondegenerate interval also exercises rounding and the endpoint clamp.
  (let* ((low least-positive-double-float)
         (high (if (< low least-positive-normalized-double-float) (* 32 low) low))
         (spec (normalize-spec-form (list 'range 'real low high)))
         (values (sample spec :count 32)))
    (ok (= 32 (length values)))
    (ok (every (lambda (value) (and (typep value 'double-float) (validp spec value))) values))))
