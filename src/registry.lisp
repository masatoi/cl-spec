;;;; src/registry.lisp
;;;;
;;;; Registry protocol and the default hash-table backend (specification §8).
;;;; The registry is deliberately a protocol rather than a single global table
;;;; so that tests, ASDF reloads and LLM-generated candidate definitions can
;;;; each work against an isolated registry.
;;;;
;;;; Package-qualified symbols are the canonical identifiers, so every index is
;;;; keyed with EQ.
;;;;
;;;; This file knows nothing about property or function-spec objects: callers
;;;; pass targets and tags explicitly, which keeps the dependency edge pointing
;;;; from those modules to this one and not back.

(defpackage #:cl-spec/src/registry
  (:use #:cl)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:call-with-definition-rollback)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:registry-find-spec
           #:registry-register-spec
           #:registry-list-specs
           #:registry-find-function-spec
           #:registry-register-function-spec
           #:registry-list-function-specs
           #:registry-find-generator
           #:registry-register-generator
           #:registry-list-generators
           #:registry-find-property
           #:registry-register-property
           #:registry-list-properties
           #:registry-properties-for
           #:registry-properties-with-tag
           #:registry-clear
           #:hash-table-registry
           #:make-hash-table-registry
           #:*registry*
           #:find-spec
           #:list-specs
           #:register-spec
           #:find-function-spec
           #:list-function-specs
           #:find-generator
           #:list-generators
           #:find-property
           #:list-properties
           #:properties-for
           #:properties-with-tag
           #:clear-registry))

(in-package #:cl-spec/src/registry)

(defgeneric registry-find-spec (registry name)
  (:documentation "Return the spec registered in REGISTRY under NAME.
Returns two values: the spec (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-spec (registry name spec)
  (:documentation "Register SPEC in REGISTRY under NAME, replacing any previous
definition.  Returns SPEC."))

(defmethod registry-register-spec :around (registry name spec)
  "Validate before changing registry storage or reverse indexes."
  (check-type name symbol)
  (call-with-definition-rollback
   spec (lambda () (validate-definition spec) (call-next-method))))

(defgeneric registry-list-specs (registry)
  (:documentation "Return the names of every spec in REGISTRY, sorted."))

(defgeneric registry-find-function-spec (registry name)
  (:documentation "Return the function spec registered in REGISTRY under NAME.
Returns two values: the function spec (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-function-spec (registry name function-spec)
  (:documentation "Register FUNCTION-SPEC in REGISTRY under NAME, replacing any
previous definition.  Returns FUNCTION-SPEC."))

(defmethod registry-register-function-spec :around (registry name function-spec)
  "Validate before changing registry storage or reverse indexes."
  (check-type name symbol)
  (call-with-definition-rollback
   function-spec (lambda () (validate-definition function-spec) (call-next-method))))

(defgeneric registry-list-function-specs (registry)
  (:documentation "Return the names of every function spec in REGISTRY, sorted."))

(defgeneric registry-find-generator (registry name)
  (:documentation "Return the custom generator registered in REGISTRY under NAME.
Returns two values: the generator (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-generator (registry name generator)
  (:documentation "Register GENERATOR in REGISTRY under NAME, replacing any
previous definition.  Returns GENERATOR."))

(defmethod registry-register-generator :around (registry name generator)
  "Validate before changing registry storage or reverse indexes."
  (check-type name symbol)
  (call-with-definition-rollback
   generator (lambda () (validate-definition generator) (call-next-method))))

(defgeneric registry-list-generators (registry)
  (:documentation "Return the names of every custom generator in REGISTRY, sorted."))

(defgeneric registry-find-property (registry name)
  (:documentation "Return the property registered in REGISTRY under NAME.
Returns two values: the property (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-property (registry name property &key targets tags)
  (:documentation "Register PROPERTY in REGISTRY under NAME.

TARGETS is a list of symbols the property is about; TAGS is a list of tag
designators.  Both are indexed for reverse lookup.  Re-registering a name
replaces the previous definition and drops its stale index entries.
Returns PROPERTY."))

(defmethod registry-register-property :around (registry name property &key targets tags)
  "Validate before changing registry storage or reverse indexes."
  (check-type name symbol)
  (dolist (keys (list targets tags))
    (unless (and (finite-list-p keys) (every #'symbolp keys))
      (error 'type-error :datum nil :expected-type 'list)))
  (call-with-definition-rollback
   property (lambda () (validate-definition property) (call-next-method))))

(defgeneric registry-list-properties (registry)
  (:documentation "Return the names of every property in REGISTRY, sorted."))

(defgeneric registry-properties-for (registry target)
  (:documentation "Return the names of properties registered against TARGET,
sorted."))

(defgeneric registry-properties-with-tag (registry tag)
  (:documentation "Return the names of properties carrying TAG, sorted."))

(defgeneric registry-clear (registry)
  (:documentation "Remove every entry from REGISTRY and return REGISTRY."))

(defstruct (property-entry (:constructor make-property-entry (property targets tags)))
  "A property together with the index keys it was registered under, so that
re-registration can retract the previous keys."
  (property nil)
  (targets nil :type list)
  (tags nil :type list))

(defun make-registry-table ()
  "Return a hash table for one registry index, keyed with EQ.

:SYNCHRONIZED is an implementation extension.  Asking for it unconditionally meant
a class :INITFORM could not be built where it is refused, so CL-SPEC would not load
at all -- measured on CLISP, which signals SIMPLE-KEYWORD-ERROR.  The guard is a
reader conditional rather than a run-time fallback because the extension is visible
to a compiler that rejects it: CCL warns about the literal keyword even though
HANDLER-CASE would catch the run-time error, and that warning fails a build with
warnings-as-errors.  Only SBCL asks for the guarantee, which is the same boundary
WITH-REGISTRY-LOCK draws -- the lock is what makes it useful for a compound update,
and a synchronized table without it only covers single operations."
  #+sbcl (make-hash-table :test #'eq :synchronized t)
  #-sbcl (make-hash-table :test #'eq))

(defclass hash-table-registry ()
  ((specs :initform (make-registry-table)
          :reader registry-specs
          :documentation "Symbol -> spec.")
   (function-specs :initform (make-registry-table)
                   :reader registry-function-specs
                   :documentation "Symbol -> function spec.")
   (generators :initform (make-registry-table)
               :reader registry-generators
               :documentation "Symbol -> CUSTOM-GENERATOR (specification §11).")
   (properties :initform (make-registry-table)
               :reader registry-properties
               :documentation "Symbol -> PROPERTY-ENTRY.")
   (properties-by-target :initform (make-registry-table)
                         :reader registry-properties-by-target
                         :documentation "Target symbol -> list of property names.")
   (properties-by-tag :initform (make-registry-table)
                      :reader registry-properties-by-tag
                      :documentation "Tag -> list of property names."))
  (:documentation "In-image registry backed by hash tables.  The default backend."))

(defmacro with-registry-lock ((registry) &body body)
  "Run BODY with REGISTRY's property table locked, so that a compound update
lands as one and no reader can see it half applied.

Each table is :SYNCHRONIZED where the implementation provides it (see
MAKE-REGISTRY-TABLE), which makes a single GETHASH, SETF GETHASH or
REMHASH atomic -- and nothing more.  The reverse indexes are maintained with
read-modify-write: INDEX-PROPERTY pushes onto a list it has just read, and
REGISTRY-REGISTER-PROPERTY's find, unindex, set, index sequence straddles four
tables.  Under contention a push is simply lost, and the loss is invisible in the
names table: §73.4 #8 measured 8 threads registering 3000 properties leaving
PROPERTIES-FOR answering with 1146 of them, with nothing on any listing to say the
index had holes.  The regression test registers 4000 and lost 2789 of them before
this lock existed.

Every writer and every reader of the reverse indexes takes this same lock -- the
one belonging to the table that holds the definitions -- so the acquisition
order is the same on both sides and it cannot deadlock.  BODY may use the hash
tables normally; the lock is recursive.

On an implementation without SB-EXT:WITH-LOCKED-HASH-TABLE the body runs
unlocked, which is the behaviour this registry has always had there: correct
when a registry is written from one thread, which is the host model §40
describes."
  #+sbcl `(sb-ext:with-locked-hash-table ((registry-properties ,registry))
            ,@body)
  #-sbcl `(locally (declare (ignore ,registry)) ,@body))

(defun make-hash-table-registry ()
  "Return a fresh empty HASH-TABLE-REGISTRY."
  (make-instance 'hash-table-registry))

(defvar *registry* (make-hash-table-registry)
  "Registry the front-end functions in this package operate on by default.
Rebind it to isolate specs and properties, for example in tests.

A rebinding does not cross a thread boundary.  §48 puts the time limit on the
execution host, so a host that runs checks off the calling thread has to carry
this value over itself -- PROGV, or the :REGISTRY argument every entry point
takes.  Without that, a run started on another thread resolves names in the
global registry: if the same name is registered in both, it checks a different
definition and reports a verdict for it, with nothing on the result to say so.")

(defun symbol-sort-key (symbol)
  "Return a string that orders SYMBOL deterministically across packages."
  (let ((package (symbol-package symbol)))
    (concatenate 'string
                 (symbol-name symbol)
                 "|"
                 (if package (package-name package) ""))))

(defun sorted-symbols (symbols)
  "Return SYMBOLS sorted by name and then by home package name."
  (sort (copy-list symbols)
        #'string<
        :key #'symbol-sort-key))

(defun hash-table-keys-sorted (table)
  "Return the keys of TABLE as a sorted list of symbols."
  (let ((keys '()))
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sorted-symbols keys)))

(defmethod registry-find-spec ((registry hash-table-registry) name)
  (gethash name (registry-specs registry)))

(defmethod registry-register-spec ((registry hash-table-registry) name spec)
  (setf (gethash name (registry-specs registry)) spec)
  spec)

(defmethod registry-list-specs ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-specs registry)))

(defmethod registry-find-function-spec ((registry hash-table-registry) name)
  (gethash name (registry-function-specs registry)))

(defmethod registry-register-function-spec ((registry hash-table-registry)
                                            name function-spec)
  (setf (gethash name (registry-function-specs registry)) function-spec)
  function-spec)

(defmethod registry-list-function-specs ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-function-specs registry)))

(defmethod registry-find-generator ((registry hash-table-registry) name)
  (gethash name (registry-generators registry)))

(defmethod registry-register-generator ((registry hash-table-registry)
                                        name generator)
  (setf (gethash name (registry-generators registry)) generator)
  generator)

(defmethod registry-list-generators ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-generators registry)))

(defmethod registry-find-property ((registry hash-table-registry) name)
  (let ((entry (gethash name (registry-properties registry))))
    (if entry
        (values (property-entry-property entry) t)
        (values nil nil))))

(defun index-property (registry name targets tags)
  "Add NAME to REGISTRY's reverse indexes for TARGETS and TAGS."
  (dolist (target targets)
    (pushnew name (gethash target (registry-properties-by-target registry))))
  (dolist (tag tags)
    (pushnew name (gethash tag (registry-properties-by-tag registry)))))

(defun unindex-property (registry name targets tags)
  "Remove NAME from REGISTRY's reverse indexes for TARGETS and TAGS.
Index keys that end up empty are dropped so that lookups return NIL."
  (dolist (target targets)
    (let ((remaining (remove name (gethash target
                                           (registry-properties-by-target registry)))))
      (if remaining
          (setf (gethash target (registry-properties-by-target registry)) remaining)
          (remhash target (registry-properties-by-target registry)))))
  (dolist (tag tags)
    (let ((remaining (remove name (gethash tag
                                           (registry-properties-by-tag registry)))))
      (if remaining
          (setf (gethash tag (registry-properties-by-tag registry)) remaining)
          (remhash tag (registry-properties-by-tag registry))))))

(defmethod registry-register-property ((registry hash-table-registry) name property
                                       &key targets tags)
  (with-registry-lock (registry)
    (let ((previous (gethash name (registry-properties registry))))
      (when previous
        (unindex-property registry name
                          (property-entry-targets previous)
                          (property-entry-tags previous))))
    (setf (gethash name (registry-properties registry))
          (make-property-entry property targets tags))
    (index-property registry name targets tags)
    property))

(defmethod registry-list-properties ((registry hash-table-registry))
  (with-registry-lock (registry)
    (hash-table-keys-sorted (registry-properties registry))))

(defmethod registry-properties-for ((registry hash-table-registry) target)
  (with-registry-lock (registry)
    (sorted-symbols (gethash target (registry-properties-by-target registry)))))

(defmethod registry-properties-with-tag ((registry hash-table-registry) tag)
  (with-registry-lock (registry)
    (sorted-symbols (gethash tag (registry-properties-by-tag registry)))))

(defmethod registry-clear ((registry hash-table-registry))
  (with-registry-lock (registry)
    (clrhash (registry-specs registry))
    (clrhash (registry-function-specs registry))
    (clrhash (registry-generators registry))
    (clrhash (registry-properties registry))
    (clrhash (registry-properties-by-target registry))
    (clrhash (registry-properties-by-tag registry))
    registry))

(defun find-spec (name &optional (registry *registry*))
  "Return the spec registered under NAME in REGISTRY, and a found-p second value."
  (registry-find-spec registry name))

(defun list-specs (&optional (registry *registry*))
  "Return the names of every spec in REGISTRY, sorted."
  (registry-list-specs registry))

(defun register-spec (name spec &optional (registry *registry*))
  "Register SPEC under NAME in REGISTRY and return SPEC."
  (registry-register-spec registry name spec))

(defun find-function-spec (name &optional (registry *registry*))
  "Return the function spec registered under NAME in REGISTRY, and found-p."
  (registry-find-function-spec registry name))

(defun list-function-specs (&optional (registry *registry*))
  "Return the names of every function spec in REGISTRY, sorted."
  (registry-list-function-specs registry))

(defun find-generator (name &optional (registry *registry*))
  "Return the custom generator registered under NAME, and a found-p second value."
  (registry-find-generator registry name))

(defun list-generators (&optional (registry *registry*))
  "Return the names of every custom generator in REGISTRY, sorted."
  (registry-list-generators registry))

(defun find-property (name &optional (registry *registry*))
  "Return the property registered under NAME in REGISTRY, and found-p."
  (registry-find-property registry name))

(defun list-properties (&optional (registry *registry*))
  "Return the names of every property in REGISTRY, sorted."
  (registry-list-properties registry))

(defun properties-for (target &optional (registry *registry*))
  "Return the names of properties registered against TARGET in REGISTRY, sorted."
  (registry-properties-for registry target))

(defun properties-with-tag (tag &optional (registry *registry*))
  "Return the names of properties carrying TAG in REGISTRY, sorted."
  (registry-properties-with-tag registry tag))

(defun clear-registry (&optional (registry *registry*))
  "Remove every entry from REGISTRY and return REGISTRY."
  (registry-clear registry))
