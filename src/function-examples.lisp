;;;; src/function-examples.lisp

(defpackage #:cl-spec/src/function-examples
  (:use #:cl)
  (:import-from #:cl-spec/src/execution
                #:trial-observation-case #:trial-observation-reason #:trial-observation-outcome)
  (:import-from #:cl-spec/src/function-spec
                #:check-call #:check-function #:call-check-result-observation
                #:call-check-result-status #:resolve-function-spec #:function-spec-cases
                #:function-case-name #:check-function-arguments)
  (:import-from #:cl-spec/src/property-runner #:property-result-status #:property-result-trials)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/utils/arguments #:check-argument)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:check-function-with-examples #:check-case-example))

(in-package #:cl-spec/src/function-examples)

(defun prepare-example-table (examples contract)
  "Validate the rows and keep their order and names independently of target mutation."
  (check-argument examples '(satisfies finite-list-p) 'check-function-with-examples :examples)
  (let* ((names (mapcar #'function-case-name (function-spec-cases contract)))
         (expected-case-type (cons 'member names)))
    (loop for row in examples
          do (check-argument row '(cons keyword (cons (satisfies finite-list-p) null))
                             'check-function-with-examples :example)
             (check-argument (first row) expected-case-type
                             'check-function-with-examples :expected-case)
          collect (copy-list row))))

(defun check-case-example (contract row registry)
  "Run one row with an optional expected case and retain its call result or error."
  (destructuring-bind (expected arguments) row
    (handler-case (check-call contract arguments :registry registry)
      (error (condition)
        (list :expected-case expected :actual-case nil :status :error
              :reason :call-error :condition condition :call nil))
      (:no-error (call)
        (let* ((observation (call-check-result-observation call))
               (actual (trial-observation-case observation))
               (status (call-check-result-status call))
               (mismatch (and expected (not (eq expected actual))
                              (or actual (consp (trial-observation-outcome observation))))))
          (list :expected-case expected :actual-case actual
                :status (if (and mismatch (eq :passed status)) :failed status)
                :reason (if mismatch :case-mismatch (trial-observation-reason observation))
                :call call))))))

(defun combined-check-status (rows generated-status)
  "Require every asserted example to pass and retain a skipped or failing generated status."
  (flet ((row-status (row) (getf row :status)))
    (cond ((or (eq generated-status :error) (find :error rows :key #'row-status)) :error)
          ((find-if (lambda (status) (member status '(:failed :rejected))) rows :key #'row-status)
           :failed)
          (t generated-status))))

(defun check-function-with-examples (function-designator examples &rest keyword-arguments
                                     &key trials seed options (registry *registry*)
                                       &allow-other-keys)
  "Check fixed examples of named Function Spec cases, then run ordinary CHECK-FUNCTION trials.

EXAMPLES is a finite list of (EXPECTED-CASE RAW-ARGUMENT-LIST) rows owned by the
caller. Each expected keyword must name a declared case. The entire table is
validated before any call. A malformed table signals INVALID-ARGUMENT. An empty
table runs generation alone. FUNCTION-DESIGNATOR and the generation keywords
:TRIALS, :SEED, :OPTIONS and :REGISTRY follow CHECK-FUNCTION.

Each row calls CHECK-CALL once in table order. Its :CALL holds the direct result.
:ACTUAL-CASE comes from the recorded observation. A different case, or a target
outcome with no case, sets :REASON to :CASE-MISMATCH. :CALL retains the target
outcome even when the function also violated its return or error contract. If
CHECK-CALL signals an error, the row records :STATUS :ERROR, :REASON :CALL-ERROR
and :CONDITION. Subsequent rows and the generated phase still run.

Return a plist with :EXAMPLES, :EXAMPLE-COUNT, :GENERATED (the FUNCTION-CHECK-RESULT),
:GENERATED-TRIALS (actual ordinary trials), and :STATUS. An error in either phase
gives :ERROR. A failed or rejected example gives :FAILED. Otherwise take the
generated status, including :SKIPPED. CHECK-FUNCTION retains its normal error
signalling, seed, shrinking, case counts and replay behavior. It validates a
saved result supplied as :SEED after all fixed calls, whose effects persist
even when the generated phase signals an error.

Fixed rows use caller-supplied state and a private copy of *RANDOM-STATE*.
Only generated trials and their shrink candidates run fixture setup and cleanup."
  (setf registry (check-function-arguments 'check-function-with-examples keyword-arguments
                                           trials seed options registry))
  (let* ((contract (resolve-function-spec function-designator registry))
         (table (prepare-example-table examples contract)))
    (let ((rows (let ((*random-state* (make-random-state *random-state*)))
                  (mapcar (lambda (row) (check-case-example contract row registry)) table)))
          (generated (apply #'check-function contract :registry registry keyword-arguments)))
      (list :status (combined-check-status rows (property-result-status generated))
            :example-count (length rows) :examples rows
            :generated-trials (property-result-trials generated) :generated generated))))
