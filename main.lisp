;;;; main.lisp
;;;;
;;;; Public API of cl-spec.  This file only re-exports; it contains no logic.

(defpackage #:cl-spec/main
  (:nicknames #:cl-spec)
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:not-implemented
                #:not-implemented-operator
                #:spec-violation
                #:spec-violation-spec
                #:spec-violation-value
                #:spec-violation-path
                #:spec-violation-errors
                #:unknown-spec
                #:unknown-spec-name
                #:unknown-property
                #:unknown-property-name
                #:no-generator-backend)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-description
                #:spec-source-form
                #:spec-source-location
                #:spec-metadata
                #:spec-kind
                #:spec-children)
  (:export ;; Conditions
           #:cl-spec-error
           #:not-implemented
           #:not-implemented-operator
           #:spec-violation
           #:spec-violation-spec
           #:spec-violation-value
           #:spec-violation-path
           #:spec-violation-errors
           #:unknown-spec
           #:unknown-spec-name
           #:unknown-property
           #:unknown-property-name
           #:no-generator-backend
           ;; Semantic IR
           #:spec
           #:spec-name
           #:spec-description
           #:spec-source-form
           #:spec-source-location
           #:spec-metadata
           #:spec-kind
           #:spec-children))

(in-package #:cl-spec/main)
