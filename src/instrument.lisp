;;;; src/instrument.lisp
;;;;
;;;; Runtime contract checking (specification §20).  Instrumentation replaces a
;;;; function's definition with a wrapper that validates arguments and return
;;;; value against its registered function spec.  It is a separate system
;;;; because production images should be able to load cl-spec without gaining
;;;; the ability to rewrite fdefinitions.

(defpackage #:cl-spec/src/instrument
  (:use #:cl)
  (:import-from #:cl-spec/src/call-schema
                #:call-layout-bindings #:bind-call-arguments #:bound-call-values
                #:return-schema-primary-spec #:return-schema-value)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec-call-layout #:function-spec-return-schema)
  (:nicknames #:cl-spec/instrument)
  (:import-from #:cl-spec/src/conditions
                #:spec-violation #:unknown-function-spec #:cl-spec-error #:unbound-target)
  (:import-from #:cl-spec/src/ir #:tuple-spec #:predicate-spec #:predicate-spec-predicate)
  (:import-from #:cl-spec/src/registry #:*registry* #:registry-find-function-spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer #:error-datum #:expected-descriptor #:proper-list-p)
  (:import-from #:cl-spec/src/schema
                #:definition-instrumentation-capability #:definition-graph #:definition-digest
                #:schema-info)
  (:import-from #:cl-spec/src/execution #:snapshot-value #:same-value-p)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec #:function-spec-name #:function-spec-argument-specs
                #:function-spec-signal-spec
                #:function-spec-precondition-function
                #:function-spec-postcondition-function #:function-spec-postconditions
                #:precondition-refuses-p)
  (:export #:unsupported-instrumentation-target #:unsupported-instrumentation-target-name
           #:unsupported-instrumentation-target-reason
           #:*instrumented-functions* #:instrumented-function-p
           #:instrument-function #:uninstrument-function
           #:instrumentation-status #:refresh-instrumentation
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

(defstruct (installation
            (:constructor make-installation
                (original wrapper &key registry contract scopes declaration declaration-available-p
                                  precondition postcondition digest digest-complete-p
                                  digest-omissions digest-exclusions)))
  "Original definition, active wrapper, and installation-time declaration evidence."
  original wrapper registry contract scopes declaration declaration-available-p
  precondition postcondition digest digest-complete-p digest-omissions digest-exclusions)

(defun unsupported-target-reason (name)
  "Return the reason NAME cannot be wrapped, or NIL for a supported definition."
  (cond
    ((not (symbolp name)) :not-a-symbol)
    ((special-operator-p name) :special-operator)
    ((macro-function name) :macro)
    ((not (fboundp name)) :unbound)
    ((eq (symbol-package name) (find-package :cl)) :common-lisp-symbol)
    ((typep (fdefinition name) 'generic-function) :generic-function)))

(defun unsupported-contract-reason (name contract)
  "Return the shared installation/capability refusal reason for NAME and CONTRACT."
  (or (unsupported-target-reason name)
      (when (function-spec-signal-spec contract) :expected-condition-contract)))

(defmethod definition-instrumentation-capability ((contract function-spec))
  (if (unsupported-contract-reason (function-spec-name contract) contract)
      :unavailable :available))

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
         (layout (function-spec-call-layout contract))
         (arity (length (call-layout-bindings layout)))
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
         (return-schema (function-spec-return-schema contract))
         (returns (return-schema-primary-spec return-schema))
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
        (when (and pre
                    (precondition-refuses-p
                     pre (bound-call-values (bind-call-arguments layout values))))
          (contract-failure name :input :precondition pre-spec values
                            (list (error-datum :predicate-failed '(:pre) values
                                               :predicate pre-test
                                               :expected (expected-descriptor pre-spec))))))
      (if (not (or output post))
          (apply original values)
          (multiple-value-call
              (lambda (&rest results)
                (let ((value (return-schema-value return-schema results)))
                  (when output
                    (let ((errors (funcall output value '(:returns))))
                      (when errors
                        (contract-failure name :output :return-spec returns value errors))))
                  (when post
                    (multiple-value-bind (holds index tag)
                         (apply post value (bound-call-values (bind-call-arguments layout values)))
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

(defun local-declaration-snapshot (contract)
  "Snapshot complete local declarations without resolving registry dependencies.
Function objects remain identity-bearing leaves. Incomplete descriptions cannot
establish a declaration comparison and return NIL/NIL."
  (multiple-value-bind (records complete)
      (definition-graph contract :resolve-links-p nil)
    (if complete
        (values (snapshot-value records) t)
        (values nil nil))))

(defun install-contract (name &key (registry *registry*) (scopes '(:input :output :post)))
  "Install enabled checks using REGISTRY, retaining the original definition for restoration.
Build the new wrapper and all metadata before replacing the active installation."
  (check-type name symbol)
  (check-type scopes (satisfies valid-scopes-p))
  (let* ((registry (or registry *registry*))
         (contract (or (registry-find-function-spec registry name)
                       (error 'unknown-function-spec :name name)))
         (reason (unsupported-contract-reason name contract)))
    (when reason
      (if (eq reason :unbound)
          (error 'unbound-target :name name)
          (error 'unsupported-instrumentation-target :name name :reason reason)))
    (let* ((active-p (instrumented-function-p name))
           (entry (gethash name *instrumented-functions*))
           (original (if active-p (installation-original entry) (fdefinition name)))
           (captured-scopes (copy-list scopes))
           (wrapper (make-contract-wrapper name original contract registry captured-scopes)))
      (multiple-value-bind (declaration available) (local-declaration-snapshot contract)
        (multiple-value-bind (digest complete omissions) (definition-digest contract :registry registry)
          (let ((new-entry
                  (make-installation
                   original wrapper :registry registry :contract contract :scopes captured-scopes
                   :declaration declaration :declaration-available-p available
                   :precondition (function-spec-precondition-function contract)
                   :postcondition (function-spec-postcondition-function contract)
                   :digest digest :digest-complete-p complete
                   :digest-omissions (snapshot-value omissions)
                   :digest-exclusions (snapshot-value (getf (schema-info) :digest-excludes)))))
            (setf (fdefinition name) wrapper
                  (gethash name *instrumented-functions*) new-entry))))
      name)))

(defun instrumentation-status (name &key (registry *registry*))
  "Describe installed checks without changing the function or installation table.
Local declaration changes are stale. Named dependencies resolve dynamically, so
their changes are reported separately. Incomplete evidence is indeterminate.
Installed omissions and digest exclusions are installation-time snapshots.
Current omissions are freshly collected; :NOT-COLLECTED distinguishes absent
inspection from a known empty omission list."
  (check-type name symbol)
  (let ((entry (gethash name *instrumented-functions*))
        (reasons nil) (stale nil) (current-digest nil) (current-complete nil)
        (local-available nil) (current-omissions :not-collected))
    (labels ((report-status (status dependency-status)
               (snapshot-value
                (list :name name :status status :reasons (reverse reasons)
                      :dependency-status dependency-status
                      :installed-digest (when entry (installation-digest entry))
                      :installed-digest-complete (when entry (installation-digest-complete-p entry))
                      :current-digest current-digest :current-digest-complete current-complete
                      :installed-digest-omissions
                      (if entry (installation-digest-omissions entry) :not-collected)
                      :current-digest-omissions current-omissions
                      :digest-exclusions
                      (if entry (installation-digest-exclusions entry) :not-collected)
                      :scopes (when entry (installation-scopes entry)))))
             (mark-stale (reason) (setf stale t) (push reason reasons)))
      (unless (typep entry 'installation)
        (setf entry nil reasons '(:not-installed))
        (return-from instrumentation-status (report-status :not-installed :indeterminate)))
      (unless (and (fboundp name) (eq (fdefinition name) (installation-wrapper entry)))
        (mark-stale :external-redefinition))
      (unless (eq registry (installation-registry entry)) (mark-stale :registry-changed))
      (handler-case
          (let ((contract (registry-find-function-spec registry name)))
            (cond
              ((null contract)
               (mark-stale :definition-missing)
               (setf current-omissions
                     (list (list :kind :missing-definition :path nil :target name
                                 :reason :not-registered))))
              (t
               (unless (eq contract (installation-contract entry))
                 (mark-stale :definition-replaced))
               (unless (eq (function-spec-precondition-function contract)
                           (installation-precondition entry))
                 (mark-stale :precondition-changed))
               (unless (eq (function-spec-postcondition-function contract)
                           (installation-postcondition entry))
                 (mark-stale :postcondition-changed))
               (multiple-value-bind (declaration available) (local-declaration-snapshot contract)
                 (setf local-available (and available (installation-declaration-available-p entry)))
                 (when (and local-available
                            (not (same-value-p declaration (installation-declaration entry))))
                   (mark-stale :declaration-changed)))
               (multiple-value-setq (current-digest current-complete current-omissions)
                 (definition-digest contract :registry registry)))))
        (error ()
          (setf current-complete nil
                current-omissions
                (list (list :kind :inspection-error :path nil :target name
                            :reason :inspection-error)))
          (push :inspection-error reasons)))
      (let* ((complete (and (installation-digest-complete-p entry) current-complete))
             (dependency-status
               ;; A full digest includes the local declaration. Attribute its
               ;; difference to dependencies only when that declaration is equal.
               (if (and complete local-available
                        (not (member :declaration-changed reasons))
                        (not (member :registry-changed reasons)))
                   (if (equal current-digest (installation-digest entry)) :unchanged :changed)
                   :indeterminate)))
        (unless (and complete local-available)
          (push :incomplete-definition reasons))
        (report-status (cond (stale :stale)
                             ((and complete local-available) :current)
                             (t :indeterminate))
                       dependency-status)))))

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

(defun refresh-instrumentation (name &key (registry nil registry-p) (scopes nil scopes-p))
  "Rebuild an active installation against its original target without stacking wrappers.
Omitted REGISTRY and SCOPES retain the installation's settings. Refuse external
redefinitions and missing installations, preserving the function and table."
  (check-type name symbol)
  (let ((entry (gethash name *instrumented-functions*)))
    (unless (typep entry 'installation)
      (error 'unsupported-instrumentation-target :name name :reason :not-installed))
    (unless (and (fboundp name) (eq (fdefinition name) (installation-wrapper entry)))
      (error 'unsupported-instrumentation-target :name name :reason :external-redefinition))
    (install-contract name
                      :registry (if registry-p registry (installation-registry entry))
                      :scopes (if scopes-p scopes (installation-scopes entry)))))

(defun uninstrument-function (name)
  "Restore NAME's original function only if its installed wrapper is still current.
Return true when restored, NIL otherwise. Forget stale entries without overwriting
a later redefinition or undoing FMAKUNBOUND."
  (let ((entry (gethash name *instrumented-functions*)))
    (prog1 (when (instrumented-function-p name)
             (setf (fdefinition name) (installation-original entry))
             t)
      (remhash name *instrumented-functions*))))
