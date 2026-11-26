;;;; src/function-spec-definition.lisp
;;;;
;;;; Function and case declarations, including the invariants enforced at registration.

(defpackage #:cl-spec/src/function-spec-definition
  (:use #:cl)
  (:import-from #:cl-spec/src/state-frame-definition
                #:state-frame #:state-frame-variables)
  (:import-from #:cl-spec/src/guard-references
                #:guard-free-variables #:guard-return-reference #:return-value-symbol)
  (:import-from #:cl-spec/src/utils/source-location
                #:source-location-package)
  (:import-from #:cl-spec/src/fixture
                #:trial-fixture)
  (:import-from #:cl-spec/src/utils/lists
                #:finite-list-p)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots
                #:call-with-definition-rollback #+sbcl #:call-with-class-update-rollback
                #:finite-definition-form-p #:definition-keyword-plist-p)
  (:import-from #:cl-spec/src/conditions
                #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/utils/arguments
                #:check-argument)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:check-registry #:registry-register-function-spec)
  (:import-from #:cl-spec/src/ir
                #:tuple-spec #:tuple-spec-element-specs)
  (:import-from #:cl-spec/src/call-schema
                #:make-call-layout #:make-return-schema #:normalize-return-declaration
                #:return-values-spec #:call-declaration-variables #:normalize-call-declarations
                #:call-layout-required-only-p #:call-layout-bindings #:argument-binding-spec
                #:call-arguments-spec)
  (:export
           #:make-function-case-with-guard #:function-spec-fixture #:function-spec
           #:function-spec-name #:function-spec-argument-specs
           #:function-spec-argument-generator #:function-spec-argument-schema
           #:function-spec-call-layout #:function-spec-return-schema #:function-spec-return-spec
           #:function-spec-signal-spec #:function-spec-preconditions
           #:function-spec-postconditions #:function-spec-post-value-variables
           #:validate-post-value-variables #:function-spec-precondition-function
           #:function-spec-postcondition-function #:function-spec-documentation
           #:function-spec-source-form #:function-spec-source-location #:function-spec-metadata
           #:function-spec-cases #:function-spec-capture-bindings
           #:function-spec-capture-functions #:function-spec-state-frame
           #:function-spec-state-postconditions #:function-spec-state-postcondition-function
           #:function-case #:function-case-name #:function-case-documentation
           #:function-case-when-forms #:function-case-when-function #:function-case-outcome-kind
           #:function-case-outcome-spec #:function-case-postconditions
           #:function-case-postcondition-function #:function-case-post-value-variables
           #:function-case-state-postconditions #:function-case-state-postcondition-function
           #:function-case-source-form #:register-function-spec #:state-observing-contract-p))

(in-package #:cl-spec/src/function-spec-definition)

(defvar *case-owner* nil
  "Contract whose input and capture bindings apply during validation of one of its cases.")

(defvar *case-guard-analysis* nil
  "The DSL guard's source, predicate and variable references in its lexical environment.")

(defun make-function-case-with-guard (form predicate references &rest initargs)
  "Construct a DSL case with the guard references observed in its macroexpansion environment."
  (let ((*case-guard-analysis* (list (copy-tree form) predicate references)))
    (apply #'make-instance 'function-case :when-forms (list form) :when-function predicate
           initargs)))

(defclass function-case ()
  ((owners :initform (make-hash-table :test #'eq :size 1
                                      #+(or sbcl ecl abcl clasp) :weakness
                                      #+(or ccl clisp) :weak
                                      #+(or sbcl ecl abcl clasp ccl clisp) :key)
            :reader case-owners
            :documentation "Contracts whose variable bindings constrain edits to this case.")
   (guard-analysis :initform *case-guard-analysis* :reader case-guard-analysis
                   :documentation "Lexical references, original source and compiled guard.")
   (name :initarg :name
         :initform nil
         :reader function-case-name
         :documentation "Keyword naming this case, unique within its contract.
Names are declarations, not search keys: selection is by condition, and the name
exists so a result, a failure identity and a report can say which behaviour was
required.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader function-case-documentation
                         :documentation "Docstring of the case, or NIL.")
   (when-forms :initarg :when-forms
              :initform nil
              :reader function-case-when-forms
              :documentation "The :WHEN form as a one-element list, or NIL when absent.

A list, like the contract's :PRE forms, so that the form NIL -- an allowed
condition that never selects the case -- is distinguishable from no condition at
all; a bare NIL slot could not tell them apart and would let a guard run with no
source for introspection or the digest.")
   (when-function :initarg :when-function
                  :initform nil
                  :reader function-case-when-function
                  :documentation "Compiled predicate over the contract's argument bindings,
true when the input selects this case.

Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.  It is
evaluated once per admitted trial, for every case, so that duplicates are
observed rather than hidden behind first-match short-circuiting.")
   (outcome-kind :initarg :outcome-kind
                 :initform nil
                 :reader function-case-outcome-kind
                 :documentation ":RETURNS or :SIGNALS, the one outcome this case requires.")
   (outcome-spec :initarg :outcome-spec
                 :initform nil
                 :reader function-case-outcome-spec
                 :documentation "The normalized primary return spec for :RETURNS, or the
normalized required-condition spec for :SIGNALS.")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-case-postconditions
                   :documentation "The case's :POST or :POST-VALUES forms, or NIL.
Refused on a :SIGNALS case in this version.")
   (postcondition-function :initarg :postcondition-function
                           :initform nil
                           :reader function-case-postcondition-function
                           :documentation "Compiled case postcondition, or NIL.
To identify a failed form for shrinking, return
\(values nil index :cl-spec-post-form-failure) exactly as the contract-level
postcondition does.")
   (post-value-variables :initarg :post-value-variables
                         :initform :primary
                         :reader function-case-post-value-variables
                         :documentation ":PRIMARY, or the explicit return names of :POST-VALUES.")
   (state-postconditions :initarg :state-postconditions
                         :initform nil
                         :reader function-case-state-postconditions
                         :documentation "The case's :STATE-POST forms, or NIL.
A separate clause from :POST and :POST-VALUES: it runs only after the case's
outcome contract passed, and it may accompany :SIGNALS.")
   (state-postcondition-function :initarg :state-postcondition-function
                                 :initform nil
                                 :reader function-case-state-postcondition-function
                                 :documentation "Compiled case state-post, or NIL.
Sees the arguments and the contract's capture values.  To identify a failed
form, return (values nil index :cl-spec-state-post-form-failure).")
   (source-form :initarg :source-form
                :initform nil
                :reader function-case-source-form
                :documentation "The whole case form as written."))
  (:documentation "One named input condition and the outcome it requires.

A FUNCTION-SPEC holds an ordered list of these when it declares :CASES.  The case
rules its own outcome; the contract's common :ARGS, :ARGS-GENERATOR and :PRE stay
on the contract and apply to every case.  A case is not a separate public
function spec and is never registered under its own name."))

(defparameter *function-case-slot-names*
  '(name documentation-string when-forms when-function outcome-kind outcome-spec
    postconditions postcondition-function post-value-variables
    state-postconditions state-postcondition-function source-form)
  "Every slot of FUNCTION-CASE, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod definition-validation-slots append ((case function-case))
  (copy-list *function-case-slot-names*))

(defmethod shared-initialize :around ((case function-case) slot-names &rest initargs)
  "Validate a case and restore its participating slots on refusal.

A clause's forms and its compiled predicate must change together, on
construction and on reinitialization alike: new text with the old predicate (or
the reverse) would run one while introspection and the digest reported the
other, which is the failure the contract-level :PRE and :POST already refuse.  A
:post-values change is that failure seen from the return bindings, so it needs
new post forms and a new compiled predicate as well."
  (flet ((supplied (key)
           (loop for (k) on initargs by #'cddr thereis (eq k key))))
    (dolist (pair '((:when-forms :when-function)
                    (:postconditions :postcondition-function)
                    (:state-postconditions :state-postcondition-function)))
      (unless (eq (not (supplied (first pair))) (not (supplied (second pair))))
        (error 'invalid-function-spec-form :form pair
               :reason "case clause forms and compiled function must change together")))
    (when (and (supplied :post-value-variables)
               (slot-boundp case 'post-value-variables)
               (not (equal (getf initargs :post-value-variables)
                           (function-case-post-value-variables case)))
               (not (and (supplied :postconditions) (supplied :postcondition-function))))
      (error 'invalid-function-spec-form
             :form initargs
             :reason "Case post-value binding changes require new forms and a compiled predicate.")))
  (call-with-definition-rollback
   case (lambda () (apply #'call-next-method case slot-names initargs))))

(defmethod shared-initialize :after ((case function-case) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition case)
  (let ((owners (case-owners case)) (attached nil) (detached-p nil))
    (maphash (lambda (owner present)
               (declare (ignore present))
               (if (and owner (member case (function-spec-cases owner)))
                   (let ((*case-owner* owner))
                     (validate-case-guard case)
                     (push owner attached))
                   (setf detached-p t)))
             owners)
    ;; ECL 24.5.10 REMHASH can leave a surviving weak key unwrapped.
    ;; Rebuild membership after the traversal and successful validation.
    (when detached-p
      (clrhash owners)
      (dolist (owner attached) (setf (gethash owner owners) t)))))

(defun validate-case-guard (case)
  "Check this case's visible guard references against its output and current input bindings."
  (let* ((form (first (function-case-when-forms case)))
         (post-values (function-case-post-value-variables case))
         (variables (when *case-owner*
                      (call-declaration-variables (function-spec-argument-specs *case-owner*))))
         (parameters (append variables
                             (when *case-owner*
                               (mapcar #'first (function-spec-capture-bindings *case-owner*)))))
         (analysis (case-guard-analysis case)))
    ;; Before ownership is known, RESULT could be an ordinary input parameter.
    (when (or *case-owner* (consp post-values))
      (let* ((references
               (if (and analysis (eq (second analysis) (function-case-when-function case))
                        (equal (first analysis) form))
                   (third analysis)
                   (guard-free-variables form nil parameters :expand-symbols *case-owner*)))
             (primary (when *case-owner* (contract-result-symbol *case-owner* variables)))
             (name (guard-return-reference references parameters
                                           (unless (eq post-values :primary) post-values)
                                           :primary primary)))
        (when name
          (error 'invalid-function-spec-form :form (list :when form)
                 :reason (format nil ":when runs before the call, so it cannot refer to ~S"
                                 name)))))))

(defmethod validate-definition ((case function-case))
  "Refuse a case the checker could not honour, and normalize what can be.

The same invariant the contract applies to :PRE, :POST and :RETURNS holds per
case: a clause's forms and its compiled predicate are present together or not at
all, because a stored form cannot be run without runtime EVAL (§60) and a
predicate without its form would run while introspection reported no such clause."
  (flet ((refuse (reason)
           (error 'invalid-function-spec-form
                  :form (function-case-source-form case) :reason reason))
         (half (value function reason)
           ;; Exactly one half present: both absent is a case with no such clause.
           (cond ((and value (null function)) reason)
                 ((and function (null value)) reason))))
    (unless (keywordp (function-case-name case))
      (refuse "a case name must be a keyword"))
    (unless (typep (function-case-documentation case) '(or null string))
      (refuse "a case docstring must be NIL or a string"))
    (unless (and (finite-list-p (function-case-when-forms case))
                 (= 1 (length (function-case-when-forms case))))
      (refuse "a case requires exactly one :when form"))
    (unless (finite-definition-form-p (function-case-when-forms case))
      (refuse "a :when form must be an acyclic finite form"))
    (when (half (function-case-when-forms case) (function-case-when-function case)
                "a case :when form and compiled predicate must change together")
      (refuse "a case :when form and compiled predicate must change together"))
    (unless (functionp (function-case-when-function case))
      (refuse "a case :when predicate must be a function"))
    (unless (member (function-case-outcome-kind case) '(:returns :signals))
      (refuse "a case requires exactly one of :returns and :signals"))
    (unless (function-case-outcome-spec case)
      (refuse "a case outcome spec must be present"))
    (unless (finite-list-p (function-case-postconditions case))
      (refuse "case postconditions must be a finite proper list"))
    (when (half (function-case-postconditions case) (function-case-postcondition-function case)
                "case post forms and compiled predicate must change together")
      (refuse "case post forms and compiled predicate must change together"))
    (when (and (function-case-postconditions case)
               (not (functionp (function-case-postcondition-function case))))
      (refuse "a case postcondition predicate must be a function"))
    (when (and (eq :signals (function-case-outcome-kind case))
               (function-case-postconditions case))
      (refuse "a :signals case cannot carry :post or :post-values in this version"))
    (unless (finite-list-p (function-case-state-postconditions case))
      (refuse "case state-post forms must be a finite proper list"))
    (when (half (function-case-state-postconditions case)
                (function-case-state-postcondition-function case)
                "case state-post forms and compiled predicate must change together")
      (refuse "case state-post forms and compiled predicate must change together"))
    (when (and (function-case-state-postconditions case)
               (not (functionp (function-case-state-postcondition-function case))))
      (refuse "a case state-post predicate must be a function"))
    (unless (finite-definition-form-p (function-case-source-form case))
      (refuse "a case source form must be an acyclic finite form"))
    (let ((kind (function-case-outcome-kind case))
          (spec (function-case-outcome-spec case)))
      (setf (slot-value case 'outcome-spec)
            (if (eq kind :returns)
                (normalize-return-declaration spec)
                (normalize-spec-form spec))))
    (unless (eq :primary (function-case-post-value-variables case))
      (unless (and (typep (function-case-outcome-spec case) 'return-values-spec)
                   (function-case-postconditions case)
                   (function-case-postcondition-function case))
        (refuse "explicit post-value bindings require fixed returns and a post predicate"))
      (validate-post-value-variables
       (function-case-post-value-variables case)
       (length (tuple-spec-element-specs (function-case-outcome-spec case)))
       (when *case-owner*
         (call-declaration-variables (function-spec-argument-specs *case-owner*))))))
  (validate-case-guard case)
  case)

(defclass function-spec ()
  ((fixture :initarg :fixture :initform nil :reader function-spec-fixture
            :documentation "Explicit recipe fixture, or NIL.")
   (state-frame :initarg :state-frame :initform nil :reader function-spec-state-frame
                :documentation "Observed state and declared changes for this contract.")
   (call-layout-cache :initform nil)
   (call-layout-declarations :initform nil)
   (call-layout-bindings-snapshot :initform nil)
   (name :initarg :name
         :initform nil
         :reader function-spec-name
         :documentation "Package-qualified symbol naming the specified function.")
   (argument-specs :initarg :argument-specs
                   :initform nil
                   :reader function-spec-argument-specs
                   :documentation "Required (PARAMETER SPEC) pairs followed optionally by
&OPTIONAL (PARAMETER SPEC [SUPPLIED-P]) and &KEY ((:KEY PARAMETER) SPEC [SUPPLIED-P])
declarations. &REST (PARAMETER WHOLE-LIST-SPEC) captures the raw remaining tail
before &KEY. A terminal &ALLOW-OTHER-KEYS permits extra keys. SPEC is normalized
to Semantic IR. Parameter and supplied-variable names are unique. Omitted values
bind to NIL in predicates without evaluating target defaults.")
   (argument-generator :initarg :argument-generator
                       :initform nil
                       :reader function-spec-argument-generator
                       :documentation "Name of a registered no-argument generator returning
the entire positional argument list, or NIL for independent argument generation.
Each draw is checked against the argument specs before preconditions or the target.")
   (signal-spec :initarg :signal-spec
                :initform nil
                :reader function-spec-signal-spec
                :documentation "Normalized spec required of an error escaping the target,
or NIL for an ordinary return contract. Normal return violates a signal contract.
Mutually exclusive with return-spec and postconditions. PROGRAM-ERROR and
UNDEFINED-FUNCTION are reserved execution failures, never accepted by this spec.")
   (return-spec :initarg :return-spec
                :initform nil
                :reader function-spec-return-spec
                :documentation "Semantic IR object the return value must
satisfy, from :RETURNS, or NIL when the contract names none.")
   (preconditions :initarg :preconditions
                  :initform nil
                  :reader function-spec-preconditions
                  :documentation "The :PRE forms as written, kept for reading
(specification §19).  PRECONDITION-FUNCTION is what actually runs.")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-spec-postconditions
                   :documentation "The :POST forms as written, kept for reading.
POSTCONDITION-FUNCTION is what actually runs.")
   (precondition-function :initarg :precondition-function
                          :initform nil
                          :reader function-spec-precondition-function
                          :documentation "Compiled predicate over the parameters,
true when every :PRE form holds, or NIL when the contract has no :PRE.
DEFSPEC-FUNCTION compiles it so that a refusal returns
\(values nil index :cl-spec-pre-form-failure), where INDEX is the zero-based
position of the first :PRE form that did not hold; a hand-built predicate may
return a plain NIL, and then no form is named.

Compiled at macroexpansion time rather than interpreted at check time, because
§60 forbids runtime EVAL and a stored form cannot otherwise be run.")
   (post-value-variables :initarg :post-value-variables
                        :initform :primary
                        :reader function-spec-post-value-variables
                        :documentation "Use :PRIMARY for legacy post predicates, or an explicit
list of return names. Explicit predicates receive the full values list first.")
   (postcondition-function :initarg :postcondition-function
                           :initform nil
                           :reader function-spec-postcondition-function
                           :documentation "Compiled predicate over the return
value followed by the parameters, true when every :POST form holds, or NIL when
the contract has no :POST. To identify a failed form for shrinking, return
(values nil index :cl-spec-post-form-failure), where INDEX is its zero-based
position in POSTCONDITIONS. A one-value predicate remains valid, but its failures
have unknown form identity and cannot be accepted as shrink reductions.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader function-spec-documentation
                         :documentation "Docstring of the contract, or NIL.

This is the contract's own prose, not the function's: it says what the contract
claims, which is what an agent asking \"what may I pass here\" needs.")
   (source-form :initarg :source-form
                :initform nil
                :reader function-spec-source-form
                :documentation "The whole DEFSPEC-FUNCTION form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader function-spec-source-location
                    :documentation "Source location plist, or NIL.")
   (case-guard-package :initform *package*
                       :reader function-spec-case-guard-package
                       :documentation "Construction package used by guards without source metadata.")
   (metadata :initarg :metadata
             :initform nil
             :reader function-spec-metadata
             :documentation "Arbitrary plist for callers and future extensions.")
   (cases :initarg :cases
          :initform nil
          :reader function-spec-cases
          :documentation "Ordered FUNCTION-CASE objects, or NIL for a case-less contract.

When present, exactly one case is selected per admitted trial and its own
:RETURNS or :SIGNALS outcome judges the invocation.  CASE-SELECTION is exclusive;
a case is not a priority rule.  :CASES is exclusive with the contract-level
:RETURNS, :SIGNALS, :POST and :POST-VALUES: there is no inherited common outcome
to override.")
   (capture-bindings :initarg :capture-bindings
                     :initform nil
                     :reader function-spec-capture-bindings
                     :documentation "Ordered (NAME FORM) pairs observed before the call, or NIL.
Each form's primary value is bound to NAME for the following forms, the case
guards, the postconditions and the state-post.  A capture variable is not a
target argument: the argument schema, generator and actual call are unchanged.")
   (capture-functions :initarg :capture-functions
                      :initform nil
                      :reader function-spec-capture-functions
                      :documentation "One compiled function per capture binding, aligned by position.
Binding i is called with the argument values followed by capture values 0..i-1,
so the forms have LET* visibility without runtime evaluation.  Present exactly
when CAPTURE-BINDINGS is, and supplied together with it.")
   (state-postconditions :initarg :state-postconditions
                         :initform nil
                         :reader function-spec-state-postconditions
                         :documentation "The case-less :STATE-POST forms, or NIL.
Runs only after the outcome contract passed, and only for a contract without
:CASES; a case-carrying contract carries the clause inside each case instead.")
   (state-postcondition-function :initarg :state-postcondition-function
                                 :initform nil
                                 :reader function-spec-state-postcondition-function
                                 :documentation "Compiled case-less state-post, or NIL.
Sees the arguments and the capture values, and no implicit RESULT, condition or
raw outcome.  To identify a failed form, return
(values nil index :cl-spec-state-post-form-failure)."))
  (:documentation "A contract attached to an existing function by name.

The function is never redefined, so an existing codebase adopts cl-spec one
function at a time (specification §3.2)."))

(defparameter *function-spec-slot-names*
  '(fixture state-frame name argument-specs argument-generator return-spec signal-spec preconditions postconditions
    precondition-function postcondition-function post-value-variables documentation-string
    source-form source-location case-guard-package metadata cases
    capture-bindings capture-functions state-postconditions state-postcondition-function
    call-layout-cache call-layout-declarations call-layout-bindings-snapshot)
  "Every slot of FUNCTION-SPEC, for the rollback in SHARED-INITIALIZE :AROUND.")

(defmethod definition-validation-slots append ((contract function-spec))
  (copy-list *function-spec-slot-names*))

#+sbcl
(defmethod update-instance-for-different-class :around
    ((previous standard-object) (current function-spec) &rest initargs)
  (declare (ignore initargs))
  (call-with-class-update-rollback previous current (lambda () (call-next-method))))

(defmethod shared-initialize :around ((contract function-spec) slot-names &rest initargs)
  "Validate paired clauses and restore all participating slots on refusal."
  (flet ((supplied (key)
           (loop for (k) on initargs by #'cddr thereis (eq k key))))
    (when (and (supplied :post-value-variables)
               (slot-boundp contract 'post-value-variables)
               (not (equal (getf initargs :post-value-variables)
                           (function-spec-post-value-variables contract)))
               (not (and (supplied :postconditions) (supplied :postcondition-function))))
      (error 'invalid-function-spec-form :form initargs
             :reason "Post-value binding changes require new forms and a compiled predicate."))
    (dolist (pair '((:preconditions :precondition-function)
                    (:postconditions :postcondition-function)
                    (:capture-bindings :capture-functions)
                    (:state-postconditions :state-postcondition-function)))
      (unless (eq (not (supplied (first pair))) (not (supplied (second pair))))
        (error 'invalid-function-spec-form :form pair
               :reason "clause forms and compiled function must change together")))
    ;; A capture list is part of every compiled predicate that reads it: the
    ;; guard, post and state-post lambdas take the capture values as trailing
    ;; parameters, so a new list with the old closures would call them with the
    ;; wrong arity.  Require the dependent clauses to change with it.
    (when (and (supplied :capture-bindings)
               (slot-boundp contract 'capture-bindings)
               (not (equal (getf initargs :capture-bindings)
                           (function-spec-capture-bindings contract))))
      (dolist (key (append (list :capture-functions)
                           (when (or (function-spec-postconditions contract)
                                     (function-spec-postcondition-function contract))
                             (list :postcondition-function))
                           (when (or (function-spec-state-postconditions contract)
                                     (function-spec-state-postcondition-function contract))
                             (list :state-postcondition-function))
                           (when (function-spec-cases contract)
                             (list :cases))))
        (unless (supplied key)
          (error 'invalid-function-spec-form :form initargs
                 :reason (format nil "changing :capture-bindings requires new ~S ~
and the compiled predicates that read the capture values" key))))))
  (call-with-definition-rollback
   contract (lambda () (apply #'call-next-method contract slot-names initargs))))

(defun validate-post-value-variables (names count arguments)
  "Require COUNT unique bindable value names distinct from ARGUMENTS and RESULT."
  (unless (and (finite-list-p names) (= (length names) count)
               (every (lambda (name)
                        (and name (symbolp name) (not (constantp name))
                             (not (and (plusp (length (symbol-name name)))
                                       (char= #\& (char (symbol-name name) 0))))
                             (not (string-equal "RESULT" (symbol-name name)))
                             (not (member name arguments))))
                      names)
               (= (length names) (length (remove-duplicates names :test #'eq))))
    (error 'invalid-function-spec-form :form names
           :reason "Post-value names must match fixed returns and be unique, bindable variables."))
  names)

(defun contract-result-symbol (contract variables)
  "Resolve the RESULT name reserved by a case guard in CONTRACT."
  (let* ((location (function-spec-source-location contract))
         (source-package (and (definition-keyword-plist-p location)
                              (source-location-package location))))
    (return-value-symbol variables
                         (or (and (stringp source-package) (find-package source-package))
                             (function-spec-case-guard-package contract)))))

(defun validate-capture-bindings (contract)
  "Refuse capture declarations the checker could not honour, and return them.

The DSL applies the same rules at macroexpansion time; enforcing them here as
well covers programmatic construction, reinitialization and registry
registration, which all reach the slots without going through the macro.  A
capture name is rejected when it collides with an argument or supplied-p
variable, the return-value binding RESULT, or an explicit :POST-VALUES name,
because the compiled predicates bind all of those in one lambda list."
  (let ((bindings (function-spec-capture-bindings contract))
        (functions (function-spec-capture-functions contract)))
    (flet ((refuse (reason)
             (error 'invalid-function-spec-form :form bindings :reason reason))
           (explicit (names)
             (unless (eq :primary names) names)))
      (unless (finite-list-p bindings)
        (refuse "capture bindings must be a finite proper list"))
      (unless (finite-list-p functions)
        (refuse "capture functions must be a finite proper list"))
      (let ((names '()))
        (dolist (binding bindings)
          (unless (and (consp binding) (finite-list-p binding) (= 2 (length binding)))
            (refuse "each capture binding must be an exact (NAME FORM) pair"))
          (let ((name (first binding)))
            (unless (and name (symbolp name) (not (keywordp name)) (not (constantp name))
                         (not (and (plusp (length (symbol-name name)))
                                   (char= #\& (char (symbol-name name) 0)))))
              (refuse "a capture name must be a bindable non-constant, non-keyword variable"))
            (when (member name names)
              (refuse "capture names must be unique"))
            (push name names)))
        (unless (and (= (length functions) (length bindings))
                     (every #'functionp functions))
          (refuse "capture bindings and compiled capture functions must align one to one"))
        (let* ((variables (call-declaration-variables (function-spec-argument-specs contract)))
               (result (return-value-symbol variables))
               (contract-values (explicit (function-spec-post-value-variables contract)))
               (case-values (loop for case in (function-spec-cases contract)
                                  append (explicit
                                          (function-case-post-value-variables case)))))
          (dolist (name (reverse names))
            (cond
              ((member name variables)
               (refuse "a capture name cannot collide with an argument or supplied-p variable"))
              ((and result (eq name result))
               (refuse "a capture name cannot collide with the return-value binding RESULT"))
              ((or (member name contract-values) (member name case-values))
               (refuse "a capture name cannot collide with a :post-values name")))))))
    bindings))

(defun state-observing-contract-p (contract)
  "Return true when CONTRACT declares state observations or an explicit fixture.

Without a fixture, state observation does not restore initial state, so shrinking,
replay of a past result and counterexample artifacts remain unsupported.
The decision is structural: a pure-looking use is not exempted by inspecting
the target or the predicate bodies."
  (or (function-spec-fixture contract)
      (function-spec-state-frame contract)
      (function-spec-capture-bindings contract)
      (function-spec-state-postconditions contract)
      (some (lambda (case) (function-case-state-postconditions case))
            (function-spec-cases contract))))

(defmethod validate-definition ((contract function-spec))
  "Refuse a contract that could not be honoured, and normalize what can be.

Enforced here rather than in CHECK-FUNCTION because the class and
REGISTER-FUNCTION-SPEC are both public: a contract can be built without the
DSL, and every consumer -- the checker, FUNCTION-SPEC-DATA, a future printer --
would otherwise have to re-derive the same invariants or be handed an object
the others rejected.

On SHARED-INITIALIZE rather than INITIALIZE-INSTANCE, because MAKE-INSTANCE is
not the only standard way to fill these slots: REINITIALIZE-INSTANCE and
CHANGE-CLASS reach them too, and a check that covers only the first lets the
second put back exactly the states it exists to refuse.

Three invariants:

A clause's forms and its compiled predicate are present together or not at all.
Forms alone cannot be run -- §60 forbids runtime EVAL, so the predicate cannot
be recovered from them -- and the checker would report :PASSED for a claim it
ignored.  A predicate alone is the same failure seen from the other side: it
runs, so inputs are refused and results judged, while FUNCTION-SPEC-DATA
reports the contract as having no such clause.

A parameter is named once.  §14's counterexample is a {name value} plist, and
one built over a name bound twice is not one: GETF answers with the first
value and the second cannot be recovered, so the counterexample reported for a
failure cannot reproduce it.

Spec designators are normalized rather than refused, because unlike a
predicate they can be recovered: NORMALIZE-SPEC-FORM is pure, and returns an
already-normalized spec unchanged, so the DSL's output passes through
untouched.  Without this a contract built through the class reached the
generator as a bare symbol and signalled NO-APPLICABLE-METHOD."
  (flet ((refuse (form reason)
           (error 'invalid-function-spec-form :form form :reason reason))
         (half (forms-initarg function-initarg forms predicate)
           (cond ((and forms (null predicate))
                  (format nil "~A was given without ~A, and a compiled ~
predicate cannot be recovered from the forms"
                          forms-initarg function-initarg))
                 ((and predicate (null forms))
                  (format nil "~A was given without ~A, so the predicate ~
would run while introspection reported no such clause"
                          function-initarg forms-initarg)))))
    (when (function-spec-fixture contract)
      (unless (typep (function-spec-fixture contract) 'trial-fixture)
        (refuse :fixture "expected a trial-fixture"))
      (when (function-spec-argument-generator contract)
        (refuse :fixture "fixture and argument-generator are exclusive"))
      (validate-definition (function-spec-fixture contract)))
    (unless (typep (function-spec-state-frame contract) '(or null state-frame))
      (refuse :state-frame "expected a compiled state frame"))
    (unless (and (symbolp (function-spec-name contract))
                 (function-spec-name contract)
                 (not (keywordp (function-spec-name contract)))
                 (not (constantp (function-spec-name contract))))
      (refuse (function-spec-name contract) "expected a nonconstant function name"))
    (unless (and (finite-list-p (function-spec-argument-specs contract))
                 (finite-list-p (function-spec-preconditions contract))
                 (finite-list-p (function-spec-postconditions contract))
                 (finite-list-p (function-spec-capture-bindings contract))
                 (finite-list-p (function-spec-capture-functions contract))
                 (finite-list-p (function-spec-state-postconditions contract))
                 (finite-list-p (function-spec-source-form contract)))
      (refuse nil "arguments, clause forms and source must be finite proper lists"))
    (unless (every #'finite-definition-form-p
                   (list (function-spec-argument-specs contract)
                         (function-spec-return-spec contract) (function-spec-signal-spec contract)
                         (function-spec-preconditions contract)
                         (function-spec-postconditions contract)
                         (function-spec-capture-bindings contract)
                         (function-spec-state-postconditions contract)
                         (function-spec-source-form contract)))
      (refuse nil "definition forms must be acyclic"))
    (dolist (predicate (list (function-spec-precondition-function contract)
                             (function-spec-postcondition-function contract)
                             (function-spec-state-postcondition-function contract)))
      (unless (or (null predicate) (functionp predicate))
        (refuse nil "compiled clause predicates must be functions")))
    (unless (typep (function-spec-documentation contract) '(or null string))
      (refuse nil "documentation must be NIL or a string"))
    (dolist (plist (list (function-spec-metadata contract)
                         (function-spec-source-location contract)))
      (unless (definition-keyword-plist-p plist)
        (refuse nil "metadata and source-location must be keyword plists without duplicates")))
    (let ((pre (half ":preconditions" ":precondition-function"
                     (function-spec-preconditions contract)
                     (function-spec-precondition-function contract)))
          (post (half ":postconditions" ":postcondition-function"
                      (function-spec-postconditions contract)
                      (function-spec-postcondition-function contract)))
          (state (half ":state-postconditions" ":state-postcondition-function"
                       (function-spec-state-postconditions contract)
                       (function-spec-state-postcondition-function contract))))
      (when pre
        (refuse (or (function-spec-preconditions contract)
                    (function-spec-precondition-function contract))
                pre))
      (when post
        (refuse (or (function-spec-postconditions contract)
                    (function-spec-postcondition-function contract))
                post))
      (when state
        (refuse (or (function-spec-state-postconditions contract)
                    (function-spec-state-postcondition-function contract))
                state)))
    ;; Cases are validated here, not only at their own construction, because a
    ;; contract can be built with case objects that were made earlier and their
    ;; :post-values names can only be checked against this contract's arguments.
    (let ((cases (function-spec-cases contract)))
      (unless (and (finite-list-p cases)
                   (every (lambda (case) (typep case 'function-case)) cases))
        (refuse cases "cases must be a finite proper list of FUNCTION-CASE objects"))
      (let ((names (mapcar #'function-case-name cases)))
        (unless (every #'keywordp names)
          (refuse cases "case names must be keywords"))
        (unless (= (length names) (length (remove-duplicates names :test #'eq)))
          (refuse cases "case names must be unique within a contract")))
      (when (and cases
                 (or (function-spec-return-spec contract)
                     (function-spec-signal-spec contract)
                     (function-spec-postconditions contract)
                     (function-spec-postcondition-function contract)
                     (function-spec-state-postconditions contract)
                     (function-spec-state-postcondition-function contract)))
        (refuse cases
                (format nil ":cases cannot be combined with a top-level :returns, ~
                             :signals, :post, :post-values or :state-post; there is no ~
                             inherited common outcome")))
      (let ((*case-owner* contract))
        (dolist (case cases) (validate-definition case))))
    ;; Capture is validated after the cases, because a capture name must not
    ;; collide with a case-level :post-values name either.
    (validate-capture-bindings contract)
    (setf (slot-value contract 'argument-specs)
          (normalize-call-declarations (function-spec-argument-specs contract)))
    (let ((frame (function-spec-state-frame contract)))
      (when (and frame
                 (not (equal (state-frame-variables frame)
                             (append (call-declaration-variables
                                      (function-spec-argument-specs contract))
                                     (mapcar #'first
                                             (function-spec-capture-bindings contract))))))
        (refuse :state-frame "changed bindings require a newly compiled frame")))
    (let ((generator (function-spec-argument-generator contract)))
      (unless (or (null generator)
                  (and (symbolp generator) (not (keywordp generator))))
        (refuse generator ":argument-generator must be NIL or a registered generator name")))
    (let ((signals (function-spec-signal-spec contract))
          (returns (function-spec-return-spec contract)))
      (when (and signals (or returns (function-spec-postconditions contract)
                             (function-spec-postcondition-function contract)))
        (refuse signals ":signal-spec cannot coexist with return-spec or postconditions"))
      (when signals
        (setf (slot-value contract 'signal-spec) (normalize-spec-form signals)))
      (when returns
        (setf (slot-value contract 'return-spec) (normalize-return-declaration returns)))))
  (unless (eq :primary (function-spec-post-value-variables contract))
    (unless (and (typep (function-spec-return-spec contract) 'return-values-spec)
                 (function-spec-postconditions contract)
                 (function-spec-postcondition-function contract))
      (error 'invalid-function-spec-form :form (function-spec-post-value-variables contract)
             :reason "Explicit post-value bindings require fixed returns and a post predicate."))
    (validate-post-value-variables
     (function-spec-post-value-variables contract)
     (length (tuple-spec-element-specs (function-spec-return-spec contract)))
     (call-declaration-variables (function-spec-argument-specs contract))))
  (setf (slot-value contract 'call-layout-cache) nil
        (slot-value contract 'call-layout-declarations) nil
        (slot-value contract 'call-layout-bindings-snapshot) nil)
  (dolist (case (function-spec-cases contract))
    (setf (gethash contract (case-owners case)) t))
  contract)

(defmethod shared-initialize :after ((contract function-spec) slot-names &key)
  (declare (ignore slot-names))
  (validate-definition contract))

(defun function-spec-argument-schema
    (contract &optional (layout (make-call-layout (function-spec-argument-specs contract))))
  "Derive a raw argument schema with a fresh layout, or the supplied LAYOUT.
An installation may supply its private layout. Both paths isolate captured checks
from the contract's exposed layout cache."
  (if (call-layout-required-only-p layout)
      (make-instance 'tuple-spec
                     :element-specs (mapcar #'argument-binding-spec (call-layout-bindings layout))
                     :generator (function-spec-argument-generator contract))
      (make-instance 'call-arguments-spec :layout layout
                     :generator (function-spec-argument-generator contract))))

(defun function-spec-call-layout (contract)
  "Return a validated layout for CONTRACT's current argument declarations.
Reuse descriptors while declaration containers and exposed binding storage match
their snapshots. Spec objects retain their identity; their internals are not
layout data. Comparing against finite snapshots also bounds malformed cycles."
  (let ((declarations (function-spec-argument-specs contract))
        (cached (slot-value contract 'call-layout-cache)))
    (if (and cached
             (equal declarations (slot-value contract 'call-layout-declarations))
             (equal (call-layout-bindings cached)
                    (slot-value contract 'call-layout-bindings-snapshot)))
        cached
        (let ((layout (make-call-layout declarations)))
          (setf (slot-value contract 'call-layout-cache) layout
                (slot-value contract 'call-layout-declarations) (copy-tree declarations)
                (slot-value contract 'call-layout-bindings-snapshot)
                (copy-list (call-layout-bindings layout)))
          layout))))

(defun function-spec-return-schema (contract)
  "Derive the return schema from CONTRACT\'s current primary return declaration."
  (make-return-schema :primary-spec (function-spec-return-spec contract)))

(defun register-function-spec (function-spec &optional (registry *registry*))
  "Register FUNCTION-SPEC in REGISTRY under its own name and return it."
  (check-argument function-spec 'function-spec 'register-function-spec :function-spec)
  (registry-register-function-spec (check-registry registry 'register-function-spec)
                                   (function-spec-name function-spec)
                                   function-spec))
