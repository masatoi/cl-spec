;;;; src/schema.lisp

(defpackage #:cl-spec/src/schema
  (:use #:cl)
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
                #:custom-generator-documentation)
  (:import-from #:cl-spec/src/generator #:*generator-backend* #:backend-capabilities)
  (:export #:schema-info #:definition-digest #:definition-metadata
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
                         list-of-spec vector-of-spec tuple-spec))))))

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
  (values (list :entity-kind :generator :name (custom-generator-name definition)
                :documentation (custom-generator-documentation definition)
                :source (custom-generator-source-form definition))
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

(defun definition-digest (designator &key entity-kind (registry *registry*))
  "Return (values DIGEST COMPLETE-P) for a declaration and registered dependencies.
A symbol requires an explicit :ENTITY-KIND. Missing or opaque definitions return
NIL/NIL. Extension programming errors propagate rather than becoming incompleteness."
  (when (symbolp designator)
    (check-type entity-kind (member :spec :property :function-spec)))
  (let ((root (resolve-definition designator entity-kind registry))
        (seen (make-hash-table :test #'eq))
        (pending nil) (records nil) (count 0))
    (unless root (return-from definition-digest (values nil nil)))
    (labels ((reference (object)
               (multiple-value-bind (id found) (gethash object seen)
                 (if found id
                     (let ((id (incf count)))
                       (when (> count 10000)
                         (return-from definition-digest (values nil nil)))
                       (setf (gethash object seen) id)
                       (push object pending)
                       id)))))
      (reference root)
      (loop while pending
            for object = (pop pending)
            do (multiple-value-bind (data children links complete)
                   (definition-description object)
                 (unless complete (return-from definition-digest (values nil nil)))
                 (let ((child-ids (mapcar #'reference children))
                       (link-ids
                         (loop for (kind . name) in links
                               for target = (ecase kind
                                              (:spec (find-spec name registry))
                                              (:generator (find-generator name registry)))
                               do (unless target
                                    (return-from definition-digest (values nil nil)))
                               collect (list kind name (reference target)))))
                   (push (list (gethash object seen) data child-ids link-ids) records))))
      (let ((digest (canonical-digest (nreverse records))))
        (values digest (not (null digest)))))))

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
  (multiple-value-bind (digest complete) (definition-digest definition :registry registry)
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
            :capabilities capabilities))))
