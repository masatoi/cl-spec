;;;; src/time-limits.lisp
(defpackage #:cl-spec/src/time-limits
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:export #:call-with-run-time-limits #:time-limits-requested-p #:time-limits-supported-p
           #:call-catching-run-timeout #:with-trial-clock #:with-run-phase
           #:mark-run-phase #:run-timeout-data #:timeout-unwinding-p
           #:call-with-timed-fixture-cleanup #:with-timer-bookkeeping
           #:with-native-shrink #:with-native-candidate
           #:call-with-run-limit-handoff #:run-clock-start))
(in-package #:cl-spec/src/time-limits)

(defstruct (run-limits (:copier nil))
  "The deadlines and private escape tag for one generated run."
  started deadline trial-ticks cleanup-ticks (tag (list nil)) timeout)

(defstruct (timed-phase (:copier nil))
  "An operation's deadline and the location reached when it expires."
  owner trial deadline limit name cleanup)

#+(and sbcl sb-thread)
(defstruct (deadline-clock (:constructor make-deadline-clock (deadline expire phase))
                           (:copier nil))
  "An armed clock in the current thread."
  deadline expire phase)

(defvar *run-limits* nil)
(defvar *active-run-limits* nil)
(defvar *trial-number* 1)
(defvar *trial-deadline* nil)
(defvar *timed-phase* nil)
(defvar *timer-scopes* nil)
(defvar *paused-timers* nil)

(defvar *backend-options-handoff* nil
  "The exact backend option list carrying the current run clock.")

(defvar *native-shrink-trial* nil
  "The ordinary trial whose native shrink candidates are being evaluated.")

(defvar *native-candidate-active-p* nil
  "Whether this native candidate already has an active clock.")

(defun time-limits-requested-p (options)
  "Return true when OPTIONS requests a run, trial or cleanup time limit."
  (some (lambda (key) (getf options key)) '(:timeout :trial-timeout :cleanup-timeout)))

(defun time-limits-supported-p ()
  "Return whether this Lisp has current-thread timers."
  #+(and sbcl sb-thread) t
  #-(and sbcl sb-thread) nil)

(defmacro with-timer-bookkeeping (&body body)
  "Commit related counters together while a deadline can interrupt the thread."
  #+(and sbcl sb-thread) `(sb-sys:without-interrupts ,@body)
  #-(and sbcl sb-thread) `(progn ,@body))

(defun seconds-to-ticks (seconds)
  (when seconds (ceiling (* (rational seconds) internal-time-units-per-second))))

(defun call-with-run-limit-handoff (options function)
  "Transfer the current deadline to the backend invocation using OPTIONS."
  (let ((*backend-options-handoff* options))
    (funcall function)))

(defun run-clock-start ()
  "Return this timed run's start tick, or the current tick outside a timed run."
  (if *run-limits* (run-limits-started *run-limits*) (get-internal-real-time)))

(defun call-with-run-time-limits (options function
                                  &optional (operator 'call-with-run-time-limits))
  "Bind a new run clock or consume a caller's exact backend handoff."
  (when (and *backend-options-handoff* (eq options *backend-options-handoff*))
    (return-from call-with-run-time-limits
      (let ((*backend-options-handoff* nil))
        (funcall function))))
  (let* ((timed-p (time-limits-requested-p options))
         (ticks (seconds-to-ticks (getf options :timeout)))
         (started (when timed-p (get-internal-real-time))))
    (when (and timed-p (not (time-limits-supported-p)))
      (error 'invalid-argument :operator operator :argument :options
             :datum options :expected-type '(not (satisfies time-limits-requested-p))
             :reason "run time limits require threaded SBCL"))
    (let* ((*run-limits*
             (when timed-p
               (make-run-limits :started started :deadline (when ticks (+ started ticks))
                                :trial-ticks (seconds-to-ticks (getf options :trial-timeout))
                                :cleanup-ticks (seconds-to-ticks
                                                (or (getf options :cleanup-timeout) 1)))))
           (*active-run-limits* (if *run-limits* (cons *run-limits* *active-run-limits*)
                                   *active-run-limits*))
           (*trial-deadline* nil)
           (*trial-number* 1)
           (*native-shrink-trial* nil)
           (*native-candidate-active-p* nil))
      (funcall function))))

(defun run-timeout-data ()
  "Return the active run's owned timeout record, when expired."
  (when *run-limits* (run-limits-timeout *run-limits*)))

(defun timeout-unwinding-p ()
  "Return true while a deadline escape is unwinding through application code."
  (some #'run-limits-timeout *active-run-limits*))

(defun call-catching-run-timeout (function on-timeout)
  "Call FUNCTION, or call ON-TIMEOUT with the owned record after its deadline escape."
  (if *run-limits*
      (let ((outcome (catch (run-limits-tag *run-limits*) (funcall function))))
        (if (run-timeout-data) (funcall on-timeout (run-timeout-data)) outcome))
      (funcall function)))

(defun abort-run-for-timeout (owner trial phase limit cleanup)
  (unless (run-limits-timeout owner)
    (setf (run-limits-timeout owner)
          (list :limit limit :trial trial :phase phase)))
  (when cleanup (setf (getf (run-limits-timeout owner) :cleanup) cleanup))
  (throw (run-limits-tag owner) nil))

(defun call-before-deadline (deadline on-timeout function &optional phase)
  #-(and sbcl sb-thread) (declare (ignore phase))
  (if (null deadline)
      (funcall function)
      #+(and sbcl sb-thread)
      (let* ((scope (make-deadline-clock deadline on-timeout phase))
             (*timer-scopes* (cons scope *timer-scopes*))
             (active t)
             (timer (sb-ext:make-timer
                     (lambda ()
                       (when (and active (not (member scope *paused-timers*)))
                         (funcall on-timeout))))))
        (sb-sys:without-interrupts
          (unwind-protect
               (let ((remaining (- deadline (get-internal-real-time))))
                 (when (<= remaining 0) (funcall on-timeout))
                 (sb-ext:schedule-timer timer (/ remaining internal-time-units-per-second))
                 (multiple-value-prog1 (sb-sys:with-local-interrupts (funcall function))
                   ;; A foreign call or an interrupt-safe extent can delay delivery.
                   (when (>= (get-internal-real-time) deadline) (funcall on-timeout))))
            (setf active nil)
            (sb-ext:unschedule-timer timer))))
      #-(and sbcl sb-thread)
      (funcall on-timeout)))

(defun call-with-trial-clock (trial function)
  (let* ((ticks (when *run-limits* (run-limits-trial-ticks *run-limits*)))
         (*trial-number* trial)
         (*trial-deadline* (when ticks (+ (get-internal-real-time) ticks))))
    (funcall function)))

(defmacro with-trial-clock ((trial) &body body)
  "Use a fresh per-trial deadline, identified by one-based ordinary TRIAL."
  `(call-with-trial-clock ,trial (lambda () ,@body)))

(defun call-with-run-phase (phase function trial)
  (if (null *run-limits*)
      (funcall function)
      (let* ((run-deadline (run-limits-deadline *run-limits*))
             (trial-first (and *trial-deadline*
                               (or (null run-deadline) (< *trial-deadline* run-deadline))))
             (frame (make-timed-phase :owner *run-limits* :trial (or trial *trial-number*) :name phase
                                      :deadline (if trial-first *trial-deadline* run-deadline)
                                      :limit (if trial-first :trial :run)))
             (*timed-phase* frame))
        (call-before-deadline
         (timed-phase-deadline frame)
         (lambda ()
           (abort-run-for-timeout (timed-phase-owner frame) (timed-phase-trial frame)
                                  (timed-phase-name frame) (timed-phase-limit frame)
                                  (timed-phase-cleanup frame)))
         function frame))))

(defmacro with-run-phase ((phase &optional trial) &body body)
  "Bound BODY by the earliest active run or trial deadline."
  `(call-with-run-phase ,phase (lambda () ,@body) ,trial))

(defmacro with-native-shrink ((trial) &body body)
  "Identify the ordinary trial before preparing native shrink candidates."
  `(let ((*native-shrink-trial* (and *run-limits* ,trial)))
     ,@body))

(defun call-with-native-candidate (function)
  (if (and *native-shrink-trial* (not *native-candidate-active-p*))
      (let ((*native-candidate-active-p* t))
        (with-trial-clock (*native-shrink-trial*)
          (with-run-phase (:shrinking) (funcall function))))
      (funcall function)))

(defmacro with-native-candidate (&body body)
  "Time one native candidate from its first preparation or validation step."
  `(call-with-native-candidate (lambda () ,@body)))

(defun mark-run-phase (phase)
  "Record a phase reached by a running trial. Shrinking keeps its own phase."
  (when (and *timed-phase* (eq *run-limits* (timed-phase-owner *timed-phase*))
             (not (eq :shrinking (timed-phase-name *timed-phase*))))
    (setf (timed-phase-name *timed-phase*) phase)))

#+(and sbcl sb-thread)
(defun earliest-active-clock ()
  (let ((earliest nil))
    (dolist (clock *timer-scopes* earliest)
      (let ((phase (deadline-clock-phase clock)))
        (unless (or (member clock *paused-timers*)
                    (and phase (run-limits-timeout (timed-phase-owner phase))))
          (when (or (null earliest)
                    (< (deadline-clock-deadline clock) (deadline-clock-deadline earliest)))
            (setf earliest clock)))))))

#+(and sbcl sb-thread)
(defun finish-timed-cleanup (function)
  (let* ((frame *timed-phase*)
         (pending (find-if #'run-limits-timeout *active-run-limits*))
         (owner (or pending (timed-phase-owner frame)))
         (now (get-internal-real-time))
         (grace (+ now (min (run-limits-cleanup-ticks owner)
                            (run-limits-cleanup-ticks (timed-phase-owner frame)))))
         (clock (earliest-active-clock))
         (clock-phase (when clock (deadline-clock-phase clock)))
         (deadline (when clock (deadline-clock-deadline clock)))
         (run-limit (if clock-phase (timed-phase-limit clock-phase) :cleanup))
         (already-due (and deadline (<= deadline now)))
         (expires-in-cleanup (and deadline (not already-due) (< deadline grace)))
         (limit (if expires-in-cleanup run-limit :cleanup))
         (tag (list nil))
         (*paused-timers* *timer-scopes*)
         (status (catch tag
                   (call-before-deadline (if expires-in-cleanup deadline grace)
                                         (lambda () (throw tag :timeout)) function)))
         (cleanup (if (eq :timeout status) (list :status :timeout :limit limit)
                      (list :status status)))
         (underlying-expiry (or already-due (and expires-in-cleanup (eq status :timeout)))))
    (setf (timed-phase-cleanup frame) cleanup)
    (when pending (setf (getf (run-limits-timeout pending) :cleanup) cleanup))
    (cond
      ;; An enclosing timer can own the earlier deadline of a nested run.
      ((and underlying-expiry (not (eq clock-phase frame)))
       (when clock-phase (setf (timed-phase-cleanup clock-phase) cleanup))
       (funcall (deadline-clock-expire clock)))
      ((and (not pending) (or already-due (eq status :timeout)))
       (abort-run-for-timeout owner (timed-phase-trial frame)
                              (if (eq :shrinking (timed-phase-name frame))
                                  :shrinking :fixture-cleanup)
                              (if already-due run-limit limit) cleanup)))))

(defun call-with-timed-fixture-cleanup (function cleanup)
  "Call FUNCTION and run CLEANUP even after a deadline, within its own bounded grace."
  #+(and sbcl sb-thread)
  (when *timed-phase*
    (return-from call-with-timed-fixture-cleanup
      (sb-sys:without-interrupts
        (unwind-protect (sb-sys:with-local-interrupts (funcall function))
          (mark-run-phase :fixture-cleanup)
          (sb-sys:allow-with-interrupts (finish-timed-cleanup cleanup))))))
  (unwind-protect (funcall function) (funcall cleanup)))
