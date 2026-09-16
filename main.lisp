;;;; main.lisp
;;;;
;;;; Public API of cl-spec.  This file only re-exports; it contains no logic.

(defpackage #:cl-spec/main
  (:nicknames #:cl-spec)
  (:use #:cl)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots)
  (:export #:validate-definition #:definition-validation-slots)
  (:import-from #:cl-spec/src/counterexample
                #:counterexample-artifact #:make-counterexample-artifact
                #:counterexample-artifact-data #:serialize-counterexample-artifact
                #:deserialize-counterexample-artifact #:recheck-counterexample
                #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason)
  (:export #:counterexample-artifact #:make-counterexample-artifact
           #:counterexample-artifact-data #:serialize-counterexample-artifact
           #:deserialize-counterexample-artifact #:recheck-counterexample
           #:invalid-counterexample-artifact #:invalid-counterexample-artifact-reason)
  (:import-from #:cl-spec/src/property-runner
                #:property-result-options #:property-result-provenance)
  (:export #:property-result-options #:property-result-provenance)
  (:import-from #:cl-spec/src/conditions
                #:invalid-backend-result #:invalid-backend-result-reason
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
                #:unknown-function-spec
                #:unknown-function-spec-name
                #:unbound-target
                #:no-generator-backend
                #:invalid-spec-form
                #:invalid-spec-form-form
                #:invalid-spec-form-reason
                #:invalid-property-form
                #:invalid-property-form-form
                #:invalid-property-form-reason
                #:invalid-function-spec-form
                #:invalid-function-spec-form-form
                #:invalid-function-spec-form-reason
                #:invalid-generator-form
                #:invalid-generated-arguments #:invalid-generated-arguments-generator
                #:invalid-generated-arguments-value #:invalid-generated-arguments-reason
                #:invalid-generator-form-form
                #:invalid-generator-form-reason
                #:generator-unavailable
                #:generator-unavailable-spec
                #:generator-unavailable-reason
                #:generation-budget-exhausted
                #:generation-budget-exhausted-report
                #:generation-budget-exhausted-request
                #:generation-budget-exhausted-attempts
                #:generation-budget-exhausted-rejections
                #:generation-budget-exhausted-budget
                #:generation-budget-exhausted-phase
                #:generation-budget-exhausted-path
                #:case-selection-error
                #:case-selection-error-function
                #:case-selection-error-kind
                #:case-selection-error-cases
                #:case-selection-error-case
                #:case-selection-error-original-condition
                #:case-selection-error-data
                #:capture-error
                #:capture-error-function
                #:capture-error-binding
                #:capture-error-index
                #:capture-error-captured
                #:capture-error-original-condition
                #:capture-error-data
                #:state-post-error
                #:state-post-error-function
                #:state-post-error-case
                #:state-post-error-index
                #:state-post-error-form
                #:state-post-error-original-condition
                #:state-post-error-data
                #:unsupported-stateful-operation
                #:unsupported-stateful-operation-operation
                #:unsupported-stateful-operation-function
                #:unsupported-stateful-operation-reason
                #:unsupported-seed)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-description
                #:spec-source-form
                #:spec-source-location
                #:spec-metadata
                #:spec-generator-name
                #:spec-kind
                #:spec-children)
  (:import-from #:cl-spec/src/utils/source-location
                #:source-location-file
                #:source-location-package)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:hash-table-registry
                #:make-hash-table-registry
                #:registry-find-spec
                #:registry-register-spec
                #:registry-list-specs
                #:registry-find-function-spec
                #:registry-register-function-spec
                #:registry-list-function-specs
                #:registry-find-generator
                #:registry-register-generator
                #:registry-list-generators
                #:registry-find-property
                #:registry-register-property
                #:registry-list-properties
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-clear
                #:find-spec
                #:list-specs
                #:register-spec
                #:find-function-spec
                #:list-function-specs
                #:find-generator
                #:list-generators
                #:find-property
                #:list-properties
                #:properties-for
                #:properties-with-tag
                #:clear-registry)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form
                #:*spec-primitives*)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:generator-for
                #:sample
                #:backend-default-trials #:backend-capabilities)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
                #:property-argument-schema
                #:property-call-arguments-p #:property-named-arguments
                #:property-targets
                #:property-kind
                #:property-tags
                #:property-documentation
                #:property-body
                #:property-function
                #:property-source-form
                #:property-source-location
                #:property-trials
                #:property-metadata
                #:register-property)
  (:import-from #:cl-spec/src/execution
                #:trial-observation
                #:make-trial-observation
                #:trial-observation-arguments
                #:trial-observation-arguments-mutated-p
                #:trial-observation-status #:trial-observation-outcome
                #:trial-observation-reason
                #:trial-observation-signature
                #:trial-observation-explanation
                #:trial-observation-condition
                #:trial-observation-condition-report
                #:trial-observation-value
                #:trial-observation-case
                #:trial-observation-state
                #:evaluate-trial
                #:observe-trial
                #:observation-failure-p
                #:failure-identities-match-p)
  (:import-from #:cl-spec/src/schema
                #:schema-info #:definition-digest #:definition-metadata #:definition-description)
  (:import-from #:cl-spec/src/property-runner
                #:result-data #:property-result-schema-metadata #:property-result-budget
                #:property-result-entity-kind
                #:property-result-failure-evidence
                #:property-result-shrunk-evidence
                #:property-result-shrunk-outcome #:property-result-shrink-report
                #:property-result-generation-report #:property-result-failure-phase
                #:property-result-rejected
                #:property-result-failure-reason
                #:property-result-failure-signature
                #:property-result-explanation
                #:property-result
                #:property-result-status
                #:property-result-property
                #:property-result-trials
                #:property-result-seed
                #:property-result-profile
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:property-result-elapsed
                #:run-property
                #:run-properties
                #:replay-property)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name
                #:function-spec-argument-specs
                #:function-spec-argument-generator #:function-spec-argument-schema
                #:function-spec-return-spec
                #:function-spec-signal-spec
                #:function-spec-preconditions
                #:function-spec-postconditions #:function-spec-post-value-variables
                #:function-spec-precondition-function
                #:function-spec-postcondition-function
                #:function-spec-documentation
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata
                #:register-function-spec
                #:function-check-result
                #:function-check-result-function
                #:function-check-result-budget
                #:function-check-result-source-form
                #:function-check-result-rejected
                #:function-check-result-failure-reason
                #:function-check-result-explanation
                #:function-check-result-shrunk-outcome
                #:function-check-result-case-report
                #:check-function)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator
                #:custom-generator-name
                #:custom-generator-function #:custom-generator-shrinker
                #:custom-generator-documentation
                #:custom-generator-source-form
                #:custom-generator-source-location
                #:register-generator)
  (:import-from #:cl-spec/src/tagged-union
                #:tagged-union-branch)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data
                #:function-spec-data
                #:semantic-data)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator)
  (:export #:schema-info #:definition-digest #:definition-metadata #:definition-description
           #:result-data #:property-result-schema-metadata #:property-result-budget
           ;; Conditions
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
           #:unknown-function-spec
           #:unknown-function-spec-name
           #:unbound-target
           #:no-generator-backend
           #:invalid-spec-form
           #:invalid-spec-form-form
           #:invalid-spec-form-reason
           #:invalid-property-form
           #:invalid-property-form-form
           #:invalid-property-form-reason
           #:invalid-function-spec-form
           #:invalid-function-spec-form-form
           #:invalid-function-spec-form-reason
           #:invalid-generator-form
           #:invalid-generated-arguments #:invalid-generated-arguments-generator
           #:invalid-generated-arguments-value #:invalid-generated-arguments-reason
           #:invalid-generator-form-form
           #:invalid-generator-form-reason
           #:generator-unavailable
           #:generator-unavailable-spec
           #:generator-unavailable-reason
           #:generation-budget-exhausted
           #:generation-budget-exhausted-report
           #:generation-budget-exhausted-request
           #:generation-budget-exhausted-attempts
           #:generation-budget-exhausted-rejections
           #:generation-budget-exhausted-budget
           #:generation-budget-exhausted-phase
           #:generation-budget-exhausted-path
           #:case-selection-error
           #:case-selection-error-function
           #:case-selection-error-kind
           #:case-selection-error-cases
           #:case-selection-error-case
           #:case-selection-error-original-condition
           #:case-selection-error-data
           #:capture-error
           #:capture-error-function
           #:capture-error-binding
           #:capture-error-index
           #:capture-error-captured
           #:capture-error-original-condition
           #:capture-error-data
           #:state-post-error
           #:state-post-error-function
           #:state-post-error-case
           #:state-post-error-index
           #:state-post-error-form
           #:state-post-error-original-condition
           #:state-post-error-data
           #:unsupported-stateful-operation
           #:unsupported-stateful-operation-operation
           #:unsupported-stateful-operation-function
           #:unsupported-stateful-operation-reason
           #:unsupported-seed
           #:invalid-backend-result #:invalid-backend-result-reason
           ;; Semantic IR
           #:spec
           #:spec-name
           #:spec-description
           #:spec-source-form
           #:spec-source-location
           #:spec-metadata
           #:spec-generator-name
           #:spec-kind
           #:spec-children
           #:source-location-file
           #:source-location-package
           ;; Registry
           #:*registry*
           #:hash-table-registry
           #:make-hash-table-registry
           #:registry-find-spec
           #:registry-register-spec
           #:registry-list-specs
           #:registry-find-function-spec
           #:registry-register-function-spec
           #:registry-list-function-specs
           #:registry-find-generator
           #:registry-register-generator
           #:registry-list-generators
           #:registry-find-property
           #:registry-register-property
           #:registry-list-properties
           #:registry-properties-for
           #:registry-properties-with-tag
           #:registry-clear
           #:find-spec
           #:list-specs
           #:register-spec
           #:find-function-spec
           #:list-function-specs
           #:find-generator
           #:list-generators
           #:find-property
           #:list-properties
           #:properties-for
           #:properties-with-tag
           #:clear-registry
           ;; Normalization
           #:normalize-spec-form
           #:*spec-primitives*
           ;; Validation
           #:compile-validator
           #:validp
           #:validate
           ;; Structured explain
           #:compile-explainer
           #:explain-data
           #:explain
           ;; Generators
           #:*generator-backend*
           #:current-generator-backend
           #:compile-generator
           #:generate-value
           #:run-generated-test
           #:generator-for
           #:sample
           #:backend-default-trials #:backend-capabilities
           ;; Properties
           #:property
           #:property-name
           #:property-arguments
           #:property-argument-schema
           #:property-call-arguments-p #:property-named-arguments
           #:property-targets
           #:property-kind
           #:property-tags
           #:property-documentation
           #:property-body
           #:property-function
           #:property-source-form
           #:property-source-location
           #:property-trials
           #:property-metadata
           #:register-property
           ;; Observed execution evidence
           #:trial-observation
           #:make-trial-observation
           #:trial-observation-arguments-mutated-p
           #:trial-observation-arguments
           #:trial-observation-status #:trial-observation-outcome
           #:trial-observation-reason
           #:trial-observation-signature
           #:trial-observation-explanation
           #:trial-observation-condition
           #:trial-observation-condition-report
           #:trial-observation-value
           #:trial-observation-case
           #:trial-observation-state
           #:evaluate-trial
           #:observe-trial
           #:observation-failure-p
           #:failure-identities-match-p
           #:property-result-entity-kind
           #:property-result-failure-evidence
           #:property-result-shrunk-evidence
           #:property-result-shrunk-outcome #:property-result-shrink-report
           #:property-result-generation-report #:property-result-failure-phase
           #:property-result-rejected
           #:property-result-failure-reason
           #:property-result-failure-signature
           #:property-result-explanation
           ;; Property results
           #:property-result
           #:property-result-status
           #:property-result-property
           #:property-result-trials
           #:property-result-seed
           #:property-result-profile
           #:property-result-counterexample
           #:property-result-shrunk-counterexample
           #:property-result-condition
           #:property-result-elapsed
           #:run-property
           #:run-properties
           #:replay-property
           ;; Function specs
           #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-argument-generator #:function-spec-argument-schema
           #:function-spec-return-spec
           #:function-spec-signal-spec
           #:function-spec-preconditions
           #:function-spec-postconditions #:function-spec-post-value-variables
           #:function-spec-precondition-function
           #:function-spec-postcondition-function
           #:function-spec-documentation
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:register-function-spec
           #:function-check-result
           #:function-check-result-function
           #:function-check-result-budget
           #:function-check-result-source-form
           #:function-check-result-rejected
           #:function-check-result-failure-reason
           #:function-check-result-explanation
           #:function-check-result-shrunk-outcome
           #:function-check-result-case-report
           #:check-function
           ;; Custom generators
           #:custom-generator
           #:custom-generator-name
           #:custom-generator-function #:custom-generator-shrinker
           #:custom-generator-documentation
           #:custom-generator-source-form
           #:custom-generator-source-location
           #:register-generator
           ;; Introspection
           #:describe-spec
           #:describe-property
           #:spec-data
           #:tagged-union-branch
           #:property-data
           #:function-spec-data
           #:semantic-data
           ;; DSL
           #:defspec
           #:defspec-function
           #:defproperty
           #:defgenerator))

(in-package #:cl-spec/main)
