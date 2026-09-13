;;;; tests/instrument-digest-details-test.lisp
(defpackage #:cl-spec/tests/instrument-digest-details-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions* #:instrument-function #:uninstrument-function
                #:instrumentation-status)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:register-function-spec)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry #:registry-clear #:registry-register-spec)
  (:import-from #:cl-spec/src/schema #:definition-description #:schema-info)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form))
(in-package #:cl-spec/tests/instrument-digest-details-test)

(defvar *inspection-fails* nil)

(defclass diagnostic-contract (function-spec) ())

(defmethod definition-description ((contract diagnostic-contract))
  (when *inspection-fails* (error "Extension metadata inspection failed"))
  (multiple-value-bind (data children links complete) (call-next-method)
    (declare (ignore complete))
    (values data children links t)))

(defmacro with-target ((contract class &rest options) &body body)
  `(let ((*registry* (make-hash-table-registry))
         (*instrumented-functions* (make-hash-table :test #'eq)))
     (setf (fdefinition 'target) #'identity)
     (unwind-protect
          (let ((,contract (register-function-spec
                            (make-instance ',class :name 'target
                                           :argument-specs '((x integer)) ,@options))))
            ,@body)
       (uninstrument-function 'target)
       (fmakunbound 'target))))

(deftest inspection-failure-is-explicit-and-preserves-installed-evidence
  (with-target (contract diagnostic-contract :return-spec 'integer)
    (declare (ignore contract))
    (let ((*inspection-fails* nil)) (instrument-function 'target))
    (let ((*inspection-fails* t))
      (let ((wrapper (fdefinition 'target))
            (status (instrumentation-status 'target)))
        (ok (eq :indeterminate (getf status :status)))
        (ok (member :inspection-error (getf status :reasons)))
        (ok (equal (list (list :kind :opaque-definition :path nil :target 'target
                              :reason :inspection-error))
                   (getf status :current-digest-omissions)))
        (ok (null (getf status :installed-digest-omissions :absent)))
        (ok (eq wrapper (fdefinition 'target)))))))

(deftest missing-current-definition-explains-omitted-digest
  (with-target (contract function-spec :return-spec 'integer)
    (declare (ignore contract))
    (instrument-function 'target)
    (registry-clear *registry*)
    (let ((status (instrumentation-status 'target)))
      (ok (eq :stale (getf status :status)))
      (ok (equal (list (list :kind :unresolved-reference :path nil :target 'target
                            :reason :definition-missing))
                 (getf status :current-digest-omissions)))
      (ok (null (getf status :installed-digest-omissions :absent))))))

(deftest status-details-are-fresh-snapshots
  (with-target (contract function-spec :return-spec 'missing-result)
    (declare (ignore contract))
    (instrument-function 'target)
    (let* ((status (instrumentation-status 'target))
           (original (copy-tree (getf status :installed-digest-omissions)))
           (exclusions (copy-list (getf status :digest-exclusions))))
      (ok (consp original))
      (when original
        (setf (getf (first (getf status :installed-digest-omissions)) :reason) :tampered))
      (when (getf status :digest-exclusions)
        (setf (car (getf status :digest-exclusions)) :tampered))
      (let ((fresh (instrumentation-status 'target)))
        (ok (equal original (getf fresh :installed-digest-omissions)))
        (ok (equal exclusions (getf fresh :digest-exclusions)))))))

(deftest installation-omissions-survive-later-dependency-completion
  (with-target (contract function-spec :return-spec 'missing-result)
    (declare (ignore contract))
    (instrument-function 'target)
    (let* ((before (instrumentation-status 'target))
           (omissions (getf before :installed-digest-omissions)))
      (ok (find 'missing-result omissions :key (lambda (item) (getf item :target))))
      (registry-register-spec *registry* 'missing-result (normalize-spec-form 'integer))
      (let ((after (instrumentation-status 'target)))
        (ok (eq :indeterminate (getf after :status)))
        (ok (not (getf after :installed-digest-complete)))
        (ok (getf after :current-digest-complete))
        (ok (null (getf after :current-digest-omissions :absent)))
        (ok (equal omissions (getf after :installed-digest-omissions)))))))

(deftest complete-details-are-known-empty-and-exclusions-are-explicit
  (with-target (contract function-spec :return-spec 'integer)
    (declare (ignore contract))
    (instrument-function 'target)
    (let ((status (instrumentation-status 'target)))
      (ok (eq :current (getf status :status)))
      (ok (null (getf status :installed-digest-omissions :absent)))
      (ok (null (getf status :current-digest-omissions :absent)))
      (ok (equal (getf (schema-info) :digest-excludes) (getf status :digest-exclusions))))))

(deftest absent-installation-has-uncollected-digest-details
  (let ((*instrumented-functions* (make-hash-table :test #'eq)))
    (let ((status (instrumentation-status 'target)))
      (ok (eq :not-collected (getf status :installed-digest-omissions)))
      (ok (eq :not-collected (getf status :current-digest-omissions))))))

(deftest status-omission-kinds-use-the-published-vocabulary
  (with-target (contract diagnostic-contract :return-spec 'integer)
    (declare (ignore contract))
    (instrument-function 'target)
    (let ((*inspection-fails* t)
           (status (instrumentation-status 'target))
           (kinds (getf (schema-info) :digest-omission-kinds)))
      (ok (every (lambda (omission) (member (getf omission :kind) kinds))
                 (getf status :current-digest-omissions))))
    (registry-clear *registry*)
    (let ((status (instrumentation-status 'target))
          (kinds (getf (schema-info) :digest-omission-kinds)))
      (ok (every (lambda (omission) (member (getf omission :kind) kinds))
                 (getf status :current-digest-omissions))))))
