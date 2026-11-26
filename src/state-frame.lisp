;;;; src/state-frame.lisp
(defpackage #:cl-spec/src/state-frame
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:cl-spec-error)
  (:import-from #:cl-spec/src/execution #:same-value-p)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/state-frame-definition
                #:register-state-observer #:observer-callback
                #:state-observer-name #:state-observer-snapshot
                #:state-observer-compare #:state-observer-project
                #:state-frame #:make-state-frame #:state-frame-clauses #:state-frame-observers
                #:state-frame-variables #:state-frame-key-function
                #:valid-frame-clauses-p #:frame-key-set-form-p #:check-frame-key-set)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:serialize-artifact-value #:deserialize-artifact-value)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:register-state-observer #:register-hash-table-state-observer
           #:state-frame #:make-state-frame #:state-frame-clauses #:state-frame-observers
           #:state-frame-variables
           #:valid-frame-clauses-p #:frame-key-set-form-p #:check-frame-key-set
           #:capture-state-frame #:check-state-frame
           #:state-frame-error #:state-frame-error-data #:state-frame-error-condition))
(in-package #:cl-spec/src/state-frame)

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
copying. VERSION is a required positive integer identifying the reader's scope
and meaning."
  (let ((read-table (observer-callback reader 'register-hash-table-state-observer :reader)))
    (register-state-observer name :version version :registry registry
                             :snapshot (lambda () (snapshot-equal-table (funcall read-table)))
                             :compare 'changed-table-keys :project 'project-table-value
                             :source (list :equal-hash-table (and (symbolp reader) reader)))))

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
     (destructuring-bind (value present)
         (multiple-value-list (funcall (state-observer-project observer) snapshot key))
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
