;;;; src/schema.lisp

(defpackage #:cl-spec/src/schema
  (:use #:cl)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout #:call-layout-data)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:field-spec #:field-spec-closed-p #:field-descriptions)
  (:import-from #:cl-spec/src/registry #:*registry* #:find-spec #:find-property #:find-generator)
  (:import-from #:cl-spec/src/ir
                #:spec #:spec-name #:spec-description #:spec-kind #:spec-source-form #:spec-metadata
                #:spec-children #:spec-generator-name
                #:type-spec #:type-spec-type-specifier
                #:reference-spec #:reference-spec-target
                #:predicate-spec #:predicate-spec-predicate
                #:member-spec #:member-spec-values
                #:range-spec #:range-spec-base-type #:range-spec-minimum #:range-spec-maximum
                #:instance-of-spec #:instance-of-spec-class-name
                #:and-spec #:or-spec #:not-spec #:nullable-spec
                #:list-of-spec #:vector-of-spec #:tuple-spec)
  (:import-from #:cl-spec/src/property
                #:property #:property-name #:property-arguments #:property-source-form
                #:property-body #:property-documentation #:property-tags
                #:property-kind #:property-targets #:property-trials
                #:property-metadata #:property-argument-schema)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator #:custom-generator-name #:custom-generator-source-form
                #:custom-generator-documentation #:custom-generator-shrinker)
  (:import-from #:cl-spec/src/generator #:*generator-backend* #:backend-capabilities)
  (:export #:schema-info #:definition-digest #:definition-metadata #:definition-graph
           #:definition-description #:definition-entity-kind #:definition-generation-schema
           #:resolve-definition #:definition-shrink-enabled-p
           #:definition-instrumentation-capability))

(in-package #:cl-spec/src/schema)

(defun schema-info ()
  "Describe version 1 of the Lisp definition/result schema, independent of MCP JSON."
  (list :schema-version 1 :format :lisp-plist :unknown-keys :ignore
        :required-metadata
        '(:schema-version :record-kind :entity-kind :definition-digest
          :definition-digest-complete :definition-digest-covers :capabilities)
        :optional-metadata '(:digest-omissions :digest-exclusions)
        :digest-omission-kinds '(:unresolved-reference :opaque-definition :missing-source
                                 :opaque-value :uninterned-symbol :resource-limit)
        :entity-kinds '(:spec :property :function-spec)
        :record-kinds '(:definition :result)
        :digest-algorithm :fnv1a64-v1
        :digest-covers :declaration-and-registered-dependencies
        :digest-excludes '(:target-implementation :helper-implementations :captured-state
                           :external-state :source-location :backend)
        :capability-states '(:available :unavailable :unknown :none)))

(defgeneric resolve-definition (designator entity-kind registry)
  (:documentation "Resolve a named definition in its explicit entity namespace."))

(defmethod resolve-definition ((designator t) entity-kind registry)
  (declare (ignore entity-kind registry))
  designator)

(defmethod resolve-definition ((designator symbol) (entity-kind (eql :spec)) registry)
  (find-spec designator registry))

(defmethod resolve-definition ((designator symbol) (entity-kind (eql :property)) registry)
  (find-property designator registry))

(defgeneric definition-entity-kind (definition)
  (:documentation "Return the entity namespace for a definition object."))

(defmethod definition-entity-kind ((definition t))
  (declare (ignore definition))
  nil)

(defmethod definition-entity-kind ((definition spec)) :spec)

(defmethod definition-entity-kind ((definition property)) :property)

(defgeneric definition-description (definition)
  (:documentation "Return values: declaration data, ordered child definitions,
registry links as (KIND . NAME) pairs, and whether the stored description is complete.
Do not invoke user code. Source locations and capabilities are excluded."))

(defmethod definition-description ((definition t))
  (declare (ignore definition))
  (values nil nil nil nil))

(defmethod definition-description ((definition spec))
  (values
   (list :entity-kind :spec :name (spec-name definition) :kind (spec-kind definition)
         :description (spec-description definition)
         :source (spec-source-form definition) :metadata (spec-metadata definition)
         :generator (spec-generator-name definition)
         :fields
         (typecase definition
            (call-arguments-spec (call-layout-data (call-arguments-spec-layout definition)))
            (field-spec (list :closed (field-spec-closed-p definition)
                              :fields (field-descriptions definition)))
           (type-spec (list :type (type-spec-type-specifier definition)))
           (reference-spec (list :target (reference-spec-target definition)))
           (predicate-spec (list :predicate (predicate-spec-predicate definition)))
           (member-spec (list :values (member-spec-values definition)))
           (range-spec (list :base (range-spec-base-type definition)
                             :minimum (range-spec-minimum definition)
                             :maximum (range-spec-maximum definition)))
           (instance-of-spec (list :class (instance-of-spec-class-name definition)))))
   (spec-children definition)
   (append (when (typep definition 'reference-spec)
             (list (cons :spec (reference-spec-target definition))))
           (when (spec-generator-name definition)
             (list (cons :generator (spec-generator-name definition)))))
   (not (null (member (class-name (class-of definition))
                       '(type-spec reference-spec predicate-spec member-spec range-spec
                         instance-of-spec and-spec or-spec not-spec nullable-spec
                         list-of-spec vector-of-spec tuple-spec plist-spec call-arguments-spec))))))

(defmethod definition-description ((definition property))
  (values
   (list :entity-kind :property :name (property-name definition)
         :variables (mapcar #'first (property-arguments definition))
         :documentation (property-documentation definition) :tags (property-tags definition)
         :source (property-source-form definition) :body (property-body definition)
         :kind (property-kind definition) :targets (property-targets definition)
         :trials (property-trials definition) :metadata (property-metadata definition))
   (list (property-argument-schema definition)) nil
   (and (eq (class-name (class-of definition)) 'property)
         (not (null (property-source-form definition))))))

(defmethod definition-description ((definition custom-generator))
  (values (append (list :entity-kind :generator :name (custom-generator-name definition)
                        :documentation (custom-generator-documentation definition)
                        :source (custom-generator-source-form definition))
                  (when (custom-generator-shrinker definition) (list :shrinker t)))
          nil nil (and (eq (class-name (class-of definition)) 'custom-generator)
                        (not (null (custom-generator-source-form definition))))))

(defgeneric definition-generation-schema (definition)
  (:documentation "Return the schema used to generate this definition's inputs or values."))

(defmethod definition-generation-schema ((definition spec)) definition)

(defmethod definition-generation-schema ((definition property))
  (property-argument-schema definition))

(defgeneric definition-shrink-enabled-p (definition)
  (:documentation "Return whether the declaration enables automatic shrinking."))

(defmethod definition-shrink-enabled-p ((definition t)) t)

(defmethod definition-shrink-enabled-p ((definition property))
  (getf (property-metadata definition) :shrink t))

(defun canonical-digest (value)
  "Hash a tagged graph without Lisp printer settings or unreadable object addresses.
At most 100000 nodes, 1000000 characters and 128 nested CAR/array levels are walked.
Return NIL rather than a fingerprint of a truncated or opaque representation."
  (block hashing
    (let ((*print-pretty* nil)
          (hash 14695981039346656037)
          (characters 0) (nodes 0)
          (seen (make-hash-table :test #'eq))
          (pending (list (cons value 0))))
      (labels ((emit (text)
                 (incf characters (length text))
                 (when (> characters 1000000) (return-from hashing nil))
                 ;; Four little-endian octets per character code define v1's encoding.
                 (loop for char across text
                       for code = (char-code char)
                       do (dotimes (i 4)
                            (setf hash (ldb (byte 64 0)
                                            (* 1099511628211
                                               (logxor hash (ldb (byte 8 (* i 8)) code))))))))
               (number-text (integer)
                 (when (> (integer-length integer) 65536) (return-from hashing nil))
                 (write-to-string integer :base 10 :radix nil :pretty nil))
               (token (tag text)
                 (emit tag) (emit (number-text (length text))) (emit ":") (emit text)))
        (loop while pending
              for entry = (pop pending)
              for item = (car entry)
              for depth = (cdr entry)
              do (when (or (> (incf nodes) 100000) (> depth 128))
                   (return-from hashing nil))
                 (cond
                   ((null item) (emit "N;"))
                   ((symbolp item)
                    (unless (symbol-package item) (return-from hashing nil))
                    (token "P" (package-name (symbol-package item)))
                    (token "S" (symbol-name item)))
                   ((integerp item) (token "I" (number-text item)))
                   ((rationalp item)
                    (token "R" (number-text (numerator item)))
                    (token "/" (number-text (denominator item))))
                   ((floatp item)
                    (destructuring-bind (significand exponent sign)
                         (handler-case (multiple-value-list (integer-decode-float item))
                           ;; Non-finite floats have no portable INTEGER-DECODE-FLOAT encoding.
                           ;; Keep this handler on the primitive, not on extension methods.
                           (error () (return-from hashing nil)))
                      (emit "F")
                      (push (cons (list (type-of item) significand exponent sign
                                        (float-radix item) (float-digits item))
                                  (1+ depth))
                            pending)))
                   ((characterp item) (token "C" (number-text (char-code item))))
                   ((stringp item) (token "T" item))
                   ((or (consp item) (arrayp item))
                    (multiple-value-bind (id found) (gethash item seen)
                      (if found
                          (token "@" (number-text id))
                          (progn
                            (setf (gethash item seen) (hash-table-count seen))
                            (if (consp item)
                                (progn
                                  (emit "(")
                                  (push (cons (cdr item) depth) pending)
                                  (push (cons (car item) (1+ depth)) pending))
                                (progn
                                  (emit "A")
                                  (when (> (array-total-size item) 100000)
                                    (return-from hashing nil))
                                  (loop for i downfrom (1- (array-total-size item)) to 0
                                        do (push (cons (row-major-aref item i) (1+ depth)) pending))
                                  (push (cons (list (array-dimensions item)
                                                    (array-element-type item)
                                                    (when (array-has-fill-pointer-p item)
                                                      (fill-pointer item)))
                                              (1+ depth))
                                        pending)))))))
                   (t (return-from hashing nil))))
        (format nil "fnv1a64-v1:~(~16,'0X~)" hash)))))

(defun digest-omission (kind path target reason)
  "Construct one stable explanation of declaration data absent from a digest."
  (list :kind kind :path path :target (when (symbolp target) target) :reason reason))

(defun canonical-value-omissions (value)
  "Locate unsupported canonical values using a bounded, cycle-safe traversal.
Paths are positional indexes below :DECLARATIONS. List spines use element indexes.
Array cursors schedule one child at a time, keeping pending work bounded by depth."
  (let ((seen (make-hash-table :test #'eq))
        (reported (make-hash-table :test #'eq))
        (pending (list (list value 0 '(:declarations) 0)))
        (nodes 0) (characters 0) (omissions nil))
    (labels ((omit (object kind path reason)
               (unless (member (list kind reason) (gethash object reported) :test #'equal)
                 (push (list kind reason) (gethash object reported))
                 (push (digest-omission kind (reverse path) nil reason) omissions)))
             (limit (object path reason)
               (omit object :resource-limit path reason)
               (setf pending nil)))
      (loop while pending
            for task = (pop pending)
            do (destructuring-bind (item depth path index &optional array-cursor-p) task
                 (if array-cursor-p
                     (progn
                       (when (< (1+ index) (array-total-size item))
                         (incf (fourth task))
                         (push task pending))
                       (push (list (row-major-aref item index) (1+ depth)
                                   (cons index path) 0)
                             pending))
                     (progn
                       (cond
                         ((> (incf nodes) 100000) (limit item path :node-limit))
                         ((> depth 128) (omit item :resource-limit path :depth-limit))
                         ((null item))
                         ((symbolp item)
                          (if (symbol-package item)
                              (incf characters
                                    (+ (length (symbol-name item))
                                       (length (package-name (symbol-package item)))))
                              (omit item :uninterned-symbol path :no-home-package)))
                         ((rationalp item)
                          (when (or (> (integer-length (numerator item)) 65536)
                                    (> (integer-length (denominator item)) 65536))
                            (omit item :resource-limit path :integer-limit)))
                         ((floatp item)
                          (handler-case (integer-decode-float item)
                            (error () (omit item :opaque-value path :nonfinite-float))))
                         ((characterp item))
                         ((stringp item) (incf characters (length item)))
                         ((or (consp item) (arrayp item))
                          (unless (gethash item seen)
                            (setf (gethash item seen) t)
                            (if (consp item)
                                (progn
                                  (push (list (cdr item) depth path (1+ index)) pending)
                                  (push (list (car item) (1+ depth) (cons index path) 0) pending))
                                (cond
                                  ((> (array-total-size item) 100000)
                                   (omit item :resource-limit path :array-limit))
                                  ((plusp (array-total-size item))
                                   (push (list item depth path 0 t) pending))))))
                         (t (omit item :opaque-value path
                                  (if (functionp item) :function-object :unsupported-object))))
                       (when (> characters 1000000) (limit item path :character-limit))))))
      (nreverse omissions))))

(defun collect-definition-graph (root registry resolve-links-p)
  "Collect ordered records and independent omission reasons without changing digest ordering."
  (let ((seen (make-hash-table :test #'eq)) (reported (make-hash-table :test #'eq))
        (paths (make-hash-table :test #'eq))
        (pending nil) (records nil) (omissions nil) (count 0) (edges 0))
    (labels ((omit (object kind path target reason)
               (unless (member (list kind reason) (gethash object reported) :test #'equal)
                 (push (list kind reason) (gethash object reported))
                 (push (digest-omission kind path target reason) omissions)))
             (reference (object path)
               (multiple-value-bind (id found) (gethash object seen)
                 (if found id
                     (if (> (incf count) 10000)
                         (progn (omit root :resource-limit path nil :definition-limit) nil)
                         (progn
                           (setf (gethash object seen) count (gethash object paths) path)
                           (push object pending)
                           count)))))
             (bounded-list (items path)
               (let ((tails (make-hash-table :test #'eq)))
                 (loop for tail = items then (cdr tail)
                       while tail
                       do (unless (and (consp tail) (not (gethash tail tails))
                                       (<= (incf edges) 100000))
                            (omit root :resource-limit path nil :description-list-limit)
                            (return-from bounded-list nil))
                          (setf (gethash tail tails) t)
                       finally (return t)))))
      (unless root
        (return-from collect-definition-graph
          (values nil nil (list (digest-omission :unresolved-reference nil nil
                                                 :definition-missing)))))
      (reference root nil)
      (loop while pending
            for object = (pop pending)
            for path = (gethash object paths)
            do (multiple-value-bind (data children links complete) (definition-description object)
                 (unless complete
                   (let ((source-missing
                           (or (and (eq (class-name (class-of object)) 'property)
                                    (null (property-source-form object)))
                               (and (eq (class-name (class-of object)) 'custom-generator)
                                    (null (custom-generator-source-form object))))))
                     (omit object (if source-missing :missing-source :opaque-definition)
                           path nil
                           (if source-missing :source-unavailable :incomplete-description))))
                 (when (and (bounded-list children path) (bounded-list links path))
                   (let ((child-ids
                           (loop for child in children for index from 0
                                 collect (reference child
                                                    (list :definitions (gethash object seen)
                                                          :children index)))))
                     (push
                      (if resolve-links-p
                          (list (gethash object seen) data child-ids
                                (loop for (kind . name) in links
                                      for target = (ecase kind
                                                     (:spec (find-spec name registry))
                                                     (:generator (find-generator name registry)))
                                      for link-path = (list :definitions (gethash object seen)
                                                            :links kind name)
                                      do (unless target
                                           (omit name :unresolved-reference link-path name
                                                 :definition-missing))
                                      collect (list kind name
                                                    (when target (reference target link-path)))))
                          (list (gethash object seen) (class-name (class-of object))
                                data child-ids links complete))
                      records)))))
      (values (nreverse records) (null omissions) (nreverse omissions)))))

(defun definition-graph (root &key (registry *registry*) (resolve-links-p t))
  "Collect complete ordered declarations, returning records, completeness and omissions.
With RESOLVE-LINKS-P false, retain link names and local classes without traversing
registry dependencies. Opaque scalar values remain available for local comparison."
  (multiple-value-bind (records complete omissions)
      (collect-definition-graph root registry resolve-links-p)
    (values (when complete records) complete omissions)))

(defun definition-digest (designator &key entity-kind (registry *registry*))
  "Return DIGEST, COMPLETE-P and a stable list of digest omission records.
The first two values retain their version-one meaning and complete digest bytes.
Missing or opaque declarations return NIL/NIL with explanatory omissions.
Extension programming errors propagate rather than becoming incompleteness."
  (when (symbolp designator)
    (check-type entity-kind (member :spec :property :function-spec)))
  (let ((root (resolve-definition designator entity-kind registry)))
    (unless root
      (return-from definition-digest
        (values nil nil (list (digest-omission :unresolved-reference nil designator
                                              :definition-missing)))))
    (multiple-value-bind (records complete omissions)
        (collect-definition-graph root registry t)
      (let* ((digest (canonical-digest records))
             (value-omissions
               (unless digest
                 (or (canonical-value-omissions records)
                     (list (digest-omission :resource-limit '(:declarations) nil
                                           :canonical-encoding-limit))))))
        (values (when complete digest) (and complete (not (null digest)))
                (append omissions value-omissions))))))

(defgeneric definition-instrumentation-capability (definition)
  (:documentation "Return :AVAILABLE or :UNAVAILABLE for runtime instrumentation support.
The core default is :UNAVAILABLE; only the optional instrumentation module enables it.
This reports support, not whether the target is currently instrumented.")
  (:method ((definition t))
    (declare (ignore definition))
    :unavailable))

(defun metadata-definition-p (definition)
  "Return true for an entity supported by the public metadata envelope."
  (not (null (member (definition-entity-kind definition) '(:spec :property :function-spec)))))

(defun definition-metadata (definition &key (registry *registry*)
                                          (capabilities nil capabilities-p))
  "Return v1 metadata for a spec, property or function-spec definition.
Other objects, including custom-generator dependencies, signal TYPE-ERROR.
CAPABILITIES, when supplied, replaces the backend probe; execution uses this
to avoid compiling a disposable generator before constructing the actual one."
  (check-type definition (satisfies metadata-definition-p))
  (multiple-value-bind (digest complete omissions) (definition-digest definition :registry registry)
    (let ((capabilities
            (copy-list (if capabilities-p capabilities
                           (backend-capabilities *generator-backend*
                                                 (definition-generation-schema definition)
                                                 :registry registry)))))
      (unless (definition-shrink-enabled-p definition)
        (setf (getf capabilities :shrinking) :none))
      ;; Instrumentation belongs to the separate core module, not the generator backend.
      (setf (getf capabilities :instrumentation)
            (definition-instrumentation-capability definition))
      (list :schema-version 1 :record-kind :definition
            :entity-kind (definition-entity-kind definition)
            :definition-digest digest :definition-digest-complete complete
            :definition-digest-covers :declaration-and-registered-dependencies
            :digest-omissions omissions
            :digest-exclusions (list :target-implementation :helper-implementations :captured-state
                                     :external-state :source-location :backend)
            :capabilities capabilities))))
