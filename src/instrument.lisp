;;;; src/instrument.lisp
;;;;
;;;; Runtime contract checking (specification §20).  Instrumentation replaces a
;;;; function's definition with a wrapper that validates arguments and return
;;;; value against its registered function spec.  It is a separate system
;;;; because production images should be able to load cl-spec without gaining
;;;; the ability to rewrite fdefinitions.

(defpackage #:cl-spec/src/instrument
  (:use #:cl)
  (:nicknames #:cl-spec/instrument)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation #:unknown-function-spec #:cl-spec-error #:unbound-target)
  (:import-from #:cl-spec/src/ir #:tuple-spec #:predicate-spec #:predicate-spec-predicate)
  (:import-from #:cl-spec/src/registry #:*registry* #:registry-find-function-spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer #:error-datum #:expected-descriptor #:proper-list-p)
  (:import-from #:cl-spec/src/schema #:definition-instrumentation-capability)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-spec-name #:function-spec-argument-specs
                #:function-spec-signal-spec
                #:function-spec-return-spec #:function-spec-precondition-function
                #:function-spec-postcondition-function #:function-spec-postconditions
                #:precondition-refuses-p)
  (:export #:unsupported-instrumentation-target #:unsupported-instrumentation-target-name
           #:unsupported-instrumentation-target-reason
           #:*instrumented-functions* #:instrumented-function-p
           #:instrument-function #:uninstrument-function
           #:instrumentation-violation #:instrumentation-violation-function
           #:instrumentation-violation-scope #:instrumentation-violation-reason))

(in-package #:cl-spec/src/instrument)

(defvar *instrumented-functions* (make-hash-table :test #'eq)
  "Symbol -> private installation entry. Bind a fresh table only in isolated tests.
Installations and function redefinitions must be serialized by the caller.")

(define-condition instrumentation-violation (spec-violation)
  ((function :initarg :function :reader instrumentation-violation-function
             :documentation "Symbol naming the wrapped function.")
   (scope :initarg :scope :reader instrumentation-violation-scope
          :documentation "The failed :INPUT, :OUTPUT or :POST scope.")
   (reason :initarg :reason :reader instrumentation-violation-reason
           :documentation "The failed arity, argument, precondition,
return or postcondition check."))
  (:report (lambda (condition stream)
             (format stream "Runtime contract violation in ~S (~S, ~S)."
                     (instrumentation-violation-function condition)
                     (instrumentation-violation-scope condition)
                     (instrumentation-violation-reason condition))))
  (:documentation "Runtime contract failure with SPEC-VIOLATION's structured error evidence."))

(define-condition unsupported-instrumentation-target (cl-spec-error program-error)
  ((name :initarg :name :reader unsupported-instrumentation-target-name
         :documentation "The name whose definition cannot be wrapped.")
   (reason :initarg :reason :reader unsupported-instrumentation-target-reason
           :documentation "Why this definition is unsupported."))
  (:report (lambda (condition stream)
             (format stream "Cannot instrument ~S: ~A."
                     (unsupported-instrumentation-target-name condition)
                     (unsupported-instrumentation-target-reason condition))))
  (:documentation
   "A defined target is not an ordinary writable function supported by this module."))

(defstruct (installation (:constructor make-installation (original wrapper)))
  "Original definition and the wrapper installed in its place."
  original wrapper)

(defun unsupported-target-reason (name)
  "Return the reason NAME cannot be wrapped, or NIL for a supported definition."
  (cond
    ((not (symbolp name)) :not-a-symbol)
    ((special-operator-p name) :special-operator)
    ((macro-function name) :macro)
    ((not (fboundp name)) :unbound)
    ((eq (symbol-package name) (find-package :cl)) :common-lisp-symbol)
    ((typep (fdefinition name) 'generic-function) :generic-function)))

(defun ordinary-target-p (name)
  "Return true for a supported, defined target."
  (null (unsupported-target-reason name)))

(defmethod definition-instrumentation-capability ((contract function-spec))
  (if (and (not (function-spec-signal-spec contract))
           (ordinary-target-p (function-spec-name contract)))
      :available :unavailable))

(defun valid-scopes-p (scopes)
  "Recognize a finite list containing only supported scope keywords."
  (and (proper-list-p scopes)
       (every (lambda (scope) (member scope '(:input :output :post))) scopes)))

(defun contract-failure (name scope reason spec value errors)
  "Report captured ERRORS against the actual SPEC without rerunning any predicate."
  (error 'instrumentation-violation
         :function name :scope scope :reason reason :spec spec :value value
         :path (getf (first errors) :path) :errors errors))

(defun make-contract-wrapper (name original contract registry scopes)
  "Compile enabled checks and capture their predicates around ORIGINAL."
  (let* ((arguments (function-spec-argument-specs contract))
         (arity (length arguments))
         (context (list :registry registry))
         (input-p (member :input scopes))
         (argument-schema (when input-p
                            (make-instance 'tuple-spec :element-specs (mapcar #'second arguments))))
         (inputs (when input-p
                   (mapcar (lambda (argument)
                             (list (second argument)
                                   (list (first argument) :args)
                                   (compile-explainer (second argument) :context context)))
                           arguments)))
         (pre (when input-p (function-spec-precondition-function contract)))
         (pre-test (when pre
                     (lambda (values) (not (precondition-refuses-p pre values)))))
         (pre-spec (when pre (make-instance 'predicate-spec :predicate pre-test)))
         (returns (function-spec-return-spec contract))
         (output (when (and (member :output scopes) returns)
                   (compile-explainer returns :context context)))
         (post (when (member :post scopes) (function-spec-postcondition-function contract)))
         (post-spec (when post
                      (make-instance 'predicate-spec
                                     :predicate (lambda (value-and-args)
                                                  (apply post value-and-args)))))
         (post-count (length (function-spec-postconditions contract))))
    (lambda (&rest values)
      (when input-p
        (unless (= arity (length values))
          (contract-failure
           name :input :arity argument-schema values
           (list (error-datum :wrong-length '(:args) values
                              :expected (expected-descriptor argument-schema)
                              :expected-length arity :actual-length (length values)))))
        (loop for (spec path explainer) in inputs
              for value in values
              for errors = (funcall explainer value path)
              when errors do (contract-failure name :input :argument-spec spec value errors))
        (when (precondition-refuses-p pre values)
          (contract-failure name :input :precondition pre-spec values
                            (list (error-datum :predicate-failed '(:pre) values
                                               :predicate pre-test
                                               :expected (expected-descriptor pre-spec))))))
      (if (not (or output post))
          (apply original values)
          (multiple-value-call
              (lambda (&rest results)
                (let ((value (first results)))
                  (when output
                    (let ((errors (funcall output value '(:returns))))
                      (when errors
                        (contract-failure name :output :return-spec returns value errors))))
                  (when post
                    (multiple-value-bind (holds index tag) (apply post value values)
                      (unless holds
                        (let ((path (if (and (eq tag :cl-spec-post-form-failure)
                                             (integerp index) (<= 0 index) (< index post-count))
                                        (list index :post) '(:post)))
                              (value-and-args (cons value values)))
                          (contract-failure
                           name :post :postcondition post-spec value-and-args
                           (list (error-datum :predicate-failed path value-and-args
                                              :predicate (predicate-spec-predicate post-spec)
                                              :expected (expected-descriptor post-spec))))))))
                  (values-list results)))
            (apply original values))))))

(defun install-contract (name &key (registry *registry*) (scopes '(:input :output :post)))
  "Install enabled checks using REGISTRY, retaining the original definition for restoration."
  (check-type name symbol)
  (check-type scopes (satisfies valid-scopes-p))
  (let* ((registry (or registry *registry*))
         (contract (or (registry-find-function-spec registry name)
                       (error 'unknown-function-spec :name name)))
         (reason (unsupported-target-reason name)))
    (when reason
      (if (eq reason :unbound)
          (error 'unbound-target :name name)
          (error 'unsupported-instrumentation-target :name name :reason reason)))
    (when (function-spec-signal-spec contract)
      (error 'unsupported-instrumentation-target
             :name name :reason :expected-condition-contract))
    (let* ((active-p (instrumented-function-p name))
           (entry (gethash name *instrumented-functions*))
           (original (if active-p (installation-original entry) (fdefinition name)))
           (wrapper (make-contract-wrapper name original contract registry scopes)))
      (setf (fdefinition name) wrapper
            (gethash name *instrumented-functions*) (make-installation original wrapper))
      name)))

(defun instrumented-function-p (name)
  "Return true while NAME's fdefinition is our wrapper; forget stale installation state."
  (let ((entry (gethash name *instrumented-functions*)))
    (if (and (typep entry 'installation) (fboundp name)
             (eq (fdefinition name) (installation-wrapper entry)))
        t
        (progn (remhash name *instrumented-functions*) nil))))

(defun instrument-function (name &rest options)
  "Install checks for NAME and return NAME; refresh an existing wrapper without stacking.

OPTIONS accepts :REGISTRY (NIL or omitted means *REGISTRY*) and :SCOPES
(default (:INPUT :OUTPUT :POST)). The positional registry argument is also accepted.
:INPUT checks arity, argument specs and :PRE; :OUTPUT checks the primary value;
:POST checks postconditions. NIL scopes disables checks. All target values and
conditions pass through. Failed checks signal INSTRUMENTATION-VIOLATION.

Only ordinary symbol-named functions outside COMMON-LISP are supported.
Missing contracts signal UNKNOWN-FUNCTION-SPEC, undefined targets UNBOUND-TARGET,
and unsupported definitions UNSUPPORTED-INSTRUMENTATION-TARGET.
:INPUT describes the entire argument list, not a prefix of the target lambda list.
Checks capture the contract at installation; reinstall to refresh it. Previously
captured function objects, lexical and inlined calls are not intercepted."
  (if (and options (not (keywordp (first options))))
      (apply #'install-contract name :registry (first options) (rest options))
      (apply #'install-contract name options)))

(defun uninstrument-function (name)
  "Restore NAME's original function only if its installed wrapper is still current.
Return true when restored, NIL otherwise. Forget stale entries without overwriting
a later redefinition or undoing FMAKUNBOUND."
  (let ((entry (gethash name *instrumented-functions*)))
    (prog1 (when (instrumented-function-p name)
             (setf (fdefinition name) (installation-original entry))
             t)
      (remhash name *instrumented-functions*))))
