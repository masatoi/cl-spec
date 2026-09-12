;;;; src/execution.lisp

(defpackage #:cl-spec/src/execution
  (:use #:cl)
  (:import-from #:cl-spec/src/property #:property #:property-function)
  (:export #:*trial-observations* #:trial-observation #:make-trial-observation
           #:trial-observation-arguments #:trial-observation-arguments-mutated-p
           #:trial-observation-status
           #:trial-observation-reason #:trial-observation-signature
           #:trial-observation-explanation #:trial-observation-condition
           #:trial-observation-condition-report #:trial-observation-value
           #:evaluate-trial #:observe-trial #:observation-failure-p
           #:failure-identities-match-p #:snapshot-value #:same-value-p))

(in-package #:cl-spec/src/execution)

(defstruct (trial-observation (:copier nil))
  "Evidence from one invocation, captured before another trial can change it.
Lists and arrays are copied. Arbitrary objects and external state are not
checkpointed. CONDITION retains the actual condition; CONDITION-REPORT is its
text at observation time."
  (arguments nil :read-only t)
  (arguments-mutated-p nil :read-only t)
  (status :passed :read-only t)
  (reason nil :read-only t)
  (signature nil :read-only t)
  (explanation nil :read-only t)
  (condition nil :read-only t)
  (condition-report nil :read-only t)
  (value nil :read-only t))

(defun snapshot-value (value)
  "Copy conses and arrays, preserving cycles and sharing within VALUE.
Other objects retain identity; this is not a snapshot of arbitrary application
state. Array dimensions, element types and fill pointers are preserved."
  (let ((copies (make-hash-table :test #'eq)))
    (labels ((copy-value (item)
               (or (gethash item copies)
                   (cond
                     ((consp item)
                      (let ((copy (cons nil nil)))
                        (setf (gethash item copies) copy
                              (car copy) (copy-value (car item))
                              (cdr copy) (copy-value (cdr item)))
                        copy))
                     ((arrayp item)
                      (let ((copy (make-array
                                   (array-dimensions item)
                                   :element-type (array-element-type item)
                                   :adjustable (adjustable-array-p item)
                                   :fill-pointer (when (array-has-fill-pointer-p item)
                                                   (fill-pointer item)))))
                        (setf (gethash item copies) copy)
                        (dotimes (i (array-total-size item))
                          (setf (row-major-aref copy i)
                                (copy-value (row-major-aref item i))))
                        copy))
                     (t item)))))
      (copy-value value))))

(defun same-value-p (left right)
  "Compare observed arguments without conflating numeric types or looping on cycles."
  (let ((seen (make-hash-table :test #'eq))
        (reverse-seen (make-hash-table :test #'eq)))
    (labels ((same (a b)
               (cond
                 ((eql a b) t)
                 ((gethash a seen) (eq b (gethash a seen)))
                 ((gethash b reverse-seen) nil)
                 ((and (consp a) (consp b))
                  (setf (gethash a seen) b
                        (gethash b reverse-seen) a)
                  (and (same (car a) (car b)) (same (cdr a) (cdr b))))
                 ((and (arrayp a) (arrayp b)
                       (equal (array-dimensions a) (array-dimensions b))
                       (equal (array-element-type a) (array-element-type b))
                       (eql (array-has-fill-pointer-p a) (array-has-fill-pointer-p b))
                       (or (not (array-has-fill-pointer-p a))
                           (= (fill-pointer a) (fill-pointer b))))
                  (setf (gethash a seen) b
                        (gethash b reverse-seen) a)
                  (loop for i below (array-total-size a)
                        always (same (row-major-aref a i) (row-major-aref b i))))
                 (t nil))))
      (same left right))))

(defun failure-identities-match-p (original candidate)
  "Compare observed failure signatures against the ORIGINAL trial.
False property results and conditions have distinct classes, and conditions
compare by type. Function return-spec/postcondition crossings retain their shared
return-value class; within each clause, spec shapes or post-form indices must agree.
An unknown post-form identity never establishes a match, including clause crossings."
  (and original candidate
       (eq (first original) (first candidate))
       (not (and (eq (first original) :return-value)
                 (eq (second original) :postcondition)
                 (null (third original))))
       (not (and (eq (first candidate) :return-value)
                 (eq (second candidate) :postcondition)
                 (null (third candidate))))
       (if (eq (first original) :return-value)
           (or (not (eq (second original) (second candidate)))
               (equal (cddr original) (cddr candidate)))
           (equal (rest original) (rest candidate)))))

(defun observation-failure-p (observation)
  "Return true when OBSERVATION records a failed or signalled trial."
  (and (typep observation 'trial-observation)
       (member (trial-observation-status observation) '(:failed :error))
       t))

(defgeneric evaluate-trial (property arguments &key context)
  (:documentation "Evaluate PROPERTY once, returning status, reason, signature,
explanation, condition and value. Status is :passed, :rejected, :failed or :error.
Backends call OBSERVE-TRIAL to capture these values with the input snapshot.
Specializations must classify during this invocation, never by rerunning it."))

(defmethod evaluate-trial ((property property) arguments &key context)
  (declare (ignore context))
  (handler-case
      (let ((value (apply (property-function property) arguments)))
        (if value
            (values :passed nil nil nil nil value)
            (values :failed :predicate-false '(:property-false) nil nil nil)))
    (error (condition)
      (values :error :condition (list :property-condition (type-of condition))
              nil condition nil))))

(defun render-condition-report (condition)
  "Capture diagnostic text without losing evidence to a broken condition printer."
  (when condition
    (handler-case
        (let ((*print-circle* t))
          (princ-to-string condition))
      (error () (format nil "~S (condition report unavailable)" (type-of condition))))))

(defvar *trial-observations* nil
  "Dynamically scoped observation-to-property table for the active backend invocation.")

(defun observe-trial (property arguments &key context)
  "Evaluate generated objects once, snapshot evidence and record invocation provenance.
Mutations of conses and arrays, including changed sharing, stop backend shrinking."
  (let ((snapshot (snapshot-value arguments)))
    (multiple-value-bind (status reason signature explanation condition value)
        (evaluate-trial property arguments :context context)
      (let ((observation
              (make-trial-observation
               :arguments snapshot
               :arguments-mutated-p (not (same-value-p snapshot arguments))
               :status status :reason reason
               :signature (snapshot-value signature)
               :explanation (snapshot-value explanation)
               :condition condition
               :condition-report (render-condition-report condition)
               :value (snapshot-value value))))
        (when *trial-observations*
          (setf (gethash observation *trial-observations*) property))
        observation))))
