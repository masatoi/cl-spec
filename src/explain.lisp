;;;; src/explain.lisp
;;;;
;;;; Structured explanation (specification §22).  The structured plist is the
;;;; primary representation; the human readable rendering, the condition report
;;;; and any JSON/MCP projection are all derived from it.

(defpackage #:cl-spec/src/explain
  (:use #:cl)
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

(defgeneric expected-descriptor (spec)
  (:documentation "Return a small plist saying what SPEC admits.

This is the shape EXPLAIN renders as a checklist line and the shape an agent
reads to learn what a value should have been."))

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
  (list :list-of (expected-descriptor (collection-spec-element-spec spec))))

(defmethod expected-descriptor ((spec vector-of-spec))
  (list :vector-of (expected-descriptor (collection-spec-element-spec spec))))

(defmethod expected-descriptor ((spec tuple-spec))
  (list* :tuple (mapcar #'expected-descriptor (tuple-spec-element-specs spec))))

(defmethod expected-descriptor ((spec not-spec))
  (list :not (expected-descriptor (not-spec-inner-spec spec))))

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

(defun proper-list-p (object)
  "Recognize a finite proper list before collection explainers iterate it.
Two cursors detect cycles using constant auxiliary space."
  (let ((slow object)
        (fast object))
    (loop
      (when (null fast) (return t))
      (unless (consp fast) (return nil))
      (setf fast (cdr fast))
      (when (null fast) (return t))
      (unless (consp fast) (return nil))
      (setf fast (cdr fast)
            slow (cdr slow))
      (when (eq slow fast) (return nil)))))

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

(defmethod compile-node ((spec list-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (proper-list-p value))
          (list (error-datum :not-a-list path value :expected expected))
          (loop for item in value
                for index from 0
                append (funcall element item (cons index path)))))))

(defmethod compile-node ((spec vector-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (vectorp value))
          (list (error-datum :not-a-vector path value :expected expected))
          (loop for index from 0 below (length value)
                append (funcall element (aref value index) (cons index path)))))))

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
         (unless (equal (getf child :expected) failed-expected)
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
