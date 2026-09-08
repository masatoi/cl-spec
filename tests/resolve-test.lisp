;;;; tests/resolve-test.lisp

(defpackage #:cl-spec/tests/resolve-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec
                #:unknown-property)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/property
                #:property)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec
                #:registry-register-property)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:resolve-property
                #:context-registry))

(in-package #:cl-spec/tests/resolve-test)

(deftest resolving-a-spec-designator
  (let ((registry (make-hash-table-registry))
        (spec (make-instance 'type-spec :type-specifier 'integer)))
    (registry-register-spec registry 'small spec)
    (testing "a symbol resolves through the registry"
      (ok (eq spec (resolve-spec 'small registry))))
    (testing "a spec object resolves to itself"
      (ok (eq spec (resolve-spec spec registry))))
    (testing "an unregistered symbol signals UNKNOWN-SPEC"
      (ok (signals (resolve-spec 'absent registry) 'unknown-spec)))))

(deftest resolving-a-property-designator
  (let* ((registry (make-hash-table-registry))
         (property (make-instance 'property :name 'p)))
    (registry-register-property registry 'p property)
    (testing "a symbol resolves through the registry"
      (ok (eq property (resolve-property 'p registry))))
    (testing "a property object resolves to itself"
      (ok (eq property (resolve-property property registry))))
    (testing "an unregistered symbol signals UNKNOWN-PROPERTY"
      (ok (signals (resolve-property 'absent registry) 'unknown-property)))))

(deftest context-registry-defaults
  (let ((registry (make-hash-table-registry)))
    (testing "a context plist supplies the registry"
      (ok (eq registry (context-registry (list :registry registry)))))
    (testing "an empty context falls back to *REGISTRY*"
      (ok (eq cl-spec/src/registry:*registry* (context-registry nil))))))
