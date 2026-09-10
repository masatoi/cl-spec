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
  (:import-from #:cl-spec/src/property
                #:property-arguments
                #:property-function
                #:property-metadata)
  (:import-from #:cl-spec/src/utils/random
                #:seed->random-state)
  (:export #:check-it-backend
           #:install-check-it-backend
           #:default-trials))

(in-package #:cl-spec/src/backends/check-it)

(defparameter *base-size* *size*
  "CHECK-IT:*SIZE* as it stands when this file is loaded.

Generation starts from this rather than from the ambient value.  RUN-GENERATED-TEST
raises *SIZE* to whatever the widest argument bound needs, and reading the
ambient value made that raise cumulative: a run started inside another -- a
property body that calls CHECK-FUNCTION, a :POST that calls RUN-PROPERTY, both
of which this design invites -- inherited the outer run's size and generated
different inputs.  The same call then reported :FAILED nested and :PASSED alone,
and replaying the nested result contradicted it, which §72.3 forbids.")

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
  "Draw one value from COMPILED-GENERATOR, optionally from a seeded state."
  (declare (ignore backend))
  (flet ((draw ()
           (let ((*size* (max *size* (compiled-generator-size compiled-generator))))
             (generate (compiled-generator-generator compiled-generator)))))
    (if seed
        (let ((*random-state* (seed->random-state seed)))
          (draw))
        (draw))))

(defmethod backend-default-trials ((backend check-it-backend))
  "Return check-it's current default number of trials."
  (declare (ignore backend))
  *num-trials*)

(defun call-property (function arguments)
  "Apply FUNCTION to ARGUMENTS, returning (values RESULT CONDITION).

A signalled condition is data here rather than a stack unwind: section 13 counts
it as a failure, and the result has to say which kind of failure it was."
  (handler-case (values (apply function arguments) nil)
    (error (condition) (values nil condition))))

(defun shrinking-test (function)
  "Return the one-argument test CHECK-IT:SHRINK drives.

SHRINK hands the test a whole argument list, and an error during shrinking means
the smaller value still fails."
  (lambda (arguments)
    (handler-case (apply function arguments)
      (error () nil))))

(defun copy-generated-value (value)
  "Return a copy of VALUE that shares no mutable storage with it.

CHECK-IT's shrinker mutates a compound generator's cached value in place
(SETF NTH on a list-generator's cached list, SETF NTH on a tuple-generator's
cached tuple) rather than always allocating a fresh spine, and a nested
LIST-OF, VECTOR-OF or TUPLE argument's elements are EQ to the sub-generator
that produced them.  A shallow COPY-LIST at the top level only protects the
top-level spine, so a captured compound counterexample can still be corrupted
by a shrink that runs later.

Recursion follows CONS cells and non-string vectors, because those are the
only two compound shapes this backend's generators ever build in place.  A
string is left alone because CHECK-IT:JOIN-LIST always allocates a fresh one
when a string is shrunk; every other value (numbers, characters, symbols) is
immutable as far as generation and shrinking are concerned, so sharing it is
safe."
  (cond
    ((consp value)
     (cons (copy-generated-value (car value)) (copy-generated-value (cdr value))))
    ((stringp value)
     value)
    ((vectorp value)
     (map 'vector #'copy-generated-value value))
    (t value)))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Run PROPERTY through check-it, shrinking any counterexample.

Returns the plist the caller assembles into a PROPERTY-RESULT:

  (:status :passed | :failed | :error
   :trials <integer>
   :counterexample <list of values>
   :shrunk-counterexample <list of values>
   :condition <condition or NIL>)

Counterexamples are positional.  Naming the arguments is the caller's job, which
is what keeps this method from having to know the property's variables."
  (let* ((context (list :registry (getf options :registry)))
         (trials (getf options :trials))
         (function (property-function property))
         (shrink-p (getf (property-metadata property) :shrink t))
         (compiled (loop for (nil spec) in (property-arguments property)
                         collect (compile-generator backend spec :context context)))
         ;; One binding covers generation and shrinking alike, and has to be
         ;; wide enough for the widest bound any argument asks for.
         (*size* (reduce #'max compiled
                         :key #'compiled-generator-size :initial-value *base-size*))
         (generator (make-instance 'tuple-generator
                                   :sub-generators
                                   (mapcar #'compiled-generator-generator compiled))))
    (loop for trial from 1 to trials
          do (generate generator)
             ;; CHECK-IT:SHRINK rewrites the tuple generator's cached value in
             ;; place, so the counterexample must be copied out before it runs
             ;; -- deeply, since a compound argument's elements are EQ to a
             ;; sub-generator's own cached value and get mutated the same way.
             (let ((arguments (copy-generated-value (cached-value generator))))
               (multiple-value-bind (result condition) (call-property function arguments)
                 (when (or condition (null result))
                   (return (list :status (if condition :error :failed)
                                 :trials trial
                                 :counterexample arguments
                                 :shrunk-counterexample
                                 (when shrink-p
                                   (copy-generated-value
                                    (shrink generator (shrinking-test function))))
                                 :condition condition)))))
          finally (return (list :status :passed :trials trials)))))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
