;;;; src/backends/check-it-generators.lisp
;;;;
;;;; Semantic IR -> check-it generator (specification §10, §12).  check-it's
;;;; GENERATOR macro expands into MAKE-INSTANCE forms over exported classes, so
;;;; the mapping is built by calling MAKE-INSTANCE directly: no runtime EVAL is
;;;; needed, and the DSL stays out of the compilation path.

(defpackage #:cl-spec/src/backends/check-it-generators
  (:use #:cl)
  (:import-from #:check-it
                #:generator
                #:generate
                #:shrink
                #:regenerate
                #:*size*
                #:cached-value
                #:int-generator
                #:real-generator
                #:char-generator
                #:string-generator
                #:list-generator
                #:tuple-generator
                #:or-generator
                #:mapped-generator)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:alist-spec #:hash-table-spec #:object-spec
                #:field-spec-fields #:field-key-test #:key-test-name
                #:field-key #:field-value-spec #:field-required-p)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-spec #:tagged-union-branches #:branch-spec)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-kind
                #:type-spec
                #:type-spec-type-specifier
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:member-spec
                #:member-spec-values
                #:or-spec
                #:or-spec-children
                #:and-spec
                #:and-spec-children
                #:nullable-spec
                #:nullable-spec-inner-spec
                #:tuple-spec
                #:tuple-spec-element-specs
                #:collection-spec-element-spec
                #:collection-spec-min-length
                #:collection-spec-max-length
                #:collection-spec-unique-p
                #:list-of-spec
                #:vector-of-spec
                #:reference-spec
                #:reference-spec-target
                #:spec-generator-name)
  (:import-from #:cl-spec/src/registry
                #:registry-find-generator)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator-function #:custom-generator-shrinker)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:context-registry)
  (:import-from #:cl-spec/src/validator
                #:compile-validator)
  (:import-from #:cl-spec/src/generation-request
                #:*generation-request*
                #:make-generation-request
                #:reserve-generation-candidate
                #:record-generation-rejection
                #:with-generation-phase)
  (:export #:custom-value-generator #:custom-value-generator-shrinker #:spec-generator
           #:bounded-filter-generator #:bounded-filter-sub-generator
           #:bounded-filter-validator #:bounded-filter-path
           #:plist-value-generator #:plist-generator-fields #:plist-generator-children
           #:keyed-value-generator #:keyed-generator-fields #:keyed-generator-children
           #:bounded-collection-generator #:bounded-generator-min-length
           #:bounded-generator-max-length #:bounded-generator-enumerated
           #:bounded-generator-distinct-range #:bounded-generator-domain-size
           #:bounded-generator-element-probe
           #:compile-spec-generator))

(in-package #:cl-spec/src/backends/check-it-generators)

(defvar *required-size* 0
  "Largest bound magnitude seen while compiling the current generator.

check-it clamps every numeric limit to CHECK-IT:*SIZE*, so a range that does not
overlap [-*size*, *size*] silently generates values outside itself: (range
integer 20 100) draws 10.  Compilation records how far *SIZE* has to be raised,
and the caller binds it around GENERATE.")

(defvar *reference-trail* nil
  "Spec names currently being compiled, innermost first.

Compiling a generator walks references eagerly, so a self referential spec
would recurse forever.  The trail turns that into a clear condition.")

(defgeneric spec-generator (spec context)
  (:documentation "Return a check-it generator producing values that satisfy SPEC.

CONTEXT is the compilation plist; :REGISTRY names the registry references
resolve against.  Signals GENERATOR-UNAVAILABLE when SPEC has no generation
strategy.  The result may be an ordinary value rather than a generator object:
check-it's GENERATE treats a non-generator as a constant."))

(defmethod spec-generator ((spec spec) context)
  (declare (ignore context))
  (error 'generator-unavailable
         :spec spec
         :reason (format nil "~S has no generation strategy" (spec-kind spec))))

(defclass custom-value-generator (generator)
  ((function :initarg :function
             :reader custom-value-generator-function
             :documentation "Function of no arguments returning one value.")
   (shrinker :initarg :shrinker :initform nil :reader custom-value-generator-shrinker
             :documentation "Optional copied-value to finite candidate-list function."))
  (:documentation "A generator that calls a user function once per draw.

Its own class rather than the MAPPED-GENERATOR over a constant this first was.
check-it's MAPPED-GENERATOR shrink method reads its sub-generators' cached values,
and a constant is not a generator, so every FAILING run with a custom generator
signalled NO-APPLICABLE-METHOD-ERROR instead of returning a result.  It was on the
shrink path only, which is why a sample and a passing run hid it (PR review)."))

(defmethod generate ((generator custom-value-generator))
  "Draw one value from GENERATOR and cache it, as check-it's generators do."
  (let ((value (funcall (custom-value-generator-function generator))))
    (setf (cached-value generator) value)
    value))

(defmethod shrink ((generator custom-value-generator) test)
  "Keep nested custom values unchanged.
The backend invokes an explicit shrinker only for a whole argument generator,
where it can validate and observe the complete correlated candidate."
  (declare (ignore test))
  (cached-value generator))

(defclass plist-value-generator (generator)
  ((fields :initarg :fields :reader plist-generator-fields)
   (children :initarg :children :reader plist-generator-children)
   (validators :initarg :validators :reader plist-generator-validators))
  (:documentation "Generate declared plist fields and shrink their values without losing keys."))

(defmethod generate ((generator plist-value-generator))
  "Draw required fields and independently choose whether each optional field is present."
  (setf (cached-value generator)
        (loop for field in (plist-generator-fields generator)
              for child in (plist-generator-children generator)
              when (or (field-required-p field) (zerop (random 2)))
                append (list (field-key field) (generate child)))))

(defmethod shrink ((generator plist-value-generator) test)
  "Remove optional fields and retain only tested, valid reductions of field values."
  (loop for field in (plist-generator-fields generator)
        for child in (plist-generator-children generator)
        for validator in (plist-generator-validators generator)
        for key = (field-key field)
        do (unless (field-required-p field)
             (let ((candidate (copy-list (cached-value generator))))
               (when (and (remf candidate key) (not (funcall test candidate)))
                 (setf (cached-value generator) candidate))))
           (when (and (typep child 'generator)
                      (loop for tail on (cached-value generator) by #'cddr
                            thereis (eq key (car tail))))
             ;; Some check-it shrinkers return an untested transformed value.
             ;; Only a value observed by the callback can replace this field.
             (shrink child
                     (lambda (value)
                       (if (not (funcall validator value))
                           t
                           (let ((candidate (copy-list (cached-value generator))))
                             (setf (getf candidate key) value)
                             (if (funcall test candidate)
                                 t
                                 (progn
                                   (setf (cached-value generator) candidate)
                                   nil))))))))
  (cached-value generator))

(defmethod spec-generator ((spec plist-spec) context)
  (let ((fields (field-spec-fields spec)))
    (make-instance 'plist-value-generator
                   :fields fields
                   :children (mapcar (lambda (field)
                                       (spec-generator (field-value-spec field) context))
                                     fields)
                   :validators (mapcar (lambda (field)
                                         (compile-validator (field-value-spec field)
                                                            :context context))
                                       fields))))

(defclass keyed-value-generator (generator)
  ((fields :initarg :fields :reader keyed-generator-fields)
   (children :initarg :children :reader keyed-generator-children)
   (validators :initarg :validators :reader keyed-generator-validators)
   (key-test :initarg :key-test :reader keyed-generator-key-test))
  (:documentation "Generate an alist or hash table from declared fields and shrink it.

Subclasses only encode and decode the association list; presence, optional
removal and value shrinking are shared, so both representations keep required
keys and compare keys with the test the spec declares."))

(defgeneric encode-associations (generator associations)
  (:documentation "Return ASSOCIATIONS, a list of (KEY . VALUE), as GENERATOR's representation."))

(defgeneric decode-associations (generator value)
  (:documentation "Return VALUE as a list of (KEY . VALUE) associations."))

(defclass alist-value-generator (keyed-value-generator)
  ()
  (:documentation "Generate alists whose keys are unique under the declared test."))

(defmethod encode-associations ((generator alist-value-generator) associations)
  (loop for (key . value) in associations collect (cons key value)))

(defmethod decode-associations ((generator alist-value-generator) value)
  "Reconstruct associations from a generated alist.

Every CDR is the value, matching the validator's ASSOC reading, so a dotted pair
and a two-element list are read the same way here as they are checked."
  (declare (ignore generator))
  (loop for entry in value collect (cons (car entry) (cdr entry))))

(defclass hash-table-value-generator (keyed-value-generator)
  ()
  (:documentation "Generate hash tables using the key test the spec declares."))

(defmethod encode-associations ((generator hash-table-value-generator) associations)
  (let ((table (make-hash-table :test (key-test-name (keyed-generator-key-test generator)))))
    (loop for (key . value) in associations
          do (setf (gethash key table) value))
    table))

(defmethod decode-associations ((generator hash-table-value-generator) value)
  "Return VALUE's entries as associations.

The order is unspecified but immaterial: generation encodes in field order, and
shrinking looks each declared key up rather than walking the decoded list."
  (declare (ignore generator))
  (let ((associations nil))
    (maphash (lambda (key item) (push (cons key item) associations)) value)
    associations))

(defmethod generate ((generator keyed-value-generator))
  "Draw required fields and independently choose whether each optional field is present."
  (setf (cached-value generator)
        (encode-associations
         generator
         (loop for field in (keyed-generator-fields generator)
               for child in (keyed-generator-children generator)
               when (or (field-required-p field) (zerop (random 2)))
                 collect (cons (field-key field) (generate child))))))

(defmethod shrink ((generator keyed-value-generator) test)
  "Remove optional fields and retain only tested, valid reductions of field values.

The shape mirrors PLIST-VALUE-GENERATOR's shrinker: TEST returns NIL while a
candidate still fails the property, so a candidate is kept exactly when it is
valid and still failing."
  (let ((test-name (key-test-name (keyed-generator-key-test generator))))
    (loop for field in (keyed-generator-fields generator)
          for child in (keyed-generator-children generator)
          for validator in (keyed-generator-validators generator)
          for key = (field-key field)
          do (unless (field-required-p field)
               (let ((associations (decode-associations generator (cached-value generator))))
                 (when (assoc key associations :test test-name)
                   (let ((candidate (encode-associations
                                     generator
                                     (remove key associations :key #'car :test test-name))))
                     (when (not (funcall test candidate))
                       (setf (cached-value generator) candidate))))))
             (let ((associations (decode-associations generator (cached-value generator))))
               (when (and (typep child 'generator)
                          (assoc key associations :test test-name))
                 ;; Some check-it shrinkers return an untested transformed value.
                 ;; Only a value observed by the callback can replace this field.
                 (shrink child
                         (lambda (value)
                           (if (not (funcall validator value))
                               t
                               (let* ((associations (decode-associations
                                                     generator (cached-value generator)))
                                      (candidate (encode-associations
                                                  generator
                                                  (acons key value
                                                         (remove key associations
                                                                 :key #'car :test test-name)))))
                                 (if (funcall test candidate)
                                     t
                                     (progn (setf (cached-value generator) candidate)
                                            nil))))))))))
    (cached-value generator))

(defun make-keyed-value-generator (class spec context)
  "Build an instance of CLASS for the keyed field SPEC."
  (let ((fields (field-spec-fields spec)))
    (make-instance class
                   :fields fields
                   :key-test (field-key-test spec)
                   :children (mapcar (lambda (field)
                                       (spec-generator (field-value-spec field) context))
                                     fields)
                   :validators (mapcar (lambda (field)
                                         (compile-validator (field-value-spec field)
                                                            :context context))
                                       fields))))

(defmethod spec-generator ((spec alist-spec) context)
  (make-keyed-value-generator 'alist-value-generator spec context))

(defmethod spec-generator ((spec hash-table-spec) context)
  (make-keyed-value-generator 'hash-table-value-generator spec context))

(defmethod spec-generator ((spec object-spec) context)
  "Refuse to invent an object: readers observe but do not construct.
A (:GENERATOR NAME) on the definition is the supported way to draw instances,
because only its author knows the constructor and its initargs."
  (declare (ignore context))
  (error 'generator-unavailable
         :spec spec
         :reason "an OBJECT-OF spec is observed through readers and cannot be constructed; ~
                  declare a (:GENERATOR NAME) to draw instances"))

(defmethod spec-generator ((spec tagged-union-spec) context)
  "Draw from every branch through an OR, so each branch a tag selects is reachable.
A branch spec must produce a value whose tag reads as the branch name; the union
does not inject the tag, because it does not know the branch representation."
  (let ((branches (tagged-union-branches spec)))
    (when (null branches)
      (error 'generator-unavailable :spec spec :reason "an empty tagged union admits nothing"))
    (let ((generators (mapcar (lambda (branch) (spec-generator (branch-spec branch) context))
                              branches)))
      ;; A single branch needs no weighted choice, matching OR's handling.
      (if (null (rest generators))
          (first generators)
          (make-instance 'or-generator :sub-generators generators)))))

(defun custom-spec-generator (name spec context)
  "Return a generator drawing from the custom generator NAME names.

The value is not checked against SPEC.  A custom generator that draws outside its
spec should be seen for what it is -- a property reporting a counterexample the
contract refuses -- rather than hidden behind a guard, which as AND's method
notes would retry with no depth limit.

An AND that would fold a conjunct with a custom generator is refused by
FOLD-AND-CHILDREN. A generator on the whole AND overrides folding explicitly."
  (let ((entry (registry-find-generator (context-registry context) name)))
    (unless entry
      (error 'generator-unavailable
             :spec spec
             :reason (format nil "the custom generator ~S is not registered" name)))
    (make-instance 'custom-value-generator
                   :function (custom-generator-function entry)
                   :shrinker (custom-generator-shrinker entry))))

(defmethod spec-generator :around ((spec spec) context)
  "Prefer the custom generator SPEC names over the one its node type would build.

An :AROUND method on the base class rather than a check inside each method: a
(:GENERATOR NAME) clause on an AND, a MEMBER or a REFERENCE has to win over the
strategy that node type would otherwise get, and this is the only place that runs
before the type's own method does."
  (let ((name (spec-generator-name spec)))
    (if name
        (custom-spec-generator name spec context)
        (call-next-method))))

(defun type-specifier-generator (type-specifier spec)
  "Return a generator for the Common Lisp TYPE-SPECIFIER.

The table is deliberately short.  A type is listed only when check-it produces
values the corresponding TYPEP actually accepts: REAL-GENERATOR yields floats,
so FLOAT and RATIONAL are absent rather than silently wrong."
  (case type-specifier
    ((integer) (make-instance 'int-generator))
    ((real) (make-instance 'real-generator))
    ((character) (make-instance 'char-generator))
    ((string) (make-instance 'string-generator))
    ((null) nil)
    ((boolean) (make-instance 'or-generator :sub-generators (list t nil)))
    (t (error 'generator-unavailable
              :spec spec
              :reason (format nil "no generator is registered for the type ~S"
                              type-specifier)))))

(defun real-range-generator (lower upper)
  "Return a generator producing reals in [LOWER, UPPER], where either bound may
be check-it's open-bound marker, *.  A degenerate range (LOWER and UPPER equal
and finite) returns LOWER itself: check-it's GENERATE treats a non-generator as
a constant, and an interval of width zero admits exactly LOWER anyway -- this
also sidesteps the bug below, which would otherwise call (RANDOM 0.0) for it.

Works around a bug in check-it's REAL-GENERATOR-FUNCTION: when both bounds are
finite, its lower-bound calculation reads (ABS UPPER) where it should read
(ABS LOWER).  Whenever LOWER and UPPER do not straddle zero this collapses the
interval to zero width and (RANDOM 0.0) signals a TYPE-ERROR; confirmed by
calling CHECK-IT::REAL-GENERATOR-FUNCTION directly with no cl-spec code
involved.  Shifting a finite/finite pair to start at zero sidesteps it. SIGNUM
of a zero lower bound is 0 under both the correct and the buggy formula, so the
bug has no effect there, and the draw is mapped back by adding LOWER.  An open
bound is passed through unshifted: check-it's asymmetric branches (one bound *)
do not have this bug."
  (cond
    ((or (eq lower '*) (eq upper '*))
     (make-instance 'real-generator :lower-limit lower :upper-limit upper))
    ((= lower upper)
     lower)
    (t
     (make-instance 'mapped-generator
                    :mapping (lambda (value) (+ value lower))
                    :sub-generators
                    (list (make-instance 'real-generator
                                         :lower-limit 0
                                         :upper-limit (- upper lower)))))))

(defmethod spec-generator ((spec type-spec) context)
  (declare (ignore context))
  (type-specifier-generator (type-spec-type-specifier spec) spec))

(defun bounded-generator (base-type minimum maximum spec)
  "Return a numeric generator for BASE-TYPE limited by MINIMUM and MAXIMUM.

:UNBOUNDED is written back as check-it's own open bound marker, *.  Each finite
bound also raises *REQUIRED-SIZE*: without it check-it clamps the bound away and
generates outside the range.  When both bounds are finite, the interval's width
raises it too: REAL-RANGE-GENERATOR asks check-it for the shifted interval
[0, MAXIMUM - MINIMUM], which is wider than either bound's own magnitude
whenever MINIMUM and MAXIMUM straddle zero, and *SIZE* has to cover that
shifted width or half the declared range goes unreachable."
  (dolist (bound (list minimum maximum))
    (unless (eq bound :unbounded)
      (setf *required-size* (max *required-size* (ceiling (abs bound))))))
  (when (and (not (eq minimum :unbounded)) (not (eq maximum :unbounded)))
    (setf *required-size* (max *required-size* (ceiling (abs (- maximum minimum))))))
  (let ((lower (if (eq minimum :unbounded) '* minimum))
        (upper (if (eq maximum :unbounded) '* maximum)))
    (case base-type
      ((integer) (make-instance 'int-generator :lower-limit lower :upper-limit upper))
      ((real) (real-range-generator lower upper))
      (t (error 'generator-unavailable
                :spec spec
                :reason (format nil "~S cannot carry a numeric range" base-type))))))

(defmethod spec-generator ((spec range-spec) context)
  (declare (ignore context))
  (bounded-generator (or (range-spec-base-type spec) 'real)
                     (range-spec-minimum spec)
                     (range-spec-maximum spec)
                     spec))

(defmethod spec-generator ((spec member-spec) context)
  (declare (ignore context))
  (let ((values (member-spec-values spec)))
    (cond
      ((null values)
       (error 'generator-unavailable :spec spec :reason "an empty MEMBER admits nothing"))
      ;; CHECK-IT:COMPUTE-WEIGHTS divides by (1- LEN), so a single-valued
      ;; MEMBER would signal a floating point error inside check-it rather
      ;; than generating its one admissible value. check-it's GENERATE treats
      ;; a non-generator as a constant, so returning the value directly is
      ;; equivalent to wrapping it and skips the weighting machinery entirely.
      ((null (rest values)) (first values))
      (t (make-instance 'or-generator :sub-generators (copy-list values))))))

(defmethod spec-generator ((spec or-spec) context)
  (let ((children (or-spec-children spec)))
    (cond
      ((null children)
       (error 'generator-unavailable :spec spec :reason "an empty OR admits nothing"))
      ;; A single child needs no weighted choice, and check-it's
      ;; COMPUTE-WEIGHTS divides by zero when asked to choose among one
      ;; generator, so return it directly rather than wrapping it.
      ((null (rest children)) (spec-generator (first children) context))
      (t (make-instance 'or-generator
                        :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                                children))))))

(defmethod spec-generator ((spec nullable-spec) context)
  (make-instance 'or-generator
                 :sub-generators
                 (list nil (spec-generator (nullable-spec-inner-spec spec) context))))

(defmethod spec-generator ((spec tuple-spec) context)
  (make-instance 'tuple-generator
                 :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                         (tuple-spec-element-specs spec))))

(defun collection-constrained-p (spec)
  "Return true when SPEC declares a length or uniqueness constraint."
  (or (plusp (collection-spec-min-length spec))
      (not (eq :unbounded (collection-spec-max-length spec)))
      (collection-spec-unique-p spec)))

(defparameter *enumeration-limit* 1000
  "Largest finite element domain ENUMERABLE-VALUES materializes for UNIQUE.")

(defun integer-range-bounds (spec)
  "Return (VALUES MINIMUM MAXIMUM) for an integer RANGE-SPEC, or NIL.

Fractional finite endpoints are read the way validation reads them: the admitted
values are the integers between the endpoints, so the minimum rounds up and the
maximum rounds down.  A missing result means either that no integer lies in the
interval (MINIMUM above MAXIMUM) or that a bound is not a finite number, which is
why INTEGER-RANGE-P tells the two apart."
  (let ((minimum (range-spec-minimum spec))
        (maximum (range-spec-maximum spec)))
    (when (and (eq (range-spec-base-type spec) 'integer)
               (realp minimum) (realp maximum))
      (let ((low (ceiling minimum))
            (high (floor maximum)))
        (when (<= low high)
          (values low high))))))

(defun integer-range-p (spec)
  "Return true when SPEC is an integer range with finite real endpoints."
  (and (eq (range-spec-base-type spec) 'integer)
       (realp (range-spec-minimum spec))
       (realp (range-spec-maximum spec))))

(defgeneric enumerable-values (spec context)
  (:documentation "Return (VALUES VALUES ENUMERABLE-P) for SPEC.

VALUES is a finite list of the values SPEC admits and ENUMERABLE-P says whether
that list is the whole domain -- so an empty domain is (VALUES NIL T) and stays
distinguishable from a spec that cannot be enumerated at all.

UNIQUE generation draws distinct elements from this list; a spec without a finite
enumeration refuses UNIQUE rather than retrying collisions forever through
check-it's guard generator, which recurses with no depth limit.")
  (:method ((spec spec) context)
    (declare (ignore context))
    (values nil nil)))

(defmethod enumerable-values ((spec member-spec) context)
  (declare (ignore context))
  (values (remove-duplicates (copy-list (member-spec-values spec)) :test #'eql) t))

(defmethod enumerable-values ((spec type-spec) context)
  (declare (ignore context))
  (case (type-spec-type-specifier spec)
    ((null) (values (list nil) t))
    ((boolean) (values (list t nil) t))
    (t (values nil nil))))

(defmethod enumerable-values ((spec nullable-spec) context)
  (multiple-value-bind (inner enumerable-p)
      (enumerable-values (nullable-spec-inner-spec spec) context)
    (if (not enumerable-p)
        (values nil nil)
        ;; ADJOIN rather than CONS: a boolean or member inner domain already holds
        ;; NIL, and an EQL-duplicated domain would overstate the finite size and let
        ;; UNIQUE draw a repeated NIL.
        (values (adjoin nil (copy-list inner) :test #'eql) t))))

(defmethod enumerable-values ((spec range-spec) context)
  (declare (ignore context))
  (when (integer-range-p spec)
    (multiple-value-bind (low high) (integer-range-bounds spec)
      (cond
        ;; Fractions such as (range integer 0.5 0.9) admit no integer: that is an
        ;; empty domain, not a domain that cannot be enumerated.
        ((null low) (values nil t))
        ((<= (- high low) *enumeration-limit*)
         (values (loop for value from low to high collect value) t))
        (t (values nil nil))))))

(defmethod enumerable-values ((spec or-spec) context)
  (let ((values nil))
    (dolist (child (or-spec-children spec))
      (multiple-value-bind (child-values child-p) (enumerable-values child context)
        (unless child-p (return-from enumerable-values (values nil nil)))
        (setf values (union values child-values :test #'eql))))
    (values values t)))

(defmethod enumerable-values ((spec reference-spec) context)
  "Resolve a named spec so a finite domain reached by name stays enumerable.

Without this, (list-of id :unique t) for (defspec id (member 1 2 3)) refused
generation even though the target is one of the enumerable domains."
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    (when (member target *reference-trail*)
      (error 'generator-unavailable
             :spec spec
             :reason "recursive specs have no finite element enumeration"))
    (let ((resolved (resolve-spec target registry))
          (*reference-trail* (cons target *reference-trail*)))
      ;; A custom generator owns the distribution; enumerating the target's
      ;; underlying node would silently replace it.
      (unless (spec-generator-name resolved)
        (enumerable-values resolved context)))))

(defgeneric finite-integer-range (spec context)
  (:documentation "Return (values MINIMUM MAXIMUM) when SPEC admits a finite integer interval.")
  (:method ((spec spec) context)
    (declare (ignore context))
    nil))

(defmethod finite-integer-range ((spec range-spec) context)
  (declare (ignore context))
  (multiple-value-bind (low high) (integer-range-bounds spec)
    ;; An interval with no integer in it is left to ENUMERABLE-VALUES, which
    ;; reports it as an empty domain rather than as no domain at all.
    (when low (values low high))))

(defmethod finite-integer-range ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    (when (member target *reference-trail*)
      (error 'generator-unavailable
             :spec spec
             :reason "recursive specs have no finite integer range"))
    (let ((resolved (resolve-spec target registry))
          (*reference-trail* (cons target *reference-trail*)))
      (unless (spec-generator-name resolved)
        (finite-integer-range resolved context)))))

(defun shuffle-list (sequence)
  "Return a fresh copy of SEQUENCE in random order (Fisher-Yates)."
  (let ((copy (copy-seq (coerce sequence 'vector))))
    (loop for index from (1- (length copy)) downto 1
          for other = (random (1+ index))
          do (rotatef (aref copy index) (aref copy other)))
    (coerce copy 'list)))

(defun sample-distinct-integers (minimum maximum count)
  "Return COUNT distinct integers from the inclusive interval [MINIMUM, MAXIMUM].

Partial Fisher-Yates over a sparse swap map: only COUNT entries are touched, so
a range wider than *ENUMERATION-LIMIT* is sampled without materializing it, and
each draw removes the chosen value from the remaining pool."
  (let* ((width (1+ (- maximum minimum)))
         (take (min count width))
         (swaps (make-hash-table :test #'eql))
         (result nil))
    (loop for index from 0 below take
          for candidate = (+ index (random (- width index)))
          for chosen = (gethash candidate swaps candidate)
          for current = (gethash index swaps index)
          do (push (+ minimum chosen) result)
             (setf (gethash index swaps) chosen
                   (gethash candidate swaps) current))
    result))

(defun eql-duplicates-p (items)
  "Return true when ITEMS contains two EQL values."
  (let ((seen (make-hash-table :test #'eql)))
    (loop for index from 0 below (length items)
          for item = (elt items index)
          when (nth-value 1 (gethash item seen)) return t
          do (setf (gethash item seen) t)
          finally (return nil))))

(defclass bounded-collection-generator (generator)
  ((element-generator :initarg :element-generator
                      :reader bounded-generator-element-generator
                      :documentation "Function of no arguments returning a
fresh element generator.")
   (element-validator :initarg :element-validator
                      :reader bounded-generator-element-validator
                      :documentation "Predicate each element must satisfy.")
   (element-probe :initarg :element-probe
                  :initform nil
                  :reader bounded-generator-element-probe
                  :documentation "Eagerly compiled element generator, kept only to
report whether element-wise shrinking is possible.")
   (min-length :initarg :min-length :reader bounded-generator-min-length)
   (max-length :initarg :max-length :reader bounded-generator-max-length)
   (unique-p :initarg :unique-p :reader bounded-generator-unique-p)
   (vector-p :initarg :vector-p :reader bounded-generator-vector-p)
   (enumerated :initarg :enumerated :initform nil :reader bounded-generator-enumerated
               :documentation "Finite element domain as a vector when UNIQUE-P, else NIL.
A present but empty vector means the domain is empty, which is different from
having no finite domain at all.")
   (distinct-range :initarg :distinct-range :initform nil
                   :reader bounded-generator-distinct-range
                   :documentation "Inclusive integer bounds when UNIQUE-P samples a range
too wide to materialize, else NIL.")
   (children :initform nil :accessor bounded-generator-children
             :documentation "Element generators of the current draw, for element-wise shrinking."))
  (:documentation "Generate a bounded, optionally UNIQUE collection and shrink within the range."))

(defun bounded-candidate (generator list)
  "Build a collection of GENERATOR's representation from LIST."
  (if (bounded-generator-vector-p generator)
      (coerce list 'vector)
      list))

(defun bounded-generator-domain-size (generator)
  "Return the finite UNIQUE domain size of GENERATOR, or NIL when it draws elements.

Generation truncates a requested length to this size, so capability reporting and
removal shrinking both need it.  An empty enumerated domain is present, so it
reports 0 rather than falling through to the element generators."
  (let ((enumerated (bounded-generator-enumerated generator)))
    (if enumerated
        (length enumerated)
        (let ((range (bounded-generator-distinct-range generator)))
          (and range (1+ (- (cdr range) (car range))))))))

(defmethod generate ((generator bounded-collection-generator))
  (let* ((minimum (bounded-generator-min-length generator))
         (maximum (bounded-generator-max-length generator))
         (size (max check-it:*size* minimum))
         (upper (if (eq maximum :unbounded) size (min maximum size)))
         (count (if (>= upper minimum)
                    (+ minimum (random (1+ (- upper minimum))))
                    minimum))
         (enumerated (bounded-generator-enumerated generator))
         (distinct-range (bounded-generator-distinct-range generator)))
    (cond
      (distinct-range
       (setf (bounded-generator-children generator) nil
             (cached-value generator)
             (bounded-candidate generator
                                (sample-distinct-integers (car distinct-range)
                                                          (cdr distinct-range)
                                                          count))))
      (enumerated
       (let* ((pool (shuffle-list enumerated))
              (items (subseq pool 0 (min count (length pool)))))
         (setf (bounded-generator-children generator) nil
               (cached-value generator) (bounded-candidate generator items))))
      (t
       (let ((children nil)
             (items nil))
         (loop repeat count
               do (let ((child (funcall (bounded-generator-element-generator generator))))
                    (push child children)
                    (push (generate child) items)))
         (setf (bounded-generator-children generator) (nreverse children)
               (cached-value generator)
               (bounded-candidate generator (nreverse items))))))))

(defmethod shrink ((generator bounded-collection-generator) test)
  "Shrink length-wise while MIN-LENGTH holds, then element-wise within the constraints."
  (let ((minimum (bounded-generator-min-length generator))
        (unique (bounded-generator-unique-p generator)))
    (labels ((items () (cached-value generator))
             (build (list) (bounded-candidate generator list))
             (element-wise ()
               (let ((validator (bounded-generator-element-validator generator)))
                 (loop for index from 0 below (length (items))
                       for child in (bounded-generator-children generator)
                       when (typep child 'generator)
                         do (shrink child
                                    (lambda (value)
                                      ;; Some check-it shrinkers return an untested
                                      ;; transformed value.  Only a value the callback
                                      ;; observed -- valid and still failing -- may
                                      ;; replace this element.
                                      (if (and validator (not (funcall validator value)))
                                          t
                                          (let ((candidate (copy-seq (items))))
                                            (setf (elt candidate index) value)
                                            (if (or (and unique (eql-duplicates-p candidate))
                                                    (funcall test (build candidate)))
                                                t
                                                (progn
                                                  (setf (elt (items) index) value)
                                                  nil)))))))
                 (items)))
             (remove-wise ()
               (loop for index from 0 below (length (items))
                     when (> (length (items)) minimum)
                       do (let* ((head (subseq (items) 0 index))
                                 (tail (subseq (items) (1+ index)))
                                 (shrunk (build (concatenate (if (bounded-generator-vector-p
                                                                  generator)
                                                                 'vector 'list)
                                                             head tail))))
                            (unless (funcall test shrunk)
                              (setf (cached-value generator) shrunk)
                              (let ((children (bounded-generator-children generator)))
                                (when children
                                  (setf (bounded-generator-children generator)
                                        (append (subseq children 0 index)
                                                (subseq children (1+ index))))))
                              (return-from remove-wise t))))
               nil))
      (cond ((zerop (length (items))) (items))
            ((and (> (length (items)) minimum) (remove-wise)) (shrink generator test))
            (t (element-wise))))))

(defun effective-generator-name (spec context)
  "Return the custom generator SPEC names, following references and enumerable
composites, or NIL.

A custom generator owns how its values are drawn, so UNIQUE refuses a domain
whose values it would otherwise have to enumerate instead.  The traversal mirrors
ENUMERABLE-VALUES: a custom generator nested in a NULLABLE or OR node owns that
node's distribution too, and enumerating the node's underlying member or boolean
domain would silently replace it."
  (or (spec-generator-name spec)
      (typecase spec
        (reference-spec
         (let ((target (reference-spec-target spec)))
           (unless (member target *reference-trail*)
             (let ((*reference-trail* (cons target *reference-trail*)))
               (effective-generator-name (resolve-spec target (context-registry context))
                                         context)))))
        (nullable-spec
         (effective-generator-name (nullable-spec-inner-spec spec) context))
        (or-spec
         (some (lambda (child) (effective-generator-name child context))
               (or-spec-children spec))))))

(defun compile-collection-generator (spec context vector-p)
  "Compile a generator for the bounded collection SPEC."
  (let ((element (collection-spec-element-spec spec))
        (minimum (collection-spec-min-length spec))
        (maximum (collection-spec-max-length spec))
        (unique (collection-spec-unique-p spec)))
    (when (eql maximum 0)
      ;; No element can be drawn, so the element spec need not compile or
      ;; enumerate: the empty collection is the only admissible value.
      (return-from compile-collection-generator
        (make-instance 'bounded-collection-generator
                       :element-generator (lambda () nil)
                       :element-validator nil
                       :element-probe nil
                       :min-length 0
                       :max-length 0
                       :unique-p unique
                       :vector-p vector-p
                       :enumerated nil
                       :distinct-range nil)))
    (when (and unique (effective-generator-name element context))
      (error 'generator-unavailable
             :spec spec
             :reason "UNIQUE cannot enumerate a spec whose custom generator owns its distribution"))
    (let ((probe nil)
          (enumerated nil)
          (distinct-range nil))
      (when unique
        (multiple-value-bind (range-minimum range-maximum)
            (finite-integer-range element context)
          (if range-minimum
              ;; A finite integer range samples without materializing, so its
              ;; width is not capped by *ENUMERATION-LIMIT*.
              (let ((width (1+ (- range-maximum range-minimum))))
                (when (< width minimum)
                  (error 'generator-unavailable
                         :spec spec
                         :reason (format nil "UNIQUE admits ~D values, fewer than MIN-LENGTH ~D"
                                         width minimum)))
                (setf distinct-range (cons range-minimum range-maximum)))
              (multiple-value-bind (values enumerable-p) (enumerable-values element context)
                (unless enumerable-p
                  (error 'generator-unavailable
                         :spec spec
                         :reason "UNIQUE needs a finite element domain to draw distinct values"))
                (when (> (length values) *enumeration-limit*)
                  (error 'generator-unavailable
                         :spec spec
                         :reason (format nil "UNIQUE domain has ~D values, more than the ~D ~
                                              the enumeration limit allows"
                                         (length values) *enumeration-limit*)))
                (when (< (length values) minimum)
                  (error 'generator-unavailable
                         :spec spec
                         :reason (format nil "UNIQUE admits ~D values, fewer than MIN-LENGTH ~D"
                                         (length values) minimum)))
                ;; A vector keeps an empty domain distinct from "no domain": the
                ;; empty collection is then the one admissible value of a
                ;; MIN-LENGTH 0 collection.
                (setf enumerated (coerce values 'vector))))))
      ;; A UNIQUE collection draws from its domain, keeps no element generators
      ;; and reports shrinking from the domain size, so the eager probe would only
      ;; raise *REQUIRED-SIZE* to the element range's width and make GENERATE try
      ;; to build a collection that wide.
      (unless unique
        (setf probe (spec-generator element context)))
      (setf *required-size* (max *required-size* minimum))
      (make-instance 'bounded-collection-generator
                     :element-generator (lambda () (spec-generator element context))
                     :element-probe probe
                     :element-validator (compile-validator element :context context)
                     :min-length minimum
                     :max-length maximum
                     :unique-p unique
                     :vector-p vector-p
                     :enumerated enumerated
                     :distinct-range distinct-range))))

(defmethod spec-generator ((spec list-of-spec) context)
  (if (collection-constrained-p spec)
      (compile-collection-generator spec context nil)
      (let ((element (collection-spec-element-spec spec)))
        ;; Compile the element once, eagerly, purely so its bounds reach
        ;; *REQUIRED-SIZE* while COMPILE-SPEC-GENERATOR's binding is still in
        ;; effect -- the value itself is discarded. check-it still needs a fresh
        ;; generator per element for element-wise shrinking, which the closure
        ;; below provides; it calls the generator function once per element per
        ;; draw.
        (spec-generator element context)
        (make-instance 'list-generator
                       :generator-function (lambda () (spec-generator element context))))))

(defmethod spec-generator ((spec vector-of-spec) context)
  (if (collection-constrained-p spec)
      (compile-collection-generator spec context t)
      (let ((element (collection-spec-element-spec spec)))
        ;; See LIST-OF-SPEC's method: the eager call below exists only to raise
        ;; *REQUIRED-SIZE*; the closure still supplies a fresh generator per
        ;; element.
        (spec-generator element context)
        (make-instance 'mapped-generator
                       :mapping (lambda (items) (coerce items 'vector))
                       :sub-generators
                       (list (make-instance 'list-generator
                                            :generator-function
                                            (lambda () (spec-generator element context))))))))

(defmethod spec-generator ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    (when (member target *reference-trail*)
      (error 'generator-unavailable
             :spec spec
             :reason "recursive specs have no generator in this version"))
    (let ((resolved (resolve-spec target registry))
          (*reference-trail* (cons target *reference-trail*)))
      (spec-generator resolved context))))

(defun compile-spec-generator (spec context)
  "Return (values GENERATOR REQUIRED-SIZE) for SPEC.

REQUIRED-SIZE is what CHECK-IT:*SIZE* has to reach for the generator to respect
the bounds the spec asks for.  The caller binds it around GENERATE; returning it
rather than binding it here lets one binding cover a whole trial loop."
  (let ((*required-size* 0))
    (values (spec-generator spec context) *required-size*)))

(defun supported-type-specifier-p (type-specifier spec)
  "Return true when TYPE-SPECIFIER-GENERATOR can build a base for TYPE-SPECIFIER."
  (handler-case (progn (type-specifier-generator type-specifier spec) t)
    (generator-unavailable () nil)))

(defun merge-base-type (current new spec)
  "Return the base type implied by both CURRENT and NEW.

Two unequal types that both name a supported generator are a genuine conflict and
signal.  Two unequal unsupported (typically nonnumeric) types have no numeric
fold to contribute, so they merge to NIL and declaration-order source selection
can still consider a structured conjunct, as in
\(and (type list) (type sequence) (list-of integer))."
  (cond ((null current) new)
        ((null new) current)
        ((eq current new) current)
        ((and (member current '(integer real)) (member new '(integer real))) 'integer)
        ((or (supported-type-specifier-p current spec)
             (supported-type-specifier-p new spec))
         (error 'generator-unavailable
                :spec spec
                :reason (format nil "conflicting base types ~S and ~S" current new)))
        (t nil)))

(defun tighter-minimum (current new)
  "Return the greater of two lower bounds, treating :UNBOUNDED as no bound."
  (cond ((eq new :unbounded) current)
        ((eq current :unbounded) new)
        (t (max current new))))

(defun tighter-maximum (current new)
  "Return the lesser of two upper bounds, treating :UNBOUNDED as no bound."
  (cond ((eq new :unbounded) current)
        ((eq current :unbounded) new)
        (t (min current new))))

(defclass bounded-filter-generator (generator)
  ((sub-generator :initarg :sub-generator
                  :reader bounded-filter-sub-generator
                  :documentation "Generator the filter draws candidates from.")
   (filter :initarg :filter
           :reader bounded-filter-validator
           :documentation "Whole-AND validator every returned candidate must satisfy.")
   (spec :initarg :spec
         :reader bounded-filter-spec
         :documentation "The AND spec this filter enforces.")
   (path :initarg :path
         :initform nil
         :reader bounded-filter-path
         :documentation "Stable declaration path reported when the request is spent."))
  (:documentation "Draw from a source and keep only whole-AND valid candidates.

Unlike check-it's GUARD-GENERATOR this wrapper never recurses without a bound:
each candidate reservation comes from the active generation request, and a
request that runs out signals GENERATION-BUDGET-EXHAUSTED with its report.
Request budgets and counters live in that request, never on this reusable object."))

(defmethod generate ((generator bounded-filter-generator))
  "Reserve a candidate, draw once, and validate against the whole AND.

Reservation precedes the source call, so a source error propagates without
becoming a rejection.  The final permitted candidate may succeed; exhaustion is
signalled only when another reservation is required, and consumes no extra draw
or random number."
  (let ((draw (lambda ()
                (loop
                  (reserve-generation-candidate (bounded-filter-path generator)
                                                (bounded-filter-spec generator))
                  (let ((candidate (generate (bounded-filter-sub-generator generator))))
                    (if (funcall (bounded-filter-validator generator) candidate)
                        (return (setf (cached-value generator) candidate))
                        (record-generation-rejection)))))))
    (if *generation-request*
        (funcall draw)
        ;; A bare draw outside every public boundary still gets a finite request,
        ;; so a direct backend GENERATE call cannot loop forever.
        (let ((*generation-request* (make-generation-request :planned 1)))
          (funcall draw)))))

(defmethod shrink ((generator bounded-filter-generator) test)
  "Shrink the source, never adopting a candidate the whole AND rejects.

The delegated shrinker's return value is not evidence: some check-it shrinkers
return a transformed value they never presented to TEST.  A candidate may replace
the cached value only from this callback, and only when it passes the whole AND
and TEST accepts it as a reduction; otherwise the previous value stands.  Any
fresh draw a nested bounded filter makes here is charged to :SHRINKING."
  (with-generation-phase (:shrinking)
    (shrink (bounded-filter-sub-generator generator)
            (lambda (candidate)
              (if (or (funcall test candidate)
                      (not (funcall (bounded-filter-validator generator) candidate)))
                  t
                  (progn (setf (cached-value generator) candidate) nil))))
    (cached-value generator)))

(defmethod regenerate ((generator bounded-filter-generator))
  "Draw a fresh whole-AND valid candidate, charging the shrinking phase.

Unlike check-it's GUARD-GENERATOR delegation, regeneration validates before
returning, so a regenerated shrink candidate can never violate the AND.  A draw
the filter rejects is counted as a shrinking rejection as well as an attempt, or
the report would understate the work an exhaustion consumed."
  (with-generation-phase (:shrinking)
    (setf (cached-value generator)
          (loop
            (reserve-generation-candidate (bounded-filter-path generator)
                                          (bounded-filter-spec generator))
            (let ((candidate (generate (bounded-filter-sub-generator generator))))
              (if (funcall (bounded-filter-validator generator) candidate)
                  (return candidate)
                  (record-generation-rejection)))))))

(defun fold-and-children (children context spec base-type minimum maximum leftovers)
  "Return (VALUES BASE-TYPE MINIMUM MAXIMUM LEFTOVERS), folding CHILDREN into the
accumulators of the same names.

A TYPE-SPEC or RANGE-SPEC child narrows BASE-TYPE/MINIMUM/MAXIMUM directly.  A
REFERENCE-SPEC child is resolved through CONTEXT's registry and folded as if
its target had been written inline -- otherwise a named spec such as (AND
MY-RANGE (SATISFIES ODDP)) would fold nothing from MY-RANGE and either lose
its constraints or, worse, leave them to a GUARD-GENERATOR that rejects every
draw forever.  The resolution is guarded by *REFERENCE-TRAIL* against
recursion, exactly as the REFERENCE-SPEC method guards its own.  A nested
AND-SPEC child is flattened the same way, so (AND A (AND B C)) folds
identically to (AND A B C). A custom generator on any folded child is refused,
including one reached through aliases: deriving values would discard its chosen
distribution. Anything else is collected into LEFTOVERS."
  (dolist (child children)
    (when (spec-generator-name child)
      (error 'generator-unavailable
             :spec spec
             :reason "a conjunct has a custom generator; name a generator on the whole AND"))
    (typecase child
      (type-spec
       (setf base-type (merge-base-type base-type (type-spec-type-specifier child) spec)))
      (range-spec
       (setf base-type (merge-base-type base-type (range-spec-base-type child) spec)
             minimum (tighter-minimum minimum (range-spec-minimum child))
             maximum (tighter-maximum maximum (range-spec-maximum child))))
      (and-spec
       (multiple-value-setq (base-type minimum maximum leftovers)
         (fold-and-children (and-spec-children child) context spec
                            base-type minimum maximum leftovers)))
      (reference-spec
       (let ((target (reference-spec-target child))
             (registry (context-registry context)))
         (when (member target *reference-trail*)
           (error 'generator-unavailable
                  :spec spec
                  :reason "recursive specs have no generator in this version"))
         (let ((resolved (resolve-spec target registry))
               (*reference-trail* (cons target *reference-trail*)))
           (multiple-value-setq (base-type minimum maximum leftovers)
             (fold-and-children (list resolved) context spec
                                base-type minimum maximum leftovers)))))
      (t (push child leftovers))))
  (values base-type minimum maximum leftovers))

(defmethod spec-generator ((spec and-spec) context)
  "Build one generation source for SPEC and filter it against the whole AND.

Source selection is deterministic and construction-time only; it never draws a
value, runs a custom generator body, or evaluates the validator.  A unique custom
conjunct wins ahead of numeric folding; multiple custom conjuncts are refused
rather than silently coalesced; supported numeric folding stays a fast path;
otherwise the first ordinarily constructible conjunct is the source.  Every new
fallback checks the whole AND, so the selected source's own constraints are
enforced too."
  (labels ((resolve-candidate (child trail)
             (let ((node child) (seen trail))
               (loop
                 (when (spec-generator-name node)
                   (return (values t node seen)))
                 (unless (typep node 'reference-spec)
                   (return (values nil node seen)))
                 (let ((target (reference-spec-target node)))
                   (when (member target seen)
                     (error 'generator-unavailable
                            :spec node
                            :reason "recursive specs have no generator in this version"))
                   (setf seen (cons target seen)
                         node (resolve-spec target (context-registry context)))))))
           (entries-for (child path trail)
             (multiple-value-bind (custom-p node extended)
                 (resolve-candidate child trail)
               (cond
                 (custom-p (list (list :spec node :path path :custom-p t)))
                 ((typep node 'and-spec)
                  (entries (and-spec-children node) path extended))
                 (t (list (list :spec node :path path :custom-p nil))))))
           (entries (children prefix trail)
             (let ((collected nil))
               (loop for child in children
                     for index from 0
                     do (setf collected
                              (append collected
                                      (entries-for child
                                                   (append prefix (list index))
                                                   trail))))
               collected))
           (constructible (candidates)
             "Return (VALUES GENERATOR ENTRY) for the first candidate that compiles."
             (dolist (entry candidates)
               (handler-case
                   (return (values (spec-generator (getf entry :spec) context) entry))
                 (generator-unavailable () nil))))
           (filtered (source path)
             (make-instance 'bounded-filter-generator
                            :sub-generator source
                            :filter (compile-validator spec :context context)
                            :spec spec
                            :path path)))
    (let* ((candidates (entries (and-spec-children spec) nil *reference-trail*))
           (customs (remove-if-not (lambda (entry) (getf entry :custom-p)) candidates))
           (ordinaries (remove-if (lambda (entry) (getf entry :custom-p)) candidates)))
      (cond
        ((rest customs)
         (error 'generator-unavailable
                :spec spec
                :reason (format nil "~D conjuncts name a custom generator (~{~S~^, ~}); ~
                                     name one on the whole AND to choose explicitly"
                                (length customs)
                                (mapcar (lambda (entry) (getf entry :path)) customs))))
        (customs
         ;; P1: a unique custom source wins ahead of numeric folding.
         (let ((entry (first customs)))
           (filtered (spec-generator (getf entry :spec) context)
                     (getf entry :path))))
        (t
         (multiple-value-bind (base-type minimum maximum leftovers)
             (fold-and-children (and-spec-children spec) context spec
                                nil :unbounded :unbounded '())
           (if (and base-type (member base-type '(integer real character string
                                                   null boolean)))
               ;; P2: supported numeric/primitive folding stays a fast path.
               (let ((bounded-p (not (and (eq minimum :unbounded)
                                          (eq maximum :unbounded)))))
                 (when (and (not (eq minimum :unbounded))
                            (not (eq maximum :unbounded))
                            (> minimum maximum))
                   (error 'generator-unavailable
                          :spec spec :reason "the folded range is empty"))
                 (let ((base (if bounded-p
                                 (bounded-generator base-type minimum maximum spec)
                                 (type-specifier-generator base-type spec))))
                   (if leftovers
                       (filtered base nil)
                       base)))
               ;; P3: first ordinary conjunct whose construction succeeds.
               (multiple-value-bind (source entry) (constructible ordinaries)
                 (if entry
                     (filtered source (getf entry :path))
                     ;; P4: no eligible source.
                     (error 'generator-unavailable
                            :spec spec
                            :reason "no conjunct has an ordinary generator strategy"))))))))))
