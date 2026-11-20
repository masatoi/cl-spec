;;;; ci/asdf-test-failure.lisp
;;;;
;;;; Load after cl-spec/tests in a disposable image. ASDF must propagate a
;;;; failed assertion even though Rove finishes running the other suites.

(in-package #:cl-spec/tests/main-test)

(defvar *asdf-sentinel-ran-p* nil)

(rove:deftest asdf-failure-sentinel
  (setf *asdf-sentinel-ran-p* t)
  (rove:ok nil "Intentional ASDF test-op failure sentinel"))

(let ((*asdf-sentinel-ran-p* nil))
  (assert (handler-case (progn (asdf:test-system "cl-spec") nil)
            (cl-spec/tests::test-suite-failure () t))
          () "ASDF returned normally after an intentionally failing test.")
  (assert *asdf-sentinel-ran-p* () "ASDF did not execute the failure sentinel."))
