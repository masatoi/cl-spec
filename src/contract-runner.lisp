;;;; src/contract-runner.lisp

(defpackage #:cl-spec/src/contract-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:import-from #:cl-spec/src/evidence #:assess-evidence)
  (:import-from #:cl-spec/src/execution #:snapshot-value)
  (:import-from #:cl-spec/src/function-examples #:check-case-example)
  (:import-from #:cl-spec/src/function-spec #:check-function #:call-check-data)
  (:import-from #:cl-spec/src/property #:property-trials)
  (:import-from #:cl-spec/src/property-runner
                #:run-property #:check-profile #:property-result-status
                #:property-result-condition #:result-data)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:check-registry #:find-property #:find-function-spec
                #:list-properties #:list-function-specs #:properties-with-tag)
  (:import-from #:cl-spec/src/utils/arguments
                #:check-argument #:check-keyword-arguments #:check-run-options)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/utils/printing #:condition-report-text)
  (:import-from #:cl-spec/src/utils/random #:make-seed)
  (:export #:check-contracts #:judge-contract-result))

(in-package #:cl-spec/src/contract-runner)

(defun judge-contract-result (result &optional
                                       (policy '(:policy-version 1
                                                 :requirements
                                                 ((:kind :min-checked-trials :count 1)
                                                  (:kind :all-declared-cases :min-checked 1)))))
  "Return the generated RESULT's verdict, evidence assessment and problems."
  (let* ((status (property-result-status result))
         (condition (property-result-condition result))
         (assessment (assess-evidence result policy))
         (problems
           (append (unless (eq status :passed)
                     (list (list :kind :run-status :status status)))
                   (when condition (list (list :kind :run-condition)))
                   (unless (eq :satisfied (getf assessment :assessment))
                     (list (list :kind :evidence :status (getf assessment :assessment)))))))
    (values (if problems :failed :passed) assessment problems)))

(defun condition-data (condition)
  "Project an escaped or retained condition for diagnostics."
  (list :type (type-of condition) :report (condition-report-text condition)))

(defun check-contract-selection (names names-p package package-p tag tag-p seeds examples)
  "Validate all selectors, seeds and example shapes before executing user code."
  (when (> (count t (list names-p package-p tag-p)) 1)
    (error 'invalid-argument :operator 'check-contracts :argument :selection
           :datum (list :names names :package package :tag tag)
           :expected-type '(or null (member :names :package :tag))
           :reason "supply at most one of :NAMES, :PACKAGE and :TAG"))
  (when names-p
    (check-argument names '(satisfies finite-list-p) 'check-contracts :names)
    (dolist (name names)
      (let ((name-type '(and symbol (not null) (not keyword))))
        (check-argument name
                        `(or ,name-type
                             (cons (member :function-spec :property) (cons ,name-type null)))
                        'check-contracts :name))))
  (when package-p
    (check-argument package '(or package string symbol character) 'check-contracts :package))
  (when tag-p
    (check-argument tag 'symbol 'check-contracts :tag))
  (check-argument seeds '(satisfies finite-list-p) 'check-contracts :seeds)
  (dolist (seed seeds)
    (check-argument seed '(or (eql :fresh) (integer 0 *)) 'check-contracts :seed))
  (check-argument examples '(satisfies finite-list-p) 'check-contracts :examples)
  (dolist (example examples)
    (check-argument example
                    '(cons (and symbol (not null) (not keyword))
                           (cons (satisfies finite-list-p)
                                 (or null (cons (or null keyword) null))))
                    'check-contracts :example)))

(defun named-targets (target registry)
  "Resolve the kinds of a bare target name or retain an explicit kind."
  (if (consp target)
      (list (copy-list target))
      (handler-case
          (or (append (when (nth-value 1 (find-function-spec target registry))
                        (list (list :function-spec target)))
                      (when (nth-value 1 (find-property target registry))
                        (list (list :property target))))
              (list (list :unresolved target)))
        (serious-condition (condition)
          (list (list :unresolved target condition))))))

(defun select-contract-targets (names names-p package package-p tag tag-p registry)
  "Return the ordered target designators for this suite."
  (remove-duplicates
   (cond (names-p (mapcan (lambda (target) (named-targets target registry)) names))
         (tag-p (loop for name in (properties-with-tag tag registry)
                      collect (list :property name)))
         (t (let ((home (when package-p (find-package package))))
              (when (or (not package-p) home)
                (flet ((in-package-p (name)
                         (or (not package-p) (eq home (symbol-package name)))))
                  (append
                   (loop for name in (list-function-specs registry)
                         when (in-package-p name) collect (list :function-spec name))
                   (loop for name in (list-properties registry)
                         when (in-package-p name) collect (list :property name))))))))
   :test #'equal :from-end t))

(defun failed-entry (status &rest details)
  "Return a failed entry for a check that produced no supported verdict."
  (list* :status status :verdict :failed
         :problems (list (list :kind :run-status :status status)) details))

(defun supported-result-p (data versions kind name)
  "Recognize the supported result envelope and requested definition identity."
  (and (member (getf data :schema-version) versions)
       (eq :result (getf data :record-kind))
       (eq kind (getf data :entity-kind))
       (eq name (getf data :name))))

(defun generated-entry-data (result name kind seed)
  "Project and judge a generated RESULT with the expected identity."
  (let ((data (result-data result)))
    (if (and (supported-result-p data '(1 2) kind name) (eql seed (getf data :seed)))
        (multiple-value-bind (verdict assessment problems)
            (judge-contract-result result)
          (let ((condition (property-result-condition result)))
            (append (list :status (getf data :status) :verdict verdict :assessment assessment
                          :problems problems :result data)
                    (when condition (list :condition (condition-data condition))))))
        (failed-entry :unsupported-result :result data))))

(defun run-suite-target (target seed profile trials options registry)
  "Run and judge one selected TARGET under the chosen seed and settings."
  (destructuring-bind (kind name &optional selection-condition) target
    (let ((seed (if (eq seed :fresh) (make-seed) seed)))
      (list* :kind kind :name name :seed (format nil "~D" seed)
             (handler-case
                 (if selection-condition
                     (failed-entry :condition-signalled
                                   :condition (condition-data selection-condition))
                     (multiple-value-bind (definition present)
                         (ecase kind
                           (:property (find-property name registry))
                           (:function-spec (find-function-spec name registry))
                           (:unresolved (values nil nil)))
                       (cond
                         ((not present) (failed-entry :not-registered))
                         ((and (eq kind :property) profile
                               (not (getf (property-trials definition) profile)))
                          (failed-entry :unknown-profile :profile profile))
                         (t
                          (generated-entry-data
                           (ecase kind
                             (:property (run-property definition :seed seed :profile profile
                                                      :options options :registry registry))
                             (:function-spec (check-function definition :seed seed :trials trials
                                                            :options options :registry registry)))
                           name kind seed)))))
               (serious-condition (condition)
                 (failed-entry :condition-signalled :condition (condition-data condition))))))))

(defun run-suite-example (example registry)
  "Run one fixed example with the same call and case comparison as named examples."
  (destructuring-bind (name arguments &optional expected-case) example
    (let ((saved-arguments (snapshot-value arguments)))
      (list* :kind :example :name name :arguments saved-arguments :expected-case expected-case
             (handler-case
                 (let* ((row (check-case-example name (list expected-case arguments) registry))
                        (condition (getf row :condition))
                        (result (when (getf row :call) (call-check-data (getf row :call))))
                        (status (getf row :status))
                        (reason (getf row :reason)))
                   (if (and result (not (supported-result-p result '(1) :function-spec name)))
                       (failed-entry :unsupported-result :result result)
                       (append
                        (list :status status :verdict (if (eq status :passed) :passed :failed)
                              :actual-case (getf row :actual-case)
                              :result result
                              :problems
                              (unless (eq status :passed)
                                (list (list :kind (or reason :run-status) :status status))))
                        (when condition (list :condition (condition-data condition))))))
               (serious-condition (condition)
                 (failed-entry :condition-signalled :condition (condition-data condition))))))))

(defun check-contracts (&rest keyword-arguments
                        &key (names nil names-p) (package nil package-p) (tag nil tag-p)
                          (seeds '(:fresh)) profile trials options examples (registry *registry*)
                        &allow-other-keys)
  "Run registered Function Specs and properties and return a CI verdict plist.

Select at most one of :NAMES, :PACKAGE and :TAG. With none, run everything in
REGISTRY. NAMES is a list of symbols or (:FUNCTION-SPEC NAME) and (:PROPERTY NAME)
pairs. A bare symbol selects both kinds when registered under both. PACKAGE
selects names whose home package it designates. TAG selects tagged properties.

For each item in SEEDS, run each selected target once. Defaults to (:FRESH).
Each :FRESH draws a seed per target. Fixed seeds are nonnegative integers.
TRIALS sets the Function Spec budget. A non-NIL PROFILE must be declared by
each selected property. With NIL, use the ordinary property budget. OPTIONS
goes to both generated runners. EXAMPLES is a list of (NAME ARGS [EXPECTED-CASE])
rows checked once after generation. Each row uses CHECK-CALL.

The report has :STATUS, :ENTRIES, :EXAMPLES and suite-level :PROBLEMS. Each run
entry records :KIND, :NAME, :SEED as decimal text, execution :STATUS and CI
:VERDICT. It includes the RESULT-DATA record and evidence :ASSESSMENT when
available. Example entries retain CALL-CHECK-DATA when available.

The suite passes with a nonempty selection and seed list, passing generated
results with measured checked trials and every declared case checked, and passing
examples that reach any expected case. Unknown or missing results fail."
  (check-keyword-arguments keyword-arguments
                           '(:names :package :tag :seeds :profile :trials :options :examples
                             :registry)
                           'check-contracts)
  (check-contract-selection names names-p package package-p tag tag-p seeds examples)
  (check-profile profile 'check-contracts)
  (check-argument trials '(or null (integer 0 *)) 'check-contracts :trials)
  (check-run-options options 'check-contracts)
  (setf registry (check-registry registry 'check-contracts))
  (setf seeds (copy-list seeds) examples (mapcar #'copy-list examples))
  (multiple-value-bind (targets selection-problem)
      (handler-case
          (select-contract-targets names names-p package package-p tag tag-p registry)
        (serious-condition (condition)
          (values nil (list :kind :selection-error :condition (condition-data condition)))))
    (let* ((problems (append (when selection-problem (list selection-problem))
                             (unless (or targets selection-problem)
                               (list (list :kind :empty-selection)))
                             (unless seeds (list (list :kind :empty-seeds)))))
           (entries (loop for seed in seeds
                          append (loop for target in targets
                                       collect (run-suite-target
                                                target seed profile trials options registry))))
           (examples (let ((*random-state* (make-random-state *random-state*)))
                       (loop for example in examples collect (run-suite-example example registry))))
           (passed (and (null problems)
                        (every (lambda (entry) (eq :passed (getf entry :verdict))) entries)
                        (every (lambda (row) (eq :passed (getf row :verdict))) examples))))
      (list :schema-version 1 :record-kind :contract-suite
            :status (if passed :passed :failed)
            :entries entries :examples examples :problems problems))))
