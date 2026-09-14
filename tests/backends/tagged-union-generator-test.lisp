;;;; tests/backends/tagged-union-generator-test.lisp

(defpackage #:cl-spec/tests/backends/tagged-union-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/dsl #:defspec)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form))

(in-package #:cl-spec/tests/backends/tagged-union-generator-test)

(defun union-form ()
  "The returned-or-signaled union every generation test draws from."
  '(tagged-by :kind
     (:returned (plist (:required (:kind (member :returned)) (:values (list-of integer)))
                       (:closed t)))
     (:signaled (plist (:required (:kind (member :signaled))
                                  (:condition-type (member simple-error)))
                       (:closed t)))))

(deftest tagged-union-generation-reaches-every-branch
  (let* ((spec (normalize-spec-form (union-form)))
         (values (sample spec :count 80 :seed 1)))
    (ok (every (lambda (value) (validp spec value)) values))
    (ok (equal '(:returned :signaled)
               (sort (remove-duplicates (mapcar (lambda (value) (getf value :kind)) values))
                     #'string< :key #'symbol-name)))))

(deftest tagged-union-branch-targeting
  (let* ((spec (normalize-spec-form (union-form)))
         (returned (sample spec :count 20 :seed 7 :branch :returned))
         (signaled (sample spec :count 20 :seed 7 :branch :signaled)))
    (ok (every (lambda (value) (eq :returned (getf value :kind))) returned))
    (ok (every (lambda (value) (eq :signaled (getf value :kind))) signaled))
    (ok (every (lambda (value) (validp spec value)) returned))
    (ok (every (lambda (value) (validp spec value)) signaled))
    (testing "the branch sample replays from its seed"
      (ok (equal (mapcar (lambda (value) (getf value :values)) returned)
                 (mapcar (lambda (value) (getf value :values))
                         (sample spec :count 20 :seed 7 :branch :returned)))))
    (testing "an unknown branch is refused"
      (ok (handler-case (progn (sample spec :count 1 :branch :missing) nil)
            (invalid-spec-form () t))))))

(deftest tagged-union-named-spec-branch-targeting
  (let ((*registry* (make-hash-table-registry)))
    (defspec outcome-union
        (tagged-by :kind
          (:returned (plist (:required (:kind (member :returned))
                                       (:values (list-of integer)))
                            (:closed t)))
          (:signaled (plist (:required (:kind (member :signaled))
                                       (:condition-type (member simple-error)))
                            (:closed t)))))
    (let ((values (sample 'outcome-union :count 10 :seed 3 :branch :signaled)))
      (ok (every (lambda (value) (eq :signaled (getf value :kind))) values))
      (ok (every (lambda (value) (validp 'outcome-union value)) values)))))

(deftest tagged-union-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (ok (equal '(:generation :available :shrinking :available)
               (backend-capabilities backend (normalize-spec-form (union-form)))))))
