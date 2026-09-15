;;;; src/explain.lisp
;;;;
;;;; Structured explanation (specification §22).  The structured plist is the
;;;; primary representation; the human readable rendering, the condition report
;;;; and any JSON/MCP projection are all derived from it.

(defpackage #:cl-spec/src/explain
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-kind
                #:spec-source-form
                #:type-spec
                #:type-spec-type-specifier
                #:predicate-spec
                #:predicate-spec-predicate
                #:member-spec
                #:member-spec-values
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:instance-of-spec
                #:instance-of-spec-class-name
                #:bounded-collection-spec
                #:collection-spec-min-length
                #:collection-spec-max-length
                #:collection-spec-unique-p
                #:collection-constraint-plist
                #:reference-spec
                #:reference-spec-target
                #:and-spec
                #:and-spec-children
                #:or-spec
                #:or-spec-children
                #:not-spec
                #:not-spec-inner-spec
                #:nullable-spec
                #:nullable-spec-inner-spec
                #:collection-spec-element-spec
                #:list-of-spec
                #:vector-of-spec
                #:tuple-spec
                #:tuple-spec-element-specs)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:keyed-field-spec #:alist-spec #:hash-table-spec
                #:object-spec #:object-spec-class-name #:reader-function
                #:field-spec-fields #:field-spec-closed-p
                #:field-key #:field-value-spec #:field-required-p #:field-key-test
                #:key-test-name
                #:plist-structure-error
                #:alist-structure-error #:hash-table-structure-error)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-spec #:tagged-union-tag-reader #:tagged-union-branches
                #:branch-name #:branch-spec #:read-tag-value)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:context-registry
                #:spec-display-name)
  (:export #:compile-explainer
           #:explain-data
           #:explain
           #:compile-node
           #:expected-descriptor
           #:error-datum
           #:proper-list-p))

(in-package #:cl-spec/src/explain)

(declaim (ftype (function (spec &key (:context t)) function) compile-explainer))

(defun error-datum (kind path value &rest extra)
  "Build one structured error plist.

PATH is accumulated innermost first and reversed here, so callers always see it
running from the root value down to the failing part."
  (list* :kind kind :path (reverse path) :actual value extra))

(defparameter +field-structure-error-kinds+
  '(:not-a-plist :not-an-alist :not-a-hash-table :bad-association
    :duplicate-key :missing-key :unknown-key :wrong-key-test :unbound-slot
    :no-branch)
  "EXPLAIN-DATA kinds a composite node's own structure check produces.

These stay visible inside a conjunction instead of collapsing into one
checklist line, because each names a different malformed position.")

(defgeneric expected-descriptor (spec)
  (:documentation "Return a small plist saying what SPEC admits.

This is the shape EXPLAIN renders as a checklist line and the shape an agent
reads to learn what a value should have been. Composite built-in nodes include
their child descriptors. Extensions with additional constraints should specialize
this generic; the default only identifies the node kind."))

(defmethod expected-descriptor ((spec spec))
  (list :kind (spec-kind spec)))

(defmethod expected-descriptor ((spec type-spec))
  (list :type (type-spec-type-specifier spec)))

(defmethod expected-descriptor ((spec predicate-spec))
  (list :satisfies (predicate-spec-predicate spec)))

(defmethod expected-descriptor ((spec member-spec))
  (list* :member (member-spec-values spec)))

(defmethod expected-descriptor ((spec range-spec))
  (list :range :min (range-spec-minimum spec) :max (range-spec-maximum spec)))

(defmethod expected-descriptor ((spec instance-of-spec))
  (list :instance-of (instance-of-spec-class-name spec)))

(defmethod expected-descriptor ((spec reference-spec))
  (list :spec (reference-spec-target spec)))

(defmethod expected-descriptor ((spec list-of-spec))
  (list* :list-of (expected-descriptor (collection-spec-element-spec spec))
         (collection-constraint-plist spec)))

(defmethod expected-descriptor ((spec vector-of-spec))
  (list* :vector-of (expected-descriptor (collection-spec-element-spec spec))
         (collection-constraint-plist spec)))

(defmethod expected-descriptor ((spec tuple-spec))
  (list* :tuple (mapcar #'expected-descriptor (tuple-spec-element-specs spec))))

(defmethod expected-descriptor ((spec and-spec))
  (list* :and (mapcar #'expected-descriptor (and-spec-children spec))))

(defmethod expected-descriptor ((spec or-spec))
  (list* :or (mapcar #'expected-descriptor (or-spec-children spec))))

(defmethod expected-descriptor ((spec nullable-spec))
  (list :nullable (expected-descriptor (nullable-spec-inner-spec spec))))

(defmethod expected-descriptor ((spec not-spec))
  (list :not (expected-descriptor (not-spec-inner-spec spec))))

(defun field-expectation-descriptors (spec)
  "Return the expected descriptor of each declared field of SPEC, in declaration order."
  (loop for field in (field-spec-fields spec)
        collect (list :key (field-key field)
                      :required (field-required-p field)
                      :expected (expected-descriptor (field-value-spec field)))))

(defmethod expected-descriptor ((spec plist-spec))
  (list :kind :plist :closed (field-spec-closed-p spec)
        :fields (field-expectation-descriptors spec)))

(defmethod expected-descriptor ((spec keyed-field-spec))
  (list :kind (spec-kind spec) :test (field-key-test spec)
        :closed (field-spec-closed-p spec)
        :fields (field-expectation-descriptors spec)))

(defmethod expected-descriptor ((spec object-spec))
  (list :kind :object :class (object-spec-class-name spec)
        :fields (field-expectation-descriptors spec)))

(defmethod expected-descriptor ((spec tagged-union-spec))
  (list :kind :tagged-union
        :tag-reader (tagged-union-tag-reader spec)
        :branches (loop for branch in (tagged-union-branches spec)
                        collect (list :name (branch-name branch)
                                      :expected (expected-descriptor (branch-spec branch))))))

(defgeneric compile-node (spec context)
  (:documentation "Compile SPEC into a function of (VALUE PATH).

The compiled function returns a list of structured error plists, empty when
VALUE satisfies SPEC.  PATH is the accumulated position, innermost first."))

(defmethod compile-node ((spec spec) context)
  (declare (ignore context))
  (error 'invalid-spec-form
         :form (spec-source-form spec)
         :reason (format nil "~S has no explainer in this version" (spec-kind spec))))

(defmethod compile-node ((spec type-spec) context)
  (declare (ignore context))
  (let ((type-specifier (type-spec-type-specifier spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (unless (typep value type-specifier)
        (list (error-datum :type-failed path value :expected expected))))))

(defmethod compile-node ((spec predicate-spec) context)
  (declare (ignore context))
  (let ((predicate (predicate-spec-predicate spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (handler-case
          (unless (funcall predicate value)
            (list (error-datum :predicate-failed path value
                               :predicate predicate :expected expected)))
        ((and error (not (or undefined-function program-error))) (condition)
          ;; A predicate applied to the wrong kind of value is a fact about the
          ;; value, not a bug in the caller: VALIDP must answer NIL rather than
          ;; unwind. UNDEFINED-FUNCTION (a typo'd predicate name) and
          ;; PROGRAM-ERROR (a predicate called with the wrong number of
          ;; arguments) are authoring bugs instead, and are left to propagate
          ;; so the reader is pointed at the broken spec rather than told the
          ;; value is bad.
          (list (error-datum :predicate-errored path value
                             :predicate predicate :expected expected
                             :condition-type (type-of condition)
                             :condition-report (princ-to-string condition))))))))

(defmethod compile-node ((spec member-spec) context)
  (declare (ignore context))
  (let ((values (member-spec-values spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (unless (member value values :test #'eql)
        (list (error-datum :not-member path value :expected expected))))))

(defmethod compile-node ((spec range-spec) context)
  (declare (ignore context))
  (let ((base-type (or (range-spec-base-type spec) 'real))
        (minimum (range-spec-minimum spec))
        (maximum (range-spec-maximum spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (cond
        ((not (typep value base-type))
         (list (error-datum :type-failed path value :expected expected)))
        ((and (not (eq minimum :unbounded)) (< value minimum))
         (list (error-datum :out-of-range path value
                            :expected expected :violated-bound :minimum)))
        ((and (not (eq maximum :unbounded)) (> value maximum))
         (list (error-datum :out-of-range path value
                            :expected expected :violated-bound :maximum)))))))

(defmethod compile-node ((spec instance-of-spec) context)
  (declare (ignore context))
  (let ((class-name (instance-of-spec-class-name spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (let ((class (find-class class-name nil)))
        (unless (and class (typep value class))
          (list (error-datum :not-an-instance path value :expected expected)))))))

(defun proper-list-p (value)
  "Use the shared cycle-safe proper-list check."
  (finite-list-p value))

(defmethod compile-node ((spec and-spec) context)
  (let* ((children (and-spec-children spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) children))
         (descriptors (mapcar #'expected-descriptor children)))
    (lambda (value path)
      ;; Short-circuiting is both the safe reading and the one section 22's
      ;; example shows: a later conjunct may only be meaningful once the
      ;; earlier ones hold, as (satisfies plusp) is only meaningful for a number.
      (loop for child-function in compiled
            for index from 0
            for child-errors = (funcall child-function value path)
            when child-errors
              return (list (error-datum
                            :conjunct-failed path value
                            :conjuncts (loop for descriptor in descriptors
                                             for position from 0
                                             collect (list :expected descriptor
                                                           :status (cond ((< position index)
                                                                          :satisfied)
                                                                         ((= position index)
                                                                          :failed)
                                                                         (t :unchecked))))
                            :errors child-errors))))))

(defmethod compile-node ((spec or-spec) context)
  (let* ((children (or-spec-children spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) children))
         (descriptors (mapcar #'expected-descriptor children)))
    (lambda (value path)
      (let ((branch-errors (mapcar (lambda (function) (funcall function value path))
                                   compiled)))
        (unless (some #'null branch-errors)
          (list (error-datum :no-branch-matched path value
                             :branches (mapcar (lambda (descriptor errors)
                                                 (list :expected descriptor :errors errors))
                                               descriptors branch-errors))))))))

(defmethod compile-node ((spec not-spec) context)
  (let ((inner (compile-node (not-spec-inner-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (when (null (funcall inner value path))
        (list (error-datum :negation-failed path value :expected expected))))))

(defmethod compile-node ((spec nullable-spec) context)
  (let ((inner (compile-node (nullable-spec-inner-spec spec) context)))
    (lambda (value path)
      (unless (null value)
        (funcall inner value path)))))

(defun collection-length-errors (spec value path expected)
  "Return a :too-short or :too-long error datum for VALUE, or NIL."
  (let ((minimum (collection-spec-min-length spec))
        (maximum (collection-spec-max-length spec))
        (length (length value)))
    (cond ((< length minimum)
           (list (error-datum :too-short path value :expected expected
                              :minimum-length minimum :actual-length length)))
          ((and (integerp maximum) (> length maximum))
           (list (error-datum :too-long path value :expected expected
                              :maximum-length maximum :actual-length length))))))

(defun collection-uniqueness-errors (spec value path expected)
  "Return a :duplicate-element datum for every repeated element of VALUE, or NIL.

Elements are compared with EQL, which is what the declaration promises; a keyed
identity is future work, not a hidden reinterpretation of EQL.  A list is walked
with DOLIST rather than indexed access, so a long unique list stays linear."
  (when (collection-spec-unique-p spec)
    (let ((seen (make-hash-table :test #'eql))
          (errors nil)
          (index 0))
      (flet ((examine (item)
               (multiple-value-bind (first-index present-p) (gethash item seen)
                 (if present-p
                     (push (error-datum :duplicate-element (cons index path) item
                                        :expected expected :first-index first-index)
                           errors)
                     (setf (gethash item seen) index)))
               (incf index)))
        (if (listp value)
            (dolist (item value) (examine item))
            (loop for position from 0 below (length value)
                  do (examine (aref value position)))))
      (nreverse errors))))

(defmethod compile-node ((spec list-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (proper-list-p value))
          (list (error-datum :not-a-list path value :expected expected))
          (append (collection-length-errors spec value path expected)
                  (loop for item in value
                        for index from 0
                        append (funcall element item (cons index path)))
                  (collection-uniqueness-errors spec value path expected))))))

(defmethod compile-node ((spec vector-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (vectorp value))
          (list (error-datum :not-a-vector path value :expected expected))
          (append (collection-length-errors spec value path expected)
                  (loop for index from 0 below (length value)
                        append (funcall element (aref value index) (cons index path)))
                  (collection-uniqueness-errors spec value path expected))))))

(defmethod compile-node ((spec tuple-spec) context)
  (let* ((element-specs (tuple-spec-element-specs spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) element-specs))
         (arity (length element-specs))
         (expected (expected-descriptor spec)))
    (lambda (value path)
      (cond
        ((not (or (proper-list-p value) (vectorp value)))
         (list (error-datum :not-a-sequence path value :expected expected)))
        ((/= (length value) arity)
         (list (error-datum :wrong-length path value :expected expected
                            :expected-length arity :actual-length (length value))))
        (t
         (loop for function in compiled
               for index from 0
               append (loop for datum in
                             (funcall function (elt value index) (cons index path))
                             collect
                             (let ((copy (copy-list datum)))
                               ;; Tuple positions select distinct specs. Collection
                               ;; indices in :PATH only locate values.
                               (setf (getf copy :tuple-path)
                                     (cons index (getf datum :tuple-path)))
                               copy))))))))

(defmethod compile-node ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    ;; Resolving on every call rather than at compile time is what makes forward
    ;; references, redefinition and recursive specs all work: compiling the
    ;; target eagerly would either capture a stale definition or never terminate.
    (lambda (value path)
      (let ((resolved (resolve-spec target registry)))
        (funcall (compile-node resolved (list :registry registry)) value path)))))

(defmethod compile-node ((spec plist-spec) context)
  (let* ((fields (field-spec-fields spec))
         (compiled (mapcar (lambda (field) (compile-node (field-value-spec field) context))
                           fields))
         (declared-keys (make-hash-table :test #'eq))
         (closed-p (field-spec-closed-p spec))
         (expected (expected-descriptor spec)))
    (dolist (field fields)
      (setf (gethash (field-key field) declared-keys) t))
    (lambda (value path)
      (multiple-value-bind (kind key index keys) (plist-structure-error value)
        (if kind
            (list (error-datum kind (if (eq kind :duplicate-key) (cons key path) path)
                               value :expected expected))
            (append
             (loop for field in fields
                   for function in compiled
                   for key = (field-key field)
                   append
                   (multiple-value-bind (item present-p) (gethash key index)
                     (let ((errors
                             (cond
                               (present-p (funcall function item (cons key path)))
                               ((field-required-p field)
                                (list (error-datum :missing-key (cons key path) nil
                                                   :expected
                                                   (expected-descriptor
                                                    (field-value-spec field))))))))
                       (loop for datum in errors
                             collect (let ((copy (copy-list datum)))
                                       (setf (getf copy :field-path)
                                             (cons key (getf datum :field-path)))
                                       copy)))))
             (when closed-p
               (loop for key in keys
                     unless (gethash key declared-keys)
                       collect (error-datum :unknown-key (cons key path) (gethash key index)
                                            :expected expected)))))))))

(defun field-path-errors (errors key)
  "Return ERRORS with KEY prepended to each datum's declared :FIELD-PATH.

:FIELD-PATH carries only declared field keys, which is what lets failure identity
separate a violation in one field from the same violation in another."
  (loop for datum in errors
        collect (let ((copy (copy-list datum)))
                  (setf (getf copy :field-path)
                        (cons key (getf datum :field-path)))
                  copy)))

(defmethod compile-node ((spec alist-spec) context)
  (let* ((fields (field-spec-fields spec))
         (compiled (mapcar (lambda (field) (compile-node (field-value-spec field) context))
                           fields))
         (test-name (key-test-name (field-key-test spec)))
         (declared (mapcar #'field-key fields))
         (closed-p (field-spec-closed-p spec))
         (expected (expected-descriptor spec)))
    (lambda (value path)
      (multiple-value-bind (kind key) (alist-structure-error value (field-key-test spec))
        (if kind
            (list (error-datum kind (if (eq kind :duplicate-key) (cons key path) path)
                               value :expected expected))
            (append
             (loop for field in fields
                   for function in compiled
                   for field-key = (field-key field)
                   append
                   (let ((entry (assoc field-key value :test test-name)))
                     (field-path-errors
                      (cond
                        (entry (funcall function (cdr entry) (cons field-key path)))
                        ((field-required-p field)
                         (list (error-datum :missing-key (cons field-key path) nil
                                            :expected
                                            (expected-descriptor
                                             (field-value-spec field))))))
                      field-key)))
             (when closed-p
               (loop for entry in value
                     for key = (car entry)
                     unless (member key declared :test test-name)
                       collect (error-datum :unknown-key (cons key path) (cdr entry)
                                            :expected expected)))))))))

(defmethod compile-node ((spec hash-table-spec) context)
  (let* ((fields (field-spec-fields spec))
         (compiled (mapcar (lambda (field) (compile-node (field-value-spec field) context))
                           fields))
         (test-name (key-test-name (field-key-test spec)))
         (declared (make-hash-table :test test-name))
         (closed-p (field-spec-closed-p spec))
         (expected (expected-descriptor spec)))
    (dolist (field fields)
      (setf (gethash (field-key field) declared) t))
    (lambda (value path)
      (multiple-value-bind (kind actual) (hash-table-structure-error value (field-key-test spec))
        (if kind
            (if (eq kind :wrong-key-test)
                (list (error-datum kind path value :expected expected :actual-test actual))
                (list (error-datum kind path value :expected expected)))
            (append
             (loop for field in fields
                   for function in compiled
                   for field-key = (field-key field)
                   append
                   (multiple-value-bind (item present-p) (gethash field-key value)
                     (field-path-errors
                      (cond
                        (present-p (funcall function item (cons field-key path)))
                        ((field-required-p field)
                         (list (error-datum :missing-key (cons field-key path) nil
                                            :expected
                                            (expected-descriptor
                                             (field-value-spec field))))))
                      field-key)))
             (when closed-p
               ;; MAPHASH order is unspecified and arbitrary keys may have a
               ;; signalling or nonterminating printer, so the errors are
               ;; reported in that order rather than sorted by a printed key.
               ;; Every :unknown-key datum has the same failure shape, so the
               ;; order does not affect failure identity.
               (let ((unknown nil))
                 (maphash (lambda (key item)
                            (unless (gethash key declared)
                              (push (error-datum :unknown-key (cons key path) item
                                                 :expected expected)
                                    unknown)))
                          value)
                 (nreverse unknown)))))))))

(defun read-object-field (object reader)
  "Return (values PRESENT-P VALUE CONDITION) reading OBJECT through READER.

PRESENT-P is NIL and CONDITION is NIL when READER signals UNBOUND-SLOT, which is
how an unbound CLOS slot announces itself; a bound slot holding NIL stays a
present field.  Any other condition is returned as CONDITION for the caller to
report, except UNDEFINED-FUNCTION and PROGRAM-ERROR, which describe a broken
reader rather than a bad value and propagate to the author."
  (handler-case
      (values t (funcall (reader-function reader) object) nil)
    (unbound-slot () (values nil nil nil))
    ((and error (not (or undefined-function program-error))) (condition)
      (values nil nil condition))))

(defmethod compile-node ((spec object-spec) context)
  (let* ((class-name (object-spec-class-name spec))
         (fields (field-spec-fields spec))
         (compiled (mapcar (lambda (field) (compile-node (field-value-spec field) context))
                           fields))
         (expected (expected-descriptor spec)))
    (lambda (value path)
      (let ((class (find-class class-name nil)))
        (if (not (and class (typep value class)))
            (list (error-datum :not-an-instance path value :expected expected))
            (loop for field in fields
                  for function in compiled
                  for key = (field-key field)
                  append
                  (multiple-value-bind (present-p item condition) (read-object-field value key)
                    (cond
                      (present-p
                       (field-path-errors (funcall function item (cons key path)) key))
                      (condition
                       (field-path-errors
                        (list (error-datum :reader-errored (cons key path) value
                                           :expected
                                           (expected-descriptor (field-value-spec field))
                                           :condition-type (type-of condition)
                                           :condition-report (princ-to-string condition)))
                        key))
                      ((field-required-p field)
                       (field-path-errors
                        (list (error-datum :unbound-slot (cons key path) nil
                                           :expected
                                           (expected-descriptor (field-value-spec field))))
                        key))
                      (t nil)))))))))

(defun read-union-tag (value designator)
  "Return (values OK TAG CONDITION) reading VALUE's tag through DESIGNATOR.

OK is NIL when the reader signalled; CONDITION then describes it.  A tag that
cannot be read is a fact about the value, so it is reported as :READER-ERRORED
rather than treated as an absent tag."
  (handler-case
      (values t (read-tag-value value designator) nil)
    ((and error (not (or undefined-function program-error))) (condition)
      (values nil nil condition))))

(defun branch-errors (errors name)
  "Return ERRORS tagged with the matched branch NAME.

:BRANCH names the innermost union that produced the datum, so a nested union's
selection survives an outer union's tagging; :BRANCH-PATH accumulates every
enclosing branch name outermost first, the way :FIELD-PATH accumulates fields.
Only top-level datums are tagged: a nested :ERRORS list belongs to the same
branch."
  (loop for datum in errors
        collect (let ((copy (copy-list datum)))
                  (unless (getf copy :branch)
                    (setf (getf copy :branch) name))
                  (setf (getf copy :branch-path)
                        (cons name (getf copy :branch-path)))
                  copy)))

(defmethod compile-node ((spec tagged-union-spec) context)
  (let* ((designator (tagged-union-tag-reader spec))
         (branches (tagged-union-branches spec))
         (compiled (mapcar (lambda (branch) (compile-node (branch-spec branch) context))
                           branches))
         (tags (mapcar #'branch-name branches))
         (expected (expected-descriptor spec)))
    (lambda (value path)
      (multiple-value-bind (ok tag condition) (read-union-tag value designator)
        (if (not ok)
            (list (error-datum :reader-errored path value :expected expected
                               :condition-type (type-of condition)
                               :condition-report (princ-to-string condition)))
            (let ((index (position tag tags :test #'eql)))
              (if index
                  (branch-errors (funcall (nth index compiled) value path) (nth index tags))
                  (list (error-datum :no-branch path value :expected expected
                                     :observed-tag tag :known-tags tags)))))))))

(defun compile-explainer (spec &key context)
  "Compile SPEC into a function of (VALUE PATH) returning structured errors.

CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The returned function returns an empty list exactly when VALUE satisfies SPEC,
which is what makes VALIDP and EXPLAIN-DATA incapable of disagreeing."
  (compile-node spec context))

(defun explain-data (spec-designator value &key (registry *registry*))
  "Return a plist describing whether VALUE satisfies SPEC-DESIGNATOR and why not.

  (:valid <boolean> :spec <symbol> :value <value> :path () :errors (<plist> ...))

This is the primary representation; EXPLAIN, condition reports and any JSON or
MCP projection are derived from it."
  (let* ((spec (resolve-spec spec-designator registry))
         (errors (funcall (compile-explainer spec :context (list :registry registry))
                          value nil)))
    (list :valid (null errors)
          :spec (spec-display-name spec-designator spec)
          :value value
          :path nil
          :errors errors)))

(defun format-expected (descriptor)
  "Return the compact rendering of DESCRIPTOR that EXPLAIN prints.

A type, a predicate or a spec name reads better bare than wrapped in its
descriptor, which is why the common cases are unwrapped here."
  (case (first descriptor)
    ((:type :satisfies :spec :instance-of) (format nil "~S" (second descriptor)))
    (t (format nil "~S" descriptor))))

(defun conjunct-mark (status)
  "Return the character EXPLAIN prints for a conjunct STATUS."
  (ecase status
    (:satisfied "✓")
    (:failed "✗")
    (:unchecked "·")))

(defun print-explain-error (datum stream indent)
  "Print one structured error DATUM to STREAM, indented to column INDENT."
  (case (getf datum :kind)
    ((:not-a-plist :not-an-alist :not-a-hash-table :bad-association
      :duplicate-key :missing-key :unknown-key :wrong-key-test :unbound-slot)
     (format stream "~vT✗ ~A~@[ at ~S~]; expected ~A~%"
             indent
             (case (getf datum :kind)
               (:not-a-plist "not a plist")
               (:not-an-alist "not an alist")
               (:not-a-hash-table "not a hash table")
               (:bad-association "malformed association")
               (:duplicate-key "duplicate key")
               (:missing-key "missing key")
               (:unknown-key "unknown key")
               (:wrong-key-test "wrong key test")
               (:unbound-slot "unbound field"))
             (getf datum :path)
             (format-expected (getf datum :expected))))
    (:no-branch
     (format stream "~vT✗ no branch for tag ~S; known tags ~S~%"
             indent (getf datum :observed-tag) (getf datum :known-tags)))
    (:conjunct-failed
     (dolist (conjunct (getf datum :conjuncts))
       (format stream "~vT~A ~A~%"
               indent
               (conjunct-mark (getf conjunct :status))
               (format-expected (getf conjunct :expected))))
     ;; The checklist line above already rendered the failing conjunct's own
     ;; descriptor, so recursing into an :ERRORS entry with that same
     ;; :EXPECTED would print it again -- exactly the case when the failing
     ;; conjunct is a leaf.  A conjunct that is itself a collection or
     ;; disjunction reports errors under a different :EXPECTED (an element's,
     ;; or none at all for a nested :CONJUNCT-FAILED/​:NO-BRANCH-MATCHED), so
     ;; those still carry real structure and are still printed.
     (let* ((failed-conjunct (find :failed (getf datum :conjuncts)
                                   :key (lambda (c) (getf c :status))))
            (failed-expected (getf failed-conjunct :expected)))
       (dolist (child (getf datum :errors))
         (unless (and (equal (getf child :expected) failed-expected)
                       (not (member (getf child :kind) +field-structure-error-kinds+)))
           (print-explain-error child stream (+ indent 2))))))
    (:no-branch-matched
     (format stream "~vTno branch matched~%" indent)
     (dolist (branch (getf datum :branches))
       (format stream "~vT✗ ~A~%" (+ indent 2) (format-expected (getf branch :expected)))))
    (t
     (format stream "~vT✗ ~A~@[ at ~S~]~%"
             indent
             (format-expected (getf datum :expected))
             (getf datum :path)))))

(defun explain (spec-designator value &key (stream *standard-output*) (registry *registry*))
  "Print a human readable rendering of (EXPLAIN-DATA SPEC-DESIGNATOR VALUE).

Writes to STREAM and returns NIL.  This is a projection of EXPLAIN-DATA and
must not compute anything EXPLAIN-DATA does not already report."
  (let ((data (explain-data spec-designator value :registry registry)))
    (if (getf data :valid)
        (format stream "~&~S satisfies ~S~%" value (getf data :spec))
        (progn
          (format stream "~&~S does not satisfy ~S~%" value (getf data :spec))
          (dolist (datum (getf data :errors))
            (print-explain-error datum stream 2)))))
  nil)
