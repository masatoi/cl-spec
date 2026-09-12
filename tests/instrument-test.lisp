;;;; tests/instrument-test.lisp

(defpackage #:cl-spec/tests/instrument-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation #:spec-violation-path #:spec-violation-errors
                #:unknown-function-spec)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/dsl #:defspec-function #:defspec)
  (:import-from #:cl-spec/src/introspection #:function-spec-data #:spec-data)
  (:import-from #:cl-spec/src/property-runner #:result-data)
  (:import-from #:cl-spec/src/generator #:*generator-backend*)
  (:import-from #:cl-spec/src/backends/check-it)
  (:import-from #:cl-spec/src/function-spec #:function-spec #:register-function-spec #:check-function)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions* #:instrumented-function-p
                #:instrument-function #:uninstrument-function
                #:instrumentation-violation-scope #:instrumentation-violation-reason
                #:instrumentation-violation-function))

(in-package #:cl-spec/tests/instrument-test)

(defmacro with-target ((function &rest contract-options) &body body)
  `(let ((*registry* (make-hash-table-registry))
         (*instrumented-functions* (make-hash-table :test #'eq)))
     (setf (fdefinition 'target) ,function)
     (unwind-protect
          (progn
            (register-function-spec
             (make-instance 'function-spec :name 'target ,@contract-options))
            ,@body)
       (uninstrument-function 'target)
       (fmakunbound 'target))))

(deftest input-checks-precede-target
  (let ((calls 0))
    (with-target ((lambda (x) (incf calls) x) :argument-specs '((x integer))
                  :preconditions '((plusp x)) :precondition-function #'plusp)
      (instrument-function 'target)
      (ok (signals (funcall (fdefinition 'target) "bad") 'spec-violation))
      (ok (signals (funcall (fdefinition 'target) 0) 'spec-violation))
      (ok (signals (funcall (fdefinition 'target)) 'spec-violation))
      (ok (signals (funcall (fdefinition 'target) 1 2) 'spec-violation))
      (ok (= calls 0))
      (ok (= 3 (funcall (fdefinition 'target) 3)))
      (ok (= calls 1)))))

(deftest output-and-post-are-enforced
  (let ((calls 0))
    (with-target ((lambda (x) (incf calls) x) :argument-specs '((x integer))
                  :return-spec 'integer
                  :postconditions '((plusp result))
                  :postcondition-function (lambda (result x) (declare (ignore x)) (plusp result)))
      (instrument-function 'target)
      (ok (signals (funcall (fdefinition 'target) 0) 'spec-violation))
      (ok (= calls 1)))
    (with-target ((lambda (x) (declare (ignore x)) (incf calls) "bad")
                  :argument-specs '((x integer)) :return-spec 'integer)
      (instrument-function 'target)
      (ok (signals (funcall (fdefinition 'target) 1) 'spec-violation))
      (ok (= calls 2)))))

(deftest lifecycle-does-not-stack-or-overwrite-redefinitions
  (with-target (#'identity :argument-specs '((x integer)))
    (let ((original (fdefinition 'target)))
      (instrument-function 'target)
      (instrument-function 'target)
      (ok (instrumented-function-p 'target))
      (ok (uninstrument-function 'target))
      (ok (eq original (fdefinition 'target)))
      (ok (not (uninstrument-function 'target)))
      (instrument-function 'target)
      (setf (fdefinition 'target) #'list)
      (ok (not (instrumented-function-p 'target)))
      (ok (not (uninstrument-function 'target)))
      (ok (eq #'list (fdefinition 'target))))))

(deftest target-values-and-conditions-pass-through
  (with-target ((lambda () (values 1 2 3)) :return-spec 'integer)
    (instrument-function 'target)
    (ok (equal '(1 2 3) (multiple-value-list (funcall (fdefinition 'target))))))
  (let ((failure (make-condition 'simple-error :format-control "target failed")))
    (with-target ((lambda () (error failure)))
      (instrument-function 'target)
      (ok (eq failure (handler-case (funcall (fdefinition 'target))
                        (error (condition) condition)))))))

(deftest old-registry-call-and-unbinding
  (with-target (#'identity :argument-specs '((x integer)))
    (let ((registry *registry*) (*registry* (make-hash-table-registry)))
      (instrument-function 'target registry)
      (ok (signals (funcall (fdefinition 'target) "bad") 'spec-violation))
      (fmakunbound 'target)
      (ok (not (instrumented-function-p 'target)))
      (ok (not (uninstrument-function 'target)))
      (ok (not (fboundp 'target))))))

(deftest invalid-installation-leaves-function-alone
  (with-target (#'identity :argument-specs '((x integer)))
    (let ((original (fdefinition 'target)))
      (ok (signals (instrument-function 'target :scopes '(:bogus)) 'type-error))
      (ok (signals (instrument-function 'target :scopes :input) 'type-error))
      (ok (eq original (fdefinition 'target)))
      (ok (not (instrumented-function-p 'target)))))
  (let ((*registry* (make-hash-table-registry)))
    (ok (signals (instrument-function 'unknown) 'unknown-function-spec))))

(deftest scopes-select-only-requested-checks
  (with-target ((lambda (x) (declare (ignore x)) "bad")
                :argument-specs '((x integer)) :return-spec 'integer
                :postconditions '(nil)
                :postcondition-function (lambda (&rest args) (declare (ignore args)) nil))
    (instrument-function 'target :scopes '(:input))
    (ok (equal "bad" (funcall (fdefinition 'target) 1)))
    (ok (signals (funcall (fdefinition 'target) "bad") 'spec-violation))
    (instrument-function 'target :scopes '(:output))
    (ok (signals (funcall (fdefinition 'target) "anything") 'spec-violation))
    (instrument-function 'target :scopes nil)
    (ok (equal "bad" (funcall (fdefinition 'target) "anything"))))
  (with-target ((lambda (x) (declare (ignore x)) 1)
                :argument-specs '((x integer)) :return-spec 'string
                :postconditions '((plusp result))
                :postcondition-function (lambda (result x) (declare (ignore x)) (plusp result)))
    (instrument-function 'target :scopes '(:post))
    (ok (= 1 (funcall (fdefinition 'target) "not an integer")))))

(deftest output-only-does-not-enforce-input-or-post
  (with-target ((lambda (x) (declare (ignore x)) 3)
                :argument-specs '((x integer)) :return-spec 'integer
                :preconditions '(nil) :precondition-function (lambda (x) (declare (ignore x)) nil)
                :postconditions '(nil)
                :postcondition-function (lambda (&rest args) (declare (ignore args)) nil))
    (instrument-function 'target :scopes '(:output))
    (ok (= 3 (funcall (fdefinition 'target) "outside input domain")))))

(deftest unsupported-targets-are-refused
  (let ((*registry* (make-hash-table-registry)))
    (dolist (name '(if when identity missing))
      (register-function-spec (make-instance 'function-spec :name name))
      (ok (signals (instrument-function name) 'program-error))))
  (with-target (#'identity)
    (fmakunbound 'target)
    (ensure-generic-function 'target :lambda-list '(x))
    (let ((original (fdefinition 'target)))
      (ok (signals (instrument-function 'target) 'program-error))
      (ok (eq original (fdefinition 'target))))))

(deftest registry-references-and-reinstall-refresh
  (with-target (#'identity)
    (defspec argument integer)
    (defspec-function target (:args (x argument)))
    (let ((registry *registry*) (*registry* (make-hash-table-registry)))
      (instrument-function 'target :registry registry)
      (ok (= 1 (funcall (fdefinition 'target) 1)))
      (ok (signals (funcall (fdefinition 'target) "bad") 'spec-violation)))
    (defspec argument string)
    (ok (equal "now valid" (funcall (fdefinition 'target) "now valid")))
    (defspec-function target (:args (x integer)))
    (instrument-function 'target)
    (ok (signals (funcall (fdefinition 'target) "now invalid") 'spec-violation))
    (ok (= 1 (funcall (fdefinition 'target) 1)))))

(deftest no-values-and-mutated-post-arguments
  (with-target ((lambda () (values)))
    (instrument-function 'target)
    (ok (null (multiple-value-list (funcall (fdefinition 'target))))))
  (with-target ((lambda (x) (setf (car x) 2) x)
                :argument-specs '((x (list-of integer))) :postconditions '(t)
                :postcondition-function (lambda (result x)
                                          (and (eq result x) (= 2 (car x)))))
    (instrument-function 'target)
    (ok (equal '(2) (funcall (fdefinition 'target) (list 1))))))

(deftest dsl-violations-carry-path-and-nested-explanation
  (with-target (#'identity)
    (defspec-function target (:args (x (list-of integer)))
      (:returns (list-of integer)) (:post (consp result) (< (first result) 10)))
    (instrument-function 'target)
    (let ((failure (handler-case (funcall (fdefinition 'target) '("bad"))
                     (spec-violation (condition) condition))))
      (ok (typep failure 'spec-violation))
      (ok (equal '(:args x 0)
                 (getf (first (spec-violation-errors failure)) :path))))
    (let ((failure (handler-case (funcall (fdefinition 'target) '(20))
                     (spec-violation (condition) condition))))
      (ok (equal '(:post 1) (spec-violation-path failure))))))

(deftest pre-and-post-predicate-errors-are-not-reclassified
  (let ((failure (make-condition 'simple-error :format-control "predicate failed"))
        (calls 0))
    (with-target ((lambda (x) (incf calls) x)
                  :argument-specs '((x integer)) :preconditions '(t)
                  :precondition-function (lambda (x) (declare (ignore x)) (error failure)))
      (instrument-function 'target)
      (ok (eq failure (handler-case (funcall (fdefinition 'target) 1)
                        (error (condition) condition))))
      (ok (zerop calls)))
    (with-target ((lambda (x) (incf calls) x)
                  :argument-specs '((x integer)) :postconditions '(t)
                  :postcondition-function
                  (lambda (result x) (declare (ignore result x)) (error failure)))
      (instrument-function 'target)
      (ok (eq failure (handler-case (funcall (fdefinition 'target) 1)
                        (error (condition) condition))))
      (ok (= 1 calls)))))

(deftest capability-reflects-supported-targets-without-installing
  (with-target (#'identity :argument-specs '((x integer)))
    (defspec scalar integer)
    (let ((*generator-backend* nil))
      (ok (eq :available
              (getf (getf (function-spec-data 'target) :capabilities) :instrumentation)))
      (ok (not (instrumented-function-p 'target)))
      (ok (eq :unavailable (getf (getf (spec-data 'scalar) :capabilities)
                                :instrumentation))))
    (ok (eq :available
            (getf (getf (result-data (check-function 'target :trials 1 :seed 42))
                        :capabilities) :instrumentation)))
    (fmakunbound 'target)
    (ok (eq :unavailable
            (getf (getf (function-spec-data 'target) :capabilities) :instrumentation)))))

(deftest structured-violation-identifies-failed-clause
  (dolist (case '((:input :argument-spec (:input) "bad")
                  (:input :precondition (:input) 0)
                  (:output :return-spec (:output) 1)
                  (:post :postcondition (:post) 1)))
    (destructuring-bind (scope reason scopes argument) case
      (with-target ((lambda (x) (declare (ignore x)) "bad")
                    :argument-specs '((x integer)) :return-spec 'integer
                    :preconditions '((plusp x)) :precondition-function #'plusp
                    :postconditions '(nil)
                    :postcondition-function (lambda (&rest args) (declare (ignore args)) nil))
        (instrument-function 'target :scopes scopes)
        (let ((failure (handler-case (funcall (fdefinition 'target) argument)
                         (spec-violation (condition) condition))))
          (ok (eq scope (instrumentation-violation-scope failure)))
          (ok (eq reason (instrumentation-violation-reason failure)))
          (ok (eq 'target (instrumentation-violation-function failure))))))))

(defun faulty-spec-predicate (value)
  (declare (ignore value))
  (error "Spec predicate failed."))

(deftest spec-predicate-errors-retain-explainer-semantics
  (dolist (scope '(:input :output))
    (let ((calls 0))
      (with-target ((lambda (x) (incf calls) x)
                    :argument-specs '((x (satisfies faulty-spec-predicate)))
                    :return-spec '(satisfies faulty-spec-predicate))
        (instrument-function 'target :scopes (list scope))
        (let* ((failure (handler-case (funcall (fdefinition 'target) 1)
                          (spec-violation (condition) condition)))
               (detail (first (spec-violation-errors failure))))
          (ok (eq scope (instrumentation-violation-scope failure)))
          (ok (eq :predicate-errored (getf detail :kind)))
          (ok (eq 'simple-error (getf detail :condition-type)))
          (ok (= calls (if (eq scope :input) 0 1))))))))

(deftest reinstall-after-redefinition-and-failed-refresh
  (with-target (#'identity :argument-specs '((x integer)))
    (instrument-function 'target)
    (let ((wrapper (fdefinition 'target)))
      (ok (signals (instrument-function 'target :scopes '(:invalid)) 'type-error))
      (ok (eq wrapper (fdefinition 'target)))
      (ok (signals (funcall (fdefinition 'target) "bad") 'spec-violation)))
    (setf (fdefinition 'target) #'list)
    (instrument-function 'target)
    (ok (equal '(1) (funcall (fdefinition 'target) 1)))
    (ok (uninstrument-function 'target))
    (ok (eq #'list (fdefinition 'target)))))
