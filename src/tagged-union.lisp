;;;; src/tagged-union.lisp
;;;;
;;;; Tagged (dispatched) unions (specification §9.5).  A union reads a tag from
;;;; the value through an explicit reader and validates only the branch that tag
;;;; selects, so a failure names one branch instead of listing every alternative
;;;; the way OR does.

(defpackage #:cl-spec/src/tagged-union
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/definition-validation #:validate-definition)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:import-from #:cl-spec/src/field-spec
                #:reader-designator-p #:reader-function)
  (:export #:branch-definition #:make-branch-definition
           #:branch-name #:branch-spec
           #:tagged-union-spec #:tagged-union-tag-reader #:tagged-union-branches
           #:tag-reader-designator-p #:read-tag-value
           #:find-branch #:tagged-union-branch #:branch-descriptions))

(in-package #:cl-spec/src/tagged-union)

(defstruct (branch-definition
             (:constructor make-branch-definition (&key name spec))
             (:conc-name branch-))
  "One union branch: the tag value that selects it and the spec it must satisfy."
  (name nil :read-only t)
  (spec (error "A branch requires a spec.") :type spec :read-only t))

(defclass tagged-union-spec (spec)
  ((tag-reader :initarg :tag-reader
               :initform nil
               :reader tagged-union-tag-reader
               :documentation "Keyword naming a plist entry, or a symbol/function naming a one-argument tag reader.")
   (branches :initarg :branches
             :initform nil
             :reader tagged-union-branches
             :documentation "Ordered branch definitions; each name is the EQL tag value that selects it."))
  (:documentation "A union that dispatches on a tag read from the value.

The tag reader is explicit: a keyword reads a plist entry with GETF, while any
other symbol or function names a one-argument reader resolved like an object
field reader.  Only the branch the tag selects is validated, so a failure names
that branch instead of reporting every alternative as OR does."))

(defmethod spec-kind ((spec tagged-union-spec))
  :tagged-union)

(defmethod spec-children ((spec tagged-union-spec))
  (mapcar #'branch-spec (tagged-union-branches spec)))

(defun tag-reader-designator-p (object)
  "Return true when OBJECT can read a tag from a value.

A keyword is the plist shorthand; anything else must be a reader designator."
  (or (keywordp object)
      (reader-designator-p object)))

(defun read-tag-value (value designator)
  "Return the tag READ from VALUE by DESIGNATOR.

A keyword reads the plist entry with GETF; anything else is called as a
one-argument reader.  GETF walks forever on a circular tail that never
associates the key, so the keyword path first checks that VALUE is a finite
proper list and signals otherwise, which the explainer reports as a structured
:READER-ERRORED datum instead of hanging.  A signalling reader is not caught
here, so the explainer can report it as a fact about the value."
  (if (keywordp designator)
      (progn
        (unless (finite-list-p value)
          ;; The offending value is described by its type rather than printed:
          ;; a circular list has no finite printed representation here.
          (error "The tag reader ~S needs a finite proper plist, not a ~S."
                 designator (type-of value)))
        (getf value designator))
      (funcall (reader-function designator) value)))

(defun find-branch (spec tag)
  "Return SPEC's branch whose name is EQL to TAG, or NIL."
  (find tag (tagged-union-branches spec) :key #'branch-name :test #'eql))

(defun tagged-union-branch (spec name)
  "Return the branch spec of tagged union SPEC named NAME.

Signals INVALID-SPEC-FORM when SPEC is not a tagged union or NAME is unknown, so
a caller aiming generation at one branch is told which branches exist."
  (unless (typep spec 'tagged-union-spec)
    (error 'invalid-spec-form :form spec :reason "not a tagged union spec"))
  (let ((branch (find-branch spec name)))
    (unless branch
      (error 'invalid-spec-form
             :form spec
             :reason (format nil "no branch named ~S; known branches are ~S"
                             name (mapcar #'branch-name (tagged-union-branches spec)))))
    (branch-spec branch)))

(defun branch-descriptions (spec)
  "Describe branch-to-child associations without duplicating the child IR."
  (loop for branch in (tagged-union-branches spec)
        for index from 0
        collect (list :name (branch-name branch) :child-index index)))

(defun validate-tagged-union (spec tag-reader branches)
  "Check SPEC's tag reader and branches, returning SPEC."
  (unless (tag-reader-designator-p tag-reader)
    (error 'invalid-spec-form
           :form (list :tag-reader tag-reader)
           :reason "A tagged union needs a keyword tag key or a reader designator."))
  (unless (and (finite-list-p branches) (plusp (length branches)))
    (error 'invalid-spec-form
           :form (list :branches branches)
           :reason "A tagged union needs a finite nonempty branch list."))
  (let ((seen nil))
    (dolist (branch branches)
      (unless (and (typep branch 'branch-definition)
                   (symbolp (branch-name branch))
                   (not (null (branch-name branch)))
                   (typep (branch-spec branch) 'spec))
        (error 'invalid-spec-form
               :form (list :branches branches)
               :reason "Each branch needs a non-NIL symbol name and a spec."))
      (when (member (branch-name branch) seen)
        (error 'invalid-spec-form
               :form (list :branches branches)
               :reason "Branch names must be unique."))
      (push (branch-name branch) seen)))
  spec)

(defmethod validate-definition ((spec tagged-union-spec))
  (validate-tagged-union spec (tagged-union-tag-reader spec) (tagged-union-branches spec)))

(defmethod shared-initialize :around
    ((spec tagged-union-spec) slot-names &rest initargs
     &key (tag-reader nil tag-reader-p) (branches nil branches-p))
  "Validate the tag reader and branches before changing SPEC.

The candidate values are threaded rather than read from the slots because
reinitialization validates before the slots change."
  (declare (ignore slot-names initargs))
  (validate-tagged-union
   spec
   (if tag-reader-p tag-reader
       (when (slot-boundp spec 'tag-reader) (tagged-union-tag-reader spec)))
   (if branches-p branches
       (when (slot-boundp spec 'branches) (tagged-union-branches spec))))
  (call-next-method))
