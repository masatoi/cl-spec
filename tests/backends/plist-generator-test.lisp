;;;; tests/backends/plist-generator-test.lisp

(defpackage #:cl-spec/tests/backends/plist-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/backends/check-it-generators #:compile-spec-generator)
  (:import-from #:cl-spec/src/conditions #:generator-unavailable)
  (:import-from #:cl-spec/src/dsl #:defproperty)
  (:import-from #:cl-spec/src/property-runner
                #:run-property #:property-result-status
                #:property-result-shrunk-counterexample)
  (:import-from #:check-it #:generate #:shrink))

(in-package #:cl-spec/tests/backends/plist-generator-test)

(deftest plist-samples
  (ok
   (handler-case
       (let* ((form '(plist (:required (:id (range integer 20 100)) (:nothing null))
                           (:optional (:label string)) (:closed t)))
              (spec (normalize-spec-form form))
              (values (sample spec :count 100 :seed 42)))
         (and (every (lambda (value) (validp spec value)) values)
              (every (lambda (value) (member :nothing value)) values)
              (some (lambda (value) (member :label value)) values)
              (some (lambda (value) (not (member :label value))) values)
              (equal values (sample spec :count 100 :seed 42))))
     (error () nil))))

(deftest plist-property-shrinks
  (ok
   (handler-case
       (let ((*registry* (make-hash-table-registry)))
         (defproperty plist-under-ten
             ((record (plist (:required (:id (range integer 1 100)) (:nothing null))
                             (:optional (:label string)))))
           (:trials (:normal 100))
           (< (getf record :id) 10))
         (let* ((result (run-property 'plist-under-ten :seed 42))
                (value (getf (property-result-shrunk-counterexample result) 'record)))
           (and (eq :failed (property-result-status result))
                (equal value '(:id 10 :nothing nil)))))
     (error () nil))))

(deftest plist-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (entry '(((plist) :none)
                     ((plist (:required (:nothing null) (:tag (member :fixed)))) :none)
                     ((plist (:optional (:nothing null))) :available)
                     ((plist (:required (:id integer))) :available)))
      (ok (handler-case
              (equal (list :generation :available :shrinking (second entry))
                     (backend-capabilities backend (normalize-spec-form (first entry))))
            (error () nil))))
    (ok (handler-case
            (progn
              (compile-spec-generator
               (normalize-spec-form '(plist (:optional (:opaque (satisfies consp))))) nil)
              nil)
          (generator-unavailable () t)
          (error () nil)))))

(deftest plist-shrinking-keeps-keys-and-constants
  (ok
   (handler-case
       (let* ((spec (normalize-spec-form
                     '(plist (:required (:id (range integer 10 100))
                                        (:nothing null) (:tag (member :fixed)))
                             (:optional (:extra null)) (:closed t))))
              (generator (compile-spec-generator spec nil))
              (seen nil))
         (loop repeat 100
               until (member :extra (generate generator)))
         (let ((result
                 (shrink generator
                         (lambda (value)
                           (push (copy-list value) seen)
                           (not (and (validp spec value) (>= (getf value :id) 10)))))))
           (and seen
                (every (lambda (value) (validp spec value)) seen)
                (= 10 (getf result :id))
                (member :nothing result)
                (eq :fixed (getf result :tag))
                (not (member :extra result)))))
     (error () nil))))

(deftest nested-plists-shrink-without-losing-field-associations
  (let ((*registry* (make-hash-table-registry)))
    (defproperty nested-under-ten
        ((record (plist
                   (:required
                     (:payload (plist (:required (:count (range integer 1 100)))
                                      (:optional (:note null)) (:closed t))))
                   (:optional (:extra null)) (:closed t))))
      (:trials (:normal 100))
      (< (getf (getf record :payload) :count) 10))
    (dolist (seed '(1 42 2026))
      (let* ((result (run-property 'nested-under-ten :seed seed))
             (record (getf (property-result-shrunk-counterexample result) 'record)))
        (ok (eq :failed (property-result-status result)))
        (ok (equal '(:payload (:count 10)) record))))))
