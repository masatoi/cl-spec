;;;; src/introspection.lisp
;;;;
;;;; Introspection API (specification §38).  Structured data is the primary
;;;; representation and the DESCRIBE-* functions are projections of it, because
;;;; the intended first-class consumer is a coding agent rather than a human
;;;; reading a REPL transcript.

(defpackage #:cl-spec/src/introspection
  (:use #:cl)
  (:import-from #:cl-spec/src/call-schema
                #:call-arguments-spec #:call-arguments-spec-layout #:call-layout-data
                #:call-layout-policy-data
                #:call-layout-bindings #:argument-binding-name #:argument-binding-spec
                #:argument-binding-kind #:argument-binding-supplied-name #:argument-binding-keyword)
  (:import-from #:cl-spec/src/field-spec
                #:field-spec #:field-spec-closed-p #:field-descriptions)
  (:import-from #:cl-spec/src/schema #:definition-metadata)
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
                #:spec-generator-name
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
  (:import-from #:cl-spec/src/function-spec
                #:resolve-function-spec
                #:function-spec-name
                #:function-spec-call-layout
                #:function-spec-argument-generator #:function-spec-argument-schema
                #:function-spec-return-spec #:function-spec-signal-spec
                #:function-spec-preconditions
                #:function-spec-postconditions #:function-spec-post-value-variables
                #:function-spec-documentation
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata)
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
           #:function-spec-data
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
  (:documentation "Return the SPEC-DATA keys specific to SPEC's node type.

Every per-node method combines with CALL-NEXT-METHOD rather than returning a fresh
list, so a key added to the base method reaches every node type.  A method that
replaces the base one drops it silently on the kinds that have a method of their
own -- which is how :GENERATOR went missing from six node kinds before it moved to
SPEC->DATA, where the definition-level attributes live (PR review)."))

(defmethod node-attributes ((spec call-arguments-spec))
  (let ((layout (call-arguments-spec-layout spec)))
    (append (list :bindings (call-layout-data layout))
            (call-layout-policy-data layout))))

(defmethod node-attributes ((spec spec))
  nil)

(defmethod node-attributes ((spec type-spec))
  (list* :type (type-spec-type-specifier spec) (call-next-method)))

(defmethod node-attributes ((spec reference-spec))
  (list* :target (reference-spec-target spec) (call-next-method)))

(defmethod node-attributes ((spec predicate-spec))
  (list* :predicate (predicate-spec-predicate spec) (call-next-method)))

(defmethod node-attributes ((spec member-spec))
  (list* :values (member-spec-values spec) (call-next-method)))

(defmethod node-attributes ((spec range-spec))
  (list* :base-type (range-spec-base-type spec)
         :min (range-spec-minimum spec)
         :max (range-spec-maximum spec)
         (call-next-method)))

(defmethod node-attributes ((spec instance-of-spec))
  (list* :class-name (instance-of-spec-class-name spec) (call-next-method)))

(defmethod node-attributes ((spec field-spec))
  (list* :closed (field-spec-closed-p spec) :fields (field-descriptions spec)
         (call-next-method)))

(defun spec->data (spec &optional (registry *registry*) envelope-p)
  "Return the SPEC-DATA plist for one IR node, recursing into its children.

ENVELOPE-P adds the seven schema metadata keys to this node only. Nested nodes
remain IR projections, so rendering them does not repeat digest or backend probes.

The generator is emitted here because it belongs to the definition rather than to
the node type, next to :NAME and :KIND.  It was in the base NODE-ATTRIBUTES method
first, where the per-node methods dropped it for every TYPE, RANGE, MEMBER,
PREDICATE, INSTANCE-OF and REFERENCE spec; those methods combine with
CALL-NEXT-METHOD now, but a definition-level key still belongs on this side."
  (append (if envelope-p (definition-metadata spec :registry registry)
              (list :entity-kind :spec))
          (list :name (spec-name spec)
                :kind (spec-kind spec)
                :generator (spec-generator-name spec))
          (node-attributes spec)
          (list :source-form (spec-source-form spec)
                :source-location (source-location->data (spec-source-location spec)))
          (let ((children (spec-children spec)))
            (when children
              (list :children (mapcar (lambda (child) (spec->data child registry)) children))))))

(defun spec-data (spec-designator &key (registry *registry*))
  "Return a plist describing the registered spec named by SPEC-DESIGNATOR.

  (:name <symbol> :entity-kind :spec :kind <keyword> :generator <symbol or NIL>
   <node specific keys> :source-form <form>
   :source-location (:file <string> :package <string>)
   :children (<nested plist> ...))

:CHILDREN is present only on nodes that have children. The root additionally has
:SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND, :DEFINITION-DIGEST,
:DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and :CAPABILITIES (see
SCHEMA-INFO, specification §38.1). Children are plain IR projections."
  (spec->data (resolve-spec spec-designator registry) registry t))

(defun property-data (property-designator &key (registry *registry*))
  "Return a plist describing the registered property named by PROPERTY-DESIGNATOR.

  (:name <symbol> :entity-kind :property :kind <author classification>
   :targets (<symbol> ...) :tags (<tag> ...)
   :documentation <string> :trials <plist>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :body (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>)

The root additionally carries the seven schema envelope keys described by
SCHEMA-INFO: :SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND, :DEFINITION-DIGEST,
:DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and :CAPABILITIES.
Nested specs are plain IR projections. :TRIALS is a profile table in this
definition record; result records carry executed counts under that key.
The body is the author's source rather than the compiled function (§39)."
  (let ((property (resolve-property property-designator registry)))
    (append (definition-metadata property :registry registry)
            (list :name (property-name property)
                  :kind (property-kind property)
                  :targets (property-targets property)
                  :tags (property-tags property)
                  :documentation (property-documentation property)
                  :trials (property-trials property)
                  :arguments
                  (loop for (variable spec) in (property-arguments property)
                        collect (list :variable variable :spec (spec->data spec registry)))
                  :body (property-body property)
                  :source-form (property-source-form property)
                  :source-location (source-location->data (property-source-location property))
                  :metadata (property-metadata property)))))

(defun function-spec-data (function-spec-designator &key (registry *registry*))
  "Return a plist describing the contract registered for FUNCTION-SPEC-DESIGNATOR.

  (:name <symbol> :entity-kind :function-spec :kind :function-spec
   :documentation <string-or-nil>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :argument-generator <symbol-or-nil> :argument-schema <tuple spec-data>
   :preconditions (<form> ...) :returns <spec-data plist or NIL>
   :signals <spec-data plist or NIL>
   :postconditions (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>)

This is the projection that answers the two questions a caller asks before
editing a function: which inputs it accepts, and which output it must return
(§28).  :ARGUMENTS, :RETURNS and :SIGNALS carry normalized IR rather than the designators
as written, so a consumer reads one shape whether the contract named a spec or
inlined it.

:PRE and :POST are the forms as written.  Their compiled counterparts are not
projected: a function cannot be read, and a caller who wants to know whether
they hold runs CHECK-FUNCTION rather than inspecting them.

The root additionally carries :SCHEMA-VERSION, :RECORD-KIND, :ENTITY-KIND,
:DEFINITION-DIGEST, :DEFINITION-DIGEST-COMPLETE, :DEFINITION-DIGEST-COVERS and
:CAPABILITIES (SCHEMA-INFO, §38.1). These envelope keys are always present.
Argument, return, signals and argument-schema nodes are plain IR projections.
Fixed return declarations use :KIND :VALUES with ordered children. Explicit
:POST-VALUES adds :POST-VALUE-VARIABLES; ordinary :POST omits that key."
  (let ((contract (resolve-function-spec function-spec-designator registry)))
    (append (definition-metadata contract :registry registry)
            (unless (eq :primary (function-spec-post-value-variables contract))
              (list :post-value-variables (function-spec-post-value-variables contract)))
            (list :name (function-spec-name contract)
                  ;; KIND is retained for compatibility; ENTITY-KIND routes records.
                  :kind :function-spec
                  :documentation (function-spec-documentation contract)
                  :arguments
                  (loop for binding in (call-layout-bindings (function-spec-call-layout contract))
                        collect
                        (append (list :variable (argument-binding-name binding)
                                      :spec (spec->data (argument-binding-spec binding) registry))
                                (unless (eq :required (argument-binding-kind binding))
                                  (list :kind (argument-binding-kind binding)
                                        :supplied-p (argument-binding-supplied-name binding)))
                               (when (eq :key (argument-binding-kind binding))
                                 (list :keyword (argument-binding-keyword binding)))))
                  :argument-generator (function-spec-argument-generator contract)
                  :argument-schema (spec->data (function-spec-argument-schema contract) registry)
                  :preconditions (function-spec-preconditions contract)
                  :returns (let ((spec (function-spec-return-spec contract)))
                             (when spec (spec->data spec registry)))
                  :signals (let ((spec (function-spec-signal-spec contract)))
                             (when spec (spec->data spec registry)))
                  :postconditions (function-spec-postconditions contract)
                  :source-form (function-spec-source-form contract)
                  :source-location (source-location->data (function-spec-source-location contract))
                  :metadata (function-spec-metadata contract)))))

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
