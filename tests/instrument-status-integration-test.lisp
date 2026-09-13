;;;; tests/instrument-status-integration-test.lisp
(defpackage #:cl-spec/tests/instrument-status-integration-test
  (:use #:cl)
  (:import-from #:cl-spec/src/ir #:predicate-spec #:spec)
  (:import-from #:cl-spec/specs)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/registry #:find-function-spec #:registry-clear)
  (:import-from #:cl-spec/src/explain #:compile-node)
  (:import-from #:cl-spec/src/dsl #:defspec-function)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:register-function-spec)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions* #:instrument-function #:uninstrument-function
                #:instrumentation-status #:refresh-instrumentation
                #:instrumentation-violation))
(in-package #:cl-spec/tests/instrument-status-integration-test)

(defmacro with-target (&body body)
  `(let ((*registry* (make-hash-table-registry))
         (*instrumented-functions* (make-hash-table :test #'eq)))
     (setf (fdefinition 'target) #'identity)
     (unwind-protect (progn ,@body)
       (uninstrument-function 'target)
       (fmakunbound 'target))))

(deftest refresh-retains-installed-registry-and-scopes
  (with-target
    (defspec-function target (:args (x integer)) (:returns string))
    (let ((registry *registry*))
      (instrument-function 'target :scopes '(:input))
      (let ((*registry* (make-hash-table-registry)))
        (refresh-instrumentation 'target))
      ;; Default refresh must use the installed registry and preserve input-only.
      (ok (= 3 (funcall (fdefinition 'target) 3)))
      (ok (signals (funcall (fdefinition 'target) "x") 'instrumentation-violation))
      (ok (eq :current (getf (instrumentation-status 'target :registry registry) :status))))))

(deftest symbolic-predicates-remain-dynamic
  (with-target
    (setf (fdefinition 'allowed-p) #'integerp)
    (unwind-protect
         (progn
           (defspec-function target (:args (x (satisfies allowed-p))))
           (instrument-function 'target)
           (setf (fdefinition 'allowed-p) #'stringp)
           (ok (eq :current (getf (instrumentation-status 'target) :status)))
           (ok (string= "x" (funcall (fdefinition 'target) "x")))
           (ok (signals (funcall (fdefinition 'target) 3) 'instrumentation-violation)))
      (fmakunbound 'allowed-p))))

(deftest opaque-declarations-never-prove-current
  (with-target
    (register-function-spec
     (make-instance 'function-spec :name 'target
                    :argument-specs (list (list 'x
                      (make-instance 'predicate-spec :predicate (lambda (x) (integerp x)))))))
    (instrument-function 'target)
    (ok (eq :indeterminate (getf (instrumentation-status 'target) :status)))))

(deftest queries-do-not-call-target-or-clear-evidence
  (with-target
    (let ((calls 0))
      (setf (fdefinition 'target) (lambda (x) (incf calls) x))
      (defspec-function target (:args (x integer)))
      (instrument-function 'target)
      (let ((wrapper (fdefinition 'target)))
        (dotimes (i 3) (instrumentation-status 'target))
        (ok (= calls 0))
        (ok (eq wrapper (fdefinition 'target)))
        (setf (fdefinition 'target) #'list)
        (ok (eq :stale (getf (instrumentation-status 'target) :status)))
        (ok (eq :stale (getf (instrumentation-status 'target) :status)))
        (ok (= 1 (hash-table-count *instrumented-functions*)))))))

(defclass uncompilable-spec (spec) ())

(defmethod compile-node ((spec uncompilable-spec) context)
  (declare (ignore context))
  (error "Intentional explainer compilation failure"))

(deftest failed-compilation-and-deletion-preserve-wrapper
  (with-target
    (defspec-function target (:args (x integer)) (:returns integer))
    (instrument-function 'target)
    (let ((wrapper (fdefinition 'target))
          (entry (gethash 'target *instrumented-functions*)))
      (reinitialize-instance (find-function-spec 'target)
                             :return-spec (make-instance 'uncompilable-spec))
      (ok (signals (refresh-instrumentation 'target) 'error))
      (ok (eq wrapper (fdefinition 'target)))
      (ok (eq entry (gethash 'target *instrumented-functions*)))
      (ok (= 3 (funcall (fdefinition 'target) 3)))
      (registry-clear *registry*)
      (ok (signals (refresh-instrumentation 'target) 'error))
      (ok (eq wrapper (fdefinition 'target)))
      (ok (eq entry (gethash 'target *instrumented-functions*))))))

(deftest local-changes-do-not-claim-independent-dependency-changes
  (with-target
    (defspec-function target (:args (x integer)) (:returns integer))
    (instrument-function 'target)
    (reinitialize-instance (find-function-spec 'target) :return-spec 'string)
    (let ((status (instrumentation-status 'target)))
      (ok (eq :stale (getf status :status)))
      (ok (eq :indeterminate (getf status :dependency-status))))))

(deftest replaced-post-predicate-is-stale
  (with-target
    (defspec-function target (:args (x integer)) (:returns integer) (:post (plusp result)))
    (instrument-function 'target)
    (reinitialize-instance (find-function-spec 'target)
                           :postconditions '((plusp result))
                           :postcondition-function (lambda (result x)
                                                     (declare (ignore x)) (> result 10)))
    (let ((status (instrumentation-status 'target)))
      (ok (eq :stale (getf status :status)))
      (ok (member :postcondition-changed (getf status :reasons))))))

(deftest executable-status-contract
  (with-target
    (let* ((name (cl-spec/specs:register-instrumentation-specifications))
           (result (cl-spec:check-function name :trials 5 :seed 42)))
      (ok (eq :passed (cl-spec:property-result-status result))))))
