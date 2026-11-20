;;;; tests/withdraw-cancellation-example-test.lisp

(defpackage #:cl-spec/tests/withdraw-cancellation-example-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/examples/withdraw-cancellation #:demo-double-cancellation))

(in-package #:cl-spec/tests/withdraw-cancellation-example-test)

(deftest generated-double-cancellation-shrinks-and-reproduces
  (let* ((report (demo-double-cancellation :seed 2))
         (original (getf report :original)) (smaller (getf report :shrunk)))
    (ok (eq :failed (getf report :status)))
    (ok (> (length original) (length smaller)))
    (ok (equal smaller '(:withdraw :cancel :cancel)))
    (ok (equal (getf report :signature) '(:state-machine :observation-mismatch :cancel)))
    (ok (equal (getf report :divergence)
               '(:index 2 :command :cancel :expected 100 :actual 110)))
    (ok (equal original (getf report :replayed-original)))
    (ok (equal smaller (getf report :replayed-shrunk)))
    (ok (equal (getf report :signature) (getf report :direct-signature)))
    (ok (eq :same-failure (getf report :saved-recheck)))
    (ok (eq :passed (getf report :repaired-direct)))
    (ok (eq :passed (getf report :repaired-recheck)))
    (ok (eq :passed (getf report :repaired-run)))))

(deftest changing-the-seed-generates-another-original-trace
  (let ((first (demo-double-cancellation :seed 2)) (second (demo-double-cancellation :seed 4)))
    (ok (not (equal (getf first :original) (getf second :original))))
    (ok (equal '(:withdraw :cancel :cancel) (getf second :shrunk)))))
