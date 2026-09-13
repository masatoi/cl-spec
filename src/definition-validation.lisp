;;;; src/definition-validation.lisp
(defpackage #:cl-spec/src/definition-validation
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:validate-definition #:definition-validation-slots
           #:call-with-definition-rollback #:finite-definition-form-p
           #:definition-keyword-plist-p))
(in-package #:cl-spec/src/definition-validation)

(defgeneric validate-definition (object)
  (:documentation "Validate and normalize a definition, returning OBJECT."))

(defmethod validate-definition ((object t)) object)

(defgeneric definition-validation-slots (object)
  (:method-combination append)
  (:documentation "Append participating slot names from a definition and its subclasses."))

(defmethod definition-validation-slots append ((object t)) nil)

(defun finite-definition-form-p (value)
  "Recognize acyclic cons and array graphs, allowing shared subforms."
  (let ((states (make-hash-table :test #'eq))
        (pending (list (cons :enter value))))
    (loop while pending
          for (phase . object) = (pop pending)
          when (or (consp object) (and (arrayp object) (not (stringp object))))
            do (cond
                 ((eq phase :leave) (setf (gethash object states) :done))
                 ((eq (gethash object states) :active)
                  (return-from finite-definition-form-p nil))
                 ((eq (gethash object states) :done))
                 (t
                  (setf (gethash object states) :active)
                  (push (cons :leave object) pending)
                  (if (consp object)
                      (progn (push (cons :enter (cdr object)) pending)
                             (push (cons :enter (car object)) pending))
                      (dotimes (index (array-total-size object))
                        (push (cons :enter (row-major-aref object index)) pending))))))
    t))

(defun definition-keyword-plist-p (value)
  "Recognize a finite plist with unique keyword keys."
  (and (finite-list-p value)
       (evenp (length value))
       (let ((seen (make-hash-table :test #'eq)))
         (loop for (key) on value by #'cddr
               always (and (keywordp key) (not (gethash key seen))
                           (setf (gethash key seen) t))))))

(defun call-with-definition-rollback (object thunk)
  "Call THUNK, restoring participating slot bindings if it does not complete.
Snapshots preserve boundness and value identity. Subclasses extend the slot list
with DEFINITION-VALIDATION-SLOTS APPEND methods. Destructive changes inside slot
values and changes to an object's class are outside this rollback boundary."
  (let ((snapshot
          (loop for slot in (remove-duplicates (definition-validation-slots object))
                collect (list slot (slot-boundp object slot)
                              (when (slot-boundp object slot) (slot-value object slot)))))
        (completed nil))
    (unwind-protect
         (multiple-value-prog1 (funcall thunk) (setf completed t))
      (unless completed
        (dolist (entry snapshot)
          (destructuring-bind (slot boundp value) entry
            (if boundp
                (setf (slot-value object slot) value)
                (slot-makunbound object slot))))))))
