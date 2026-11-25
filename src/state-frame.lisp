;;;; src/state-frame.lisp
(defpackage #:cl-spec/src/state-frame
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:cl-spec-error #:invalid-argument)
  (:import-from #:cl-spec/src/definition-validation #:finite-definition-form-p
                #:validate-definition)
  (:import-from #:cl-spec/src/execution #:same-value-p #:snapshot-value)
  (:import-from #:cl-spec/src/registry #:*registry* #:check-registry
                #:registry-find-state-observer #:registry-register-state-observer)
  (:import-from #:cl-spec/src/schema #:definition-description)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:serialize-artifact-value #:deserialize-artifact-value)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:register-state-observer #:register-hash-table-state-observer
           #:state-frame #:make-state-frame #:state-frame-clauses #:state-frame-observers
           #:valid-frame-clauses-p #:capture-state-frame #:check-state-frame
           #:state-frame-error #:state-frame-error-data #:state-frame-error-condition))
(in-package #:cl-spec/src/state-frame)

(defstruct (state-observer
            (:constructor make-state-observer (name version snapshot compare project source))
            (:copier nil))
  "Registered snapshot, compare and display operations with a declaration identity."
  (name nil :read-only t)
  (version 1 :read-only t)
  (snapshot nil :read-only t)
  (compare nil :read-only t)
  (project nil :read-only t)
  (source nil :read-only t))

(defun observer-name-p (value)
  "Recognize an interned, non-NIL name in the observer namespace."
  (and value (symbolp value) (symbol-package value)))

(defmethod validate-definition ((observer state-observer))
  observer)

(defmethod definition-description ((observer state-observer))
  (let ((source (state-observer-source observer)))
    (values (list :state-observer (state-observer-name observer)
                  :version (state-observer-version observer) :source source)
            nil nil (not (null source)))))

(defun observer-callback (designator operator argument)
  "Capture a callable global function or closure at registration."
  (check-argument designator '(or function symbol) operator argument)
  (if (functionp designator)
      designator
      (if (and (fboundp designator) (not (macro-function designator))
               (not (special-operator-p designator)))
          (symbol-function designator)
          (error 'invalid-argument :operator operator :argument argument
                 :datum designator :expected-type '(or function symbol)
                 :reason :not-a-function))))

(defun register-state-observer (name &key version snapshot compare project source
                                          (registry *registry*))
  "Register three operations for NAME in REGISTRY.
SNAPSHOT () returns an independent view of the observed state. COMPARE (BEFORE
AFTER) returns a finite list of changed keys. PROJECT (SNAPSHOT KEY) returns a
bounded AV1 value and a boolean presence flag. The functions are captured at
registration. Supply SOURCE as stable declaration data for any anonymous
operation, and increase VERSION when its meaning or observed scope changes."
  (check-argument name '(satisfies observer-name-p) 'register-state-observer :name)
  (check-argument version '(integer 1 *) 'register-state-observer :version)
  (check-argument source '(satisfies finite-definition-form-p) 'register-state-observer :source)
  (let* ((operator 'register-state-observer)
         (snapshot-function (observer-callback snapshot operator :snapshot))
         (compare-function (observer-callback compare operator :compare))
         (project-function (observer-callback project operator :project))
         (operations (list (and (symbolp snapshot) snapshot)
                           (and (symbolp compare) compare)
                           (and (symbolp project) project)))
         (description (when (or source (every #'identity operations))
                        (list :operations operations :source (snapshot-value source)))))
    (registry-register-state-observer
     (check-registry registry operator) name
     (make-state-observer name version snapshot-function compare-function
                          project-function description))))

(defun copy-state-data (value)
  "Freeze bounded printable data with no live object references."
  (deserialize-artifact-value
   (serialize-artifact-value value :max-chars 16384 :max-nodes 2048 :max-depth 32)
   :max-chars 16384 :max-nodes 2048 :max-depth 32))

(defun copy-frame-key (key)
  "Freeze a key whose identity is preserved by the frame's EQUAL comparison."
  (let ((copy (copy-state-data key)))
    (unless (equal key copy)
      (error "The state key does not survive a snapshot under EQUAL."))
    copy))

(defun snapshot-equal-table (table)
  "Copy the keys and values of an EQUAL table into an independent snapshot."
  (unless (and (hash-table-p table) (eq 'equal (hash-table-test table)))
    (error "An in-memory state observer requires an EQUAL hash table."))
  (let ((snapshot (make-hash-table :test #'equal)))
    (maphash (lambda (key value)
               (setf (gethash (copy-frame-key key) snapshot) (copy-state-data value)))
             table)
    snapshot))

(defun changed-table-keys (before after)
  "Report changed EQUAL keys in deterministic wire order."
  (let ((keys nil))
    (maphash (lambda (key previous)
               (multiple-value-bind (current present) (gethash key after)
                 (unless (and present (same-value-p previous current)) (push key keys))))
             before)
    (maphash (lambda (key value)
               (declare (ignore value))
               (unless (nth-value 1 (gethash key before)) (push key keys)))
             after)
    (sort keys #'string< :key #'serialize-artifact-value)))

(defun project-table-value (snapshot key)
  "Return the observed value and its presence in the saved table."
  (gethash key snapshot))

(defun register-hash-table-state-observer (name reader &key version (registry *registry*))
  "Register an in-memory observer for the EQUAL hash table returned by READER.
Keys and values must be bounded AV1 data, with keys stable under EQUAL after
copying. VERSION identifies the reader's scope and meaning."
  (let ((read-table (observer-callback reader 'register-hash-table-state-observer :reader)))
    (register-state-observer name :version version :registry registry
                             :snapshot (lambda () (snapshot-equal-table (funcall read-table)))
                             :compare 'changed-table-keys :project 'project-table-value
                             :source (list :equal-hash-table (and (symbolp reader) reader)))))

(defstruct (state-frame (:constructor %make-state-frame (clauses key-function observers))
                        (:copier nil))
  "One frame declaration with captured observer registrations."
  (clauses nil :read-only t)
  (key-function nil :read-only t)
  (observers nil :read-only t))

(defun valid-frame-clauses-p (clauses)
  "Recognize a finite sequence of (OBSERVER KEY-FORM ...) declarations."
  (and (consp clauses) (finite-list-p clauses) (finite-definition-form-p clauses)
       (every (lambda (entry)
                (and (consp entry) (finite-list-p entry) (observer-name-p (first entry))))
              clauses)))

(defun make-state-frame (clauses key-function &optional (registry *registry*))
  "Resolve the observer registrations used by the compiled frame."
  (check-argument clauses '(satisfies valid-frame-clauses-p) 'make-state-frame :clauses)
  (check-argument key-function 'function 'make-state-frame :key-function)
  (let ((resolved (make-hash-table :test #'eq)))
    (%make-state-frame
     (snapshot-value clauses) key-function
     (loop for (name) in clauses
           collect (or (gethash name resolved)
                       (let ((observer (registry-find-state-observer registry name)))
                         (unless (typep observer 'state-observer)
                           (error 'invalid-argument :operator 'make-state-frame
                                  :argument :observer :datum name :expected-type 'state-observer
                                  :reason :unregistered-observer))
                         (setf (gethash name resolved) observer)))))))

(define-condition state-frame-error (cl-spec-error)
  ((observer :initarg :observer :reader state-frame-error-observer)
   (stage :initarg :stage :reader state-frame-error-stage)
   (condition :initarg :condition :reader state-frame-error-condition))
  (:documentation "A state frame callback or its data protocol failed.")
  (:report (lambda (error stream)
             (format stream "State frame operation ~S failed for ~S (~S)."
                     (state-frame-error-stage error) (state-frame-error-observer error)
                     (type-of (state-frame-error-condition error))))))

(defun state-frame-error-data (error)
  "Project a failed operation as ordinary diagnostic data."
  (list :status :error :observer (state-frame-error-observer error)
        :stage (state-frame-error-stage error)
        :condition-type (type-of (state-frame-error-condition error))))

(defun call-frame-operation (observer stage function &rest arguments)
  "Attribute frame protocol errors to the observer and operation that failed."
  (handler-case (apply function arguments)
    (error (condition)
      (error 'state-frame-error :observer (and observer (state-observer-name observer))
             :stage stage :condition condition))))

(defun capture-state-frame (frame arguments captures)
  "Freeze every allowed key before the target and snapshot each observer once."
  (when frame
    (let ((key-groups (call-frame-operation
                       nil :allowed-keys
                       (lambda ()
                         (mapcar (lambda (keys) (mapcar #'copy-frame-key keys))
                                 (apply (state-frame-key-function frame)
                                        (append arguments captures))))))
          (groups nil))
      (loop for observer in (state-frame-observers frame)
            for keys in key-groups
            for group = (assoc observer groups)
            do (if group
                   (setf (second group) (append (second group) keys))
                   (push (list observer keys) groups)))
      (loop for (observer keys) in (nreverse groups)
            collect (list observer keys
                          (call-frame-operation observer :before
                                                (state-observer-snapshot observer)))))))

(defun project-frame-value (observer stage snapshot key)
  "Freeze a presence-aware projection before exposing it to the caller."
  (call-frame-operation
   observer stage
   (lambda ()
     (multiple-value-bind (value present) (funcall (state-observer-project observer)
                                                   snapshot key)
       (check-type present boolean)
       (if present
           (list :present t :value (copy-state-data value))
           (list :present nil))))))

(defun check-state-frame (captured)
  "Report the first undeclared change across the captured observer scopes."
  (loop for (observer allowed before) in captured
        for after = (call-frame-operation observer :after (state-observer-snapshot observer))
        for changed = (call-frame-operation
                       observer :compare
                       (lambda ()
                         (let ((keys (funcall (state-observer-compare observer) before after)))
                           (unless (finite-list-p keys)
                             (error "An observer comparison must return a finite key list."))
                           keys)))
        do (dolist (key changed)
             (let ((saved-key (call-frame-operation observer :key #'copy-frame-key key)))
               (unless (member saved-key allowed :test #'equal)
                 (return-from check-state-frame
                   (list :status :violation
                         :observer (state-observer-name observer) :key saved-key
                         :before (project-frame-value observer :project-before before key)
                         :after (project-frame-value observer :project-after after key))))))
        finally (return (list :status :passed))))
