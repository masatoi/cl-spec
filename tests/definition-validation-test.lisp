;;;; tests/definition-validation-test.lisp
(defpackage #:cl-spec/tests/definition-validation-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots
                #:call-with-definition-rollback)
  (:import-from #:cl-spec/src/property
                #:property #:property-arguments #:property-body
                #:property-function #:property-trials)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry #:registry-register-property
                #:registry-find-property #:registry-properties-for #:registry-properties-with-tag)
  (:import-from #:cl-spec/src/ir #:spec))
(in-package #:cl-spec/tests/definition-validation-test)

(defun rejected-p (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error () t)))

(deftest neutral-protocol-restores-bound-and-unbound-slots
  (let ((object (make-instance 'extended-property :name 'extended :function #'identity)))
    (ok (rejected-p
          (lambda ()
            (call-with-definition-rollback
              object (lambda ()
                       (setf (slot-value object 'extra) :created
                             (slot-value object 'existing) :changed)
                       (error "refuse"))))))
    (ok (not (slot-boundp object 'extra)))
    (ok (eq :original (slot-value object 'existing)))
    (ok (equal '(1 2) (multiple-value-list
                       (call-with-definition-rollback object (lambda () (values 1 2))))))))

(deftest property-construction-normalizes-and-requires-executable
  (let ((object (make-valid-property :arguments '((x integer)))))
    (ok (typep (second (first (property-arguments object))) 'spec))
    (ok (eq object (validate-definition object))))
  (dolist (initargs '((:name nil) (:name :keyword) (:name t)
                     (:function nil) (:function identity)
                     (:kind ordinary) (:documentation 3)
                     (:targets (one . two)) (:tags (one 2))
                     (:trials (:normal -1)) (:trials (:normal 1 :normal 2))
                     (:trials (:normal)) (:metadata (:shrink :yes))
                     (:metadata (:x 1 :x 2)) (:metadata (x 1))
                     (:body (a . b)) (:source-form (a . b))
                     (:source-location (:file))))
    (ok (rejected-p (lambda () (apply #'make-instance 'property
                                     (append initargs (list :name 'example :function #'identity))))))))

(deftest property-bindings-refuse-malformed-and-circular-input
  (dolist (bindings '(((x integer extra)) ((x integer) (x string))
                      ((nil integer)) ((t integer)) ((:x integer))
                      ((pi integer)) ((&optional integer))
                      ((x integer) . rest)))
    (ok (rejected-p (lambda () (make-valid-property :arguments bindings)))))
  (let ((spine (list '(x integer))) (nested (list 'list-of nil)))
    (setf (cdr spine) spine
          (second nested) nested)
    (ok (rejected-p (lambda () (make-valid-property :arguments spine))))
    (ok (rejected-p (lambda () (make-valid-property :arguments (list (list 'x nested))))))))

(deftest refused-reinitialization-restores-all-participating-slots
  (let* ((object (make-instance 'extended-property :name 'extended :function #'identity
                               :arguments '((x integer))))
         (arguments (property-arguments object)))
    (ok (rejected-p (lambda ()
                      (reinitialize-instance object :extra :invalid :existing :changed
                                             :arguments '((x string))))))
    (ok (eq arguments (property-arguments object)))
    (ok (not (slot-boundp object 'extra)))
    (ok (eq :original (slot-value object 'existing)))
    (ok (rejected-p (lambda () (reinitialize-instance object :trials '(:normal -1)))))
    (ok (null (property-trials object)))))

(deftest source-and-callable-update-together
  (let* ((predicate #'identity)
         (object (make-instance 'property :name 'paired :function predicate :body '(x))))
    (ok (rejected-p (lambda () (reinitialize-instance object :body '((not x))))))
    (ok (equal '(x) (property-body object)))
    (ok (eq predicate (property-function object)))
    (ok (rejected-p (lambda () (reinitialize-instance object :function #'not))))
    (ok (eq predicate (property-function object)))
    (reinitialize-instance object :body '((not x)) :function #'not)
    (ok (not (funcall (property-function object) t))))
  (let ((object (make-valid-property)))
    (reinitialize-instance object :function #'not)
    (ok (not (funcall (property-function object) t)))))

(deftest change-class-validates-and-restores-participating-state
  (let* ((object (make-valid-property :arguments '((x integer))))
         (arguments (property-arguments object)))
    (ok (rejected-p
          (lambda ()
            (change-class object 'extended-property :extra :invalid :arguments '((x string))))))
    (ok (eq arguments (property-arguments object)))
    (ok (or (not (slot-exists-p object 'extra))
            (not (slot-boundp object 'extra))))))

(defconstant +unusable-property-name+ 17)

(deftest property-names-refuse-defined-constants
  (ok (rejected-p
        (lambda () (make-instance 'property :name '+unusable-property-name+ :function #'identity)))))

(deftest registry-rejects-corrupt-replacement-before-changing-indexes
  (let ((registry (make-hash-table-registry))
         (original (make-valid-property :targets '(old-target) :tags '(:old)))
         (replacement (make-valid-property :targets '(new-target) :tags '(:new))))
    (registry-register-property registry 'example original :targets '(old-target) :tags '(:old))
    (setf (slot-value replacement 'cl-spec/src/property::property-function) nil)
    (ok (rejected-p
          (lambda () (registry-register-property registry 'example replacement
                                                 :targets '(new-target) :tags '(:new)))))
    (ok (eq original (registry-find-property registry 'example)))
    (ok (equal '(example) (registry-properties-for registry 'old-target)))
    (ok (equal '(example) (registry-properties-with-tag registry :old)))
    (ok (null (registry-properties-for registry 'new-target)))
    (ok (null (registry-properties-with-tag registry :new)))))

(defun make-valid-property (&rest initargs)
  (apply #'make-instance 'property :name 'example :function #'identity initargs))

(defclass extended-property (property)
  ((extra :initarg :extra)
   (existing :initarg :existing :initform :original)))

(defmethod definition-validation-slots append ((object extended-property))
  '(extra existing))

(defmethod validate-definition :after ((object extended-property))
  (when (and (slot-boundp object 'extra) (eq :invalid (slot-value object 'extra)))
    (error "Subclass rejects EXTRA")))
