;;;; examples/structured-data.lisp
;;;;
;;;; Executable integration example for cl-spec's structured-data
;;;; specifications.  The walkthrough lives in
;;;; docs/guides/structured-data-walkthrough.md.
;;;;
;;;; Loading this file defines functions and one class only.  It does not
;;;; register a spec, draw a value, or run a demo, so it never changes the
;;;; caller's *REGISTRY*.  Call REGISTER-EXAMPLE! to register the main
;;;; example's specs, contracts and properties in a dedicated registry, and the
;;;; DEMO-* entry points to run the walkthrough.

(defpackage #:cl-spec/examples/structured-data
  (:use #:cl)
  (:import-from #:cl-spec/main
                #:*registry*
                #:make-hash-table-registry
                #:defspec #:defspec-function #:defproperty #:defgenerator
                #:validp #:explain-data #:sample #:check-function #:run-property
                #:normalize-spec-form
                #:spec-data #:function-spec-data #:semantic-data #:properties-for
                #:find-spec #:backend-capabilities #:current-generator-backend
                #:generation-budget-exhausted
                #:generation-budget-exhausted-attempts
                #:generation-budget-exhausted-budget
                #:generation-budget-exhausted-rejections
                #:generation-budget-exhausted-phase
                #:generation-budget-exhausted-path
                #:generation-budget-exhausted-report
                #:property-result-status #:property-result-failure-reason
                #:property-result-counterexample #:property-result-shrunk-counterexample
                #:property-result-shrunk-outcome #:property-result-seed
                #:property-result-generation-report)
  ;; This example is an ASDF package-inferred subsystem, so its dependencies are
  ;; the packages named in this DEFPACKAGE.  A bare :IMPORT-FROM declares a
  ;; load-time dependency without importing a symbol: it is what makes loading
  ;; the example also load the check-it generator backend that SAMPLE and the
  ;; property/contract demos need.  The example's own code calls only public
  ;; CL-SPEC API (see CL-SPEC/MAIN); nothing here calls into the backend.
  (:import-from #:cl-spec/src/backends/check-it)
  (:export #:make-example-registry #:register-example!
           #:ordered-window-p #:window-span #:total-span #:broken-window-span
           #:window-object #:window-object-start #:window-object-end
           #:window-object-ordered-p
           #:demo-validation #:demo-sample #:demo-check-function #:demo-property
           #:demo-discovery #:demo-replay #:demo-keyed-representations
           #:demo-object-source #:demo-tagged-union #:demo-budget-exhaustion
           #:demo-target-violation))

(in-package #:cl-spec/examples/structured-data)

;;;; Main example: windows and batches
;;;;
;;;; A window is a closed keyword plist with integer endpoints and an optional,
;;;; unique, bounded tag list; the non-destructive ORDERED-WINDOW-P adds the
;;;; cross-field constraint :start <= :end.  A batch is a bounded list of
;;;; windows.  All functions are pure and depend on no clock, network or
;;;; database.

(defun ordered-window-p (window)
  "Return true when WINDOW's :START is not after its :END.

Non-destructive: it only reads WINDOW, so it is a valid validation predicate."
  (<= (getf window :start) (getf window :end)))

(defun window-span (window)
  "Return WINDOW's :END minus its :START.  Pure."
  (- (getf window :end) (getf window :start)))

(defun total-span (batch)
  "Return the sum of WINDOW-SPAN over BATCH.  Pure."
  (reduce #'+ batch :key #'window-span :initial-value 0))

(defun broken-window-span (window)
  "Return WINDOW's :START minus its :END.

Deliberately wrong: the result is negative for every ordered window with distinct
endpoints, so the contract registered for it in the walkthrough is violated.  It
is a separate function so no conforming definition is redefined."
  (- (getf window :start) (getf window :end)))

(defun make-example-registry ()
  "Return a fresh registry for the example.

The caller's *REGISTRY* is neither read, cleared nor replaced."
  (make-hash-table-registry))

(defun register-example! (&optional (registry (make-example-registry)))
  "Register the main example's specs, contracts and properties in REGISTRY.

Returns REGISTRY.  This function is the only place that registers anything, so
loading this file leaves every registry untouched."
  (let ((*registry* registry))
    (defspec window
      (and (plist (:required (:start integer) (:end integer))
                  (:optional (:tags (list-of (member :a :b :c)
                                             :min-length 1 :max-length 3 :unique t)))
                  (:closed t))
           (satisfies ordered-window-p)))
    (defspec batch (list-of window :min-length 1 :max-length 3))
    (defspec-function window-span
      (:args (w window))
      (:returns (range integer 0 *)))
    (defspec-function total-span
      (:args (b batch))
      (:returns (range integer 0 *)))
    (defspec-function broken-window-span
      (:args (w window))
      (:returns (range integer 0 *)))
    (defproperty span-is-non-negative ((w window))
      (:about window window-span)
      (:trials (:smoke 5 :normal 50))
      (and (integerp (window-span w)) (>= (window-span w) 0)))
    (defproperty total-span-is-additive ((a window) (b window))
      (:about total-span)
      (:trials (:smoke 5 :normal 50))
      (= (total-span (list a b))
         (+ (window-span a) (window-span b)))))
  registry)

;;;; Walkthrough entry points

(defun demo-validation (&optional (registry (register-example!)))
  "Check a conforming window and two non-conforming values.

Returns a plist with :GOOD-VALID, :UNORDERED-VALID and :UNORDERED-ERRORS for a
window whose start is after its end, and :MISSING-VALID and :MISSING-ERRORS for
one that omits the required :END field."
  (let ((good '(:start 3 :end 9 :tags (:a :b)))
        (unordered '(:start 9 :end 3))
        (missing '(:start 9)))
    (list :good-valid (validp 'window good :registry registry)
          :unordered-valid (validp 'window unordered :registry registry)
          :unordered-errors (getf (explain-data 'window unordered :registry registry) :errors)
          :missing-valid (validp 'window missing :registry registry)
          :missing-errors (getf (explain-data 'window missing :registry registry) :errors))))

(defun demo-sample (&optional (registry (register-example!)) (count 5) (seed 42))
  "Draw COUNT windows and return the values plus the generation report.

The report distinguishes REQUESTED-VALUES and GENERATED-VALUES (roots) from
ATTEMPTS and REJECTIONS (bounded-filter candidate reservations), so a caller can
see that generating five windows can take more than five candidate draws."
  (multiple-value-bind (values report)
      (sample 'window :count count :seed seed :registry registry)
    (list :values values
          :all-valid (every (lambda (value) (validp 'window value :registry registry)) values)
          :report report)))

(defun demo-check-function (&optional (registry (register-example!)) (trials 50) (seed 7))
  "Check the conforming WINDOW-SPAN contract and return its status and report."
  (let ((result (check-function 'window-span :trials trials :seed seed
                                :registry registry)))
    (list :status (property-result-status result)
          :failure-reason (property-result-failure-reason result)
          :report (property-result-generation-report result))))

(defun demo-property (&optional (registry (register-example!)) (seed 3))
  "Run both example properties and return their statuses."
  (list :non-negative
        (property-result-status
         (run-property 'span-is-non-negative :seed seed :registry registry))
        :additive
        (property-result-status
         (run-property 'total-span-is-additive :seed seed :registry registry))))

(defun demo-discovery (&optional (registry (register-example!)))
  "Show how a caller finds a spec, its contract and its related properties.

This is the in-image introspection API.  It is not a cl-mcp tool check; the MCP
adapter lives outside this repository."
  (list :spec-name (getf (spec-data 'window :registry registry) :name)
        :spec-kind (getf (spec-data 'window :registry registry) :kind)
        :spec-source-form (getf (spec-data 'window :registry registry) :source-form)
        :contract-kind (getf (function-spec-data 'window-span :registry registry) :kind)
        :contract-arguments
        (getf (function-spec-data 'window-span :registry registry) :arguments)
        :contract-returns (getf (function-spec-data 'window-span :registry registry) :returns)
        :properties (properties-for 'window registry)
        :semantic (semantic-data 'window :registry registry)
        :capability (backend-capabilities (current-generator-backend)
                                          (find-spec 'window registry)
                                          :registry registry)))

(defun demo-replay (&optional (registry (register-example!)) (trials 50) (seed 7))
  "Run the deliberately wrong contract, then replay from that result.

The replay is asked for with the result itself, so it reuses the recorded seed,
profile and options.  Reproduction holds for the same declarations, seed, backend
and deterministic functions; it is not a promise about object identity, printing
or elapsed time."
  (let* ((original (check-function 'broken-window-span :trials trials :seed seed
                                   :registry registry))
         (replay (check-function 'broken-window-span :seed original
                                 :registry registry)))
    (list :original-status (property-result-status original)
          :replay-status (property-result-status replay)
          :original-seed (property-result-seed original)
          :replay-seed (property-result-seed replay)
          :original-counterexample (property-result-counterexample original)
          :replay-counterexample (property-result-counterexample replay))))

(defun demo-target-violation (&optional (registry (register-example!))
                              (trials 50) (seed 7))
  "Run a deliberately wrong pure function and return its observed failure.

This is a target counterexample: inputs were generated and the function was
called, and the declared return spec failed.  It is distinct from generation
exhaustion.  A shrunk reduction is reported when one was accepted; no particular
minimum is promised."
  (let ((result (check-function 'broken-window-span :trials trials :seed seed
                                :registry registry)))
    (list :status (property-result-status result)
          :failure-reason (property-result-failure-reason result)
          :counterexample (property-result-counterexample result)
          :shrunk-counterexample (property-result-shrunk-counterexample result)
          :shrunk-outcome (property-result-shrunk-outcome result))))

;;;; Supplementary examples

(defun demo-keyed-representations (&optional (registry (make-example-registry)))
  "Show the same fields as an alist and as a hash table.

Both use a required nullable :note, so a present key whose value is NIL is valid
and an absent key is a missing-key failure.  The alist declares :test EQUAL for
its string keys; the hash table keeps its declared key test."
  (let ((*registry* registry))
    (defspec note-alist
      (alist (:test equal) (:required ("id" integer) ("note" (nullable string)))))
    (defspec note-table
      (hash-table (:required (:id integer) (:note (nullable string))))))
  (let ((present (make-hash-table))
        (missing (make-hash-table)))
    (setf (gethash :id present) 1
          (gethash :note present) nil)
    (setf (gethash :id missing) 1)
    (list :alist-present-nil
          (validp 'note-alist '(("id" . 1) ("note" . nil)) :registry registry)
          :alist-missing (validp 'note-alist '(("id" . 1)) :registry registry)
          :hash-present-nil (validp 'note-table present :registry registry)
          :hash-missing (validp 'note-table missing :registry registry)
          :alist-missing-errors
          (getf (explain-data 'note-alist '(("id" . 1)) :registry registry) :errors))))

(defclass window-object ()
  ((start :initarg :start :reader window-object-start)
   (end :initarg :end :reader window-object-end))
  (:documentation "A window observed through explicit readers, not MOP slot inference."))

(defun window-object-ordered-p (object)
  "Return true when OBJECT's start is not after its end.  Reads only, via readers."
  (<= (window-object-start object) (window-object-end object)))

(defun demo-object-source (&optional (registry (make-example-registry)) (seed 1))
  "Observe objects through explicit readers and reuse their generator inside AND.

WINDOW-OBJECT-SPEC carries a custom generator because OBJECT-OF has no automatic
construction.  ORDERED-WINDOW-OBJECT is an AND whose only custom generator is
that one, so it is used as the source and the whole AND filters its draws."
  (let ((*registry* registry))
    (defgenerator window-object-generator ()
      (make-instance 'window-object :start (random 5) :end (+ (random 5) 5)))
    (defspec window-object-spec
      (object-of window-object
                 (:required (window-object-start integer) (window-object-end integer)))
      (:generator window-object-generator))
    (defspec ordered-window-object
      (and window-object-spec (satisfies window-object-ordered-p))))
  (multiple-value-bind (values report)
      (sample 'ordered-window-object :count 3 :seed seed :registry registry)
    (list :endpoints (mapcar (lambda (object)
                               (list (window-object-start object)
                                     (window-object-end object)))
                             values)
          :all-ordered (every #'window-object-ordered-p values)
          :termination (getf report :termination))))

(defun demo-tagged-union (&optional (registry (make-example-registry)) (seed 1))
  "Dispatch on a tag, aim generation at one branch, and explain a wrong value.

The tag chooses the branch at validation time; a branch failure names the branch.
This is a data union, not a function's normal/error contract."
  (let ((*registry* registry))
    (defspec outcome
      (tagged-by :kind
        (:ok (plist (:required (:kind (member :ok)) (:value integer)) (:closed t)))
        (:error (plist (:required (:kind (member :error)) (:message string))
                       (:closed t))))))
  (list :error-branch (sample 'outcome :branch :error :count 2 :seed seed :registry registry)
        :wrong-value (getf (explain-data 'outcome '(:kind :ok :value "bad") :registry registry)
                           :errors)
        :unknown-tag (getf (explain-data 'outcome '(:kind :other) :registry registry)
                           :errors)))

(defun demo-budget-exhaustion (&optional (budget 6))
  "Show a bounded filter spending an explicit budget instead of retrying forever.

The spec is a hand-checkable impossible filter: (member 1) can never satisfy
EVENP.  Exhausting the budget says this strategy did not find a value within it;
it is neither a proof of unsatisfiability nor a counterexample from target code."
  (handler-case
      (progn
        (sample (normalize-spec-form '(and (member 1) (satisfies evenp)))
                :count 1 :generation-budget budget)
        (list :outcome :unexpected-success))
    (generation-budget-exhausted (condition)
      (list :outcome :exhausted
            :attempts (generation-budget-exhausted-attempts condition)
            :budget (generation-budget-exhausted-budget condition)
            :rejections (generation-budget-exhausted-rejections condition)
            :phase (generation-budget-exhausted-phase condition)
            :path (generation-budget-exhausted-path condition)
            :report (generation-budget-exhausted-report condition)))))
