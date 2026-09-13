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
  (:import-from #:cl-spec/src/utils/random #:seed->random-state)
  (:import-from #:check-it #:generate #:shrink))

(in-package #:cl-spec/tests/backends/plist-generator-test)

(defun plist-key-present-p (plist key)
  "Return true when KEY occurs in a key position, even when its value is NIL."
  (nth-value 2 (get-properties plist (list key))))

(deftest plist-samples
  (let* ((form '(plist (:required (:id (range integer 20 100)) (:nothing null)
                                  (:marker (member :label)))
                      (:optional (:label string)) (:closed t)))
         (spec (normalize-spec-form form))
         (values (sample spec :count 100 :seed 42)))
    (ok (every (lambda (value) (validp spec value)) values))
    (ok (every (lambda (value) (plist-key-present-p value :nothing)) values))
    (ok (every (lambda (value) (null (getf value :nothing))) values))
    (ok (some (lambda (value) (plist-key-present-p value :label)) values))
    (ok (some (lambda (value) (not (plist-key-present-p value :label))) values))
    (ok (equal values (sample spec :count 100 :seed 42)))))

(deftest plist-property-shrinks
  (let ((*registry* (make-hash-table-registry)))
    (defproperty plist-under-ten
        ((record (plist (:required (:id (range integer 1 100)) (:nothing null))
                        (:optional (:label string)))))
      (:trials (:normal 100))
      (< (getf record :id) 10))
    (let* ((result (run-property 'plist-under-ten :seed 42))
           (value (getf (property-result-shrunk-counterexample result) 'record)))
      (ok (eq :failed (property-result-status result)))
      (ok (equal value '(:id 10 :nothing nil))))))

(deftest existing-constant-capabilities-stay-compatible
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (form '(null (member 5) (range real 5 5) (tuple null)
                    (tuple (member 5))))
      (ok (equal '(:generation :available :shrinking :available)
                 (backend-capabilities backend (normalize-spec-form form)))
          (format nil "Existing capability reporting for ~S is preserved" form)))))

(deftest plist-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (entry '(((plist) :none)
                     ((plist (:required (:nothing null) (:tag (member :fixed)))) :none)
                     ((plist (:optional (:nothing null))) :available)
                     ((plist (:required (:id integer))) :available)))
      (ok (equal (list :generation :available :shrinking (second entry))
                 (backend-capabilities backend (normalize-spec-form (first entry))))
          (format nil "Capabilities for ~S" (first entry))))
    (ok (handler-case
            (progn
              (compile-spec-generator
               (normalize-spec-form '(plist (:optional (:opaque (satisfies consp))))) nil)
              nil)
          (generator-unavailable () t)))))

(deftest plist-shrinking-keeps-keys-and-constants
  (let ((spec (normalize-spec-form
               '(plist (:required (:id (range integer 10 100))
                                  (:nothing null) (:tag (member :extra)))
                       (:optional (:extra null)) (:closed t))))
        (*random-state* (seed->random-state 42)))
    (multiple-value-bind (generator required-size) (compile-spec-generator spec nil)
      (let ((check-it:*size* (max 10 required-size)))
        (let ((start (loop repeat 100
                           for value = (generate generator)
                           when (and (plist-key-present-p value :extra)
                                     (> (getf value :id) 10))
                             return (copy-list value)))
              (seen nil))
          (ok start "The seeded draw includes the optional key and a reducible integer")
          (ok (> (getf start :id) 10))
          (ok (plist-key-present-p start :extra))
          (let ((result (shrink generator
                                (lambda (value)
                                  (push (copy-list value) seen)
                                  (not (and (validp spec value) (>= (getf value :id) 10)))))))
            (ok seen)
            (ok (every (lambda (value) (validp spec value)) seen))
            (ok (= 10 (getf result :id)))
            (ok (< (getf result :id) (getf start :id)))
            (ok (some (lambda (value) (< (getf value :id) (getf start :id))) seen))
            (ok (plist-key-present-p result :nothing))
            (ok (null (getf result :nothing)))
            (ok (eq :extra (getf result :tag)))
            (ok (not (plist-key-present-p result :extra)))))))))

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
