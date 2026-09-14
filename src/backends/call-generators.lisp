;;;; src/backends/call-generators.lisp

(defpackage #:cl-spec/src/backends/call-generators
  (:use #:cl)
  (:import-from #:check-it #:generator #:generate #:shrink #:cached-value)
  (:import-from #:cl-spec/src/backends/check-it-generators #:spec-generator)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout
                #:call-layout-bindings #:call-layout-required-count #:call-layout-positional-count
                #:call-layout-rest-binding #:call-layout-key-p
                #:argument-binding-spec #:argument-binding-kind #:argument-binding-keyword)
  (:import-from #:cl-spec/src/ir
                #:spec-generator-name #:list-of-spec #:collection-spec-element-spec
                #:collection-constraint-plist
                #:collection-spec-min-length #:collection-spec-max-length
                #:collection-spec-unique-p
                #:reference-spec #:reference-spec-target
                #:type-spec #:type-spec-type-specifier)
  (:import-from #:cl-spec/src/resolve #:resolve-spec #:context-registry)
  (:import-from #:cl-spec/src/validator #:compile-validator)
  (:import-from #:cl-spec/src/conditions #:generator-unavailable)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:export #:call-arguments-generator #:call-generator-children #:call-generator-removable-p
           #:call-generator-rest-driven-p))

(in-package #:cl-spec/src/backends/call-generators)

(defclass call-arguments-generator (generator)
  ((children :initarg :children :reader call-generator-children)
   (layout :initarg :layout :reader call-generator-layout)
   (rest-driven-p :initarg :rest-driven-p :reader call-generator-rest-driven-p)
   (rest-length :initarg :rest-length :initform nil :reader call-generator-rest-length
                :documentation "Length bounds of a universal constrained rest tail that
the keyword generator fills, or NIL.")
   (validator :initarg :validator :reader call-generator-validator)
   (spec :initarg :spec :reader call-generator-spec))
  (:documentation "Generate raw calls and shrink their positional, rest, or keyword values."))

(defun keyword-tail-span (key-count minimum maximum)
  "Return (LOWEST . UPPER), the even tail lengths a keyword generator may draw.

Duplicate keywords are legal in a raw call and the first occurrence binds, so a
declared key is reused when MINIMUM needs more pairs than there are distinct
keywords.  UPPER otherwise stays at the distinct-key span, so generation does not
invent duplicates it does not need."
  (let ((lowest (if (evenp minimum) minimum (1+ minimum)))
        (natural (* 2 key-count)))
    (cons lowest
          (if (eq maximum :unbounded)
              (max lowest natural)
              (min maximum (max lowest natural))))))

(defun keyword-tail-pool-size (bindings)
  "Return how many distinct keyword pairs a tail may draw from BINDINGS.

This is the length KEYWORD-TAIL-POOL returns for the same bindings: an empty &key
section is still a keyword call, because the standard :ALLOW-OTHER-KEYS control
pair is accepted, so a key-p layout always has at least one pair to draw.
Capability reporting uses it without compiling the value generators."
  (max 1 (count-if (lambda (binding) (eq :key (argument-binding-kind binding)))
                   bindings)))

(defun keyword-tail-keywords (layout)
  "Return the keywords a generated keyword tail may contain.

Declared keywords come from the layout's :KEY bindings.  A keyword section that
declares none still draws the :ALLOW-OTHER-KEYS control pair, and shrinking must
be able to propose removing that pair, since generation advertises it as
removable whenever the tail may be longer than its minimum."
  (let ((declared (loop for binding in (call-layout-bindings layout)
                        when (eq :key (argument-binding-kind binding))
                          collect (argument-binding-keyword binding))))
    (or declared (list :allow-other-keys))))

(defun keyword-tail-pool (bindings children)
  "Return the (KEYWORD . CHILD) pairs a keyword tail may draw from, never empty.

CHILD is whatever SPEC-GENERATOR produced for the keyword's value spec: a
generator object, or a value that CHECK-IT:GENERATE returns as a constant.  A NIL
child therefore means the constant NIL -- (member nil) and (type null) both
compile to it -- not \"no generator\".  The empty &key fallback uses the constant
T for the :ALLOW-OTHER-KEYS control pair instead of a separate sentinel, so every
pair is drawn through the same GENERATE call.  Its length is
KEYWORD-TAIL-POOL-SIZE for the same bindings."
  (let ((declared (loop for binding in bindings
                        for child in children
                        when (eq :key (argument-binding-kind binding))
                          collect (cons (argument-binding-keyword binding) child))))
    (or declared
        (list (cons :allow-other-keys t)))))

(defun call-generator-removable-p (generator)
  "Return true when optional positional or generated keyword arguments can be omitted."
  (let ((layout (call-generator-layout generator))
        (rest-length (call-generator-rest-length generator)))
    (or (> (call-layout-positional-count layout) (call-layout-required-count layout))
        (and (not (call-generator-rest-driven-p generator))
             (if rest-length
                 ;; A keyword pair is removable only while the rest tail may still
                 ;; be longer than the minimum the rest spec declares.
                 (>= (cdr (keyword-tail-span
                           (keyword-tail-pool-size (call-layout-bindings layout))
                           (car rest-length) (cdr rest-length)))
                     (+ (car rest-length) 2))
                 (some (lambda (binding) (eq :key (argument-binding-kind binding)))
                       (call-layout-bindings layout)))))))

(defun generate-keyword-tail (bindings children rest-length spec)
  "Draw a keyword/value tail whose even length lies inside REST-LENGTH.

Duplicate keywords are legal and the first occurrence binds, so a declared key is
reused when the minimum demands more pairs than there are distinct keywords.  A
layout with no declared keywords falls back to the :ALLOW-OTHER-KEYS control pair."
  (let* ((pool (keyword-tail-pool bindings children))
         (minimum (car rest-length))
         (maximum (cdr rest-length))
         (span (keyword-tail-span (length pool) minimum maximum))
         (lowest (car span))
         (upper (cdr span)))
    (when (> lowest upper)
      (error 'generator-unavailable
             :spec spec
             :reason (format nil "the declared keywords cannot fill a rest tail of ~D to ~D elements"
                             minimum maximum)))
    (let* ((low-pairs (/ lowest 2))
           (high-pairs (floor upper 2))
           (pairs (+ low-pairs (random (1+ (- high-pairs low-pairs)))))
           (remaining (copy-list pool))
           (chosen nil))
      (loop repeat pairs
            do (when (null remaining) (setf remaining (copy-list pool)))
               (let ((index (random (length remaining))))
                 (push (nth index remaining) chosen)
                 (setf remaining (append (subseq remaining 0 index)
                                         (subseq remaining (1+ index))))))
      (loop for (keyword . child) in (nreverse chosen)
            append (list keyword (generate child))))))

(defmethod generate ((generator call-arguments-generator))
  (let* ((layout (call-generator-layout generator))
         (children (call-generator-children generator))
         (bindings (call-layout-bindings layout))
         (required (call-layout-required-count layout))
         (positional (call-layout-positional-count layout))
         (rest-driven (call-generator-rest-driven-p generator))
         (rest-length (call-generator-rest-length generator)))
    (loop repeat 100
          for tail = (cond (rest-driven (generate (nth positional children)))
                           (rest-length (generate-keyword-tail bindings children rest-length
                                                               (call-generator-spec generator)))
                           (t (loop for binding in bindings for child in children
                                    when (and (eq :key (argument-binding-kind binding))
                                              (zerop (random 2)))
                                      append (list (argument-binding-keyword binding)
                                                   (generate child)))))
          for proper-tail = (if (finite-list-p tail) tail
                                (error 'generator-unavailable
                                       :spec (call-generator-spec generator)
                                       :reason "rest generator must produce a finite proper list"))
          for count = (if tail positional
                          (+ required (random (1+ (- positional required)))))
          for arguments = (append (loop for child in children for index from 0 below count
                                        collect (generate child))
                                  proper-tail)
          ;; Rest-driven and length-targeted draws are filtered here; an
          ;; unconstrained keyword draw is left to the backend's initial
          ;; argument validation, which refuses invalid custom output.
          when (or (not (or rest-driven rest-length))
                   (funcall (call-generator-validator generator) arguments))
            do (return-from generate (setf (cached-value generator) arguments)))
    (error 'generator-unavailable :spec (call-generator-spec generator)
           :reason "rest and keyword constraints rejected 100 generated calls")))

(defun remove-call-key (arguments positional key)
  "Return a copied call and true when its keyword pair was removed."
  (when (>= (length arguments) positional)
    (let ((tail (copy-list (nthcdr positional arguments))))
      (when (remf tail key)
        (values (append (subseq arguments 0 positional) tail) t)))))

(defmethod shrink ((generator call-arguments-generator) test)
  (let* ((layout (call-generator-layout generator))
         (positional (call-layout-positional-count layout)))
    (unless (call-generator-rest-driven-p generator)
      (dolist (keyword (keyword-tail-keywords layout))
        (multiple-value-bind (candidate removed)
            (remove-call-key (cached-value generator) positional keyword)
          (when (and removed (not (funcall test candidate)))
            (setf (cached-value generator) candidate)))))
    ;; Removing an optional argument must not consume a value from the remaining tail.
    (when (<= (length (cached-value generator)) positional)
      (loop for count from (call-layout-required-count layout)
            while (< count (length (cached-value generator)))
            do (let ((candidate (subseq (cached-value generator) 0 count)))
                 (unless (funcall test candidate)
                   (setf (cached-value generator) candidate)))))
    (loop for binding in (call-layout-bindings layout)
          for child in (call-generator-children generator)
          for position from 0
          for kind = (argument-binding-kind binding)
          for index = (case kind
                        (:rest (when (call-generator-rest-driven-p generator)
                                 (min positional (length (cached-value generator)))))
                        (:key (unless (call-generator-rest-driven-p generator)
                                (loop for tail on (nthcdr (min positional
                                                               (length (cached-value generator)))
                                                          (cached-value generator)) by #'cddr
                                      for i from positional by 2
                                      when (eq (car tail) (argument-binding-keyword binding))
                                        return (1+ i))))
                        (otherwise
                         (when (< position (length (cached-value generator))) position)))
          when (and index (typep child 'generator))
            do (shrink child
                       (lambda (value)
                         (let ((candidate
                                 (if (eq kind :rest)
                                     (when (finite-list-p value)
                                       (append (subseq (cached-value generator) 0 index) value))
                                     (let ((copy (copy-list (cached-value generator))))
                                       (setf (nth index copy) value)
                                       copy))))
                           (if (or (and (eq kind :rest) (not (finite-list-p value)))
                                   (funcall test candidate))
                               t
                               (progn (setf (cached-value generator) candidate) nil)))))))
  (cached-value generator))

(defun resolve-rest-spec (spec context &optional trail)
  "Return the spec a rest declaration's reference chain ends at, or NIL.

The chain is followed so a name registered for `(list-of t ...)` is classified
like the same spec written inline.  A link carrying a custom generator ends the
walk with NIL: that generator owns the values, so the universal-rest shortcut
must not fill the tail with keyword pairs instead.  RECURSIVE chains and a
custom generator on the resolved node are both NIL for the same reason."
  (when (spec-generator-name spec)
    (return-from resolve-rest-spec nil))
  (if (typep spec 'reference-spec)
      (let ((target (reference-spec-target spec)))
        (when (member target trail :test #'eq)
          (return-from resolve-rest-spec nil))
        (resolve-rest-spec (resolve-spec target (context-registry context))
                           context
                           (cons target trail)))
      spec))

(defun universal-rest-list-p (spec)
  "Return true when SPEC is (list-of t ...) with universal elements and no custom generator."
  (and (eq (class-of spec) (find-class 'list-of-spec))
       (null (spec-generator-name spec))
       (let ((element (collection-spec-element-spec spec)))
         (and (eq (class-of element) (find-class 'type-spec))
              (null (spec-generator-name element))
              (eq t (type-spec-type-specifier element))))))

(defun unconstrained-rest-list-p (spec)
  "Recognize an unannotated universal list without bypassing extension generators."
  (and (universal-rest-list-p spec)
       (null (collection-constraint-plist spec))))

(defun keyword-rest-bounds (spec layout)
  "Return (MIN . MAX) when SPEC is a universal length-constrained rest tail that
the keyword generator can fill, else NIL.

Only length bounds are handled: UNIQUE over an arbitrary tail is not something
keyword pairs can promise, so that combination keeps the rest-driven path."
  (when (and (call-layout-key-p layout)
             (universal-rest-list-p spec)
             (not (collection-spec-unique-p spec))
             (or (plusp (collection-spec-min-length spec))
                 (not (eq :unbounded (collection-spec-max-length spec)))))
    (cons (collection-spec-min-length spec)
          (collection-spec-max-length spec))))

(defmethod spec-generator ((spec call-arguments-spec) context)
  (let* ((layout (call-arguments-spec-layout spec))
         (rest (call-layout-rest-binding layout))
         (rest-spec (and rest (argument-binding-spec rest)))
         ;; Resolve names first: a registered (list-of t ...) is the same tail as
         ;; the inline form, while a generator-annotated link keeps its owner.
         (rest-target (and rest-spec (resolve-rest-spec rest-spec context)))
         (keyword-length (and rest-target (keyword-rest-bounds rest-target layout)))
         (unconstrained (and rest-target (unconstrained-rest-list-p rest-target)))
         (rest-driven (and rest
                           (not (and (call-layout-key-p layout)
                                     (or unconstrained keyword-length))))))
    (make-instance 'call-arguments-generator
                   :layout layout :spec spec :rest-driven-p rest-driven
                   :rest-length keyword-length
                   :validator (compile-validator spec :context context)
                   :children
                   (mapcar (lambda (binding)
                             (unless (or (and rest-driven
                                              (eq :key (argument-binding-kind binding)))
                                         (and (not rest-driven)
                                              (eq :rest (argument-binding-kind binding))))
                               (spec-generator (argument-binding-spec binding) context)))
                           (call-layout-bindings layout)))))
