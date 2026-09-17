;;;; self-spec-fixtures.lisp
;;;;
;;;; Fixtures, finite corpora and test-support specials for the executable
;;;; self-specifications in SPECS.LISP.  Loading this file defines functions,
;;;; classes and variables only: it registers no definition, draws no value and
;;;; never changes CL-SPEC:*REGISTRY*.  The bundle in SPECS.LISP owns the
;;;; registration, and the fixture builders below take a fresh registry of their
;;;; own so a trial observes state the implementation under test cannot have
;;;; touched before the trial started.

(defpackage #:cl-spec/self-spec-fixtures
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:defgenerator
                #:defspec-function
                #:make-hash-table-registry
                #:property
                #:registry-find-property
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-register-property)
  (:export
   #:*function-projection-expectations*
   #:*scripted-registration-scenarios*
   #:*scripted-state-inputs*
   #:*scripted-validate-inputs*
   #:*state-projection-expectations*
   #:*validate-corpus*
   #:function-projection-fixtures
   #:index-keys-shape-p
   #:registration-index-shape-p
   #:registration-scenario
   #:registration-scenario-state-p
   #:registration-scenario-tags-p
   #:registration-scenario-targets-p
   #:self-registration-name
   #:*self-state-balance*
   #:*self-state-calls*
   #:self-state-capture-target
   #:self-state-observed-target
   #:*self-state-scenario*
   #:self-state-uncalled-target
   #:state-projection-fixtures
   #:validate-corpus-entry))

(in-package #:cl-spec/self-spec-fixtures)

;;; Fixed declarations for the registry state contract.  They are symbols rather
;;; than values the scenario computes, so the expected after-state follows from
;;; the declared input and the observed before-state alone.

(defparameter *self-registration-names*
  '(:subject self-registration-subject
    :sentinel self-registration-sentinel
    :shared-target self-shared-target
    :old-target self-old-target
    :new-target self-new-target
    :shared-tag self-shared-tag
    :old-tag self-old-tag
    :new-tag self-new-tag)
  "Fixed symbols the registry state contract declares, indexes and then checks.")

(defun self-registration-name (key)
  "Return the fixed registration symbol named by KEY.

The contract's capture, guards and state-post read the symbol through this
function, so the expected index key is stated once and never re-derived from the
registry it is checking."
  (getf *self-registration-names* key))

(defparameter *function-projection-expectations*
  (list :case-selection :exclusive
        :case-names '(:admitted :refused)
        :case-outcomes '(:returns :signals)
        :admitted-when '(>= n 0)
        :refused-when '(< n 0)
        :admitted-postconditions '((eq result n))
        :state-capture '((:name n-before :form n))
        :state-case-state-post '((= n n-before)))
  "Explicit expected projections, built here with the fixture's own symbols.

The property in CL-SPEC/SPECS compares these with EQUAL, which compares symbols
by identity.  A projection that substituted a same-named symbol from another
package is therefore rejected; comparing only symbol names would accept it.")

(defparameter *state-projection-expectations*
  (list :declared '(balance-before marker)
        :values (list (cons 'balance-before 10) (cons 'marker nil))
        :capture-error-binding 'balance-before)
  "Explicit expected state evidence for the scripted :FORGET run.

:VALUES keeps a captured NIL, (MARKER . NIL), distinct from a binding that was
declared but never obtained.")

(defun registration-scenario-targets-p (targets)
  "True for exactly the explicit target arguments REGISTRATION-SCENARIO returns.

The contract declares this finite domain rather than T.  Its state-post names
the scenario's fixed target symbols, so it is a statement about these inputs,
not about arbitrary index lists; a generator producing some other valid list is
outside the contract, not a counterexample to it."
  (or (eql targets 42)
      (equal targets (list (self-registration-name :new-target)
                           (self-registration-name :shared-target)))))

(defun registration-scenario-tags-p (tags)
  "True for exactly the explicit tag arguments REGISTRATION-SCENARIO returns.

See REGISTRATION-SCENARIO-TARGETS-P for why the contract declares this finite
domain instead of T."
  (or (equal tags "not-a-symbol")
      (equal tags (list (self-registration-name :new-tag)
                        (self-registration-name :shared-tag)))))

(defun registration-scenario-state-p (registry name targets tags)
  "True when REGISTRY is in exactly the initial state REGISTRATION-SCENARIO builds.

The state contract's expected index keys are the scenario's fixed symbols, so the
common :PRE has to admit the whole scenario, not only the argument values.  A
registry that carries the same argument values but some other history is outside
the contract, not a counterexample to it."
  (labels ((same-name-set-p (left right)
             (null (set-exclusive-or left right))))
    (let* ((subject (self-registration-name :subject))
           (sentinel (self-registration-name :sentinel))
           (new-target (self-registration-name :new-target))
           (old-target (self-registration-name :old-target))
           (shared-target (self-registration-name :shared-target))
           (new-tag (self-registration-name :new-tag))
           (old-tag (self-registration-name :old-tag))
           (shared-tag (self-registration-name :shared-tag))
           (subject-present (nth-value 1 (registry-find-property registry subject))))
      (and (eq name subject)
           (nth-value 1 (registry-find-property registry sentinel))
           (same-name-set-p (registry-properties-for registry new-target) nil)
           (same-name-set-p (registry-properties-for registry old-target)
                            (when subject-present (list subject)))
           (same-name-set-p (registry-properties-for registry shared-target)
                            (if subject-present (list subject sentinel) (list sentinel)))
           (same-name-set-p (registry-properties-with-tag registry new-tag) nil)
           (same-name-set-p (registry-properties-with-tag registry old-tag)
                            (when subject-present (list subject)))
           (same-name-set-p (registry-properties-with-tag registry shared-tag)
                            (if subject-present (list subject sentinel) (list sentinel)))
           ;; The argument values agree with the observed initial state.
           (if (eql targets 42)
               subject-present
               (equal targets (list new-target shared-target)))
           (if (equal tags "not-a-symbol")
               subject-present
               (equal tags (list new-tag shared-tag)))))))

;;; Test support.  Each special, when bound, replaces a finite random draw with a
;;; caller-supplied sequence, so a boundary test can name the exact inputs it runs
;;; instead of depending on what a seed happens to reach.

(defvar *scripted-registration-scenarios* nil
  "When bound to a list, REGISTRATION-SCENARIO pops one scenario kind per draw.
Each entry is :NEW, :REPLACE, :REFUSED-TARGETS or :REFUSED-TAGS.")

(defvar *scripted-validate-inputs* nil
  "When bound to a list, the validate generator pops one (FORM VALUE) per draw.")

(defvar *scripted-state-inputs* nil
  "When bound to a list, the result-projection fixtures pop one AMOUNT per draw.")

(defun index-keys-shape-p (keys)
  "Independent shape check for explicit registry index keys.

Deliberately not the registry's own predicate: this is the oracle the state
contract compares the implementation's acceptance against, so it must not share
the code under test.  Total, so a malformed index argument cannot make a case
guard signal instead of selecting the refusal case."
  (handler-case (and (listp keys) (every #'symbolp keys))
    (error () nil)))

(defun registration-index-shape-p (targets tags)
  "True when both explicit index arguments have the shape the API documents."
  (and (index-keys-shape-p targets) (index-keys-shape-p tags)))

(defun make-registration-subject (name)
  "Return a fresh, valid property the registration contract can index."
  (make-instance 'property :name name :arguments '((x integer))
                 :function (lambda (x) (declare (ignore x)) t)))

(defun registration-scenario ()
  "Return an argument list for REGISTRY-REGISTER-PROPERTY for one fresh scenario.

Every draw builds a new target registry and a sentinel property that shares a
target and a tag with the subject, so the state contract's state-post can check
that a replacement retracts only the subject's own stale keys and leaves the
sentinel's entries alone.  The subjects are fresh instances; the names, targets
and tags are the fixed declarations above."
  (let ((registry (make-hash-table-registry))
        (sentinel (make-registration-subject (self-registration-name :sentinel)))
        (kind (if *scripted-registration-scenarios*
                  (pop *scripted-registration-scenarios*)
                  (nth (random 4) '(:new :replace :refused-targets :refused-tags)))))
    (registry-register-property
     registry (self-registration-name :sentinel) sentinel
     :targets (list (self-registration-name :shared-target))
     :tags (list (self-registration-name :shared-tag)))
    (when (member kind '(:replace :refused-targets :refused-tags))
      (registry-register-property
       registry (self-registration-name :subject)
       (make-registration-subject (self-registration-name :subject))
       :targets (list (self-registration-name :shared-target)
                      (self-registration-name :old-target))
       :tags (list (self-registration-name :shared-tag)
                   (self-registration-name :old-tag))))
    (list registry
          (self-registration-name :subject)
          (make-registration-subject (self-registration-name :subject))
          :targets (if (eq kind :refused-targets)
                       42
                       (list (self-registration-name :new-target)
                             (self-registration-name :shared-target)))
          :tags (if (eq kind :refused-tags)
                    "not-a-symbol"
                    (list (self-registration-name :new-tag)
                          (self-registration-name :shared-tag))))))

;;; Finite validate corpus.  Each admitted form is paired with a value it refuses,
;;; so a run that reaches both pairs reaches both named outcomes.  This is a finite
;;; corpus, not the whole DSL or the whole value domain, and the boundary test in
;;; TESTS/SELF-SPECS-TEST.LISP names the exact sequence it uses.

(defparameter *validate-corpus*
  '((integer 0) (integer "refused")
    (string "ok") (string 3)
    (boolean t) (boolean 42)
    ((member 1 2 3) 2) ((member 1 2 3) 4)
    ((or integer string) "text") ((or integer string) :keyword)
    (null nil) (null t))
  "Finite (FORM VALUE) pairs spanning admitted and refused values.")

(defun validate-corpus-entry ()
  "Return one (FORM VALUE) pair, scripted or drawn from the finite corpus."
  (if *scripted-validate-inputs*
      (pop *scripted-validate-inputs*)
      (nth (random (length *validate-corpus*)) *validate-corpus*)))

;;; Explicit Function Spec projection fixtures.  Each call registers the three
;;; declarations in a registry of its own, so the projection property reads only
;;; definitions it made and the caller's registry is never touched.

(defun function-projection-fixtures ()
  "Register the explicit Function Spec projection fixtures and return the registry.

The three contracts are declared here, not derived from the projection under
test: one uses none of the new clauses, one declares a returns case and a
signals case, and one declares a capture binding and a per-case state-post."
  (let ((cl-spec:*registry* (make-hash-table-registry)))
    (defspec-function self-projection-plain
      "A contract that uses none of the case, capture or state-post clauses."
      (:args (n integer))
      (:returns integer)
      (:post (eq result n)))
    (defspec-function self-projection-cases
      "A contract with one returns case and one signals case."
      (:args (n integer))
      (:cases
       (:admitted
        "The nonnegative branch."
        (:when (>= n 0))
        (:returns integer)
        (:post (eq result n)))
       (:refused
        "The negative branch."
        (:when (< n 0))
        (:signals (type simple-error)))))
    (defspec-function self-projection-state
      "A contract that captures state and checks it in the selected case."
      (:args (n integer))
      (:capture (n-before n))
      (:cases
       (:admitted
        "The only case, with a state-post."
        (:when (>= n 0))
        (:returns integer)
        (:post (eq result n))
        (:state-post (= n n-before)))))
    (list :registry cl-spec:*registry*
          :plain 'self-projection-plain
          :cases 'self-projection-cases
          :state 'self-projection-state)))

;;; Small stateful targets and their contracts, for the result-projection
;;; property.  The scenario special selects the mistake a target makes; the
;;; property always binds the balance before the run, so no trial starts from the
;;; object an earlier one mutated.

(defvar *self-state-balance* 0
  "Balance the current result-projection run starts from.")

(defvar *self-state-calls* 0
  "Target invocations of the current result-projection run.")

(defvar *self-state-scenario* :correct
  "Which behaviour the stateful projection targets perform.")

(defun self-state-observed-target (amount)
  "Withdraw AMOUNT on the correct path, or answer the receipt without changing it."
  (incf *self-state-calls*)
  (case *self-state-scenario*
    (:correct (decf *self-state-balance* amount) amount)
    (:forget amount)))

(defun self-state-capture-target (amount)
  "Target whose contract's :capture form signals before it can be called."
  (declare (ignore amount))
  (incf *self-state-calls*)
  :never)

(defun self-state-uncalled-target (amount)
  "Target whose contract's only case guard matches nothing."
  (declare (ignore amount))
  (incf *self-state-calls*)
  :never)

(defun state-projection-fixtures ()
  "Register the result-projection fixtures and return the registry.

The generator pops *SCRIPTED-STATE-INPUTS*, so an inner run draws exactly the
amounts the property supplies."
  (let ((cl-spec:*registry* (make-hash-table-registry)))
    (defgenerator self-projection-amounts ()
      (list (pop *scripted-state-inputs*)))
    (defspec-function self-state-observed-target
      "A capture/state-post contract over STATE-OBSERVED-TARGET."
      (:args (amount (range integer 1 10)))
      (:args-generator self-projection-amounts)
      (:capture (balance-before *self-state-balance*)
                (marker nil))
      (:returns integer)
      (:post (= result amount))
      (:state-post (= *self-state-balance* (- balance-before amount))))
    (defspec-function self-state-capture-target
      "A contract whose capture form signals before the target runs."
      (:args (amount (range integer 1 10)))
      (:args-generator self-projection-amounts)
      (:capture (balance-before (error 'simple-error :format-control "fixture capture"))
                (marker nil))
      (:returns integer))
    (defspec-function self-state-uncalled-target
      "A case-carrying contract whose only guard matches nothing."
      (:args (amount (range integer 1 10)))
      (:args-generator self-projection-amounts)
      (:capture (balance-before *self-state-balance*))
      (:cases
       (:impossible
        "Guarded so that no trial selects it."
        (:when (> amount balance-before))
        (:returns integer)
        (:state-post (= *self-state-balance* balance-before)))))
    (list :registry cl-spec:*registry*
          :observed 'self-state-observed-target
          :capture 'self-state-capture-target
          :uncalled 'self-state-uncalled-target)))
