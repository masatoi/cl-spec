;;;; tests/backends/keyed-generator-test.lisp

(defpackage #:cl-spec/tests/backends/keyed-generator-test
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
                #:property-result-shrunk-counterexample))

(in-package #:cl-spec/tests/backends/keyed-generator-test)

(defun alist-key-present-p (alist key)
  "Return true when KEY occurs in ALIST, even when its value is NIL."
  (not (null (assoc key alist :test #'eql))))

(deftest alist-samples
  (let* ((form '(alist (:required (:id (range integer 20 100)) (:nothing null)
                                (:marker (member :label)))
                       (:optional (:label string)) (:closed t)))
         (spec (normalize-spec-form form))
         (values (sample spec :count 100 :seed 42)))
    (ok (every (lambda (value) (validp spec value)) values))
    (ok (every (lambda (value) (alist-key-present-p value :nothing)) values))
    (ok (every (lambda (value) (null (cdr (assoc :nothing value)))) values))
    (ok (some (lambda (value) (alist-key-present-p value :label)) values))
    (ok (some (lambda (value) (not (alist-key-present-p value :label))) values))
    (ok (equal values (sample spec :count 100 :seed 42)))))

(deftest hash-table-samples
  (let* ((form '(hash-table (:test equal)
                            (:required (:id (range integer 20 100)) (:nothing null)
                                       (:marker (member :label)))
                            (:optional (:label string)) (:closed t)))
         (spec (normalize-spec-form form))
         (values (sample spec :count 100 :seed 42)))
    (ok (every (lambda (value) (validp spec value)) values))
    (ok (every (lambda (value) (eq 'equal (hash-table-test value))) values)
        "generated tables carry the declared key test")
    (ok (every (lambda (value) (nth-value 1 (gethash :nothing value))) values))
    (ok (every (lambda (value) (null (gethash :nothing value))) values))
    (ok (some (lambda (value) (nth-value 1 (gethash :label value))) values))
    (ok (some (lambda (value) (not (nth-value 1 (gethash :label value)))) values))
    (ok (equalp (first (sample spec :count 100 :seed 42)) (first values)))))

(deftest keyed-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (entry '(((alist) :none)
                     ((alist (:required (:nothing null) (:tag (member :fixed)))) :none)
                     ((alist (:optional (:nothing null))) :available)
                     ((alist (:required (:id integer))) :available)
                     ((hash-table) :none)
                     ((hash-table (:required (:nothing null))) :none)
                     ((hash-table (:optional (:nothing null))) :available)
                     ((hash-table (:required (:id integer))) :available)))
      (ok (equal (list :generation :available :shrinking (second entry))
                 (backend-capabilities backend (normalize-spec-form (first entry))))
          (format nil "Capabilities for ~S" (first entry)))))
  (dolist (form '((alist (:optional (:opaque (satisfies consp))))
                  (hash-table (:optional (:opaque (satisfies consp))))))
    (ok (handler-case
            (progn (compile-spec-generator (normalize-spec-form form) nil) nil)
          (generator-unavailable () t))
        (format nil "~S refuses an unsupported child generator" form))))

(deftest alist-property-shrinks
  (let ((*registry* (make-hash-table-registry)))
    (defproperty alist-under-ten
        ((record (alist (:required (:id (range integer 1 100)) (:nothing null))
                        (:optional (:label string)))))
      (:trials (:normal 100))
      (< (cdr (assoc :id record)) 10))
    (let* ((result (run-property 'alist-under-ten :seed 42))
           (value (getf (property-result-shrunk-counterexample result) 'record)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 10 (cdr (assoc :id value))))
      (ok (alist-key-present-p value :nothing))
      (ok (null (cdr (assoc :nothing value))))
      (ok (not (alist-key-present-p value :label))))))

(deftest hash-table-property-shrinks
  (let ((*registry* (make-hash-table-registry)))
    (defproperty table-under-ten
        ((record (hash-table (:test equal)
                             (:required (:id (range integer 1 100)) (:nothing null))
                             (:optional (:label string)))))
      (:trials (:normal 100))
      (< (gethash :id record) 10))
    (let* ((result (run-property 'table-under-ten :seed 42))
           (value (getf (property-result-shrunk-counterexample result) 'record)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 10 (gethash :id value)))
      (ok (nth-value 1 (gethash :nothing value)))
      (ok (null (gethash :nothing value)))
      (ok (not (nth-value 1 (gethash :label value))))
      (ok (eq 'equal (hash-table-test value))))))
