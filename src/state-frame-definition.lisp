;;;; src/state-frame-definition.lisp

(defpackage #:cl-spec/src/state-frame-definition
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:import-from #:cl-spec/src/definition-description #:definition-description)
  (:import-from #:cl-spec/src/definition-validation
                #:finite-definition-form-p #:validate-definition)
  (:import-from #:cl-spec/src/registry #:*registry* #:check-registry
                #:registry-find-state-observer #:registry-register-state-observer)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/utils/value-snapshot #:snapshot-value)
  (:export #:register-state-observer #:observer-callback
           #:state-observer-name #:state-observer-snapshot
           #:state-observer-compare #:state-observer-project
           #:state-frame #:make-state-frame #:state-frame-clauses #:state-frame-observers
           #:state-frame-variables #:state-frame-key-function
           #:valid-frame-clauses-p #:frame-key-set-form-p #:check-frame-key-set))

(in-package #:cl-spec/src/state-frame-definition)

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
registration. VERSION is a required positive integer. Supply SOURCE as stable
declaration data for any anonymous operation. Increase VERSION when an
operation's meaning or observed scope changes."
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

(defstruct (state-frame (:constructor %make-state-frame (clauses variables key-function observers))
                        (:copier nil))
  "One frame declaration with captured observer registrations."
  (clauses nil :read-only t)
  (variables nil :read-only t)
  (key-function nil :read-only t)
  (observers nil :read-only t))

(defun frame-key-set-form-p (form)
  "Recognize an explicit key set marker in a frame declaration."
  (and (consp form) (eq :each (first form))))

(defun valid-frame-clauses-p (clauses)
  "Recognize a finite sequence of (OBSERVER KEY-FORM ...) declarations."
  (and (consp clauses) (finite-list-p clauses) (finite-definition-form-p clauses)
       (every (lambda (entry)
                (and (consp entry)
                     (finite-list-p entry)
                     (observer-name-p (first entry))
                     (every (lambda (form)
                              (or (not (frame-key-set-form-p form))
                                  (and (consp (cdr form)) (null (cddr form)))))
                            (rest entry))))
              clauses)))

(defun check-frame-key-set (value)
  "Copy the spine of VALUE after validating a finite proper list of allowed keys."
  (check-argument value '(satisfies finite-list-p) 'check-frame-key-set :each)
  (copy-list value))

(defun make-state-frame (clauses variables key-function &optional (registry *registry*))
  "Resolve the observer registrations used by the compiled frame."
  (check-argument clauses '(satisfies valid-frame-clauses-p) 'make-state-frame :clauses)
  (check-argument key-function 'function 'make-state-frame :key-function)
  (let ((resolved (make-hash-table :test #'eq)))
    (%make-state-frame
     (snapshot-value clauses) (copy-list variables) key-function
     (loop for (name) in clauses
           collect (or (gethash name resolved)
                       (let ((observer (registry-find-state-observer registry name)))
                         (unless (typep observer 'state-observer)
                           (error 'invalid-argument :operator 'make-state-frame
                                  :argument :observer :datum name :expected-type 'state-observer
                                  :reason :unregistered-observer))
                         (setf (gethash name resolved) observer)))))))
