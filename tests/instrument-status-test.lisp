;;;; tests/instrument-status-test.lisp
(defpackage #:cl-spec/tests/instrument-status-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/ir #:type-spec)
  (:import-from #:cl-spec/src/schema #:definition-description)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions* #:instrument-function #:uninstrument-function
                #:instrumented-function-p #:instrumentation-status #:refresh-instrumentation
                #:unsupported-instrumentation-target #:unsupported-instrumentation-target-reason)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:register-function-spec)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:make-hash-table-registry #:registry-clear #:registry-register-spec)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form))
(in-package #:cl-spec/tests/instrument-status-test)

(defmacro with-target ((contract &rest options) &body body)
  `(let ((*registry* (make-hash-table-registry))
         (*instrumented-functions* (make-hash-table :test #'eq)))
     (setf (fdefinition 'target) #'identity)
     (unwind-protect
          (let ((,contract (register-function-spec
                            (make-instance 'function-spec :name 'target
                                           :argument-specs '((x integer))
                                           ,@options))))
            ,@body)
       (uninstrument-function 'target)
       (fmakunbound 'target))))

(defun refused-reason (thunk)
  (handler-case (progn (funcall thunk) nil)
    (unsupported-instrumentation-target (condition)
      (unsupported-instrumentation-target-reason condition))))

(defclass partial-status-spec (type-spec)
  ((annotation :initarg :annotation :accessor partial-status-annotation))
  (:documentation "A spec extension exposing only an incomplete diagnostic description."))

(defmethod definition-description ((spec partial-status-spec))
  (values (list :annotation (partial-status-annotation spec)) nil nil nil))

(deftest partial-descriptions-do-not-prove-declaration-change
  (let ((spec (make-instance 'partial-status-spec :type-specifier 'integer
                                                :annotation :before)))
    (with-target (contract :return-spec spec)
      (declare (ignore contract))
      (instrument-function 'target)
      (setf (partial-status-annotation spec) :after)
      (let ((status (instrumentation-status 'target)))
        (ok (eq :indeterminate (getf status :status)))
        (ok (eq :indeterminate (getf status :dependency-status)))
        (ok (not (member :declaration-changed (getf status :reasons))))))))

(deftest partial-descriptions-retain-known-predicate-changes
  (let ((spec (make-instance 'partial-status-spec :type-specifier 'integer
                                                :annotation :before)))
    (with-target (contract :return-spec spec :source-form '(contract target)
                          :preconditions '((plusp x)) :precondition-function #'plusp)
      (instrument-function 'target)
      (setf (partial-status-annotation spec) :after)
      (reinitialize-instance contract :preconditions '((plusp x))
                             :precondition-function (lambda (x) (> x 10)))
      (let ((status (instrumentation-status 'target)))
        (ok (eq :stale (getf status :status)))
        (ok (member :precondition-changed (getf status :reasons)))
        (ok (not (member :declaration-changed (getf status :reasons))))))))

(deftest missing-named-dependency-is-indeterminate
  (with-target (contract :return-spec 'named-result)
    (registry-register-spec *registry* 'named-result (normalize-spec-form 'integer))
    (instrument-function 'target)
    (registry-clear *registry*)
    (register-function-spec contract)
    (let ((status (instrumentation-status 'target)))
      (ok (eq :indeterminate (getf status :status)))
      (ok (eq :indeterminate (getf status :dependency-status)))
      (ok (not (getf status :current-digest-complete)))
      (ok (not (member :declaration-changed (getf status :reasons))))
      (ok (instrumented-function-p 'target)))))

(deftest refresh-replaces-checks-without-stacking
  (with-target (contract :return-spec '(range integer 0 10))
    (let ((original (fdefinition 'target)))
      (instrument-function 'target)
      (reinitialize-instance contract :return-spec '(range integer 0 100))
      (refresh-instrumentation 'target)
      (ok (eq :current (getf (instrumentation-status 'target) :status)))
      (ok (= 20 (funcall (fdefinition 'target) 20)))
      (ok (instrumented-function-p 'target))
      (uninstrument-function 'target)
      (ok (eq original (fdefinition 'target))))))

(deftest failed-refresh-preserves-old-wrapper
  (with-target (contract :return-spec 'integer)
    (instrument-function 'target)
    (let ((entry (gethash 'target *instrumented-functions*))
          (wrapper (fdefinition 'target)))
      (reinitialize-instance contract :return-spec nil :signal-spec 'simple-error)
      (ok (eq :expected-condition-contract
              (refused-reason (lambda () (refresh-instrumentation 'target)))))
      (ok (eq entry (gethash 'target *instrumented-functions*)))
      (ok (eq wrapper (fdefinition 'target)))
      (ok (= 3 (funcall (fdefinition 'target) 3))))))

(deftest external-redefinition-status-does-not-forget-installation
  (with-target (contract)
    (declare (ignore contract))
    (instrument-function 'target)
    (let ((entry (gethash 'target *instrumented-functions*)))
      (setf (fdefinition 'target) #'list)
      (ok (member :external-redefinition (getf (instrumentation-status 'target) :reasons)))
      (ok (eq entry (gethash 'target *instrumented-functions*)))
      (ok (eq :external-redefinition
              (refused-reason (lambda () (refresh-instrumentation 'target)))))
      (ok (eq #'list (fdefinition 'target)))
      (ok (eq entry (gethash 'target *instrumented-functions*)))))
  (ok (eq :not-installed
          (refused-reason (lambda () (refresh-instrumentation 'never-installed))))))

(deftest named-dependencies-remain-dynamic
  (with-target (contract :return-spec 'named-result)
    (declare (ignore contract))
    (registry-register-spec *registry* 'named-result (normalize-spec-form 'integer))
    (instrument-function 'target)
    (registry-register-spec *registry* 'named-result (normalize-spec-form '(range integer 0 10)))
    (let ((status (instrumentation-status 'target)))
      (ok (eq :current (getf status :status)))
      (ok (eq :changed (getf status :dependency-status))))
    (ok (= 3 (funcall (fdefinition 'target) 3)))
    (ok (handler-case (progn (funcall (fdefinition 'target) 20) nil) (error () t)))))

(deftest status-detects-replacement-deletion-and-registry-change
  (with-target (contract)
    (declare (ignore contract))
    (instrument-function 'target)
    (register-function-spec (make-instance 'function-spec :name 'target
                                          :argument-specs '((x integer))))
    (ok (member :definition-replaced (getf (instrumentation-status 'target) :reasons)))
    (ok (eq :stale (getf (instrumentation-status 'target) :status)))
    (ok (member :registry-changed
                (getf (instrumentation-status 'target :registry (make-hash-table-registry)) :reasons)))
    (registry-clear *registry*)
    (ok (member :definition-missing (getf (instrumentation-status 'target) :reasons)))))

(deftest status-detects-replaced-precondition-closure
  (with-target (contract :source-form '(contract target)
                        :preconditions '((plusp x)) :precondition-function #'plusp)
    (instrument-function 'target)
    (reinitialize-instance contract :preconditions '((plusp x))
                           :precondition-function (lambda (x) (> x 10)))
    (let ((status (instrumentation-status 'target)))
      (ok (eq :stale (getf status :status)))
      (ok (member :precondition-changed (getf status :reasons))))))

(deftest status-detects-in-place-declaration-change
  (with-target (contract :return-spec 'integer)
    (instrument-function 'target)
    (reinitialize-instance contract :return-spec nil :signal-spec 'simple-error)
    (let ((status (instrumentation-status 'target)))
      (ok (eq :stale (getf status :status)))
      (ok (member :declaration-changed (getf status :reasons))))))

(deftest status-is-current-and-read-only
  (with-target (contract :return-spec 'integer)
    (declare (ignore contract))
    (ok (eq :not-installed (getf (instrumentation-status 'target) :status)))
    (instrument-function 'target)
    (let ((wrapper (fdefinition 'target))
          (entry (gethash 'target *instrumented-functions*))
          (status (instrumentation-status 'target)))
      (ok (eq :current (getf status :status)))
      (ok (eq :unchanged (getf status :dependency-status)))
      (ok (getf status :installed-digest-complete))
      (ok (equal (getf status :installed-digest) (getf status :current-digest)))
      (ok (eq wrapper (fdefinition 'target)))
      (ok (eq entry (gethash 'target *instrumented-functions*))))))
