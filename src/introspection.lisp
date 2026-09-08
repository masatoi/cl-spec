;;;; src/introspection.lisp
;;;;
;;;; Introspection API (specification §38).  Structured data is the primary
;;;; representation and the DESCRIBE-* functions are projections of it, because
;;;; the intended first-class consumer is a coding agent rather than a human
;;;; reading a REPL transcript.

(defpackage #:cl-spec/src/introspection
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-kind
                #:spec-source-form
                #:spec-source-location
                #:spec-children
                #:type-spec
                #:type-spec-type-specifier
                #:reference-spec
                #:reference-spec-target
                #:predicate-spec
                #:predicate-spec-predicate
                #:member-spec
                #:member-spec-values
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:instance-of-spec
                #:instance-of-spec-class-name)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec)
  (:import-from #:cl-spec/src/utils/source-location
                #:source-location-file
                #:source-location-package)
  (:export #:describe-spec
           #:describe-property
           #:spec-data
           #:property-data))

(in-package #:cl-spec/src/introspection)

(defun source-location->data (location)
  "Return LOCATION as a plain plist, or NIL when there is no location.

Expanding it here is what keeps the opaque location object out of the public
introspection API."
  (when location
    (list :file (source-location-file location)
          :package (source-location-package location))))

(defgeneric node-attributes (spec)
  (:documentation "Return the SPEC-DATA keys specific to SPEC's node type."))

(defmethod node-attributes ((spec spec))
  nil)

(defmethod node-attributes ((spec type-spec))
  (list :type (type-spec-type-specifier spec)))

(defmethod node-attributes ((spec reference-spec))
  (list :target (reference-spec-target spec)))

(defmethod node-attributes ((spec predicate-spec))
  (list :predicate (predicate-spec-predicate spec)))

(defmethod node-attributes ((spec member-spec))
  (list :values (member-spec-values spec)))

(defmethod node-attributes ((spec range-spec))
  (list :base-type (range-spec-base-type spec)
        :min (range-spec-minimum spec)
        :max (range-spec-maximum spec)))

(defmethod node-attributes ((spec instance-of-spec))
  (list :class-name (instance-of-spec-class-name spec)))

(defun spec->data (spec)
  "Return the SPEC-DATA plist for one IR node, recursing into its children.

Every node carries the same keys whether or not they have a value, so that a
consumer never has to distinguish an absent key from a NIL one."
  (append (list :name (spec-name spec)
                :kind (spec-kind spec))
          (node-attributes spec)
          (list :source-form (spec-source-form spec)
                :source-location (source-location->data (spec-source-location spec)))
          (let ((children (spec-children spec)))
            (when children
              (list :children (mapcar #'spec->data children))))))

(defun spec-data (spec-designator &key (registry *registry*))
  "Return a plist describing the registered spec named by SPEC-DESIGNATOR.

  (:name <symbol> :kind <keyword> <node specific keys>
   :source-form <form> :source-location (:file <string> :package <string>)
   :children (<nested plist> ...))

:CHILDREN is present only on nodes that have children.  This is what the JSON
and MCP projections are built from."
  (spec->data (resolve-spec spec-designator registry)))

(defun property-data (property-designator &optional (registry *registry*))
  "Return a plist describing the registered property named by
PROPERTY-DESIGNATOR: its name, targets, kind, argument specs, tags,
documentation, source form, source location and trial configuration.

Not implemented yet."
  (declare (ignore property-designator registry))
  (error 'not-implemented :operator 'property-data))

(defun describe-spec (spec-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (SPEC-DATA SPEC-DESIGNATOR) to STREAM.

Returns NIL.  This is a projection of SPEC-DATA and must not report anything
SPEC-DATA does not already carry.

Not implemented yet."
  (declare (ignore spec-designator stream))
  (error 'not-implemented :operator 'describe-spec))

(defun describe-property (property-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (PROPERTY-DATA PROPERTY-DESIGNATOR) to
STREAM.  Returns NIL.

Not implemented yet."
  (declare (ignore property-designator stream))
  (error 'not-implemented :operator 'describe-property))
