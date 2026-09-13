;;;; src/call-schema.lisp

(defpackage #:cl-spec/src/call-schema
 (:use #:cl)
 (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
 (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
 (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form)
 (:import-from #:cl-spec/src/definition-validation #:finite-definition-form-p)
 (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
 (:export #:validate-call-declarations #:normalize-call-declarations #:call-declaration-variables
 #:argument-binding-supplied-name #:call-layout-required-count #:call-layout-data
 #:call-layout-accepts-p #:call-layout-required-only-p #:call-arguments-spec
 #:call-arguments-spec-layout #:argument-binding #:call-layout #:bound-call #:return-schema
 #:make-call-layout #:call-layout-bindings #:argument-binding-name #:argument-binding-spec
 #:argument-binding-kind #:bind-call-arguments #:bound-call-arguments #:bound-call-values
 #:bound-call-presence #:bound-call-bindings #:make-return-schema #:return-schema-primary-spec
 #:return-schema-mode #:return-schema-value))

(in-package #:cl-spec/src/call-schema)

(defstruct (argument-binding
             (:constructor %make-argument-binding (name spec kind supplied-name)) (:copier nil))
 "One normalized required or optional parameter descriptor."
 (name nil :type symbol :read-only t)
 (spec nil :type spec :read-only t)
 (kind :required :type (member :required :optional) :read-only t)
 (supplied-name nil :type symbol :read-only t))

(defstruct (call-layout (:constructor %make-call-layout (bindings)) (:copier nil))
  "Required parameter descriptors in predicate argument order."
  (bindings nil :type list :read-only t))

(defstruct (bound-call (:constructor %make-bound-call (arguments values presence bindings))
                       (:copier nil))
  "A raw call and its bound values; application values retain their actual identity."
  (arguments nil :type list :read-only t)
  (values nil :type list :read-only t)
  (presence nil :type list :read-only t)
  (bindings nil :type list :read-only t))

(defun validate-call-declarations (declarations)
 "Validate finite required and optional parameter declarations without evaluation."
 (labels ((bad (reason)
            (error 'invalid-function-spec-form :form declarations :reason reason)))
   (unless (and (finite-list-p declarations) (finite-definition-form-p declarations))
     (bad "Argument declarations must be finite proper forms."))
   (let ((optional-p nil) (seen (make-hash-table :test #'eq)))
     (labels ((name (value)
                (unless (and (symbolp value) value (not (constantp value))
                             (not (and (plusp (length (symbol-name value)))
                                       (char= #\& (char (symbol-name value) 0))))
                             (not (gethash value seen)))
                  (bad "Argument and supplied-p names must be unique nonconstant variables."))
                (setf (gethash value seen) t)))
       (dolist (declaration declarations)
         (cond
           ((eq declaration '&optional)
            (when optional-p (bad "Duplicate &optional marker."))
            (setf optional-p t))
           (t
            (unless (and (finite-list-p declaration)
                         (if optional-p (member (length declaration) '(2 3))
                             (= (length declaration) 2)))
              (bad "Expected (NAME SPEC), or optional (NAME SPEC SUPPLIED-P)."))
            (name (first declaration))
            (when (cddr declaration) (name (third declaration))))))))
   declarations))

(defun normalize-call-declarations (declarations)
 "Normalize only spec positions in validated argument declarations."
 (validate-call-declarations declarations)
 (mapcar (lambda (declaration)
           (if (eq declaration '&optional) declaration
               (list* (first declaration) (normalize-spec-form (second declaration))
                      (copy-list (cddr declaration)))))
         declarations))

(defun call-declaration-variables (declarations)
 "Return value and supplied-p names in predicate binding order."
 (validate-call-declarations declarations)
 (loop for declaration in declarations
       unless (eq declaration '&optional)
         append (cons (first declaration) (copy-list (cddr declaration)))))

(defun call-layout-required-count (layout)
 "Return the minimum accepted positional argument count."
 (count :required (call-layout-bindings layout) :key #'argument-binding-kind))

(defun call-layout-accepts-p (layout arguments)
 "Check proper call shape and arity without validating or evaluating any values."
 (check-type layout call-layout)
 (and (finite-list-p arguments)
      (<= (call-layout-required-count layout) (length arguments)
          (length (call-layout-bindings layout)))))

(defun call-layout-required-only-p (layout)
 "Return true when all parameter bindings are required."
 (every (lambda (binding) (eq :required (argument-binding-kind binding)))
        (call-layout-bindings layout)))

(defun call-layout-data (layout)
 "Describe parameter names, kinds and supplied-p names without including specs."
 (mapcar (lambda (binding)
           (list :variable (argument-binding-name binding) :kind (argument-binding-kind binding)
                 :supplied-p (argument-binding-supplied-name binding)))
         (call-layout-bindings layout)))

(defun make-call-layout (declarations)
 "Construct required and optional bindings from normalized declarations."
 (handler-case (validate-call-declarations declarations)
   (invalid-function-spec-form () (error 'program-error)))
 (let ((kind :required))
   (%make-call-layout
    (loop for declaration in declarations
          if (eq declaration '&optional) do (setf kind :optional)
          else collect
            (let ((spec (second declaration)))
              (check-type spec spec)
              (%make-argument-binding (first declaration) spec kind (third declaration)))))))

(defun bind-call-arguments (layout raw-arguments)
 "Bind supplied values and absent NILs, with supplied-p flags, without evaluation."
 (unless (call-layout-accepts-p layout raw-arguments) (error 'program-error))
 (let ((remaining raw-arguments) (values nil) (presence nil) (bindings nil))
   (dolist (binding (call-layout-bindings layout))
     (let ((present-p (not (null remaining))) (value (pop remaining)))
       (push value values)
       (push present-p presence)
       (push (cons (argument-binding-name binding) value) bindings)
       (when (argument-binding-supplied-name binding)
         (push present-p values)
         (push (cons (argument-binding-supplied-name binding) present-p) bindings))))
   (%make-bound-call raw-arguments (nreverse values) (nreverse presence) (nreverse bindings))))

(defstruct (return-schema (:constructor %make-return-schema (primary-spec)) (:copier nil))
  "The legacy primary-value contract, distinct from a future fixed values contract."
  (primary-spec nil :type (or null spec) :read-only t)
  (mode :primary :type (member :primary) :read-only t))

(defclass call-arguments-spec (spec)
 ((layout :initarg :layout :reader call-arguments-spec-layout))
 (:documentation "A positional argument contract with presence-aware optional parameters."))

(defmethod spec-children ((object call-arguments-spec))
 (mapcar #'argument-binding-spec (call-layout-bindings (call-arguments-spec-layout object))))

(defmethod spec-kind ((object call-arguments-spec))
 :call-arguments)

(defmethod initialize-instance :after ((object call-arguments-spec) &key)
 (check-type (call-arguments-spec-layout object) call-layout))

(defun make-return-schema (&key primary-spec)
  "Describe an optional normalized primary-value spec without changing return arity."
  (check-type primary-spec (or null spec))
  (%make-return-schema primary-spec))

(defun return-schema-value (schema returned-values)
  "Project the primary value; zero values and one NIL both project to NIL.
The original outcome retains their distinct return counts."
  (check-type schema return-schema)
  (unless (finite-list-p returned-values) (error 'program-error))
  (first returned-values))
