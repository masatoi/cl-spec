;;;; src/utils/random.lisp
;;;;
;;;; Seed handling (specification §15).  An integer seed is the public contract
;;;; because that is what section 14's result schema shows and what survives a
;;;; trip through JSON to an agent.  ANSI gives no way to derive a RANDOM-STATE
;;;; from an integer, so the implementation-specific part is confined to this
;;;; file: adding another Lisp means adding one reader conditional here.

(defpackage #:cl-spec/src/utils/random
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unsupported-seed)
  (:export #:make-seed
           #:seed->random-state))

(in-package #:cl-spec/src/utils/random)

(defconstant +seed-limit+ (expt 2 62)
  "Exclusive upper bound of the seeds MAKE-SEED draws.")

(defun make-seed ()
  "Return a fresh integer seed drawn from the current *RANDOM-STATE*."
  (random +seed-limit+))

(defun seed->random-state (seed)
  "Return a fresh RANDOM-STATE derived deterministically from integer SEED.

The caller binds *RANDOM-STATE* to the result; the current state is left
untouched.  Signals UNSUPPORTED-SEED on implementations with no such mapping."
  (check-type seed (integer 0))
  #+sbcl (sb-ext:seed-random-state seed)
  #-sbcl (error 'unsupported-seed))
