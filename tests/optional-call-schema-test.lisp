;;;; tests/optional-call-schema-test.lisp

(defpackage #:cl-spec/tests/optional-call-schema-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/call-schema
                #:validate-call-declarations #:normalize-call-declarations
                #:call-declaration-variables #:make-call-layout
                #:call-layout-bindings #:call-layout-required-count
                #:call-layout-accepts-p #:call-layout-required-only-p
                #:argument-binding-supplied-name
                #:bind-call-arguments #:bound-call-arguments #:bound-call-values
                #:bound-call-presence #:bound-call-bindings)
  (:import-from #:cl-spec/src/call-validation)
  (:import-from #:cl-spec/src/ir #:spec)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form))

(in-package #:cl-spec/tests/optional-call-schema-test)

(defun invalid-declarations-p (value)
  (handler-case (progn (validate-call-declarations value) nil)
    (invalid-function-spec-form () t)))

(deftest optional-declarations-normalize-only-specs
  (let* ((declarations '((required integer) &optional (optional string optional-p) (last integer)))
         (normalized (normalize-call-declarations declarations)))
    (ok (eq declarations (validate-call-declarations declarations)))
    (ok normalized)
    (when normalized
      (ok (eq '&optional (second normalized)))
      (ok (typep (second (first normalized)) 'spec))
      (ok (typep (second (third normalized)) 'spec))
      (ok (eq 'optional-p (third (third normalized))))
      (ok (equal '(required optional optional-p last)
                 (call-declaration-variables normalized))))))

(deftest optional-binding-preserves-absence-and-explicit-nil
  (let ((layout (make-call-layout
                 (normalize-call-declarations '((required integer) &optional (value t value-p))))))
    (ok (eql 1 (call-layout-required-count layout)))
    (ok (not (call-layout-required-only-p layout)))
    (ok (call-layout-accepts-p layout '(1)))
    (ok (call-layout-accepts-p layout '(1 nil)))
    (ok (not (call-layout-accepts-p layout nil)))
    (ok (not (call-layout-accepts-p layout '(1 2 3))))
    (when (eql 1 (call-layout-required-count layout))
      (let* ((raw (list 1 nil))
             (omitted (bind-call-arguments layout '(1)))
             (provided (bind-call-arguments layout raw)))
        (ok (equal '(1 nil nil) (bound-call-values omitted)))
        (ok (equal '(t nil) (bound-call-presence omitted)))
        (ok (equal '(1 nil t) (bound-call-values provided)))
        (ok (equal '(t t) (bound-call-presence provided)))
        (ok (eq raw (bound-call-arguments provided)))
        (ok (null (cdr (assoc 'value-p (bound-call-bindings omitted)))))
        (ok (eq t (cdr (assoc 'value-p (bound-call-bindings provided)))))
        (ok (eq 'value-p (argument-binding-supplied-name (second (call-layout-bindings layout)))))))))

(deftest optional-declarations-refuse-malformed-and-duplicate-bindings
  (dolist (declarations
           '((&optional &optional) (&rest (value integer)) (&key (value integer))
             ((value integer flag)) (&optional (value integer flag extra))
             (&optional (value integer :flag)) (&optional (value integer nil))
             ((same integer) &optional (other integer same))
             (&optional (same integer flag) (other integer flag))
             (&optional (same integer flag) (flag integer))
             (&optional (value . integer)) ((value integer) . tail)))
    (ok (invalid-declarations-p declarations)))
  (let ((cycle (list '&optional)))
    (setf (cdr cycle) cycle)
    (ok (invalid-declarations-p cycle)))
  (let ((cycle (list 'or 'integer)))
    (setf (cddr cycle) cycle)
    (ok (invalid-declarations-p (list (list 'value cycle))))))

(deftest optional-calls-refuse-dotted-and-cyclic-shapes
  (let ((layout (make-call-layout (normalize-call-declarations '(&optional (value integer))))))
    (ok (not (call-layout-accepts-p layout '(1 . 2))))
    (let ((cycle (list 1)))
      (setf (cdr cycle) cycle)
      (ok (not (call-layout-accepts-p layout cycle))))))

(deftest declaration-parsing-never-evaluates-spec-forms
 (let* ((calls 0)
        (predicate (make-instance 'cl-spec/src/ir:predicate-spec
                                  :predicate (lambda (value) (incf calls) (integerp value))))
        (declarations (list '&optional (list 'value predicate 'value-p)))
        (layout (make-call-layout (normalize-call-declarations declarations)))
        (spec (make-instance 'cl-spec/src/call-schema:call-arguments-spec :layout layout))
        (check (cl-spec/src/explain:compile-node spec nil)))
   (ok (eq declarations (validate-call-declarations declarations)))
   (ok (zerop calls))
   (ok (null (funcall check nil nil)))
   (ok (zerop calls))
   (ok (funcall check '(nil) nil))
   (ok (= 1 calls))))

(deftest optional-validation-checks-only-provided-values
 (let* ((layout (make-call-layout (normalize-call-declarations '(&optional (value integer value-p)))))
        (spec (make-instance 'cl-spec/src/call-schema:call-arguments-spec :layout layout))
        (check (cl-spec/src/explain:compile-node spec nil)))
   (ok (null (funcall check nil nil)))
   (ok (null (funcall check '(3) nil)))
   (let ((error (first (funcall check '(nil) nil))))
     (ok (eq :type-failed (getf error :kind)))
     (ok (equal '(:args 0 value) (getf error :path)))
     (ok (equal '(0) (getf error :tuple-path))))
   (ok (eq :wrong-length (getf (first (funcall check '(1 2) nil)) :kind)))
   (ok (eq :not-a-list (getf (first (funcall check '(1 . 2) nil)) :kind)))
   (let ((data (first (getf (cl-spec/src/explain:expected-descriptor spec) :arguments))))
     (ok (eq :optional (getf data :kind)))
     (ok (eq 'value-p (getf data :supplied-p)))
     (ok (equal '(:type integer) (getf data :expected))))))
