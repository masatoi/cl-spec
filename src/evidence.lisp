;;;; src/evidence.lisp
(defpackage #:cl-spec/src/evidence
  (:use #:cl)
  (:import-from #:cl-spec/src/execution #:snapshot-value)
  (:export #:evidence-declared-cases #:evidence-facts #:evidence-summary #:assess-evidence
           #:invalid-evidence-policy #:invalid-evidence-policy-reason
           #:evidence-subject #:single-observation-report))
(in-package #:cl-spec/src/evidence)

(defgeneric invalid-evidence-policy-reason (condition)
  (:documentation "Return the reason an evidence policy was refused."))

(define-condition invalid-evidence-policy (error)
  ((reason :initarg :reason :reader invalid-evidence-policy-reason))
  (:documentation "An unsupported or malformed declarative evidence policy.")
  (:report (lambda (condition stream)
             (format stream "Invalid evidence policy: ~A"
                     (invalid-evidence-policy-reason condition)))))

(defgeneric evidence-facts (result)
  (:documentation "Return saved execution facts without lookup or executing application code."))

(defgeneric evidence-declared-cases (definition)
  (:documentation "Snapshot declared cases before execution; unknown is distinct from none.")
  (:method ((definition t)) :not-collected))

(defun bounded-list-p (value maximum)
  "Recognize a proper list in at most MAXIMUM cons steps, refusing cycles."
  (loop repeat maximum
        while (consp value) do (setf value (cdr value))
        finally (return (null value))))

(defun exact-policy-record-p (value keys)
  "Recognize a small plist containing each required key exactly once."
  (and (bounded-list-p value (* 2 (length keys)))
       (= (length value) (* 2 (length keys)))
       (equal (sort (loop for (key) on value by #'cddr collect key)
                    #'string< :key (lambda (key) (if (keywordp key) (symbol-name key) "")))
              (sort (copy-list keys) #'string< :key #'symbol-name))))

(defun validate-evidence-policy (policy)
  "Validate the complete closed policy grammar before inspecting any result."
  (labels ((refuse () (error 'invalid-evidence-policy :reason :invalid-policy)))
    (unless (and (exact-policy-record-p policy '(:policy-version :requirements))
                 (eql 1 (getf policy :policy-version)))
      (refuse))
    (let ((requirements (getf policy :requirements)) (seen nil))
      (unless (and requirements (bounded-list-p requirements 3)) (refuse))
      (dolist (requirement requirements)
        (unless (and (bounded-list-p requirement 4) (evenp (length requirement)))
          (refuse))
        (let* ((kind (getf requirement :kind))
               (threshold (case kind
                            (:min-checked-trials :count)
                            (:all-declared-cases :min-checked))))
          (unless (and (member kind '(:min-checked-trials :all-declared-cases
                                     :requested-trials-completed))
                       (not (member kind seen))
                       (exact-policy-record-p requirement
                                              (if threshold (list :kind threshold) '(:kind)))
                       (or (null threshold)
                           (typep (getf requirement threshold) '(integer 1 *))))
            (refuse))
          (push kind seen))))
    (copy-tree policy)))

(defun evidence-subject (name metadata &optional provenance)
  "Project the captured declaration and target identity, including unknown identity."
  (list :name name :definition-digest (getf metadata :definition-digest)
        :definition-digest-complete (getf metadata :definition-digest-complete)
        :target-revision (getf provenance :target-revision :unknown)))

(defun single-observation-report (status)
  "Describe the final classification of one direct invocation."
  (list :report-version 1 :collection :complete :unit :single-call
        :counts (loop for key in '(:passed :failed :rejected :error)
                      append (list key (if (eq key status) 1 0)))
        :checked (if (member status '(:passed :failed)) 1 0)))

(defun evidence-dimensions (facts)
  "Build measured dimensions from saved reports; missing measurements stay missing."
  (let* ((report (getf facts :trial-report :not-collected))
         (collected (and (listp report) (eq :complete (getf report :collection))))
         (declared (getf facts :declared-cases :not-collected))
         (cases (getf facts :case-report :not-collected))
         (case-availability (cond ((eq declared :not-collected) :not-collected)
                                  ((null declared) :not-applicable)
                                  ((listp cases) :collected)
                                  (t :not-collected)))
         (budget (getf facts :budget))
         (trials (getf facts :trials))
         (budget-availability
           (cond ((eq :single-call (getf facts :scope)) :not-applicable)
                 ((and (typep budget '(integer 0 *)) (typep trials '(integer 0 *)))
                  :collected)
                 (t :not-collected))))
    (list
     (append (list :kind :checked-trials :availability
                   (if collected :collected :not-collected)
                   :unit (if (eq :single-call (getf facts :scope)) :single-call :normal-trials)
                   :source '(:trial-report :checked))
             (when collected
               (list :value (getf report :checked) :counts (getf report :counts))))
     (append (list :kind :declared-cases :availability case-availability
                   :unit (if (eq :single-call (getf facts :scope)) :single-call :normal-trials)
                    :source '(:case-report :cases))
             (unless (eq declared :not-collected) (list :declared declared))
             (when (eq case-availability :collected)
               (list :cases
                     (loop for name in declared
                           for entry = (find name (getf cases :cases)
                                             :key (lambda (x) (getf x :name)))
                           collect (if entry
                                       (list :name name :called (getf entry :called)
                                             :checked (+ (getf entry :passed) (getf entry :failed)))
                                       (list :name name :availability :not-collected))))))
     (append (list :kind :requested-trials :availability budget-availability
                   :source '(:trials :budget))
             (when (eq budget-availability :collected)
               (list :value trials :required budget))))))

(defun dimension (dimensions kind)
  "Find a dimension by its stable protocol name."
  (find kind dimensions :key (lambda (entry) (getf entry :kind))))

(defun summary-from-facts (facts)
  "Project facts without applying an implicit sufficiency threshold."
  (let ((dimensions (evidence-dimensions facts)) (gaps nil) (unknowns nil))
    (dolist (entry dimensions)
      (when (eq :not-collected (getf entry :availability))
        (push (list :kind :measurement-not-collected :dimension (getf entry :kind)
                    :source (getf entry :source)) unknowns)))
    (let ((checked (dimension dimensions :checked-trials))
          (cases (dimension dimensions :declared-cases)))
      (when (and (eq :collected (getf checked :availability))
                 (zerop (getf checked :value)))
        (push (list :kind :no-checked-trials :source '(:trial-report :checked)) gaps))
      (dolist (entry (getf cases :cases))
        (cond ((eq :not-collected (getf entry :availability))
               (push (list :kind :measurement-not-collected :dimension :declared-cases
                           :case (getf entry :name)) unknowns))
              ((zerop (getf entry :called))
               (push (list :kind :case-never-called :case (getf entry :name)
                           :source (list :case-report :cases (getf entry :name))) gaps)))))
    (list :schema-version 1 :record-kind :evidence-summary :assessment :not-assessed
          :execution-status (getf facts :execution-status)
          :scope (getf facts :scope) :subject (getf facts :subject)
          :dimensions dimensions :gaps (nreverse gaps) :unknowns (nreverse unknowns)
          :limitations (append
                        '(:single-execution-only :no-optional-field-coverage
                          :no-boundary-coverage :no-combination-coverage
                          :no-correctness-proof)
                        (unless (getf (getf facts :subject) :definition-digest-complete)
                          '(:incomplete-definition-identity))
                        (when (eq :unknown (getf (getf facts :subject) :target-revision :unknown))
                          '(:target-revision-unknown))
                        (when (getf facts :run-error) '(:run-error-present)))
          :diagnostics (list :generation-report (getf facts :generation-report :not-collected)
                             :shrink-report (getf facts :shrink-report :not-collected)
                             :capabilities (getf facts :capabilities :not-collected)))))

(defun evidence-summary (result)
  "Summarize saved evidence without re-execution or an implicit verification policy."
  (snapshot-value (summary-from-facts (evidence-facts result))))

(defun assess-requirement (requirement dimensions)
  "Return a requirement check, known gaps and unknown measurements."
  (let* ((kind (getf requirement :kind))
         (entry (dimension dimensions
                           (ecase kind
                             (:min-checked-trials :checked-trials)
                             (:all-declared-cases :declared-cases)
                             (:requested-trials-completed :requested-trials))))
         (availability (getf entry :availability))
         (gaps nil) (unknowns nil) (observations nil))
    (cond
      ((eq availability :not-applicable)
       (return-from assess-requirement
         (values (list :requirement requirement :status :not-applicable) nil nil)))
      ((eq availability :not-collected)
       (push (list :kind :measurement-not-collected :dimension (getf entry :kind)
                   :source (getf entry :source)) unknowns))
      ((eq kind :all-declared-cases)
       (dolist (case (getf entry :cases))
         (if (eq :not-collected (getf case :availability))
             (push (list :kind :measurement-not-collected :dimension :declared-cases
                         :case (getf case :name)) unknowns)
             (when (< (getf case :checked) (getf requirement :min-checked))
               (push (list :kind :case-checks-below-minimum :case (getf case :name)
                           :required (getf requirement :min-checked)
                           :observed (getf case :checked)
                           :source (list :case-report :cases (getf case :name))) gaps)))))
      (t
       (let ((observed (getf entry :value))
             (required (if (eq kind :min-checked-trials)
                           (getf requirement :count) (getf entry :required))))
         (setf observations (list :observed observed :required required))
         (when (< observed required)
           (push (list :kind (if (eq kind :min-checked-trials)
                                :checked-trials-below-minimum :requested-trials-not-completed)
                       :required required :observed observed :source (getf entry :source)) gaps)))))
    (values (append (list :requirement requirement
                          :status (cond (gaps :insufficient) (unknowns :unknown) (t :satisfied)))
                    observations)
            (nreverse gaps) (nreverse unknowns))))

(defun assess-evidence (result policy)
  "Assess explicit version-one POLICY against saved evidence, independently of status."
  (let ((policy (validate-evidence-policy policy))
         (summary (evidence-summary result))
         (checks nil) (gaps nil) (unknowns nil))
    (dolist (requirement (getf policy :requirements))
      (multiple-value-bind (check new-gaps new-unknowns)
          (assess-requirement requirement (getf summary :dimensions))
        (push check checks)
        (setf gaps (append gaps new-gaps) unknowns (append unknowns new-unknowns))))
    (let* ((checks (nreverse checks))
           (applicable (some (lambda (check) (not (eq :not-applicable (getf check :status))))
                             checks))
           (status (cond (gaps :insufficient) (unknowns :unknown)
                         (applicable :satisfied) (t :not-assessed))))
      (snapshot-value
       (append (list :schema-version 1 :record-kind :evidence-assessment
                     :execution-status (getf summary :execution-status)
                     :assessment status :scope (getf summary :scope)
                     :subject (getf summary :subject) :policy policy :checks checks
                     :gaps gaps :unknowns unknowns :limitations (getf summary :limitations))
               (unless applicable (list :reason :no-applicable-requirements)))))))
