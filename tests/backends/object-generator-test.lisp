;;;; tests/backends/object-generator-test.lisp

(defpackage #:cl-spec/tests/backends/object-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/dsl #:defgenerator))

(in-package #:cl-spec/tests/backends/object-generator-test)

(defclass object-generated ()
  ((id :initarg :id :reader object-generated-id))
  (:documentation "Fixture a custom generator constructs."))

(deftest object-generation-is-unavailable
  (testing "readers observe but do not construct, so the backend refuses to invent an instance"
    (let ((backend (make-instance 'check-it-backend)))
      (ok (equal '(:generation :unavailable :shrinking :unavailable)
                 (backend-capabilities
                  backend
                  (normalize-spec-form
                   '(object-of object-generated (:required (object-generated-id integer))))))))))

(deftest object-custom-generator-draws-instances
  (testing "a (:GENERATOR NAME) is the supported way to draw an OBJECT-OF value"
    (let ((*registry* (make-hash-table-registry)))
      (defgenerator object-generated-generator ()
        (make-instance 'object-generated :id (random 100)))
      (let* ((spec (normalize-spec-form
                    '(object-of object-generated (:required (object-generated-id integer)))
                    :generator 'object-generated-generator))
             (values (sample spec :count 20 :seed 42)))
        (ok (every (lambda (value) (typep value 'object-generated)) values))
        (ok (every (lambda (value) (validp spec value)) values))
        (ok (equal (mapcar #'object-generated-id values)
                   (mapcar #'object-generated-id (sample spec :count 20 :seed 42))))))))
