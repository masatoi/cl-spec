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
                #:*registry*
                #:find-spec
                #:find-function-spec
                #:find-property
                #:properties-for)
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
                #:resolve-spec
                #:resolve-property)
  (:import-from #:cl-spec/src/property
                #:property-name
                #:property-arguments
                #:property-targets
                #:property-kind
                #:property-tags
                #:property-documentation
                #:property-body
                #:property-source-form
                #:property-source-location
                #:property-trials
                #:property-metadata)
  (:import-from #:cl-spec/src/utils/source-location
                #:source-location-file
                #:source-location-package)
  (:export #:describe-spec
           #:describe-property
           #:spec-data
           #:property-data
           #:semantic-data))

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

(defun property-data (property-designator &key (registry *registry*))
  "Return a plist describing the registered property named by PROPERTY-DESIGNATOR.

  (:name <symbol> :kind <keyword> :targets (<symbol> ...) :tags (<tag> ...)
   :documentation <string> :trials <plist>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :body (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>)

The body is the author's source rather than the compiled function, because a
compiled function cannot be read (specification §39)."
  (let ((property (resolve-property property-designator registry)))
    (list :name (property-name property)
          :kind (property-kind property)
          :targets (property-targets property)
          :tags (property-tags property)
          :documentation (property-documentation property)
          :trials (property-trials property)
          :arguments (loop for (variable spec) in (property-arguments property)
                           collect (list :variable variable :spec (spec->data spec)))
          :body (property-body property)
          :source-form (property-source-form property)
          :source-location (source-location->data (property-source-location property))
          :metadata (property-metadata property))))

(defun semantic-data (symbol &key (registry *registry*))
  "Return a routing table of what REGISTRY knows about SYMBOL.

  (:symbol <symbol> :package <string-or-nil>
   :spec <symbol-or-nil> :function-spec <symbol-or-nil>
   :property <symbol-or-nil> :properties-about (<symbol> ...))

Every value is a name, or a list of names, never expanded content: pass
:SPEC to SPEC-DATA, and each of :PROPERTIES-ABOUT to PROPERTY-DATA, to fetch
the content itself. cl-mcp runs in the same Lisp image as cl-spec, so a
follow-up lookup is a function call rather than a round trip -- there is no
argument for inlining here that a round trip would otherwise supply. And
PROPERTY-DATA carries a property's body and source form while SPEC-DATA is
small, so inlining either here would make this response's size vary by an
order of magnitude depending on which symbol was asked about.

:SPEC and :FUNCTION-SPEC hold SYMBOL itself when something is registered under
it, NIL otherwise. This is redundant today, since lookup is by identity, but
it keeps the shape stable if lookup ever stops being identity, and lets the
caller pass the value straight into a follow-up call. :PROPERTY holds SYMBOL
when SYMBOL is itself the name of a registered property, which is a different
relationship from :PROPERTIES-ABOUT: the sorted names of properties registered
*about* SYMBOL (see PROPERTIES-FOR). A symbol can be both at once.

:PACKAGE is the name of SYMBOL's home package, or NIL when SYMBOL is
uninterned (specification §8).

SEMANTIC-DATA never signals for an unknown symbol: it returns the full shape
with every value NIL or empty. This is a deliberate asymmetry with SPEC-DATA,
which signals UNKNOWN-SPEC for an unregistered name. Callers such as cl-mcp's
describe_symbol call this on arbitrary symbols, most of which have nothing
registered, so signalling would force every caller to handle a condition for
what is the common case.

That guarantee covers an unknown symbol, not an unknown value: SYMBOL must be
a symbol, and passing anything else signals a TYPE-ERROR from SYMBOL-PACKAGE
before any lookup runs. A caller that takes a name from outside the image --
from JSON, say -- resolves it to a symbol first. Every key listed above is
always present, whatever its value: a key that appears and disappears with its
value would break JSON consumers, matching the rule SPEC-DATA already
follows."
  (list :symbol symbol
        :package (let ((package (symbol-package symbol)))
                   (when package (package-name package)))
        :spec (when (nth-value 1 (find-spec symbol registry)) symbol)
        :function-spec (when (nth-value 1 (find-function-spec symbol registry)) symbol)
        :property (when (nth-value 1 (find-property symbol registry)) symbol)
        :properties-about (properties-for symbol registry)))

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
