;;;; tests/call-schema-test.lisp

(defpackage #:cl-spec/tests/call-schema-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout
                #:make-call-layout #:call-layout-bindings
                #:argument-binding-name #:argument-binding-spec #:argument-binding-kind
                #:bind-call-arguments #:bound-call-arguments #:bound-call-values
                #:bound-call-presence #:bound-call-bindings
                #:make-return-schema #:return-schema-primary-spec
                #:return-schema-mode #:return-schema-value)
  (:import-from #:cl-spec/src/ir #:spec-children)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form))

(in-package #:cl-spec/tests/call-schema-test)

(defun program-error-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (program-error () t)))

(deftest required-bindings-preserve-values-and-presence
  (let* ((spec (normalize-spec-form t))
         (pairs (list (list 'first spec) (list 'second spec)))
         (layout (make-call-layout pairs))
         (object (list :nested))
         (arguments (list nil object)))
    (ok layout)
    (when layout
      (let ((bindings (call-layout-bindings layout))
            (call (bind-call-arguments layout arguments)))
        (ok (equal '(first second) (mapcar #'argument-binding-name bindings)))
        (ok (every (lambda (binding) (eq :required (argument-binding-kind binding))) bindings))
        (ok (every (lambda (binding) (eq spec (argument-binding-spec binding))) bindings))
        (ok (eq arguments (bound-call-arguments call)))
        (ok (equal '(t t) (bound-call-presence call)))
        (ok (null (first (bound-call-values call))))
        (ok (eq object (second (bound-call-values call))))
        (ok (equal '(first second) (mapcar #'car (bound-call-bindings call))))
        (ok (eq object (cdr (assoc 'second (bound-call-bindings call)))))
        ;; Descriptor construction must not retain the caller's mutable pair containers.
        (setf (caar pairs) 'changed)
        (ok (eq 'first (argument-binding-name (first (call-layout-bindings layout)))))))))

(deftest binding-refuses-malformed-calls
  (let ((layout (make-call-layout (list (list 'value (normalize-spec-form t))))))
    (dolist (arguments '(nil (1 2) (1 . 2)))
      (ok (program-error-p (lambda () (bind-call-arguments layout arguments)))))
    (let ((cycle (list 1)))
      (setf (cdr cycle) cycle)
      (ok (program-error-p (lambda () (bind-call-arguments layout cycle)))))))

(deftest layout-refuses-invalid-descriptors
  (let ((spec (normalize-spec-form t)))
    (dolist (pairs (list (list (list nil spec)) (list (list t spec))
                        (list (list :value spec)) (list (list '&optional spec))
                        (list (list '|&optional| spec)) (list (list '&future spec))
                        (list (list 'value spec) (list 'value spec))
                        (list (list 'value spec :extra))
                        (list (list 'value 'integer)) (cons (list 'value spec) 3)))
      (ok (handler-case (progn (make-call-layout pairs) nil) (error () t))))
    (let ((cycle (list (list 'value spec))))
      (setf (cdr cycle) cycle)
      (ok (handler-case (progn (make-call-layout cycle) nil) (error () t))))))

(deftest zero-argument-calls-are-valid
  (let ((layout (make-call-layout nil)))
    (ok layout)
    (when layout
      (let ((call (bind-call-arguments layout nil)))
        (ok call)
        (ok (null (bound-call-values call)))
        (ok (null (bound-call-bindings call)))
        (ok (null (bound-call-presence call)))))))

(deftest primary-return-schema-preserves-legacy-projection
  (let* ((spec (normalize-spec-form 'integer))
         (schema (make-return-schema :primary-spec spec))
         (object (list 4)))
    (ok schema)
    (when schema
      (ok (eq :primary (return-schema-mode schema)))
      (ok (eq spec (return-schema-primary-spec schema)))
      (ok (null (return-schema-value schema nil)))
      (ok (null (return-schema-value schema '(nil))))
      (ok (eq object (return-schema-value schema (list object 9))))))
  (ok (make-return-schema))
  (ok (handler-case (progn (make-return-schema :primary-spec 'integer) nil)
        (type-error () t))))

(deftest invalid-layout-store-value-repairs-the-slot
  (testing "the STORE-VALUE restart writes the repaired layout into the object"
    ;; CHECK-TYPE's restart repairs its place.  When that place was a lexical,
    ;; the object kept the invalid layout and later accessors failed on it.
    (let* ((declarations (list (list 'value (normalize-spec-form 'integer))))
           (layout (make-call-layout declarations))
           (object nil))
      (handler-bind ((type-error (lambda (condition)
                                   (declare (ignore condition))
                                   (invoke-restart 'store-value layout))))
        (setf object (make-instance 'call-arguments-spec :layout :not-a-layout)))
      (ok (eq layout (call-arguments-spec-layout object)))
      (ok (= 1 (length (spec-children object)))))))
