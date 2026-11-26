;;;; src/time-limits.lisp
(defpackage #:cl-spec/src/time-limits
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-argument)
  (:export #:call-with-run-time-limits #:time-limits-requested-p #:time-limits-supported-p
           #:call-catching-run-timeout #:call-with-run-finalization
           #:with-trial-clock #:with-run-phase
           #:mark-run-phase #:run-timeout-data
           #:call-with-timed-fixture-cleanup #:current-shrink-candidate-phase
           #:with-timer-bookkeeping
           #:call-with-shrink-candidate #:with-native-shrink
           #:with-native-candidate #:with-native-shrink-draw
           #:call-with-run-limit-handoff #:run-clock-start))
(in-package #:cl-spec/src/time-limits)

(defstruct (run-limits (:copier nil))
  "The deadlines and private escape tag for one generated run."
  started deadline trial-ticks cleanup-ticks enclosing-clocks (tag (list nil)) timeout)

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

(defvar *shrink-candidate-owners* nil
  "Active owners of recoverable shrink-candidate trial deadlines.")

(defvar *native-shrink-trial* nil
  "The ordinary trial whose native shrink candidates are being evaluated.")

(defvar *native-candidate-runner* nil
  "The backend's clock and rejection handler for a native candidate predicate.")

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
                                :enclosing-clocks *timer-scopes*
                                :trial-ticks (seconds-to-ticks (getf options :trial-timeout))
                                :cleanup-ticks (seconds-to-ticks
                                                (or (getf options :cleanup-timeout) 1)))))
           (*active-run-limits* (if *run-limits* (cons *run-limits* *active-run-limits*)
                                   *active-run-limits*))
           (*trial-deadline* nil)
           (*trial-number* 1)
           (*native-shrink-trial* nil)
           (*native-candidate-runner* nil)
           (*native-candidate-active-p* nil))
      (funcall function))))

(defun run-timeout-data ()
  "Return the active run's owned timeout record, when expired."
  (when *run-limits* (run-limits-timeout *run-limits*)))

(defun call-catching-run-timeout (function on-timeout)
  "Call FUNCTION, or call ON-TIMEOUT with the owned record after its deadline escape."
  (if *run-limits*
      (let ((outcome (catch (run-limits-tag *run-limits*) (funcall function))))
        (if (run-timeout-data) (funcall on-timeout (run-timeout-data)) outcome))
      (funcall function)))

(defun retain-incomplete-cleanup (previous cleanup)
  "Keep the first incomplete cleanup recorded for a cancellation."
  (if (and previous (not (eq :completed (getf previous :status))))
      previous
      cleanup))

(defun record-timeout-cleanup (owner cleanup)
  (setf (getf (run-limits-timeout owner) :cleanup)
        (retain-incomplete-cleanup (getf (run-limits-timeout owner) :cleanup) cleanup)))

(defun abort-run-for-timeout (owner trial phase limit cleanup)
  (unless (run-limits-timeout owner)
    (setf (run-limits-timeout owner)
          (list :limit limit :trial trial :phase phase)))
  (when cleanup (record-timeout-cleanup owner cleanup))
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

(defun call-with-run-finalization (trial function)
  "Run a finalization hook under the remaining deadline and return any timeout."
  (call-catching-run-timeout
   (lambda ()
     (with-run-phase (:finalization trial) (funcall function))
     nil)
   #'identity))

(defun call-with-shrink-candidate (trial function on-timeout)
  "Evaluate one candidate or call ON-TIMEOUT after its recoverable trial expiry."
  (flet ((attempt ()
           (with-trial-clock (trial)
             (with-run-phase (:shrinking) (funcall function)))))
    (let* ((run *run-limits*)
           (ticks (when run (run-limits-trial-ticks run))))
      (if (null ticks)
          (attempt)
          ;; The enclosing shrink phase owns the absolute run deadline. A separate
          ;; owner keeps this attempt's timeout private until its cleanup finishes.
          (let* ((*run-limits* (make-run-limits
                               :started (run-limits-started run) :trial-ticks ticks
                               :cleanup-ticks (run-limits-cleanup-ticks run)
                               :enclosing-clocks *timer-scopes*))
                 (*shrink-candidate-owners* (cons *run-limits* *shrink-candidate-owners*))
                 (*active-run-limits* (cons *run-limits* *active-run-limits*)))
            (call-catching-run-timeout
             #'attempt
             (lambda (timeout)
               (let ((cleanup (getf timeout :cleanup)))
                 (if (and (eq :trial (getf timeout :limit))
                          (or (null cleanup) (eq :completed (getf cleanup :status))))
                     (funcall on-timeout)
                     (abort-run-for-timeout run trial (getf timeout :phase)
                                            (getf timeout :limit) cleanup))))))))))

(defmacro with-native-shrink ((trial &optional candidate-runner) &body body)
  "Identify the failing trial and the backend's native candidate clock boundary."
  `(let ((*native-shrink-trial* (and *run-limits* ,trial))
         (*native-candidate-runner* ,candidate-runner))
     ,@body))

(defun call-with-native-candidate (function rejectable-p)
  (if (and *native-shrink-trial* (not *native-candidate-active-p*))
      (let ((*native-candidate-active-p* t))
        (if (and rejectable-p *native-candidate-runner*)
            (funcall *native-candidate-runner* *native-shrink-trial* function)
            (with-trial-clock (*native-shrink-trial*)
              (with-run-phase (:shrinking) (funcall function)))))
      (funcall function)))

(defmacro with-native-candidate (&body body)
  "Time one native candidate from its first preparation or validation step."
  `(call-with-native-candidate (lambda () ,@body) t))

(defmacro with-native-shrink-draw (&body body)
  "Time a native draw that needs to return a generated value."
  `(call-with-native-candidate (lambda () ,@body) nil))

(defun current-shrink-candidate-phase ()
  "Capture the phase owned by the current recoverable shrink candidate."
  (when (and *timed-phase* (eq (timed-phase-owner *timed-phase*) *run-limits*)
             (member *run-limits* *shrink-candidate-owners* :test #'eq))
    *timed-phase*))

(defun mark-run-phase (phase)
  "Record a phase reached by a running trial. Shrinking keeps its own phase."
  (when (and *timed-phase* (eq *run-limits* (timed-phase-owner *timed-phase*))
             (not (eq :shrinking (timed-phase-name *timed-phase*))))
    (setf (timed-phase-name *timed-phase*) phase)))

#+(and sbcl sb-thread)
(defun earliest-active-clock (clocks &optional excluded-phase)
  (let ((earliest nil))
    (dolist (clock clocks earliest)
      (let ((phase (deadline-clock-phase clock)))
        (unless (or (member clock *paused-timers*)
                    (and phase (or (eq phase excluded-phase)
                                   (run-limits-timeout (timed-phase-owner phase)))))
          (when (or (null earliest)
                    (< (deadline-clock-deadline clock) (deadline-clock-deadline earliest)))
            (setf earliest clock)))))))

#+(and sbcl sb-thread)
(defun record-phase-cleanup (phase cleanup)
  (setf (timed-phase-cleanup phase)
        (retain-incomplete-cleanup (timed-phase-cleanup phase) cleanup)))

#+(and sbcl sb-thread)
(defun finish-timed-cleanup (function frame pending body-returned-p)
  (let* ((owner (or pending (timed-phase-owner frame)))
         (now (get-internal-real-time))
         (grace (+ now (min (run-limits-cleanup-ticks owner)
                            (run-limits-cleanup-ticks
                             (if frame (timed-phase-owner frame) owner)))))
         ;; The candidate's own trial deadline rejects it after cleanup. Keep
         ;; the original cleanup cap and the clocks that enclose the candidate.
         (candidate-deadline
           (when (and frame (not pending) (eq :trial (timed-phase-limit frame))
                      (member owner *shrink-candidate-owners* :test #'eq))
             (timed-phase-deadline frame)))
         ;; An in-flight timeout can yield to a clock enclosing its owner.
         (clocks (if pending (run-limits-enclosing-clocks pending) *timer-scopes*))
         (clock (earliest-active-clock clocks (when candidate-deadline frame)))
         (clock-phase (when clock (deadline-clock-phase clock)))
         (enclosing-clock (if (and frame (eq clock-phase frame))
                              (earliest-active-clock clocks frame)
                              clock))
         (deadline (when clock (deadline-clock-deadline clock)))
         (run-limit (if clock-phase (timed-phase-limit clock-phase) :cleanup))
         (already-due (and deadline (<= deadline now)))
         (expires-in-cleanup (and deadline (not already-due) (<= deadline grace)))
         (limit (if expires-in-cleanup run-limit :cleanup))
         (tag (list nil))
         (*paused-timers* *timer-scopes*)
         (status (catch tag
                   (call-before-deadline (if expires-in-cleanup deadline grace)
                                         (lambda () (throw tag :timeout)) function)))
         (cleanup (if (eq :timeout status) (list :status :timeout :limit limit)
                      (list :status status)))
         (finished (get-internal-real-time))
         (candidate-expired-p
           (and candidate-deadline (<= candidate-deadline (min grace finished))))
         (underlying-expiry (or already-due (and expires-in-cleanup (eq status :timeout))))
         ;; Deferred delivery can leave the enclosing deadline due after the private timer fires.
         (expired-enclosing-clock
           (cond
             ((and underlying-expiry (eq clock enclosing-clock)) clock)
             ((and enclosing-clock
                   (<= (deadline-clock-deadline enclosing-clock) finished))
              enclosing-clock))))
    (when frame (record-phase-cleanup frame cleanup))
    (when pending (record-timeout-cleanup pending cleanup))
    ;; An external transfer already unwinding continues after bounded cleanup.
    (when (or body-returned-p pending)
      (cond
        (expired-enclosing-clock
         (let ((phase (deadline-clock-phase expired-enclosing-clock)))
           (when phase (record-phase-cleanup phase cleanup)))
         (funcall (deadline-clock-expire expired-enclosing-clock)))
        ((and (not pending) (or already-due candidate-expired-p (eq status :timeout)))
         (abort-run-for-timeout owner (timed-phase-trial frame)
                                (if (eq :shrinking (timed-phase-name frame))
                                    :shrinking :fixture-cleanup)
                                (cond (already-due run-limit)
                                      (candidate-expired-p :trial)
                                      (t limit))
                                cleanup))))))

(defun call-with-timed-fixture-cleanup (function cleanup &optional candidate-phase)
  "Run FUNCTION and CLEANUP with active deadlines and an optional CANDIDATE-PHASE."
  #-(and sbcl sb-thread) (declare (ignore candidate-phase))
  #+(and sbcl sb-thread)
  (when *active-run-limits*
    (return-from call-with-timed-fixture-cleanup
      (sb-sys:without-interrupts
        (let ((frame (or candidate-phase
                         (when (and *timed-phase*
                                    (eq (timed-phase-owner *timed-phase*) *run-limits*))
                           *timed-phase*)))
              (*timed-phase* (or candidate-phase *timed-phase*))
              (body-returned-p nil)
              (prior-timeouts (remove-if-not #'run-limits-timeout *active-run-limits*)))
          (unwind-protect
               (multiple-value-prog1
                   (sb-sys:with-local-interrupts (funcall function))
                 ;; Mark completion with interrupts disabled.
                 (setf body-returned-p t))
            (let ((pending (find-if (lambda (limits)
                                      (and (run-limits-timeout limits)
                                           (not (member limits prior-timeouts :test #'eq))))
                                    *active-run-limits*)))
              ;; Only a newly triggered run timeout lends grace to an untimed fixture.
              (if (or frame (and pending (not body-returned-p)))
                  (progn
                    (mark-run-phase :fixture-cleanup)
                    (sb-sys:allow-with-interrupts
                      (finish-timed-cleanup cleanup frame pending body-returned-p)))
                  (sb-sys:with-local-interrupts (funcall cleanup)))))))))
  (unwind-protect (funcall function) (funcall cleanup)))
