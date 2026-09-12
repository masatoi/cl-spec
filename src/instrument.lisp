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
  (:import-from #:cl-spec/src/conditions #:spec-violation #:unknown-function-spec)
  (:import-from #:cl-spec/src/registry #:*registry* #:registry-find-function-spec)
  (:import-from #:cl-spec/src/explain #:compile-explainer)
  (:import-from #:cl-spec/src/schema #:definition-instrumentation-capability)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-spec-name #:function-spec-argument-specs
                #:function-spec-return-spec #:function-spec-precondition-function
                #:function-spec-postcondition-function #:function-spec-postconditions)
  (:export #:*instrumented-functions* #:instrumented-function-p
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
           :documentation "The failed arity, argument, precondition, return or postcondition check."))
  (:report (lambda (condition stream)
             (format stream "Runtime contract violation in ~S (~S, ~S)."
                     (instrumentation-violation-function condition)
                     (instrumentation-violation-scope condition)
                     (instrumentation-violation-reason condition))))
  (:documentation "Runtime contract failure with SPEC-VIOLATION's structured error evidence."))

(defstruct (installation (:constructor make-installation (original wrapper)))
  original wrapper)

(defun ordinary-target-p (name)
  (and (symbolp name) (not (eq (symbol-package name) (find-package :cl)))
       (fboundp name)
       (not (special-operator-p name)) (not (macro-function name))
       (not (typep (fdefinition name) 'generic-function))))

(defmethod definition-instrumentation-capability ((contract function-spec))
  (if (ordinary-target-p (function-spec-name contract)) :available :unavailable))

(defun valid-scopes-p (scopes)
  (and (listp scopes)
       (handler-case
           (and (list-length scopes)
                (every (lambda (scope) (member scope '(:input :output :post))) scopes))
         (type-error () nil))))

(defun contract-failure (name scope reason value path &optional errors)
  (error 'instrumentation-violation
         :function name :scope scope :reason reason :spec name :value value :path path
         :errors (or errors (list (list :kind reason :path path :value value)))))

(defun make-contract-wrapper (name original contract registry scopes)
  (let* ((arguments (function-spec-argument-specs contract))
         (arity (length arguments))
         (context (list :registry registry))
         (input-p (member :input scopes))
         (inputs (when input-p
                   (mapcar (lambda (argument)
                             (cons (first argument)
                                   (compile-explainer (second argument) :context context)))
                           arguments)))
         (pre (when input-p (function-spec-precondition-function contract)))
         (returns (function-spec-return-spec contract))
         (output (when (and (member :output scopes) returns)
                   (compile-explainer returns :context context)))
         (post (when (member :post scopes) (function-spec-postcondition-function contract)))
         (post-count (length (function-spec-postconditions contract))))
    (lambda (&rest values)
      (when input-p
        (unless (= arity (length values))
          (contract-failure name :input :arity values '(:args)
                            (list (list :kind :arity :path '(:args) :value values
                                        :expected-length arity :actual-length (length values)))))
        (loop for (parameter . explainer) in inputs
              for value in values
              for path = (list :args parameter)
              for errors = (funcall explainer value (reverse path))
              when errors do (contract-failure name :input :argument-spec value path errors))
        (when (and pre (not (apply pre values)))
          (contract-failure name :input :precondition values '(:pre))))
      (multiple-value-call
          (lambda (&rest results)
            (let ((value (first results)))
              (when output
                (let ((errors (funcall output value '(:returns))))
                  (when errors
                    (contract-failure name :output :return-spec value '(:returns) errors))))
              (when post
                (multiple-value-bind (holds index tag) (apply post value values)
                  (unless holds
                    (contract-failure name :post :postcondition value
                                      (if (and (eq tag :cl-spec-post-form-failure)
                                               (integerp index) (<= 0 index) (< index post-count))
                                          (list :post index) '(:post))))))
              (values-list results)))
        (apply original values)))))

(defun install-contract (name &key (registry *registry*) (scopes '(:input :output :post)))
  (check-type name symbol)
  (check-type scopes (satisfies valid-scopes-p))
  (let ((contract (or (registry-find-function-spec registry name)
                      (error 'unknown-function-spec :name name))))
    (unless (ordinary-target-p name)
      (error 'program-error))
    (let* ((entry (gethash name *instrumented-functions*))
           (original (if (instrumented-function-p name)
                         (installation-original entry) (fdefinition name)))
           (wrapper (make-contract-wrapper name original contract registry scopes)))
      (setf (fdefinition name) wrapper
            (gethash name *instrumented-functions*) (make-installation original wrapper))
      name)))

(defun instrumented-function-p (name)
  "Return true only while NAME's current fdefinition is our installed wrapper."
  (let ((entry (gethash name *instrumented-functions*)))
    (and (typep entry 'installation) (fboundp name)
         (eq (fdefinition name) (installation-wrapper entry)))))

(defun instrument-function (name &rest options)
  "Install checks for NAME and return NAME; refresh an existing wrapper without stacking.

OPTIONS accepts :REGISTRY (default *REGISTRY*) and :SCOPES (default
(:INPUT :OUTPUT :POST)). The legacy positional registry argument is also accepted.
:INPUT checks arity, argument specs and :PRE; :OUTPUT checks the primary value;
:POST checks postconditions. NIL scopes disables checks. All target values and
conditions pass through. Failed checks signal INSTRUMENTATION-VIOLATION.

Only ordinary symbol-named functions outside COMMON-LISP are supported. Missing contracts signal
UNKNOWN-FUNCTION-SPEC; unsupported targets signal PROGRAM-ERROR. Checks capture
the contract at installation; reinstall to refresh it. Previously captured
function objects, lexical and inlined calls are not intercepted."
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
