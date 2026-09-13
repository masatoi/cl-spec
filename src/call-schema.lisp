;;;; src/call-schema.lisp

(defpackage #:cl-spec/src/call-schema
  (:use #:cl)
  (:import-from #:cl-spec/src/ir #:spec)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:argument-binding #:call-layout #:bound-call #:return-schema
           #:make-call-layout #:call-layout-bindings
           #:argument-binding-name #:argument-binding-spec #:argument-binding-kind
           #:bind-call-arguments #:bound-call-arguments #:bound-call-values
           #:bound-call-presence #:bound-call-bindings
           #:make-return-schema #:return-schema-primary-spec
           #:return-schema-mode #:return-schema-value))

(in-package #:cl-spec/src/call-schema)

(defstruct (argument-binding (:constructor %make-argument-binding (name spec)) (:copier nil))
  "One normalized required parameter descriptor."
  (name nil :type symbol :read-only t)
  (spec nil :type spec :read-only t)
  (kind :required :type (member :required) :read-only t))

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

(defun make-call-layout (required-pairs)
  "Construct required bindings from finite (NAME NORMALIZED-SPEC) pairs.
No argument expressions, defaults, predicates or target code are evaluated."
  (unless (finite-list-p required-pairs) (error 'program-error))
  (let ((seen (make-hash-table :test #'eq)))
    (%make-call-layout
     (loop for pair in required-pairs
           do (unless (and (finite-list-p pair) (= 2 (length pair)))
                (error 'program-error))
           collect
           (let ((name (first pair)) (spec (second pair)))
             (unless (and name (symbolp name) (not (constantp name))
                          (not (and (plusp (length (symbol-name name)))
                                    (char= (char (symbol-name name) 0) #\&)))
                          (not (gethash name seen)))
               (error 'program-error))
             (check-type spec spec)
             (setf (gethash name seen) t)
             (%make-argument-binding name spec))))))

(defun bind-call-arguments (layout raw-arguments)
  "Bind exactly the required values without copying or replacing application objects.
Malformed lists and wrong argument counts signal PROGRAM-ERROR. No target runs."
  (check-type layout call-layout)
  (unless (and (finite-list-p raw-arguments)
               (= (length raw-arguments) (length (call-layout-bindings layout))))
    (error 'program-error))
  (%make-bound-call raw-arguments (copy-list raw-arguments)
                    (make-list (length raw-arguments) :initial-element t)
                    (loop for binding in (call-layout-bindings layout)
                          for value in raw-arguments
                          collect (cons (argument-binding-name binding) value))))

(defstruct (return-schema (:constructor %make-return-schema (primary-spec)) (:copier nil))
  "The legacy primary-value contract, distinct from a future fixed values contract."
  (primary-spec nil :type (or null spec) :read-only t)
  (mode :primary :type (member :primary) :read-only t))

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
