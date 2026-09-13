;;;; src/call-schema.lisp

(defpackage #:cl-spec/src/call-schema
  (:use #:cl)
  (:import-from #:cl-spec/src/ir
                #:spec #:spec-kind #:spec-children #:tuple-spec #:tuple-spec-element-specs)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/definition-validation
                #:finite-definition-form-p #:validate-definition #:call-with-definition-rollback)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:return-values-spec #:normalize-return-declaration #:call-layout-rest-binding
           #:argument-binding-keyword #:call-layout-key-p
           #:call-layout-allow-other-keys-p #:call-layout-positional-count #:call-layout-shape-error
           #:validate-call-declarations #:normalize-call-declarations #:call-declaration-variables
           #:argument-binding-supplied-name #:call-layout-required-count
           #:call-layout-data #:call-layout-policy-data
           #:call-layout-accepts-p #:call-layout-required-only-p #:call-arguments-spec
           #:call-arguments-spec-layout #:argument-binding #:call-layout
           #:bound-call #:return-schema
           #:make-call-layout #:call-layout-bindings #:argument-binding-name #:argument-binding-spec
           #:argument-binding-kind #:bind-call-arguments #:bound-call-arguments #:bound-call-values
           #:bound-call-presence #:bound-call-bindings
           #:make-return-schema #:return-schema-primary-spec
           #:return-schema-mode #:return-schema-value))

(in-package #:cl-spec/src/call-schema)

(defstruct (argument-binding
  (:constructor %make-argument-binding (name spec kind supplied-name keyword)) (:copier nil))
  "A normalized positional or explicit keyword parameter."
  (name nil :type symbol :read-only t)
  (spec nil :type spec :read-only t)
  (kind :required :type (member :required :optional :rest :key) :read-only t)
  (supplied-name nil :type symbol :read-only t)
  (keyword nil :type symbol :read-only t))

(defstruct (call-layout (:constructor %make-call-layout (bindings key-p allow-other-keys-p))
                          (:copier nil))
  "Parameter descriptors and keyword acceptance policy."
  (bindings nil :type list :read-only t)
  (key-p nil :type boolean :read-only t)
  (allow-other-keys-p nil :type boolean :read-only t))

(defstruct (bound-call (:constructor %make-bound-call (arguments values presence bindings))
                       (:copier nil))
  "A raw call and its bound values; application values retain their actual identity."
  (arguments nil :type list :read-only t)
  (values nil :type list :read-only t)
  (presence nil :type list :read-only t)
  (bindings nil :type list :read-only t))

(defun validate-call-declarations (declarations)
  "Validate finite explicit parameter declarations without evaluation or interning."
  (labels ((bad (reason)
             (error 'invalid-function-spec-form :form declarations :reason reason)))
    (unless (and (finite-list-p declarations) (finite-definition-form-p declarations))
      (bad "Argument declarations must be finite proper forms."))
    (let ((mode :required) (seen (make-hash-table :test #'eq))
          (keys (make-hash-table :test #'eq)))
      (labels ((name (value)
                 (unless (and (symbolp value) value (not (constantp value))
                              (not (and (plusp (length (symbol-name value)))
                                        (char= #\& (char (symbol-name value) 0))))
                              (not (gethash value seen)))
                   (bad "Argument and supplied-p names must be unique variables."))
                 (setf (gethash value seen) t)))
        (dolist (declaration declarations)
          (cond
            ((eq declaration '&optional)
             (unless (eq mode :required) (bad "Misplaced &optional."))
             (setf mode :optional))
            ((eq declaration '&rest)
             (unless (member mode '(:required :optional)) (bad "Misplaced &rest."))
             (setf mode :rest))
            ((eq declaration '&key)
             (unless (member mode '(:required :optional :after-rest)) (bad "Misplaced &key."))
             (setf mode :key))
            ((eq declaration '&allow-other-keys)
             (unless (eq mode :key) (bad "Misplaced &allow-other-keys."))
             (setf mode :end))
            (t
             (unless (and (not (member mode '(:end :after-rest))) (finite-list-p declaration)
                          (if (member mode '(:required :rest)) (= (length declaration) 2)
                              (member (length declaration) '(2 3))))
               (bad "Malformed parameter declaration."))
             (if (eq mode :key)
                 (let ((pair (first declaration)))
                   (unless (and (finite-list-p pair) (= (length pair) 2)
                                (keywordp (first pair))
                                (not (eq (first pair) :allow-other-keys))
                                (not (gethash (first pair) keys)))
                     (bad "Expected a unique explicit (:KEYWORD VARIABLE) binder."))
                   (setf (gethash (first pair) keys) t)
                   (name (second pair)))
                 (name (first declaration)))
             (when (cddr declaration) (name (third declaration)))
             (when (eq mode :rest) (setf mode :after-rest)))))
        (when (eq mode :rest) (bad "Missing &rest declaration."))))
    declarations))

(defun normalize-call-declarations (declarations)
  "Normalize only spec positions in validated argument declarations."
  (validate-call-declarations declarations)
  (mapcar (lambda (declaration)
            (if (symbolp declaration) declaration
                (list* (first declaration) (normalize-spec-form (second declaration))
                       (copy-list (cddr declaration)))))
          declarations))

(defun call-declaration-variables (declarations)
  "Return value and supplied-p variables in predicate order."
  (validate-call-declarations declarations)
  (loop for declaration in declarations
        unless (symbolp declaration)
          append (cons (if (consp (first declaration)) (second (first declaration))
                           (first declaration))
                       (copy-list (cddr declaration)))))

(defun call-layout-required-count (layout)
  "Return the minimum accepted positional argument count."
  (count :required (call-layout-bindings layout) :key #'argument-binding-kind))

(defun call-layout-rest-binding (layout)
  "Return the whole-tail rest descriptor, or NIL."
  (find :rest (call-layout-bindings layout) :key #'argument-binding-kind))

(defun call-layout-positional-count (layout)
  "Return the number of positional parameters."
  (count-if (lambda (binding) (member (argument-binding-kind binding) '(:required :optional)))
            (call-layout-bindings layout)))

(defun call-layout-shape-error (layout arguments)
  "Return a call shape error kind and optional offending key, or NIL."
  (cond
    ((not (finite-list-p arguments)) :not-a-list)
    ((< (length arguments) (call-layout-required-count layout)) :wrong-length)
    ((not (call-layout-key-p layout))
     (unless (or (call-layout-rest-binding layout)
                 (<= (length arguments) (call-layout-positional-count layout))) :wrong-length))
    (t
     (let ((tail (nthcdr (min (length arguments) (call-layout-positional-count layout)) arguments)))
       (cond
         ((oddp (length tail)) :odd-keyword-arguments)
         ((loop for key in tail by #'cddr thereis (not (keywordp key))) :non-keyword-argument)
         (t
          (let ((allowed (or (call-layout-allow-other-keys-p layout)
                             (getf tail :allow-other-keys))))
            (unless allowed
              (loop for key in tail by #'cddr
                    unless (or (eq key :allow-other-keys)
                               (find key (call-layout-bindings layout)
                                     :key #'argument-binding-keyword :test #'eq))
                      do (return-from call-layout-shape-error (values :unknown-key key)))))))))))

(defun call-layout-accepts-p (layout arguments)
  "Check finite shape, arity and keyword policy without evaluating values."
  (check-type layout call-layout)
  (null (call-layout-shape-error layout arguments)))

(defun call-layout-required-only-p (layout)
  "Return true for a layout containing only required positional parameters."
  (and (not (call-layout-key-p layout))
       (every (lambda (binding) (eq :required (argument-binding-kind binding)))
              (call-layout-bindings layout))))

(defun call-layout-data (layout)
  "Describe parameter names, kinds, supplied-p names and explicit keywords."
  (mapcar (lambda (binding)
            (append (list :variable (argument-binding-name binding)
                          :kind (argument-binding-kind binding)
                          :supplied-p (argument-binding-supplied-name binding))
                    (when (eq :key (argument-binding-kind binding))
                      (list :keyword (argument-binding-keyword binding)))))
          (call-layout-bindings layout)))

(defun call-layout-policy-data (layout)
  "Return keyword acceptance metadata, or NIL when LAYOUT has no keyword section."
  (when (call-layout-key-p layout)
    (list :key-arguments t :allow-other-keys (call-layout-allow-other-keys-p layout))))

(defun make-call-layout (declarations)
  "Construct a layout from normalized explicit declarations."
  (handler-case (validate-call-declarations declarations)
    (invalid-function-spec-form () (error 'program-error)))
  (let ((kind :required))
    (%make-call-layout
     (loop for declaration in declarations
           if (eq declaration '&optional) do (setf kind :optional)
           else if (eq declaration '&rest) do (setf kind :rest)
           else if (eq declaration '&key) do (setf kind :key)
           else unless (eq declaration '&allow-other-keys)
           collect (let ((spec (second declaration)) (binder (first declaration)))
                     (check-type spec spec)
                     (%make-argument-binding
                      (if (eq kind :key) (second binder) binder)
                      spec kind (third declaration) (when (eq kind :key) (first binder)))))
     (not (null (member '&key declarations)))
     (not (null (member '&allow-other-keys declarations))))))

(defun bind-call-arguments (layout raw-arguments)
  "Bind effective first keyword occurrences and greedy positional values without evaluation."
  (unless (call-layout-accepts-p layout raw-arguments) (error 'program-error))
  (let ((remaining raw-arguments) (values nil) (presence nil) (bindings nil))
    (dolist (binding (call-layout-bindings layout))
      (let* ((key-p (eq :key (argument-binding-kind binding)))
             (pair (when key-p
                     (loop for tail on remaining by #'cddr
                           when (eq (first tail) (argument-binding-keyword binding))
                             return tail)))
             (rest-p (eq :rest (argument-binding-kind binding)))
             (present-p (or rest-p (not (null (if key-p pair remaining)))))
             (value (cond (rest-p remaining) (key-p (second pair)) (t (pop remaining)))))
        (push value values)
        (push present-p presence)
        (push (cons (argument-binding-name binding) value) bindings)
        (when (argument-binding-supplied-name binding)
          (push present-p values)
          (push (cons (argument-binding-supplied-name binding) present-p) bindings))))
    (%make-bound-call raw-arguments (nreverse values) (nreverse presence) (nreverse bindings))))

(defclass return-values-spec (tuple-spec) ()
  (:documentation "An exact ordered list of returned values, including zero values."))

(defmethod spec-kind ((object return-values-spec)) :values)

(defmethod validate-definition ((object return-values-spec))
  (let ((elements (tuple-spec-element-specs object)))
    (unless (and (finite-list-p elements) (every (lambda (element) (typep element 'spec)) elements))
      (error 'invalid-function-spec-form :form elements
             :reason "Return value elements must be a finite proper list of normalized specs.")))
  object)

(defmethod shared-initialize :around ((object return-values-spec) slot-names &rest initargs)
  (declare (ignore slot-names initargs))
  (call-with-definition-rollback object (lambda () (call-next-method))))

(defmethod shared-initialize :after ((object return-values-spec) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition object))

(defun normalize-return-declaration (form)
  "Normalize function-only VALUES syntax while preserving ordinary spec error conditions."
  (unless (finite-definition-form-p form)
    (error 'invalid-function-spec-form :form form :reason "Return declaration must be finite."))
  (cond
    ((typep form 'return-values-spec) (validate-definition form))
    ((and (consp form) (symbolp (car form)) (string= "VALUES" (symbol-name (car form))))
     (unless (finite-list-p form)
       (error 'invalid-function-spec-form :form form :reason "VALUES must be a proper list."))
     (when (some (lambda (child)
                   (and (symbolp child) (plusp (length (symbol-name child)))
                        (char= #\& (char (symbol-name child) 0))))
                 (cdr form))
       (error 'invalid-function-spec-form :form form
              :reason "VALUES requires fixed spec positions, without lambda-list markers."))
     (handler-case
         (make-instance 'return-values-spec :source-form form
                        :element-specs (mapcar #'normalize-spec-form (cdr form)))
       (invalid-function-spec-form (condition) (error condition))
       (error ()
         (error 'invalid-function-spec-form :form form
                :reason "Invalid return value specification."))))
    (t (normalize-spec-form form))))

(defstruct (return-schema (:constructor %make-return-schema (primary-spec mode)) (:copier nil))
  "A primary-value or exact fixed-values return declaration."
  (primary-spec nil :type (or null spec) :read-only t)
  (mode :primary :type (member :primary :values) :read-only t))

(defclass call-arguments-spec (spec)
  ((layout :initarg :layout :reader call-arguments-spec-layout))
  (:documentation "A positional argument contract with presence-aware optional parameters."))

(defmethod spec-children ((object call-arguments-spec))
  (mapcar #'argument-binding-spec (call-layout-bindings (call-arguments-spec-layout object))))

(defmethod spec-kind ((object call-arguments-spec))
  :call-arguments)

(defmethod initialize-instance :after ((object call-arguments-spec) &key)
  ;; CHECK-TYPE takes a place, and its STORE-VALUE restart writes the place
  ;; back.  The slot has no writer, so the reader is not a usable place; the
  ;; SLOT-VALUE place is, which keeps the restart meaningful rather than
  ;; repairing a lexical the object never sees.
  (check-type (slot-value object 'layout) call-layout))

(defun make-return-schema (&key primary-spec)
  "Describe a normalized primary-value or fixed-values declaration."
  (check-type primary-spec (or null spec))
  (when (typep primary-spec 'return-values-spec) (validate-definition primary-spec))
  (%make-return-schema primary-spec (if (typep primary-spec 'return-values-spec) :values :primary)))

(defun return-schema-value (schema returned-values)
  "Project the full list for fixed values, otherwise the first value or NIL.
The original outcome always retains its distinct return count."
  (check-type schema return-schema)
  (unless (finite-list-p returned-values) (error 'program-error))
  (if (eq :values (return-schema-mode schema)) returned-values (first returned-values)))
