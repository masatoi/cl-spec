;;;; tests/backends/check-it-test.lisp

(defpackage #:cl-spec/tests/backends/check-it-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:generator-unavailable)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend
                #:install-check-it-backend
                #:default-trials)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/backends/check-it-generators
                #:spec-generator
                #:compile-spec-generator)
  (:import-from #:cl-spec/src/validator
                #:validp)
  (:import-from #:check-it
                #:generate)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec))

(in-package #:cl-spec/tests/backends/check-it-test)

(deftest loading-installs-the-backend
  (testing "loading this system leaves a CHECK-IT-BACKEND in *GENERATOR-BACKEND*"
    (ok (typep *generator-backend* 'check-it-backend))
    (ok (typep (current-generator-backend) 'check-it-backend))))

(deftest install-is-idempotent-and-returns-the-backend
  (testing "INSTALL-CHECK-IT-BACKEND can be called again safely"
    (let ((backend (install-check-it-backend)))
      (ok (typep backend 'check-it-backend))
      (ok (eq backend *generator-backend*)))))

(deftest default-trials-comes-from-check-it
  (testing "the default trial count is taken from CHECK-IT:*NUM-TRIALS*"
    (ok (integerp (default-trials)))
    (ok (plusp (default-trials)))))

(deftest backend-methods-are-stubs
  (testing "the three protocol methods are specialised but not yet written"
    (let ((backend (install-check-it-backend)))
      (ok (signals (compile-generator backend :any-spec) 'not-implemented))
      (ok (signals (generate-value backend :any-generator) 'not-implemented))
      (ok (signals (run-generated-test backend :any-property)
                   'not-implemented)))))

(defun draws-for (form &key (count 30) (registry (make-hash-table-registry)))
  "Generate COUNT values from FORM's generator, honouring the size its bounds need."
  (multiple-value-bind (generator size)
      (compile-spec-generator (normalize-spec-form form) (list :registry registry))
    (let ((check-it:*size* (max check-it:*size* size)))
      (loop repeat count collect (generate generator)))))

(deftest generated-values-satisfy-their-leaf-spec
  (dolist (form '(integer real character string (member :a :b :c)
                  (range 1 100) (range integer 1 100) (range integer 1 *)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest null-and-boolean-types
  (testing "NULL generates NIL"
    (ok (every #'null (draws-for 'null :count 5))))
  (testing "BOOLEAN generates only T and NIL"
    (ok (every (lambda (value) (member value '(t nil))) (draws-for 'boolean)))))

(deftest generated-values-satisfy-their-composite-spec
  (dolist (form '((or integer string) (nullable integer)
                  (tuple integer string) (list-of integer) (vector-of integer)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest ranges-wider-than-check-its-default-size-are-honoured
  ;; check-it clamps every numeric limit to CHECK-IT:*SIZE*, which is 10 by
  ;; default.  Without the required-size accounting these two draw 10 and -10,
  ;; both outside the range that was asked for.
  (testing "a positive range that does not straddle zero stays inside itself"
    (ok (every (lambda (value) (<= 20 value 100))
               (draws-for '(range integer 20 100)))))
  (testing "a negative range stays inside itself"
    (ok (every (lambda (value) (<= -100 value -50))
               (draws-for '(range integer -100 -50)))))
  (testing "the widened size does not leak out of the draw"
    (draws-for '(range integer 20 100) :count 1)
    (ok (= 10 check-it:*size*))))

(deftest references-are-followed
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'small
                            (normalize-spec-form '(range integer 1 10) :name 'small))
    (testing "a reference generates through its target"
      (ok (every (lambda (value) (and (integerp value) (<= 1 value 10)))
                 (draws-for 'small :registry registry))))))

(deftest specs-without-a-generation-strategy-say-so
  (dolist (form '((not integer) (satisfies plusp) (instance-of standard-object)
                  (member) (or) (type hash-table)))
    (testing (format nil "~S signals GENERATOR-UNAVAILABLE" form)
      (ok (handler-case (progn (draws-for form :count 1) nil)
            (generator-unavailable () t))))))

(deftest recursive-specs-are-refused-rather-than-hanging
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'int-tree
                            (normalize-spec-form '(or integer (tuple int-tree int-tree))
                                                 :name 'int-tree))
    (testing "a self referential spec signals instead of recursing forever"
      (ok (handler-case (progn (draws-for 'int-tree :count 1 :registry registry) nil)
            (generator-unavailable () t))))))
