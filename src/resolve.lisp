;;;; src/resolve.lisp
;;;;
;;;; Designator resolution.  Validation, explanation, generation, property
;;;; execution and introspection all accept either a name or an object, and all
;;;; of them need the same "resolve or signal" behaviour.  It lives here rather
;;;; than in SRC/REGISTRY.LISP so that the registry keeps knowing nothing about
;;;; the object types stored in it.

(defpackage #:cl-spec/src/resolve
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec
                #:unknown-property
                #:invalid-spec-form
                #:invalid-property-form)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-source-form)
  (:import-from #:cl-spec/src/property
                #:property)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-find-spec
                #:registry-find-property)
  (:export #:resolve-spec
           #:resolve-property
           #:context-registry
           #:spec-display-name))

(in-package #:cl-spec/src/resolve)

(defun resolve-spec (designator registry)
  "Return the spec DESIGNATOR names, signalling UNKNOWN-SPEC when there is none.

DESIGNATOR is either a spec object, which is returned unchanged, or a symbol
looked up in REGISTRY.  The registry protocol stores whatever a writer hands it,
so an entry that is not a spec is refused with INVALID-SPEC-FORM rather than
failing later in whatever first touches it."
  (if (typep designator 'spec)
      designator
      (multiple-value-bind (entry found-p) (registry-find-spec registry designator)
        (cond ((not found-p) (error 'unknown-spec :name designator))
              ((typep entry 'spec) entry)
              (t (error 'invalid-spec-form
                        :form designator
                        :reason "the value registered under this name is not a spec"))))))

(defun resolve-property (designator registry)
  "Return the property DESIGNATOR names, signalling UNKNOWN-PROPERTY otherwise.

DESIGNATOR is either a property object, which is returned unchanged, or a
symbol looked up in REGISTRY.  An entry that is not a property is refused with
INVALID-PROPERTY-FORM, as RESOLVE-SPEC refuses a stored non-spec."
  (if (typep designator 'property)
      designator
      (multiple-value-bind (entry found-p) (registry-find-property registry designator)
        (cond ((not found-p) (error 'unknown-property :name designator))
              ((typep entry 'property) entry)
              (t (error 'invalid-property-form
                        :form designator
                        :reason "the value registered under this name is not a property"))))))

(defun context-registry (context)
  "Return the registry named by compilation CONTEXT, defaulting to *REGISTRY*.

CONTEXT is the plist passed as :CONTEXT to the COMPILE-* functions.  Keeping
the accessor here means the compilers do not agree on a plist layout by
accident."
  (or (getf context :registry) *registry*))

(defun spec-display-name (spec-designator resolved-spec)
  "Return what EXPLAIN-DATA and VALIDATE should report as RESOLVED-SPEC's name.

SPEC-DESIGNATOR is the caller's original argument, RESOLVED-SPEC what
RESOLVE-SPEC returned for it.  A registered name is reported first, whether it
came in as the designator itself or is read back off the resolved spec.  An
anonymous spec object handed straight in -- rather than a registered name --
has no NAME slot to fall back on; reporting NIL there prints literally as
\"does not satisfy NIL\", which is worse than useless, so its SOURCE-FORM is
reported instead, since that always identifies the spec precisely."
  (cond
    ((symbolp spec-designator) spec-designator)
    ((spec-name resolved-spec) (spec-name resolved-spec))
    (t (spec-source-form resolved-spec))))
