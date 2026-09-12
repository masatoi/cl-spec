;;;; tests.lisp
;;;;
;;;; Aggregate test system.  Every test package must be listed here; the
;;;; PERFORM :AFTER method below derives the packages to run from the inferred
;;;; dependency list, so an unlisted test file is silently never run.

(defpackage #:cl-spec/tests
  (:use #:cl)
  (:import-from #:rove)
  (:import-from #:cl-spec/tests/conditions-test)
  (:import-from #:cl-spec/tests/utils/source-location-test)
  (:import-from #:cl-spec/tests/utils/random-test)
  (:import-from #:cl-spec/tests/ir-test)
  (:import-from #:cl-spec/tests/registry-test)
  (:import-from #:cl-spec/tests/resolve-test)
  (:import-from #:cl-spec/tests/normalize-test)
  (:import-from #:cl-spec/tests/validator-test)
  (:import-from #:cl-spec/tests/explain-test)
  (:import-from #:cl-spec/tests/generator-test)
  (:import-from #:cl-spec/tests/property-test)
  (:import-from #:cl-spec/tests/property-runner-test)
  (:import-from #:cl-spec/tests/function-spec-test)
  (:import-from #:cl-spec/tests/verification-evidence-test)
  (:import-from #:cl-spec/tests/argument-generator-test)
  (:import-from #:cl-spec/tests/introspection-test)
  (:import-from #:cl-spec/tests/dsl-test)
  (:import-from #:cl-spec/tests/main-test)
  (:import-from #:cl-spec/tests/backends/check-it-test)
  (:import-from #:cl-spec/tests/instrument-test)
  (:import-from #:cl-spec/tests/self-properties-test))

(in-package #:cl-spec/tests)

(defmethod asdf:perform :after ((op asdf:test-op)
                                (system (eql (asdf:find-system :cl-spec/tests))))
  (let ((test-packages (remove-if-not
                        (lambda (dependency)
                          (and (stringp dependency)
                               (uiop:string-prefix-p "cl-spec/tests/" dependency)))
                        (asdf:system-depends-on system))))
    (rove:run test-packages)))
