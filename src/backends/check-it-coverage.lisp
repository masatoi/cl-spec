;;;; src/backends/check-it-coverage.lisp
(defpackage #:cl-spec/src/backends/check-it-coverage
  (:use #:cl)
  (:import-from #:cl-spec/src/coverage #:coverage-inputs)
  (:import-from #:cl-spec/src/coverage-report
                #:*coverage-context* #:coverage-context-schema #:coverage-context-options
                #:coverage-context-plan #:coverage-fixture-p)
  (:import-from #:cl-spec/src/ir #:reference-spec #:reference-spec-target #:spec-generator-name)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:field-spec-fields #:field-key #:field-value-spec)
  (:import-from #:cl-spec/src/resolve #:resolve-spec)
  (:import-from #:cl-spec/src/property #:property-argument-schema)
  (:export #:check-it-coverage-capabilities #:prepare-coverage-plan #:next-coverage-target
           #:*coverage-target* #:planned-field #:planned-extra-key))
(in-package #:cl-spec/src/backends/check-it-coverage)

(defvar *coverage-target* nil
  "A single planned bucket for this root generation, never active during shrinking.")

(defun check-it-coverage-capabilities (schema options)
  "Describe per-bucket construction support without drawing values."
  (loop for d in (getf schema :dimensions)
        collect
        (list :id (getf d :id)
              :buckets
              (loop for bucket in (getf d :buckets)
                    for extra = (and (eq (getf d :kind) :extra-key-presence)
                                     (eq bucket :present))
                    for keys = (set-difference (getf options :extra-keys)
                                               (getf d :declared-keys))
                    for applicable = (not (member bucket (getf d :inapplicable-buckets)))
                    for supported = (and (getf d :targetable) applicable
                                         (or (not extra) (and (eq :exercise (getf options :mode))
                                                              keys)))
                    collect (list :bucket bucket
                                  :generation (if supported :supported :unknown)
                                  :targeting (if supported :supported :unsupported)
                                  :reason (cond ((not applicable) :not-applicable)
                                                ((not (getf d :targetable)) :custom-generator)
                                                ((and extra (not keys)) :extra-key-pool-exhausted)
                                                (t nil)))))))

(defun resolved-node (node registry)
  "Follow finite references already bounded by schema discovery."
  (let ((seen nil))
    (loop while (typep node 'reference-spec)
          do (when (member node seen) (return-from resolved-node nil))
             (push node seen)
             (setf node (resolve-spec (reference-spec-target node) registry))))
  node)

(defun target-route (definition dimension registry)
  "Return plist node/path pairs; never retain generated application values."
  (let ((node (second (assoc (getf dimension :argument) (coverage-inputs definition))))
        (path (getf dimension :field-path))
        (route nil))
    (loop
      (setf node (resolved-node node registry))
      (unless (typep node 'plist-spec) (return (nreverse route)))
      (push (list node path) route)
      (unless path (return (nreverse route)))
      (let ((field (find (car path) (field-spec-fields node) :key #'field-key)))
        (unless field (return nil))
        (setf node (field-value-spec field) path (cdr path))))))

(defun prepare-coverage-plan (definition registry)
  "Save a bounded one-pass plan; whole custom generators and fixture recipes are not targeted."
  (when (and *coverage-context*
             (eq :exercise (getf (coverage-context-options *coverage-context*) :mode)))
    (let* ((schema (coverage-context-schema *coverage-context*))
           (options (coverage-context-options *coverage-context*))
           (safe (and (not (coverage-fixture-p definition))
                      (null (spec-generator-name (property-argument-schema definition)))))
           (entries nil) (targets nil))
      (dolist (dimension (getf schema :dimensions))
        (let ((route (and safe (getf dimension :targetable)
                          (target-route definition dimension registry))))
          (dolist (bucket (getf dimension :buckets))
            (let* ((extra (and (eq (getf dimension :kind) :extra-key-presence)
                               (eq bucket :present)))
                   (extra-key (find-if
                               (lambda (key) (not (member key (getf dimension :declared-keys))))
                               (getf options :extra-keys)))
                   (supported (and route (not (member bucket
                                                      (getf dimension :inapplicable-buckets)))
                                   (or (not extra) extra-key)))
                   (entry (list :id (getf dimension :id) :bucket bucket
                                :status (if supported :pending :unsupported))))
              (push entry entries)
              (when supported
                (push (list :dimension dimension :bucket bucket :route route
                            :extra-key extra-key :entry entry) targets))))))
      (setf (coverage-context-plan *coverage-context*)
            (list :policy-version 1 :entries (nreverse entries)))
      (nreverse targets))))

(defun next-coverage-target (targets)
  "Mark one plan item attempted; the observer alone determines hits."
  (let ((target (car targets)))
    (when target (setf (getf (getf target :entry) :status) :attempted))
    target))

(defun planned-field (spec key)
  "Return :PRESENT/:ABSENT/:VALUE and optional value for one field, or NIL."
  (when *coverage-target*
    (let* ((route (assoc spec (getf *coverage-target* :route)))
           (path (second route))
           (dimension (getf *coverage-target* :dimension))
           (bucket (getf *coverage-target* :bucket)))
      (when (and route path (eq key (car path)))
        (cond
          ((cdr path) (values :present nil))
          ((eq (getf dimension :kind) :field-presence)
           (values bucket nil))
          ((eq (getf dimension :kind) :numeric-boundary)
           (values :value
                   (case bucket (:lower (getf dimension :minimum))
                                (:upper (getf dimension :maximum))
                                (:interior (1+ (getf dimension :minimum))))))
          (t (values :present nil)))))))

(defun planned-extra-key (spec)
  "Return one collision-free planned extra key for SPEC, or NIL."
  (when *coverage-target*
    (let ((route (assoc spec (getf *coverage-target* :route))))
      (when (and route (null (second route))
                 (eq :extra-key-presence (getf (getf *coverage-target* :dimension) :kind))
                 (eq :present (getf *coverage-target* :bucket)))
        (getf *coverage-target* :extra-key)))))
