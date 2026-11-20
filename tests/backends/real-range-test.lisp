;;;; tests/backends/real-range-test.lisp

(defpackage #:cl-spec/tests/backends/real-range-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/tests/backends/real-range-checks
                #:check-draw-formats #:check-smallest-double #:check-tiny-intervals))

(in-package #:cl-spec/tests/backends/real-range-test)

(defun report-range-check (form requirement passed)
  (ok passed (format nil "~S meets the ~S check" form requirement)))

(deftest draw-format-follows-the-range-operands
  (check-draw-formats #'report-range-check))

(deftest draws-near-the-smallest-double
  (check-smallest-double #'report-range-check))

(deftest tiny-signed-intervals-generate-and-shrink
  (check-tiny-intervals #'report-range-check))
