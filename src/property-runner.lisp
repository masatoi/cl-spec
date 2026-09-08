;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
                #:property-trials)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-property)
  (:import-from #:cl-spec/src/generator
                #:current-generator-backend
                #:run-generated-test
                #:backend-default-trials)
  (:import-from #:cl-spec/src/utils/random
                #:make-seed
                #:seed->random-state)
  (:export #:property-result
           #:property-result-status
           #:property-result-property
           #:property-result-trials
           #:property-result-seed
           #:property-result-counterexample
           #:property-result-shrunk-counterexample
           #:property-result-condition
           #:property-result-elapsed
           #:run-property
           #:run-properties
           #:replay-property))

(in-package #:cl-spec/src/property-runner)

(defclass property-result ()
  ((status :initarg :status
           :initform :pending
           :reader property-result-status
           :documentation "One of :PASSED, :FAILED, :ERROR, :SKIPPED or
:PENDING.")
   (property :initarg :property
             :initform nil
             :reader property-result-property
             :documentation "Name of the property that was run.")
   (trials :initarg :trials
           :initform nil
           :reader property-result-trials
           :documentation "Number of trials actually executed.")
   (seed :initarg :seed
         :initform nil
         :reader property-result-seed
         :documentation "Random seed the run started from, for replay.")
   (counterexample :initarg :counterexample
                   :initform nil
                   :reader property-result-counterexample
                   :documentation "Arguments of the first failing trial.")
   (shrunk-counterexample :initarg :shrunk-counterexample
                          :initform nil
                          :reader property-result-shrunk-counterexample
                          :documentation "Minimal failing arguments after
shrinking.  This is the value an agent should be shown first.")
   (signalled-condition :initarg :condition
                        :initform nil
                        :reader property-result-condition
                        :documentation "Condition signalled by the property
body, or NIL.")
   (elapsed :initarg :elapsed
            :initform nil
            :reader property-result-elapsed
            :documentation "Wall clock seconds the run took, or NIL."))
  (:documentation "Structured outcome of running one property.

A property run is never reported as a bare boolean: the seed, the trial count
and the shrunk counterexample are what make a failure actionable."))

(declaim (ftype (function ((or symbol property)
                           &key (:profile t) (:seed t) (:options t) (:registry t))
                          (values property-result &optional))
                run-property))

(defun resolve-trials (property profile backend)
  "Return the trial count for PROPERTY under PROFILE (specification §33).

PROPERTY-TRIALS is a plist keyed by profile; a property that names no count for
the profile in effect falls back to the backend's own default."
  (let ((table (property-trials property)))
    (or (and table (getf table (or profile :normal)))
        (backend-default-trials backend))))

(defun name-arguments (property values)
  "Return VALUES as a plist keyed by PROPERTY's argument variables.

The backend reports counterexamples positionally; this is where they become the
{name: value} shape section 14 shows."
  (when values
    (loop for (variable nil) in (property-arguments property)
          for value in values
          append (list variable value))))

(defun run-property (property-designator &key profile seed options (registry *registry*))
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend."
  (let* ((property (resolve-property property-designator registry))
         (backend (current-generator-backend))
         (effective-seed (or seed (make-seed)))
         (trials (resolve-trials property profile backend))
         (start (get-internal-real-time))
         ;; One binding covers generation and shrinking alike, because the whole
         ;; trial loop lives inside this single call.
         (outcome (let ((*random-state* (seed->random-state effective-seed)))
                    (run-generated-test backend property
                                        :options (list* :trials trials
                                                        :registry registry
                                                        options))))
         (elapsed (/ (float (- (get-internal-real-time) start))
                     internal-time-units-per-second)))
    (make-instance 'property-result
                   :status (getf outcome :status)
                   :property (property-name property)
                   :trials (getf outcome :trials)
                   :seed effective-seed
                   :counterexample (name-arguments property (getf outcome :counterexample))
                   :shrunk-counterexample (name-arguments
                                           property (getf outcome :shrunk-counterexample))
                   :condition (getf outcome :condition)
                   :elapsed elapsed)))

(defun run-properties (property-designators &key profile options (registry *registry*))
  "Run each property in PROPERTY-DESIGNATORS and return the results in order.

Each run draws its own seed, so one failure can be replayed without re-running
the others."
  (mapcar (lambda (designator)
            (run-property designator :profile profile :options options :registry registry))
          property-designators))

(defun replay-property (property-designator seed &key options (registry *registry*))
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

SEED is either the integer seed of an earlier run or the PROPERTY-RESULT that
run produced, since section 15 shows both spellings and an agent holding a
result should not have to dig the seed out of it."
  (run-property property-designator
                :seed (if (typep seed 'property-result)
                          (property-result-seed seed)
                          seed)
                :options options
                :registry registry))
