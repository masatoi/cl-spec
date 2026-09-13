;;;; src/call-schema.lisp

(defpackage #:cl-spec/src/call-schema
 (:use #:cl)
 (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
 (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
 (:import-from #:cl-spec/src/conditions #:invalid-function-spec-form)
 (:import-from #:cl-spec/src/definition-validation #:finite-definition-form-p)
 (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
 (:export #:argument-binding-keyword #:call-layout-key-p #:call-layout-allow-other-keys-p
 #:call-layout-positional-count #:call-layout-shape-error #:validate-call-declarations #:normalize-call-declarations #:call-declaration-variables
 #:argument-binding-supplied-name #:call-layout-required-count #:call-layout-data
 #:call-layout-accepts-p #:call-layout-required-only-p #:call-arguments-spec
 #:call-arguments-spec-layout #:argument-binding #:call-layout #:bound-call #:return-schema
 #:make-call-layout #:call-layout-bindings #:argument-binding-name #:argument-binding-spec
 #:argument-binding-kind #:bind-call-arguments #:bound-call-arguments #:bound-call-values
 #:bound-call-presence #:bound-call-bindings #:make-return-schema #:return-schema-primary-spec
 #:return-schema-mode #:return-schema-value))

(in-package #:cl-spec/src/call-schema)

(defstruct (argument-binding
 (:constructor %make-argument-binding (name spec kind supplied-name keyword)) (:copier nil))
 "A normalized positional or explicit keyword parameter."
 (name nil :type symbol :read-only t)
 (spec nil :type spec :read-only t)
 (kind :required :type (member :required :optional :key) :read-only t)
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
           ((eq declaration '&key)
            (unless (member mode '(:required :optional)) (bad "Misplaced &key."))
            (setf mode :key))
           ((eq declaration '&allow-other-keys)
            (unless (eq mode :key) (bad "Misplaced &allow-other-keys."))
            (setf mode :end))
           (t
            (unless (and (not (eq mode :end)) (finite-list-p declaration)
                         (if (eq mode :required) (= (length declaration) 2)
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
            (when (cddr declaration) (name (third declaration))))))))
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

(defun call-layout-positional-count (layout)
 "Return the number of positional parameters."
 (count-if (lambda (binding) (not (eq :key (argument-binding-kind binding))))
           (call-layout-bindings layout)))

(defun call-layout-shape-error (layout arguments)
 "Return a call shape error kind and optional offending key, or NIL."
 (cond
   ((not (finite-list-p arguments)) :not-a-list)
   ((< (length arguments) (call-layout-required-count layout)) :wrong-length)
   ((not (call-layout-key-p layout))
    (unless (<= (length arguments) (call-layout-positional-count layout)) :wrong-length))
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

(defun make-call-layout (declarations)
 "Construct a layout from normalized explicit declarations."
 (handler-case (validate-call-declarations declarations)
   (invalid-function-spec-form () (error 'program-error)))
 (let ((kind :required))
   (%make-call-layout
    (loop for declaration in declarations
          if (eq declaration '&optional) do (setf kind :optional)
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
            (present-p (not (null (if key-p pair remaining))))
            (value (if key-p (second pair) (pop remaining))))
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
