;;;; tests/digest-details-test.lisp

(defpackage #:cl-spec/tests/digest-details-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/src/schema
                #:definition-digest #:definition-metadata #:definition-graph #:definition-description #:schema-info)
  (:import-from #:cl-spec/src/ir #:type-spec #:predicate-spec)
  (:import-from #:cl-spec/src/property #:property)
  (:import-from #:cl-spec/src/generator-definition #:custom-generator)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry #:registry-register-spec))

(in-package #:cl-spec/tests/digest-details-test)

(deftest wide-nested-array-diagnostics-reserve-bounded-work
  #+sbcl
  (let ((value nil))
    (dotimes (i 4)
      (let ((array (make-array 100000 :initial-element nil)))
        (setf (aref array 0) value value array)))
    (let* ((before (sb-ext:get-bytes-consed))
           (omissions (cl-spec/src/schema::canonical-value-omissions value))
           (allocated (- (sb-ext:get-bytes-consed) before)))
      ;; The 100000-node limit must bound scheduled work, not just popped tasks.
      ;; Eager expansion of all four arrays allocates over 38 MB on 64-bit SBCL.
      (ok (find :node-limit omissions :key (lambda (item) (getf item :reason))))
      (ok (< allocated 28000000)))))

(defclass opaque-type (type-spec) ()
  (:documentation "An extension whose additional semantics are not described."))

(defclass cyclic-description ()
  ((children :initarg :children :reader cyclic-description-children))
  (:documentation "A malformed extension whose children have a cyclic list spine."))

(defmethod definition-description ((object cyclic-description))
  (values nil (cyclic-description-children object) nil t))

(deftest complete-digest-details
  (let ((spec (normalize-spec-form 'integer)))
    (multiple-value-bind (digest complete omissions) (definition-digest spec)
      (ok (equal "fnv1a64-v1:a1252f5eb6a5ce86" digest))
      (ok complete)
      (ok (null omissions)))
    (let ((metadata (definition-metadata spec :capabilities nil)))
      (ok (member :digest-omissions metadata))
      (ok (member :captured-state (getf metadata :digest-exclusions)))
      (ok (getf metadata :definition-digest-complete)))
    (ok (member :digest-omissions (getf (schema-info) :optional-metadata)))))

(deftest opaque-description-has-a-reason
  (multiple-value-bind (digest complete omissions)
      (definition-digest (make-instance 'opaque-type :type-specifier 'integer))
    (ok (null digest))
    (ok (null complete))
    (ok (eq :opaque-definition (getf (first omissions) :kind)))
    (ok (listp (getf (first omissions) :path)))))

(deftest independent-missing-dependencies-have-stable-paths
  (let ((registry (make-hash-table-registry))
         (spec (normalize-spec-form '(tuple missing-left missing-right missing-left))))
    (multiple-value-bind (digest complete omissions) (definition-digest spec :registry registry)
      (ok (null digest))
      (ok (null complete))
      (ok (= 2 (length omissions)))
      (ok (every (lambda (entry) (eq :unresolved-reference (getf entry :kind))) omissions))
      (ok (equal '(missing-left missing-right)
                 (sort (mapcar (lambda (entry) (getf entry :target)) omissions)
                       #'string< :key #'symbol-name)))
      (ok (not (equal (getf (first omissions) :path) (getf (second omissions) :path))))
      (ok (equal omissions (nth-value 2 (definition-digest spec :registry registry)))))))

(deftest missing-source-and-opaque-values-are-distinct
  (let ((property (make-instance 'property :name 'closure-property
                                :function (let ((state 1)) (lambda () state)))))
    (multiple-value-bind (digest complete omissions) (definition-digest property)
      (ok (null digest))
      (ok (null complete))
      (ok (eq :missing-source (getf (first omissions) :kind)))))
  (multiple-value-bind (digest complete omissions)
      (definition-digest (make-instance 'custom-generator :name 'closure-generator
                                       :function (lambda () 1)))
    (ok (null digest))
    (ok (null complete))
    (ok (eq :missing-source (getf (first omissions) :kind))))
  (let ((spec (make-instance 'predicate-spec :predicate (lambda (value) value))))
    (multiple-value-bind (digest complete omissions) (definition-digest spec)
      (ok (null digest))
      (ok (null complete))
      (ok (eq :opaque-value (getf (first omissions) :kind)))
      (ok (eq :function-object (getf (first omissions) :reason)))
      (ok (getf (first omissions) :path)))
    ;; An opaque scalar does not erase the available local declaration snapshot.
    (ok (nth-value 1 (definition-graph spec :resolve-links-p nil)))))

(deftest uninterned-values-and-resource-limits-have-reasons
  (let ((spec (make-instance 'type-spec :type-specifier 'integer
                            :metadata (list :note (make-symbol "OPAQUE")))))
    (ok (eq :uninterned-symbol
            (getf (first (nth-value 2 (definition-digest spec))) :kind))))
  (let ((spec (make-instance 'type-spec :type-specifier 'integer
                            :metadata (list :note (make-string 1000001 :initial-element #\x)))))
    (ok (eq :resource-limit (getf (first (nth-value 2 (definition-digest spec))) :kind)))))

(deftest shared-opaque-values-report-the-first-path-once
  (let* ((closure (lambda () t))
         (spec (make-instance 'type-spec :type-specifier 'integer
                             :metadata (list :first closure :second closure)))
         (omissions (nth-value 2 (definition-digest spec))))
    (ok (= 1 (length omissions)))
    (ok (eq :function-object (getf (first omissions) :reason)))
    (ok (equal omissions (nth-value 2 (definition-digest spec))))))

(deftest declared-source-keeps-intentional-state-exclusions-complete
  (let* ((captured 2)
         (property (make-instance 'property :name 'declared-property
                                 :source-form '(property declared-property)
                                 :function (lambda () captured)))
         (metadata (definition-metadata property :capabilities nil)))
    (ok (getf metadata :definition-digest-complete))
    (ok (null (getf metadata :digest-omissions)))
    (ok (member :captured-state (getf metadata :digest-exclusions)))
    (ok (member :helper-implementations (getf metadata :digest-exclusions)))))

(deftest malformed-description-spines-stop-at-a-bound
  (let ((children (list (normalize-spec-form 'integer))))
    (setf (cdr children) children)
    (multiple-value-bind (digest complete omissions)
        (definition-digest (make-instance 'cyclic-description :children children))
      (ok (null digest))
      (ok (null complete))
      (ok (eq :resource-limit (getf (first omissions) :kind))))))

(deftest cyclic-named-dependencies-terminate
  (let ((registry (make-hash-table-registry))
         (left (normalize-spec-form '(nullable cycle-right)))
         (right (normalize-spec-form '(nullable cycle-left))))
    (registry-register-spec registry 'cycle-left left)
    (registry-register-spec registry 'cycle-right right)
    (multiple-value-bind (digest complete omissions) (definition-digest left :registry registry)
      (ok (stringp digest))
      (ok complete)
      (ok (null omissions)))))
