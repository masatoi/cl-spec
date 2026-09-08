;;;; tests.lisp
;;;;
;;;; Aggregate test system.  Every test package must be listed here; the
;;;; PERFORM :AFTER method below derives the packages to run from the inferred
;;;; dependency list, so an unlisted test file is silently never run.

(defpackage #:cl-spec/tests
  (:use #:cl)
  (:import-from #:rove)
  (:import-from #:cl-spec/tests/conditions-test))

(in-package #:cl-spec/tests)

(defmethod asdf:perform :after ((op asdf:test-op)
                                (system (eql (asdf:find-system :cl-spec/tests))))
  (let ((test-packages (remove-if-not
                        (lambda (dependency)
                          (and (stringp dependency)
                               (uiop:string-prefix-p "cl-spec/tests/" dependency)))
                        (asdf:system-depends-on system))))
    (rove:run test-packages)))
