;;;; definitions.lisp
;;;;
;;;; Public declarations and registry operations for the definitions system.

(defpackage #:cl-spec/definitions
  (:use #:cl)
  (:import-from #:cl-spec/src/dsl
                #:defspec #:defspec-function #:defproperty #:defgenerator)
  (:import-from #:cl-spec/src/registry
                #:*registry* #:hash-table-registry #:make-hash-table-registry #:register-spec
                #:find-spec #:list-specs #:find-function-spec #:list-function-specs
                #:find-property #:list-properties #:find-generator #:list-generators
                #:properties-for #:properties-with-tag #:clear-registry)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:import-from #:cl-spec/src/property
                #:property #:register-property)
  (:import-from #:cl-spec/src/function-spec-definition
                #:function-spec #:function-case #:register-function-spec)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator #:register-generator)
  (:import-from #:cl-spec/src/state-frame-definition
                #:register-state-observer)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots)
  (:export
           #:defspec #:defspec-function #:defproperty #:defgenerator #:*registry*
           #:hash-table-registry #:make-hash-table-registry #:register-spec #:find-spec
           #:list-specs #:find-function-spec #:list-function-specs #:find-property
           #:list-properties #:find-generator #:list-generators #:properties-for
           #:properties-with-tag #:clear-registry #:spec #:property #:register-property
           #:function-spec #:function-case #:register-function-spec #:custom-generator
           #:register-generator #:register-state-observer #:validate-definition
           #:definition-validation-slots))

(in-package #:cl-spec/definitions)
