;;;; tests/result-provenance-test.lisp
(defpackage #:cl-spec/tests/result-provenance-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/property #:property #:property-trials)
  (:import-from #:cl-spec/src/property-runner
                #:property-result #:property-result-options #:property-result-provenance
                #:run-property #:result-data)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:check-function #:make-function-check-property)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend* #:run-generated-test #:backend-default-trials)
  (:import-from #:cl-spec/src/execution #:evaluate-trial))
(in-package #:cl-spec/tests/result-provenance-test)

(deftest captures-before-backend-mutation
  (let* ((*generator-backend* (make-instance 'provenance-backend))
         (options (list :nested (list :original) :target-revision (copy-seq "abc")))
         (result (run-property (make-instance 'property :name 'sample :function (constantly t))
                               :seed 5 :options options))
         (data (result-data result))
         (provenance (property-result-provenance result)))
    (ok (eq :changed (car (getf options :nested))))
    (ok (equal '(:original) (getf (property-result-options result) :nested)))
    (ok (string= "abc" (getf provenance :target-revision)))
    (ok (stringp (getf provenance :backend)))
    (ok (string= (lisp-implementation-type) (getf provenance :lisp-implementation-type)))
    (ok (string= (lisp-implementation-version) (getf provenance :lisp-implementation-version)))
    (ok (getf provenance :cl-spec-version))
    (ok (equal (property-result-options result) (getf data :options)))
    (ok (equal provenance (getf data :provenance)))))

(deftest defaults-are-explicit
  (let* ((result (make-instance 'property-result :trials 0))
         (data (result-data result)))
    (ok (null (property-result-options result)))
    (dolist (key '(:backend :lisp-implementation-type :lisp-implementation-version
                  :cl-spec-version :target-revision))
      (ok (eq :unknown (getf (getf data :provenance) key))))))

(deftest runtime-version-agrees-with-release-system
  (ok (string= cl-spec/src/property-runner::*cl-spec-version*
               (asdf:component-version (asdf:find-system "cl-spec")))))

(deftest provenance-module-has-no-asdf-runtime-dependency
  (ok (not (member "asdf"
                   (asdf:system-depends-on (asdf:find-system "cl-spec/src/property-runner"))
                   :test #'equal))))

(deftest function-adapter-needs-no-backend
  (let* ((*generator-backend* nil)
         (contract (make-instance 'function-spec :name 'identity
                                  :argument-specs '((x integer)) :return-spec 'integer))
         (property (make-function-check-property contract)))
    (ok (equal '(:normal 0) (property-trials property)))
    (ok (eq :passed (evaluate-trial property '(3))))))

(deftest function-results-retain-provenance
  (let* ((*generator-backend* (make-instance 'provenance-backend))
         (contract (make-instance 'function-spec :name 'identity
                                  :argument-specs '((x integer)) :return-spec 'integer))
         (result (check-function contract :seed 3 :options (list :nested (list :original)))))
    (ok (equal '(:original) (getf (property-result-options result) :nested)))
    (ok (stringp (getf (property-result-provenance result) :backend)))))

(defclass provenance-backend () ())

(defmethod backend-default-trials ((backend provenance-backend)) 1)

(defmethod run-generated-test ((backend provenance-backend) property &key options)
  (declare (ignore property))
  (when (getf options :nested)
    (setf (car (getf options :nested)) :changed))
  (when (getf options :target-revision)
    (setf (char (getf options :target-revision) 0) #\X))
  (list :status :passed :trials 1))
