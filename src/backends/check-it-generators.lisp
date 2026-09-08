;;;; src/backends/check-it-generators.lisp
;;;;
;;;; Semantic IR -> check-it generator (specification §10, §12).  check-it's
;;;; GENERATOR macro expands into MAKE-INSTANCE forms over exported classes, so
;;;; the mapping is built by calling MAKE-INSTANCE directly: no runtime EVAL is
;;;; needed, and the DSL stays out of the compilation path.

(defpackage #:cl-spec/src/backends/check-it-generators
  (:use #:cl)
  (:import-from #:check-it
                #:int-generator
                #:real-generator
                #:char-generator
                #:string-generator
                #:list-generator
                #:tuple-generator
                #:or-generator
                #:guard-generator
                #:mapped-generator)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable
                #:unknown-spec)
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
                #:collection-spec
                #:collection-spec-element-spec
                #:list-of-spec
                #:vector-of-spec
                #:reference-spec
                #:reference-spec-target)
  (:import-from #:cl-spec/src/registry
                #:registry-find-spec)
  (:import-from #:cl-spec/src/resolve
                #:context-registry)
  (:import-from #:cl-spec/src/validator
                #:compile-validator)
  (:export #:spec-generator
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
    (when (null values)
      (error 'generator-unavailable :spec spec :reason "an empty MEMBER admits nothing"))
    (make-instance 'or-generator :sub-generators (copy-list values))))

(defmethod spec-generator ((spec or-spec) context)
  (let ((children (or-spec-children spec)))
    (when (null children)
      (error 'generator-unavailable :spec spec :reason "an empty OR admits nothing"))
    (make-instance 'or-generator
                   :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                           children))))

(defmethod spec-generator ((spec nullable-spec) context)
  (make-instance 'or-generator
                 :sub-generators
                 (list nil (spec-generator (nullable-spec-inner-spec spec) context))))

(defmethod spec-generator ((spec tuple-spec) context)
  (make-instance 'tuple-generator
                 :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                         (tuple-spec-element-specs spec))))

(defmethod spec-generator ((spec list-of-spec) context)
  (let ((element (collection-spec-element-spec spec)))
    ;; check-it calls the generator function once per element per draw, which is
    ;; what lets it shrink each element independently.
    (make-instance 'list-generator
                   :generator-function (lambda () (spec-generator element context)))))

(defmethod spec-generator ((spec vector-of-spec) context)
  (let ((element (collection-spec-element-spec spec)))
    (make-instance 'mapped-generator
                   :mapping (lambda (items) (coerce items 'vector))
                   :sub-generators
                   (list (make-instance 'list-generator
                                        :generator-function
                                        (lambda () (spec-generator element context)))))))

(defmethod spec-generator ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    (when (member target *reference-trail*)
      (error 'generator-unavailable
             :spec spec
             :reason "recursive specs have no generator in this version"))
    (let ((resolved (or (registry-find-spec registry target)
                        (error 'unknown-spec :name target)))
          (*reference-trail* (cons target *reference-trail*)))
      (spec-generator resolved context))))

(defun compile-spec-generator (spec context)
  "Return (values GENERATOR REQUIRED-SIZE) for SPEC.

REQUIRED-SIZE is what CHECK-IT:*SIZE* has to reach for the generator to respect
the bounds the spec asks for.  The caller binds it around GENERATE; returning it
rather than binding it here lets one binding cover a whole trial loop."
  (let ((*required-size* 0))
    (values (spec-generator spec context) *required-size*)))

(defun merge-base-type (current new spec)
  "Return the base type implied by both CURRENT and NEW, signalling on conflict."
  (cond ((null current) new)
        ((null new) current)
        ((eq current new) current)
        ((and (member current '(integer real)) (member new '(integer real))) 'integer)
        (t (error 'generator-unavailable
                  :spec spec
                  :reason (format nil "conflicting base types ~S and ~S" current new)))))

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

(defmethod spec-generator ((spec and-spec) context)
  ;; Folding rather than guarding is a correctness requirement, not an
  ;; optimisation: check-it's GUARD-GENERATOR retries by recursing into GENERATE
  ;; with no depth limit, so a guard that rejects often enough overflows the
  ;; stack.  Narrowing the base generator removes the rejection entirely.
  (let ((base-type nil)
        (minimum :unbounded)
        (maximum :unbounded)
        (leftovers '()))
    (dolist (child (and-spec-children spec))
      (typecase child
        (type-spec
         (setf base-type (merge-base-type base-type (type-spec-type-specifier child) spec)))
        (range-spec
         (setf base-type (merge-base-type base-type (range-spec-base-type child) spec)
               minimum (tighter-minimum minimum (range-spec-minimum child))
               maximum (tighter-maximum maximum (range-spec-maximum child))))
        (t (push child leftovers))))
    (when (and (null base-type)
               (not (and (eq minimum :unbounded) (eq maximum :unbounded))))
      (setf base-type 'real))
    (when (null base-type)
      (error 'generator-unavailable
             :spec spec
             :reason "an AND needs a type or range conjunct to generate from"))
    (when (and (not (eq minimum :unbounded))
               (not (eq maximum :unbounded))
               (> minimum maximum))
      (error 'generator-unavailable :spec spec :reason "the folded range is empty"))
    (let ((base (if (and (eq minimum :unbounded) (eq maximum :unbounded))
                    (type-specifier-generator base-type spec)
                    (bounded-generator base-type minimum maximum spec))))
      (if leftovers
          (make-instance 'guard-generator
                         :guard (compile-validator spec :context context)
                         :sub-generator base)
          base))))
