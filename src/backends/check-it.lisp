;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
  (:import-from #:check-it
                #:*num-trials*
                #:generate
                #:*size*
                #:*list-size*
                #:*list-size-decay*
                #:*bias-sensitivity*
                #:*recursive-bias-decay*
                #:cached-value
                #:shrink
                #:tuple-generator)
  (:import-from #:cl-spec/src/backends/check-it-generators
                #:compile-spec-generator)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:backend-default-trials)
  (:import-from #:cl-spec/src/execution
                #:snapshot-value #:observe-trial #:observation-failure-p #:failure-identities-match-p #:same-value-p
                #:trial-observation-arguments #:trial-observation-arguments-mutated-p
                #:trial-observation-status
                #:trial-observation-signature)
  (:import-from #:cl-spec/src/validator #:compile-validator)
  (:import-from #:cl-spec/src/property
                #:property-arguments
                #:property-metadata)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:check-it-backend
           #:install-check-it-backend
           #:default-trials))

(in-package #:cl-spec/src/backends/check-it)

(defparameter *base-size* 10
  "The generation size a run starts from, independent of anything ambient.

A literal, not a snapshot of CHECK-IT:*SIZE*: snapshotting moved the dependency
from run time to load time without removing it, so an image that tuned check-it
before loading cl-spec replayed one seed to different inputs than an image that
did not, with nothing on the result to say so.  RUN-GENERATED-TEST
raises *SIZE* to whatever the widest argument bound needs, and reading the
ambient value made that raise cumulative: a run started inside another -- a
property body that calls CHECK-FUNCTION, a :POST that calls RUN-PROPERTY, both
of which this design invites -- inherited the outer run's size and generated
different inputs.  The same call then reported :FAILED nested and :PASSED alone,
and replaying the nested result contradicted it, which §72.3 forbids.")

(defparameter *base-list-size* 20
  "The longest list a run generates from, independent of anything ambient.

CHECK-IT:LIST-GENERATOR draws a length against *LIST-SIZE* and shrinks that
allowance for nested lists by *LIST-SIZE-DECAY*, so leaving the pair ambient made
a LIST-OF or VECTOR-OF argument's values depend on how the image happened to have
tuned check-it before cl-spec loaded.  These literals repeat check-it's own
defaults on purpose: the pin is what makes generation a function of the spec, the
seed and the backend (§73.4 #7).")

(defparameter *base-list-size-decay* 0.8
  "The factor *BASE-LIST-SIZE* shrinks by for a nested list.  See it for why.")

(defparameter *base-bias-sensitivity* 6.0
  "The sigmoid steepness CHECK-IT:CHOOSE-GENERATOR picks a branch with.

An OR, a MEMBER and a NULLABLE all draw through CHOOSE-GENERATOR, so an ambient
value here decides which branch a value comes from: the same seed picked
different branches in differently tuned images.  See *BASE-LIST-SIZE*.")

(defparameter *base-recursive-bias-decay* 1.5
  "The factor a recursive generator's bias decays by.  See *BASE-LIST-SIZE*.

No recursive spec has a generator in this version, so this changes nothing yet.
It is pinned with the rest so that adding one does not reintroduce an ambient
input -- the kind of gap that surfaces only as a replay disagreeing with the
result it was handed (§72.3).")

(defmacro with-generation-environment ((size &key trials) &body body)
  "Run BODY with every check-it special that decides what is generated pinned.

SIZE is the CHECK-IT:*SIZE* to bind, already raised to whatever the widest
argument's bounds need.  TRIALS, when supplied, also pins CHECK-IT:*NUM-TRIALS*
to the count this run resolved, so nothing reached from BODY reads a trial count
other than the one the run is running.  That count is not thereby hidden: it is
what RUN-PROPERTY resolved and recorded on the result.

Generation is documented as a function of the spec, the seed and the backend
(§15), and it was not one.  RUN-GENERATED-TEST pinned *SIZE* while *LIST-SIZE*,
*LIST-SIZE-DECAY*, *BIAS-SENSITIVITY* and *RECURSIVE-BIAS-DECAY* stayed ambient,
so one seed produced different arguments in a differently tuned image; and
GENERATE-VALUE read *SIZE* ambiently rather than from the generator it was given,
so SAMPLE could show a distribution no run draws (§73.4 #6, #7).  One place binds
them all, which is what keeps the two from drifting apart again."
  `(let ((*size* ,size)
         (*list-size* *base-list-size*)
         (*list-size-decay* *base-list-size-decay*)
         (*bias-sensitivity* *base-bias-sensitivity*)
         (*recursive-bias-decay* *base-recursive-bias-decay*)
         ,@(when trials `((*num-trials* ,trials))))
     ,@body))

(defclass check-it-backend ()
  ()
  (:documentation "Generator backend delegating to the check-it library."))

(defun default-trials ()
  "Return check-it's current default number of trials per property run."
  *num-trials*)

(defstruct (compiled-generator (:constructor make-compiled-generator (generator size)))
  "A check-it generator together with the CHECK-IT:*SIZE* its bounds require.

Pairing the two is what stops check-it from clamping a range away: *SIZE* has to
be raised around GENERATE, and only the compiler knows how far."
  (generator nil :read-only t)
  (size 0 :read-only t))

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator paired with the size its bounds need.

OPTIONS is accepted for protocol compatibility; check-it takes its sizing from
its own specials rather than per-generator options."
  (declare (ignore backend options))
  (multiple-value-bind (generator size) (compile-spec-generator spec context)
    (make-compiled-generator generator size)))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally from a seeded state.

The generation environment is the one RUN-GENERATED-TEST binds, so a value drawn
here and a value drawn inside a run come from the same distribution, at the same
size -- the size COMPILED-GENERATOR's own bounds require, not whatever *SIZE*
happened to be ambient.  Reading the ambient value made a SAMPLE taken inside
another run inherit the outer run's size, and let a SAMPLE taken alone show a
distribution no run draws (§73.4 #6)."
  (declare (ignore backend))
  (flet ((draw ()
           (with-generation-environment
               ((max *base-size* (compiled-generator-size compiled-generator)))
             (generate (compiled-generator-generator compiled-generator)))))
    (if seed
        (let ((*random-state* (seed->random-state seed)))
          (draw))
        (draw))))

(defmethod backend-default-trials ((backend check-it-backend))
  "Return check-it's current default number of trials."
  (declare (ignore backend))
  *num-trials*)

(defun admitted-arguments-p (validators arguments)
  "Check each candidate against its argument spec before invoking the property."
  (loop for validator in validators
        do (unless (and (consp arguments) (funcall validator (car arguments)))
             (return-from admitted-arguments-p nil))
           (setf arguments (cdr arguments)))
  (null arguments))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Generate trials and retain only admitted, observed reductions of the original failure.
The shrinker's return value is not evidence: some generators transform it after
the last callback. Reject internal representations and domain violations before
calling user code, and keep existing evidence if shrinking itself fails."
  (let* ((context (list :registry (getf options :registry)))
         (trials (getf options :trials))
         (shrink-p (getf (property-metadata property) :shrink t))
         (compiled (loop for (nil spec) in (property-arguments property)
                         collect (compile-generator backend spec :context context)))
         (validators (loop for (nil spec) in (property-arguments property)
                           collect (compile-validator spec :context context)))
         (generator (make-instance 'tuple-generator
                                   :sub-generators
                                   (mapcar #'compiled-generator-generator compiled)))
         (rejected 0))
    (with-generation-environment
        ((reduce #'max compiled
                 :key #'compiled-generator-size :initial-value *base-size*)
         :trials trials)
      (loop for trial from 1 to trials
            do (generate generator)
               (let ((original (observe-trial property (cached-value generator)
                                              :context context)))
                 (when (eq :rejected (trial-observation-status original))
                   (incf rejected))
                 (when (observation-failure-p original)
                   (let ((accepted nil) (different nil))
                     (when (and shrink-p (property-arguments property)
                                (not (trial-observation-arguments-mutated-p original)))
                       (handler-case
                           (block shrink-search
                             (shrink
                              generator
                              (lambda (arguments)
                                (handler-case
                                    (let ((before (snapshot-value arguments))
                                           (admitted (admitted-arguments-p validators arguments)))
                                      (unless (same-value-p before arguments)
                                        (return-from shrink-search nil))
                                      (if (not admitted)
                                          t
                                          (let ((candidate
                                                  (observe-trial property arguments
                                                                 :context context)))
                                            (when (trial-observation-arguments-mutated-p candidate)
                                              (return-from shrink-search nil))
                                            (cond
                                              ((not (observation-failure-p candidate)) t)
                                              ((failure-identities-match-p
                                                (trial-observation-signature original)
                                                (trial-observation-signature candidate))
                                               (unless (same-value-p
                                                        (trial-observation-arguments original)
                                                        (trial-observation-arguments candidate))
                                                 (setf accepted candidate))
                                               nil)
                                              (t (setf different t) t)))))
                                  (error () (setf different t) t)))))
                         (error () (setf different t))))
                     (return
                       (list :status (trial-observation-status (or accepted original))
                             :trials trial :rejected rejected
                             :failure original :shrunk-failure accepted
                             :shrunk-outcome (cond (accepted :used)
                                                   (different :different-failure)
                                                   (t :none)))))))
            finally (return (list :status :passed :trials trials :rejected rejected))))))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
