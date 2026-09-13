;;;; src/normalize.lisp
;;;;
;;;; Spec DSL -> Semantic IR (specification §9, §37).  The macros in
;;;; SRC/DSL.LISP are pure syntax sugar; all meaning is assigned here, so the
;;;; DSL can change without disturbing the IR or the introspection API.

(defpackage #:cl-spec/src/normalize
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir
                #:spec #:type-spec #:reference-spec #:predicate-spec #:member-spec
                #:range-spec #:instance-of-spec #:and-spec #:or-spec #:not-spec
                #:list-of-spec #:vector-of-spec #:tuple-spec #:nullable-spec)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:make-field-definition)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:normalize-spec-form
           #:*spec-primitives*))

(in-package #:cl-spec/src/normalize)

(defparameter *spec-primitives*
  '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
    "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "PLIST"
    "INSTANCE-OF")
  "Spec DSL head names the MVP normalizer accepts (specification §9, §52).

Heads are matched by SYMBOL-NAME, not by symbol identity: a DSL form is written
in the user's own package, so RANGE in (RANGE 1 *) there is not EQ to the RANGE
interned here.  Anything not named in this list is either a reference to a
registered spec or an error.")

(declaim (ftype (function (t &key (:name symbol) (:generator symbol)
                            (:source-location list))
                          spec)
                normalize-spec-form))

(defun cl-type-name-p (symbol)
  "Return true when SYMBOL is a COMMON-LISP symbol usable as a type specifier.

Both halves matter.  Requiring the COMMON-LISP package keeps normalization
independent of the user's CLOS environment: without it, a user class named USER
would silently turn (OR NULL USER) into a type check instead of a reference."
  (and (symbolp symbol)
       (eq (symbol-package symbol) (find-package '#:common-lisp))
       (handler-case (progn (typep nil symbol) t)
         (error () nil))))

(defun unbounded-marker-p (object)
  "Return true when OBJECT is the * that the DSL writes for an open bound."
  (and (symbolp object) (string= (symbol-name object) "*")))

(defun spec-initargs (form name source-location generator)
  "Return the initargs every IR node receives, whatever its class.

GENERATOR is threaded through rather than read from the environment, because only
the top level node of a definition receives one: a (:GENERATOR NAME) clause
belongs to the definition, so a child normalized from inside it is passed NIL."
  (list :name name :source-form form :source-location source-location
        :generator generator))

(defun require-arity (args count form)
  "Return ARGS, signalling INVALID-SPEC-FORM unless it has exactly COUNT elements."
  (unless (= (length args) count)
    (error 'invalid-spec-form :form form
                              :reason (format nil "expected ~D argument~:P, got ~D"
                                              count (length args))))
  args)

(defun normalize-symbol (form name source-location generator)
  "Normalize a bare symbol into a TYPE-SPEC or a REFERENCE-SPEC."
  (if (cl-type-name-p form)
      (apply #'make-instance 'type-spec :type-specifier form
             (spec-initargs form name source-location generator))
      (apply #'make-instance 'reference-spec :target form
             (spec-initargs form name source-location generator))))

(defun normalize-range (args form name source-location generator)
  "Normalize the arguments of a RANGE form into a RANGE-SPEC."
  (multiple-value-bind (base-type minimum maximum)
      (cond ((and (= (length args) 3)
                  (symbolp (first args))
                  (not (unbounded-marker-p (first args))))
             (values (first args) (second args) (third args)))
            ((= (length args) 2)
             (values nil (first args) (second args)))
            (t
             (error 'invalid-spec-form :form form
                                       :reason "RANGE takes (range lo hi) or (range type lo hi)")))
    (unless (member base-type '(nil integer real))
      (error 'invalid-spec-form :form form
                                :reason "RANGE is numeric; its base type must be INTEGER or REAL"))
    ;; A mis-write such as (range integer *) is meant to say "any integer",
    ;; but with only two arguments it instead matches the two-argument
    ;; grammar -- (range lo hi) with no base type -- and MINIMUM becomes the
    ;; symbol INTEGER.  Left unchecked, that symbol survives normalization
    ;; and only breaks later, inside VALIDP, as an unrelated TYPE-ERROR.
    ;; Reject it here, at the same point the three-argument branch already
    ;; rejects a bad base type.
    (dolist (bound-value (list minimum maximum))
      (unless (or (unbounded-marker-p bound-value) (realp bound-value))
        (error 'invalid-spec-form :form form
                                  :reason (format nil "RANGE bounds must be a number or *, got ~S"
                                                  bound-value))))
    (flet ((bound (value) (if (unbounded-marker-p value) :unbounded value)))
      (apply #'make-instance 'range-spec
             :base-type base-type
             :minimum (bound minimum)
             :maximum (bound maximum)
             (spec-initargs form name source-location generator)))))

(defun normalize-plist (form name source-location generator)
  "Normalize strict required/optional field clauses without assuming list well-formedness."
  (let ((seen-clauses nil)
        (seen-keys nil)
        (fields nil)
        (closed-p nil))
    (flet ((refuse (reason)
             (error 'invalid-spec-form :form form :reason reason)))
      (unless (finite-list-p form)
        (refuse "PLIST must be a finite proper list"))
      (dolist (clause (rest form))
        (unless (and (consp clause) (finite-list-p clause)
                     (member (first clause) '(:required :optional :closed)))
          (refuse "PLIST clauses are :required, :optional or :closed"))
        (when (member (first clause) seen-clauses)
          (refuse "PLIST clauses must not repeat"))
        (push (first clause) seen-clauses)
        (if (eq (first clause) :closed)
            (progn
              (unless (and (= 2 (length clause)) (typep (second clause) 'boolean))
                (refuse ":closed takes exactly one boolean"))
              (setf closed-p (second clause)))
            (dolist (entry (rest clause))
              (unless (and (finite-list-p entry) (= 2 (length entry))
                           (keywordp (first entry)))
                (refuse "PLIST fields must be (:keyword spec) pairs"))
              (when (member (first entry) seen-keys)
                (refuse "PLIST field keys must be unique across required and optional"))
              (push (first entry) seen-keys)
              (push (make-field-definition
                     :key (first entry)
                     :value-spec (normalize-spec-form (second entry))
                     :required-p (eq (first clause) :required))
                    fields)))))
    (apply #'make-instance 'plist-spec :fields (nreverse fields) :closed-p closed-p
           (spec-initargs form name source-location generator))))

(defun normalize-compound (form name source-location generator)
  "Normalize a cons whose head names a spec primitive."
  (let ((head (first form))
        (args (rest form)))
    (unless (symbolp head)
      (error 'invalid-spec-form :form form
                                :reason "the head of a spec form must be a symbol"))
    (let ((head-name (symbol-name head)))
      (cond
        ((string= head-name "PLIST")
         (normalize-plist form name source-location generator))
        ((string= head-name "TYPE")
         (apply #'make-instance 'type-spec
                :type-specifier (first (require-arity args 1 form))
                (spec-initargs form name source-location generator)))
        ((string= head-name "SATISFIES")
         (let ((predicate (first (require-arity args 1 form))))
           (unless (symbolp predicate)
             (error 'invalid-spec-form :form form
                                       :reason "SATISFIES takes a symbol naming a predicate"))
           (apply #'make-instance 'predicate-spec :predicate predicate
                  (spec-initargs form name source-location generator))))
        ((string= head-name "MEMBER")
         (apply #'make-instance 'member-spec :values args
                (spec-initargs form name source-location generator)))
        ((string= head-name "RANGE")
         (normalize-range args form name source-location generator))
        ((string= head-name "INSTANCE-OF")
         (let ((class-name (first (require-arity args 1 form))))
           (unless (symbolp class-name)
             (error 'invalid-spec-form :form form
                                       :reason "INSTANCE-OF takes a symbol naming a class"))
           (apply #'make-instance 'instance-of-spec :class-name class-name
                  (spec-initargs form name source-location generator))))
        ((string= head-name "AND")
         (apply #'make-instance 'and-spec
                :children (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location generator)))
        ((string= head-name "OR")
         (apply #'make-instance 'or-spec
                :children (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location generator)))
        ((string= head-name "NOT")
         (apply #'make-instance 'not-spec
                :inner-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location generator)))
        ((string= head-name "LIST-OF")
         (apply #'make-instance 'list-of-spec
                :element-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location generator)))
        ((string= head-name "VECTOR-OF")
         (apply #'make-instance 'vector-of-spec
                :element-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location generator)))
        ((string= head-name "TUPLE")
         (apply #'make-instance 'tuple-spec
                :element-specs (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location generator)))
        ((string= head-name "NULLABLE")
         (apply #'make-instance 'nullable-spec
                :inner-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location generator)))
        ((string= head-name "CONS-OF")
         (error 'invalid-spec-form :form form
                                   :reason "CONS-OF is post-MVP; use TUPLE or LIST-OF"))
        (t
         (error 'invalid-spec-form :form form
                                   :reason "unknown spec head; write (type ...) or ~
                                            (instance-of ...) for a user-defined type, or ~
                                            reference a registered spec by name"))))))

(defun normalize-spec-form (form &key name generator source-location)
  "Normalize spec DSL FORM into a Semantic IR object.

NAME is the symbol the resulting spec will be registered under, or NIL for an
anonymous inline spec.  GENERATOR names a custom generator the backend should
draw this spec's values from (§11), or NIL to have it derive them from the spec.
SOURCE-LOCATION is a plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION.  When FORM is parsed
from a symbol or a list, all three are attached to the top level node only;
children carry their own source form and nothing else.

When FORM is already a SPEC object -- the branch programmatic and agent-driven
composition relies on -- it is returned unchanged, and NAME/SOURCE-LOCATION are
NOT attached even when supplied.  A GENERATOR alongside one is refused rather
than dropped: NAME and SOURCE-LOCATION are missing metadata, while a generator is
a claim about where values come from, and dropping it would leave the backend
deriving them from the spec the definition said not to use.  SPEC's NAME slot has
no writer, and the same object may already be registered elsewhere or shared as
a child of another
spec, so setting it in place could rename that other registration or a nested
node out from under whoever else holds a reference to it. Attaching a
different name would require returning a copy instead, which would need a
clone protocol across every concrete SPEC subclass; nothing in this codebase
needs that yet, so it has not been built. Callers that must name an
already-built spec should register it directly (see
CL-SPEC/SRC/REGISTRY:REGISTER-SPEC) rather than relying on NAME here.

The returned spec keeps FORM verbatim in its SPEC-SOURCE-FORM slot."
  (cond
    ((typep form 'spec)
     (when generator
       (error 'invalid-spec-form
              :form form
              :reason "a spec object takes no :generator; name it where the spec is defined"))
     form)
    ((symbolp form) (normalize-symbol form name source-location generator))
    ((consp form) (normalize-compound form name source-location generator))
    (t (error 'invalid-spec-form
              :form form
              :reason "a spec form is a symbol, a list or a spec object"))))
