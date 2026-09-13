;;;; tests/instrument-binding-test.lisp

(defpackage #:cl-spec/tests/instrument-binding-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/call-schema #:bind-call-arguments)
  (:import-from #:cl-spec/src/function-spec #:function-spec)
  (:import-from #:cl-spec/src/registry #:make-hash-table-registry)
  (:import-from #:cl-spec/src/instrument #:instrumentation-violation)
  (:import-from #:cl-spec/src/conditions #:spec-violation-spec)
  (:import-from #:cl-spec/src/ir #:predicate-spec-predicate))

(in-package #:cl-spec/tests/instrument-binding-test)

(defun counted-call (function)
  "Call FUNCTION while counting projection construction, restoring the binder afterward."
  (let ((original (fdefinition 'bind-call-arguments)) (count 0))
    (unwind-protect
         (progn
           (setf (fdefinition 'bind-call-arguments)
                 (lambda (&rest arguments)
                   (incf count)
                   (apply original arguments)))
           (values (funcall function) count))
      (setf (fdefinition 'bind-call-arguments) original))))

(defun wrapper (target &rest options)
  "Build a private contract wrapper without installing a global target."
  (cl-spec/src/instrument::make-contract-wrapper
   'target target (apply #'make-instance 'function-spec :name 'target options)
   (make-hash-table-registry) '(:input :output :post)))

(deftest unchanged-invocations-bind-once
  (let ((function
          (wrapper (lambda (&key x) (values x :second))
                   :argument-specs '(&key ((:x x) integer supplied))
                   :return-spec 'integer
                   :preconditions '((and supplied (plusp x)))
                   :precondition-function (lambda (x supplied) (and supplied (plusp x)))
                   :postconditions '((= result x))
                   :postcondition-function
                   (lambda (result x supplied) (and supplied (= result x))))))
    (multiple-value-bind (result count)
        (counted-call (lambda () (multiple-value-list (funcall function :x 3))))
      (ok (equal '(3 :second) result))
      (ok (= 1 count)))))

(deftest mutations-rebind-effective-keyword-values
  (dolist (phase '(:argument :pre :target))
    (let ((saved-tail nil) (pre-value nil) (post-value nil))
      (flet ((mutate () (setf (second saved-tail) 9)))
        (let* ((rest-spec
                 (make-instance 'cl-spec/src/ir:predicate-spec
                                :predicate
                                (lambda (tail)
                                  (setf saved-tail tail)
                                  (when (eq phase :argument) (mutate))
                                  t)))
               (function
                 (wrapper (lambda (&key x)
                            (when (eq phase :target) (mutate))
                            x)
                          :argument-specs
                          (list '&rest (list 'tail rest-spec)
                                '&key '((:x x) integer supplied))
                          :preconditions '(t)
                          :precondition-function
                          (lambda (tail x supplied)
                            (declare (ignore tail supplied))
                            (setf pre-value x)
                            (when (eq phase :pre) (mutate))
                            t)
                          :postconditions '(t)
                          :postcondition-function
                          (lambda (result tail x supplied)
                            (declare (ignore result tail supplied))
                            (setf post-value x)
                            t))))
          (multiple-value-bind (result count)
              (counted-call (lambda () (funcall function :x 3)))
            (ok (= (if (eq phase :target) 3 9) result))
            (ok (= (if (eq phase :argument) 9 3) pre-value))
            (ok (= 9 post-value))
            (ok (= 2 count))))))))

(deftest changed-rest-spines-rebind-and-cycles-refuse
  (dolist (cycle-p '(nil t))
    (let* ((saved-tail nil)
           (function
             (wrapper (lambda (&rest arguments)
                        (declare (ignore arguments))
                        (setf (cdr saved-tail)
                              (if cycle-p saved-tail (list :replacement)))
                        t)
                      :argument-specs '(&rest (tail t))
                      :preconditions '(t)
                      :precondition-function (lambda (tail) (setf saved-tail tail) t)
                      :postconditions '(t)
                      :postcondition-function
                      (lambda (result tail)
                        (declare (ignore result))
                        (equal tail '(1 :replacement))))))
      (if cycle-p
          (ok (handler-case (progn (funcall function 1 2) nil) (program-error () t)))
          (multiple-value-bind (result count)
              (counted-call (lambda () (funcall function 1 2)))
            (ok result)
            (ok (= 2 count)))))))

(deftest deep-value-mutations-keep-live-object-bindings
  (let ((object (list 1))
         (function
           (wrapper (lambda (value) (setf (car value) 9) value)
                    :argument-specs '((x list))
                    :preconditions '(t) :precondition-function (constantly t)
                    :postconditions '(t)
                    :postcondition-function
                    (lambda (result x) (and (eq result x) (= 9 (car x)))))))
    (multiple-value-bind (result count)
        (counted-call (lambda () (funcall function object)))
      (ok (eq object result))
      (ok (= 1 count)))))

(deftest post-only-binding-follows-target-and-preserves-restarts
  (let* ((called nil)
         (contract
           (make-instance 'function-spec :name 'target
                          :argument-specs '((x integer))
                          :postconditions '(t) :postcondition-function (constantly t)))
         (function
           (cl-spec/src/instrument::make-contract-wrapper
            'target (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (setf called t)
                      (restart-case (error "target pause")
                        (:resume-target () (values :first :second))))
            contract (make-hash-table-registry) '(:post))))
    (multiple-value-bind (result count)
        (counted-call
         (lambda ()
           (handler-bind ((simple-error (lambda (condition)
                                          (declare (ignore condition))
                                          (invoke-restart :resume-target))))
             (multiple-value-list (funcall function "not an integer")))))
      (ok called)
      (ok (equal '(:first :second) result))
      (ok (= 1 count)))
    (setf called nil)
    (ok (handler-case
            (handler-bind ((simple-error (lambda (condition)
                                           (declare (ignore condition))
                                           (invoke-restart :resume-target))))
              (funcall function)
              nil)
          (program-error () t)))
    (ok called)))

(deftest diagnostic-predicates-bind-each-explicit-recheck
  (let* ((pre-wrapper
           (wrapper #'identity :argument-specs '((x integer))
                    :preconditions '((plusp x)) :precondition-function #'plusp))
         (post-wrapper
           (wrapper (constantly 0) :argument-specs '((x integer))
                    :postconditions '((= result x)) :postcondition-function #'=))
         (pre-spec
           (handler-case (funcall pre-wrapper 0)
             (instrumentation-violation (condition) (spec-violation-spec condition))))
         (post-spec
           (handler-case (funcall post-wrapper 2)
             (instrumentation-violation (condition) (spec-violation-spec condition)))))
    (multiple-value-bind (result count)
        (counted-call
         (lambda ()
           (list (funcall (predicate-spec-predicate pre-spec) '(2))
                 (funcall (predicate-spec-predicate pre-spec) '(0))
                 (funcall (predicate-spec-predicate post-spec) '(2 2))
                 (funcall (predicate-spec-predicate post-spec) '(0 2)))))
      (ok (equal '(t nil t nil) result))
      (ok (= 4 count)))))

(deftest captured-layouts-ignore-exposed-cache-mutation
  (let* ((contract
           (make-instance 'function-spec :name 'target
                          :argument-specs '(&key ((:x x) integer supplied))
                          :postconditions '((= result x))
                          :postcondition-function
                          (lambda (result x supplied) (and supplied (= result x)))))
         (function
           (cl-spec/src/instrument::make-contract-wrapper
            'target (lambda (&key x) x) contract (make-hash-table-registry) '(:input :post)))
         (cached (cl-spec/src/function-spec:function-spec-call-layout contract)))
    (ok (= 3 (funcall function :x 3)))
    ;; A client can change the cache's list storage, but installed checks own a
    ;; separate layout, including the call node compiled for shape diagnostics.
    (setf (car (cl-spec/src/call-schema:call-layout-bindings cached)) nil)
    (cl-spec/src/function-spec:function-spec-call-layout contract)
    (ok (handler-case (= 4 (funcall function :x 4)) (error () nil)))
    (ok (handler-case (progn (funcall function :unknown 4) nil)
          (instrumentation-violation () t)
          (error () nil)))
    (ok (handler-case (progn (funcall function :x "bad") nil)
          (instrumentation-violation () t)
          (error () nil)))
    (ok (handler-case (progn (funcall function :x) nil)
          (instrumentation-violation () t)
          (error () nil)))))

(deftest argument-schemas-isolate-compiled-call-nodes
  (let* ((contract (make-instance 'function-spec :name 'target
                                  :argument-specs '(&key ((:x x) integer))))
         (schema (cl-spec/src/function-spec:function-spec-argument-schema contract))
         (check (cl-spec/src/explain:compile-explainer schema))
         (cached (cl-spec/src/function-spec:function-spec-call-layout contract)))
    (setf (car (cl-spec/src/call-schema:call-layout-bindings cached)) nil)
    (cl-spec/src/function-spec:function-spec-call-layout contract)
    (ok (handler-case (null (funcall check '(:x 3) nil)) (error () nil)))
    (ok (handler-case (eq :unknown-key (getf (first (funcall check '(:other 3) nil)) :kind))
          (error () nil)))))
