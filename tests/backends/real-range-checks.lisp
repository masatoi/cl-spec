;;;; tests/backends/real-range-checks.lisp
;;;;
;;;; Numerical checks shared by the Rove suite and the standalone CLISP CI job.
;;;; REPORT receives the input range, the requirement and whether it held.

(defpackage #:cl-spec/tests/backends/real-range-checks
  (:use #:cl)
  (:import-from #:cl-spec/main #:normalize-spec-form #:sample #:validp)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/backends/check-it-generators #:compile-spec-generator)
  (:import-from #:check-it #:generate #:shrink)
  (:export #:check-draw-formats #:check-smallest-double #:check-tiny-intervals
           #:run-real-range-checks))

(in-package #:cl-spec/tests/backends/real-range-checks)

(defun check-draw-formats (report)
  "Check the sample count, type and admission for mixed-format and open ranges."
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
      (let* ((spec (normalize-spec-form form))
             (values (sample spec :count 32)))
        (funcall report form :sample-count (= 32 (length values)))
        (funcall report form type
                 (every (lambda (value) (and (typep value type) (validp spec value))) values))))))

(defun check-smallest-double (report)
  "Check the smallest double and, when available, the adjacent subnormal values."
  (let* ((low least-positive-double-float)
         (high (if (< low least-positive-normalized-double-float) (* 32 (rational low)) low))
         (form (list 'range 'real low high))
         (spec (normalize-spec-form form))
         (values (sample spec :count 32)))
    (funcall report form :sample-count (= 32 (length values)))
    (funcall report form :samples (every (lambda (value) (validp spec value)) values))))

(defun check-tiny-intervals (report)
  "Check samples and shrink candidates on signed intervals and adjacent endpoints."
  (dolist (tiny (list least-positive-single-float least-positive-double-float))
    (let* ((one (float 1 tiny))
           (twice (* 2 (rational tiny)))
           (normal (if (typep tiny 'single-float)
                       least-positive-normalized-single-float
                       least-positive-normalized-double-float))
           (next (* normal (+ one (scale-float one (- 1 (float-digits one)))))))
      (dolist (bounds (list (list 0 tiny) (list (- tiny) 0) (list (- tiny) tiny)
                            (list tiny twice) (list (- twice) (- tiny))
                            (list normal next) (list (- next) (- normal))))
        (let* ((form (list* 'range 'real bounds))
               (spec (normalize-spec-form form))
               (values (sample spec :count 32))
               (generator (compile-spec-generator spec nil)))
          (funcall report form :sample-count (= 32 (length values)))
          (funcall report form :samples (every (lambda (value) (validp spec value)) values))
          (funcall report form :draw (validp spec (generate generator)))
          (funcall report form :shrink
                   (validp spec (shrink generator (lambda (value) (validp spec value))))))))))

(defun run-real-range-checks ()
  "Run every numerical check, signalling an error if any requirement fails."
  (flet ((require-check (form requirement passed)
           (unless passed (error "~S failed the ~S check." form requirement))))
    (check-draw-formats #'require-check)
    (check-smallest-double #'require-check)
    (check-tiny-intervals #'require-check))
  t)
