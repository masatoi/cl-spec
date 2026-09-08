;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/property
                #:property)
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
                           &key (:profile t) (:seed t) (:options t))
                          (values property-result &optional))
                run-property))

(defun run-property (property-designator &key profile seed options)
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS plist and defaults to
:NORMAL.  SEED forces a starting seed.  OPTIONS is passed through to the
generator backend.  Signals NO-GENERATOR-BACKEND when no backend is installed.

Not implemented yet."
  (declare (ignore property-designator profile seed options))
  (error 'not-implemented :operator 'run-property))

(defun run-properties (property-designators &key profile options)
  "Run each property in PROPERTY-DESIGNATORS and return a list of PROPERTY-RESULT.

Every property is run even when an earlier one fails, so that one call reports
the whole picture.

Not implemented yet."
  (declare (ignore property-designators profile options))
  (error 'not-implemented :operator 'run-properties))

(defun replay-property (property-designator seed &key options)
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

Given the same seed and the same property definition the generated sequence is
identical, which is what makes a reported failure reproducible.

Not implemented yet."
  (declare (ignore property-designator seed options))
  (error 'not-implemented :operator 'replay-property))
