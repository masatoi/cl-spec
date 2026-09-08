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
                         :key #'compiled-generator-size :initial-value *size*))
         (generator (make-instance 'tuple-generator
                                   :sub-generators
                                   (mapcar #'compiled-generator-generator compiled))))
    (loop for trial from 1 to trials
          do (generate generator)
             ;; CHECK-IT:SHRINK rewrites the tuple generator's cached value in
             ;; place, so the counterexample must be copied out before it runs.
             (let ((arguments (copy-list (cached-value generator))))
               (multiple-value-bind (result condition) (call-property function arguments)
                 (when (or condition (null result))
                   (return (list :status (if condition :error :failed)
                                 :trials trial
                                 :counterexample arguments
                                 :shrunk-counterexample
                                 (when shrink-p
                                   (copy-list (shrink generator (shrinking-test function))))
                                 :condition condition)))))
          finally (return (list :status :passed :trials trials)))))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
