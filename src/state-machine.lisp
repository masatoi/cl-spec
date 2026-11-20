;;;; src/state-machine.lisp

(defpackage #:cl-spec/src/state-machine
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-property-form)
  (:import-from #:cl-spec/src/coverage-report
                #:*coverage-trial* #:*coverage-context*
                #:coverage-precondition-observed-p #:coverage-mark-stage)
  (:import-from #:cl-spec/src/definition-validation #:validate-definition #:definition-keyword-plist-p)
  (:import-from #:cl-spec/src/ir #:spec #:list-of-spec #:collection-spec-element-spec)
  (:import-from #:cl-spec/src/execution #:evaluate-trial #:observe-trial)
  (:import-from #:cl-spec/src/property
                #:property #:property-function #:property-arguments #:property-kind #:property-source-form
                #:register-property)
  (:import-from #:cl-spec/src/registry #:*registry* #:check-registry)
  (:import-from #:cl-spec/src/resolve #:resolve-property)
  (:import-from #:cl-spec/src/schema #:definition-description-complete-p)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument #:check-keyword-arguments)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/utils/source-location #:current-source-location)
  (:import-from #:cl-spec/src/validator #:validate)
  (:export #:defstate-machine #:check-state-machine #:state-machine-property #:command-trace-p))

(in-package #:cl-spec/src/state-machine)

(defclass state-machine-property (property) ()
  (:documentation "One property binding holds the entire command sequence."))

(defmethod validate-definition :after ((machine state-machine-property))
  "Check the machine's kind and single trace binding after ordinary property normalization."
  (unless (eq :state-machine (property-kind machine))
    (error 'invalid-property-form :form (property-kind machine)
                                  :reason "a state machine requires :kind :state-machine"))
  (let* ((bindings (property-arguments machine))
         (sequence-spec (second (first bindings))))
    (unless (and (= 1 (length bindings))
                 (typep sequence-spec 'list-of-spec)
                 (typep (collection-spec-element-spec sequence-spec) 'spec))
      (error 'invalid-property-form :form bindings
                                    :reason "a state machine requires one list-of command binding"))
    (validate-definition sequence-spec)))

(defmethod definition-description-complete-p ((machine state-machine-property))
  (and (eq (class-name (class-of machine)) 'state-machine-property)
       (not (null (property-source-form machine)))))

(defun command-trace-p (commands)
  "Recognize a finite list of keywords or proper lists headed by a command keyword."
  (and (finite-list-p commands)
       (every (lambda (command)
                (or (keywordp command)
                    (and (consp command) (keywordp (car command)) (finite-list-p command))))
              commands)))

(defun check-machine-callback (callback)
  "Require a function or the name of an ordinary function at registration time."
  (unless (or (functionp callback)
              (and (symbolp callback) (fboundp callback)
                   (not (macro-function callback)) (not (special-operator-p callback))))
    (error 'invalid-property-form :form callback :reason "expected a function designator"))
  callback)

(defun step-values (step state command)
  "Enforce the exact two-value step protocol, including an explicitly NIL observation."
  (multiple-value-call (lambda (next observation) (values next observation))
    (funcall step state command)))

(defun make-trace-predicate
    (make-model make-target model-step target-step compare enabled invariant)
  "Construct a property predicate whose secondary values classify this exact execution."
  (mapc #'check-machine-callback (list model-step target-step compare))
  (when enabled (check-machine-callback enabled))
  (when invariant (check-machine-callback invariant))
  (lambda (commands)
    (block trace
      (let ((phase :commands) (index nil) (command nil) (operation nil) (checkpoint nil))
        (labels ((position-data ()
                   (list :index index :command command))
                 (finish (status &key reason signature detail condition value)
                   (return-from trace
                     (values (eq status :passed) status reason signature detail condition
                             value checkpoint)))
                 (check-invariant (model target)
                   (setf phase :invariant)
                   (when (and invariant (not (funcall invariant model target)))
                     (finish :failed :reason :invariant-violation
                             :signature (list :state-machine :invariant-violation operation)
                             :detail (position-data)))))
          (handler-case
              (progn
                (check-argument commands '(satisfies command-trace-p)
                                'check-state-machine :commands)
                (setf phase :model-setup)
                (let ((model (funcall make-model))
                      (target (progn (setf phase :target-setup) (funcall make-target))))
                  (check-invariant model target)
                  (unless commands (setf checkpoint :pre-admitted))
                  (loop for item in commands for i from 0
                        do (setf index i command item operation (if (consp item) (car item) item))
                           (setf phase :enabled)
                           (when (and enabled (not (funcall enabled model command)))
                             (finish :rejected :value (position-data)))
                           (unless checkpoint (setf checkpoint :pre-admitted))
                           (setf phase :model-step)
                           (multiple-value-bind (next-model expected)
                               (step-values model-step model command)
                             (setf phase :target-step checkpoint :target-observed)
                             (multiple-value-bind (next-target actual)
                                 (step-values target-step target command)
                               (setf phase :compare)
                               (unless (funcall compare expected actual)
                                 (finish :failed :reason :observation-mismatch
                                         :signature (list :state-machine :observation-mismatch
                                                          operation)
                                         :detail (append (position-data)
                                                         (list :expected expected :actual actual))))
                               (setf model next-model target next-target)
                               (check-invariant model target))))
                  (finish :passed :value t)))
            (error (condition)
              (finish :error :reason :machine-error :condition condition
                      :signature (list :state-machine :machine-error phase operation
                                       (type-of condition))
                      :detail (list :index index :command command :phase phase)))))))))

(defmethod coverage-precondition-observed-p ((machine state-machine-property)) t)

(defmethod evaluate-trial ((machine state-machine-property) arguments &key context)
  (declare (ignore context))
  (multiple-value-bind (passed status reason signature detail condition value checkpoint)
      (apply (property-function machine) arguments)
    (declare (ignore passed))
    (when checkpoint (coverage-mark-stage :pre-admitted))
    (when (eq checkpoint :target-observed) (coverage-mark-stage :target-observed))
    (values status reason signature detail condition value)))

(defun check-machine-declaration (trace options)
  "Check the trace binding and the closed set of callback and property options."
  (unless (and (finite-list-p trace) (consp (rest trace)))
    (error 'invalid-property-form :form trace :reason "expected (variable command-spec options*)"))
  (let ((required '(:model :target :model-step :target-step))
        (optional '(:compare :enabled :invariant :about :trials :documentation)))
    (unless (and (definition-keyword-plist-p options)
                 (loop for key in options by #'cddr
                       always (or (member key required) (member key optional))))
      (error 'invalid-property-form :form options
                                    :reason "unknown, duplicate or malformed options"))
    (dolist (key required)
      (unless (loop for candidate in options by #'cddr thereis (eq candidate key))
        (error 'invalid-property-form :form options :reason (format nil "missing ~S" key))))))

(defmacro defstate-machine (&whole source name trace &rest options)
  "Register a model-based property named NAME in *REGISTRY*.

TRACE is (VARIABLE COMMAND-SPEC &rest LIST-OF-OPTIONS). A command is a keyword
or a proper list (KEYWORD ARGUMENT*). RUN-PROPERTY generates lists of commands
and shrinks a failure. CHECK-STATE-MACHINE executes a supplied list directly.

:MODEL and :TARGET are forms evaluated once per sequence, including each shrink
candidate. They must supply independent initial states. :MODEL-STEP and
:TARGET-STEP are function designators called with their own state and a command.
Each returns exactly two values, the next state and an observation. :COMPARE compares
the model and target observations after each step and defaults to EQUAL.

Optional :ENABLED takes (MODEL COMMAND). A false result rejects the sequence
before executing that step. Optional :INVARIANT takes (MODEL TARGET) initially
and after each pair of agreeing steps. Checks stop at the first divergence,
violated invariant, inapplicable command or callback error. Treat command data
as read-only. :ABOUT, :TRIALS and :DOCUMENTATION are literal property metadata."
  (check-machine-declaration trace options)
  (destructuring-bind (variable command-spec &rest bounds) trace
    `(register-property
      (make-instance 'state-machine-property
                     :name ',name :kind :state-machine
                     :arguments '((,variable (list-of ,command-spec ,@bounds)))
                     :targets ',(getf options :about)
                     :trials ',(getf options :trials)
                     :documentation ',(getf options :documentation)
                     :source-form ',source :source-location ',(current-source-location)
                     :function (make-trace-predicate
                                (lambda () ,(getf options :model))
                                (lambda () ,(getf options :target))
                                ,(getf options :model-step) ,(getf options :target-step)
                                ,(getf options :compare '(function equal))
                                ,(getf options :enabled) ,(getf options :invariant))))))

(defun check-state-machine (machine commands &rest keywords
                            &key (registry *registry*) &allow-other-keys)
  "Check COMMANDS exactly once against the registered state machine or its name.

Return a TRIAL-OBSERVATION. A failed observation gives a zero-based :INDEX and
:COMMAND in its explanation. An initial invariant has NIL for both. A rejected
sequence identifies the first disabled command in TRIAL-OBSERVATION-VALUE.
Malformed command syntax signals INVALID-ARGUMENT. A sequence outside its
declared argument spec signals SPEC-VIOLATION. Both checks precede initialization.
This entry point runs in core and uses no generator."
  (check-keyword-arguments keywords '(:registry) 'check-state-machine)
  (setf registry (check-registry registry 'check-state-machine))
  (check-argument machine '(or property symbol) 'check-state-machine :machine)
  (let ((property (resolve-property machine registry))
        (*coverage-context* nil)
        (*coverage-trial* nil))
    (check-argument property 'state-machine-property 'check-state-machine :machine)
    (check-argument commands '(satisfies command-trace-p) 'check-state-machine :commands)
    (validate (second (first (property-arguments property))) commands :registry registry)
    (observe-trial property (list commands) :context (list :registry registry))))
