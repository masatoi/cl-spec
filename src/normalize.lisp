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
                #:plist-spec #:alist-spec #:hash-table-spec #:object-spec
                #:make-field-definition #:reader-designator-p
                #:key-test-designator #:key-test-designator-p #:key-test-function)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-spec #:make-branch-definition)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:normalize-spec-form
           #:*spec-primitives*))

(in-package #:cl-spec/src/normalize)

(defparameter *spec-primitives*
  '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
    "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "PLIST" "ALIST" "HASH-TABLE"
    "OBJECT-OF" "TAGGED-BY"
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

(defun normalize-field-spec (form clauses name source-location generator class
                             key-predicate allowed-clauses entry-description
                             &optional class-name)
  "Normalize field CLAUSES into an instance of CLASS.

CLAUSES is the clause tail of FORM, which is the whole source form kept for
diagnostics.  ALLOWED-CLAUSES are the clause heads this representation accepts;
KEY-PREDICATE accepts one declared key and ENTRY-DESCRIPTION names the accepted
entry shape.  When :TEST is allowed the (:test ...) clause fixes the key
comparison for the keyed representations, and CLASS-NAME carries the class a
STRUCT/CLOS representation observes.

Clauses and entries are collected first and the key test applied last, so a
(:test ...) written after a field still decides that field's duplicate check."
  (let ((seen-clauses nil)
        (raw-fields nil)
        (fields nil)
        (closed-p nil)
        (key-test :eql))
    (flet ((refuse (reason)
             (error 'invalid-spec-form :form form :reason reason)))
      (dolist (clause clauses)
        (unless (and (consp clause) (finite-list-p clause)
                     (member (first clause) allowed-clauses))
          (refuse (format nil "field clauses are ~{~S~^, ~}" allowed-clauses)))
        (when (member (first clause) seen-clauses)
          (refuse "field clauses must not repeat"))
        (push (first clause) seen-clauses)
        (case (first clause)
          (:closed
           (unless (and (= 2 (length clause)) (typep (second clause) 'boolean))
             (refuse ":closed takes exactly one boolean"))
           (setf closed-p (second clause)))
          (:test
           (unless (and (= 2 (length clause)) (key-test-designator-p (second clause)))
             (refuse ":test takes one of EQ, EQL, EQUAL or EQUALP"))
           (setf key-test (key-test-designator (second clause))))
          (t
           (let ((required-p (eq (first clause) :required)))
             (dolist (entry (rest clause))
               (unless (and (finite-list-p entry) (= 2 (length entry))
                            (funcall key-predicate (first entry)))
                 (refuse entry-description))
               (push (list (first entry) (second entry) required-p)
                     raw-fields))))))
      (let ((seen-keys nil)
            (test (if (member :test allowed-clauses) (key-test-function key-test) #'eq)))
        (dolist (raw (nreverse raw-fields))
          (destructuring-bind (key value-form required-p) raw
            (when (member key seen-keys :test test)
              (refuse "field keys must be unique under the declared comparison"))
            (push key seen-keys)
            (push (make-field-definition
                   :key key
                   :value-spec (normalize-spec-form value-form)
                   :required-p required-p)
                  fields))))
      (apply #'make-instance class
             (append (list :fields (nreverse fields) :closed-p closed-p)
                     (when (member :test allowed-clauses) (list :key-test key-test))
                     (when class-name (list :class-name class-name))
                     (spec-initargs form name source-location generator))))))

(defun normalize-tagged-union (args form name source-location generator)
  "Normalize (TAGGED-BY TAG-READER (NAME SPEC) ...) into a TAGGED-UNION-SPEC.

The branch NAME is both the label reported in diagnostics and the EQL tag value
the reader is matched against, so the two can never drift apart."
  (let ((tag-reader (first args))
        (clauses (rest args)))
    (unless (and tag-reader (symbolp tag-reader))
      (error 'invalid-spec-form
             :form form
             :reason "TAGGED-BY takes a keyword tag key or a reader symbol"))
    (when (null clauses)
      (error 'invalid-spec-form :form form
                                :reason "TAGGED-BY needs at least one (NAME SPEC) branch"))
    (let ((branches nil)
          (seen nil))
      (dolist (clause clauses)
        (unless (and (finite-list-p clause) (= 2 (length clause))
                     (symbolp (first clause)) (first clause))
          (error 'invalid-spec-form
                 :form form
                 :reason "TAGGED-BY branches are (NAME SPEC) pairs with a non-NIL symbol name"))
        (when (member (first clause) seen)
          (error 'invalid-spec-form :form form
                                    :reason "TAGGED-BY branch names must be unique"))
        (push (first clause) seen)
        (push (make-branch-definition
               :name (first clause)
               :spec (normalize-spec-form (second clause)))
              branches))
      (apply #'make-instance 'tagged-union-spec
             :tag-reader tag-reader
             :branches (nreverse branches)
             (spec-initargs form name source-location generator)))))

(defun normalize-collection-options (options form)
  "Return (values MIN-LENGTH MAX-LENGTH UNIQUE) for a collection's OPTIONS.

OPTIONS is the tail after the element spec.  Values are checked here so a
malformed declaration is refused before an IR object exists, exactly as the
other compound heads do."
  (unless (evenp (length options))
    (error 'invalid-spec-form :form form :reason "collection options are keyword/value pairs"))
  (let ((min-length 0)
        (max-length :unbounded)
        (unique nil)
        (seen nil))
    (loop for (key value) on options by #'cddr
          do (when (member key seen)
               (error 'invalid-spec-form :form form
                                         :reason (format nil "~S appears more than once" key)))
             (push key seen)
             (case key
               (:min-length
                (unless (and (integerp value) (not (minusp value)))
                  (error 'invalid-spec-form :form form
                                            :reason ":min-length must be a nonnegative integer"))
                (setf min-length value))
               (:max-length
                (cond ((unbounded-marker-p value) (setf max-length :unbounded))
                      ((and (integerp value) (not (minusp value))) (setf max-length value))
                      (t (error 'invalid-spec-form
                                :form form
                                :reason ":max-length must be a nonnegative integer or *"))))
               (:unique
                (unless (member value '(nil t))
                  (error 'invalid-spec-form :form form :reason ":unique must be boolean"))
                (setf unique value))
               (otherwise
                (error 'invalid-spec-form :form form
                                          :reason (format nil "~S is not a collection option; ~
                                                               the options are :min-length, ~
                                                               :max-length and :unique"
                                                          key)))))
    (when (and (integerp max-length) (> min-length max-length))
      (error 'invalid-spec-form :form form
                                :reason ":min-length must not exceed :max-length"))
    (values min-length max-length unique)))

(defun normalize-collection (args form name source-location generator class)
  "Normalize the arguments of a LIST-OF or VECTOR-OF form into CLASS."
  (unless args
    (error 'invalid-spec-form :form form :reason "expected an element spec"))
  (multiple-value-bind (min-length max-length unique)
      (normalize-collection-options (rest args) form)
    (apply #'make-instance class
           :element-spec (normalize-spec-form (first args))
           :min-length min-length :max-length max-length :unique unique
           (spec-initargs form name source-location generator))))

(defun normalize-compound (form name source-location generator)
  "Normalize a cons whose head names a spec primitive."
  (unless (finite-list-p form)
    (error 'invalid-spec-form :form form :reason "a spec form must be a finite proper list"))
  (let ((head (first form))
        (args (rest form)))
    (unless (symbolp head)
      (error 'invalid-spec-form :form form
                                :reason "the head of a spec form must be a symbol"))
    (let ((head-name (symbol-name head)))
      (cond
        ((string= head-name "PLIST")
         (normalize-field-spec form (rest form) name source-location generator
                               'plist-spec #'keywordp '(:required :optional :closed)
                               "PLIST fields must be (:keyword spec) pairs"))
        ((string= head-name "ALIST")
         (normalize-field-spec form (rest form) name source-location generator
                               'alist-spec (constantly t)
                               '(:required :optional :closed :test)
                               "field entries must be (KEY SPEC) pairs with an admissible key"))
        ((string= head-name "HASH-TABLE")
         (normalize-field-spec form (rest form) name source-location generator
                               'hash-table-spec (constantly t)
                               '(:required :optional :closed :test)
                               "field entries must be (KEY SPEC) pairs with an admissible key"))
        ((string= head-name "OBJECT-OF")
         (let ((class-name (first args)))
           (unless (and (symbolp class-name) (not (null class-name)))
             (error 'invalid-spec-form
                    :form form
                    :reason "OBJECT-OF takes a class name symbol followed by field clauses"))
           (normalize-field-spec form (rest args) name source-location generator
                                 'object-spec #'reader-designator-p
                                 '(:required :optional)
                                 "object fields must be (READER SPEC) pairs naming a reader"
                                 class-name)))
        ((string= head-name "TAGGED-BY")
         (normalize-tagged-union args form name source-location generator))
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
         (normalize-collection args form name source-location generator 'list-of-spec))
        ((string= head-name "VECTOR-OF")
         (normalize-collection args form name source-location generator 'vector-of-spec))
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
