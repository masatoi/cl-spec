;;;; src/coverage-plist.lisp
(defpackage #:cl-spec/src/coverage-plist
  (:use #:cl)
  (:import-from #:cl-spec/src/ir
                #:spec-kind #:spec-children #:spec-generator-name
                #:reference-spec #:reference-spec-target
                #:range-spec #:range-spec-base-type #:range-spec-minimum #:range-spec-maximum)
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:field-spec-fields #:field-spec-closed-p
                #:field-key #:field-value-spec #:field-required-p #:plist-structure-error)
  (:import-from #:cl-spec/src/resolve #:resolve-spec)
  (:export #:plist-coverage-schema #:observe-dimension))
(in-package #:cl-spec/src/coverage-plist)

(defun plist-coverage-schema (roots registry dimension-limit depth-limit)
  "Describe statically accessible plist dimensions without invoking readers or predicates."
  (let ((dimensions nil) (unexpanded nil) (count 0))
    (labels ((omit (path reason)
               (push (list :path path :reason reason) unexpanded))
             (add (name path kind buckets properties)
               (if (< count dimension-limit)
                   (progn
                     (incf count)
                     (push (append
                            (list :id (append (list :call-arguments (list :argument name))
                                              (mapcar (lambda (key) (list :field key)) path)
                                              (list kind))
                                  :argument name :field-path path :kind kind :buckets buckets
                                  :input-space :call-arguments :observation :supported)
                            properties) dimensions))
                   (omit (cons name path) :dimension-limit)))
             (walk (node name path ancestors depth targetable)
               (cond
                 ((> depth depth-limit) (omit (cons name path) :depth-limit))
                 ((member node ancestors :test #'eq) (omit (cons name path) :recursive-reference))
                 ((typep node 'reference-spec)
                  (walk (resolve-spec (reference-spec-target node) registry) name path
                        (cons node ancestors) (1+ depth)
                        (and targetable (null (spec-generator-name node)))))
                 ((typep node 'plist-spec)
                  (let* ((fields (field-spec-fields node))
                         (keys (mapcar #'field-key fields))
                         (targetable (and targetable (null (spec-generator-name node)))))
                    (unless (field-spec-closed-p node)
                      (add name path :extra-key-presence '(:present :absent)
                           (list :declared-keys keys :targetable targetable)))
                    (dolist (field fields)
                      (let* ((child (field-value-spec field))
                             (child-path (append path (list (field-key field)))))
                        (unless (field-required-p field)
                          (add name child-path :field-presence '(:present :absent)
                               (list :targetable targetable)))
                        (if (typep child 'range-spec)
                            (let ((lo (range-spec-minimum child)) (hi (range-spec-maximum child)))
                              (if (and (eq 'integer (range-spec-base-type child))
                                       (integerp lo) (integerp hi) (<= lo hi))
                                  (add name child-path :numeric-boundary '(:lower :upper :interior)
                                       (list :minimum lo :maximum hi
                                             :inapplicable-buckets
                                             (when (<= (- hi lo) 1) '(:interior))
                                             :targetable
                                             (and targetable (null (spec-generator-name child)))))
                                  (omit (cons name child-path) :unsupported-boundary)))
                            (walk child name child-path (cons node ancestors) (1+ depth)
                                  targetable))))))
                 ((spec-children node) (omit (cons name path) :unsupported-composite)))))
      (dolist (root roots) (walk (second root) (first root) nil nil 0 t)))
    (list :schema-version 1 :record-kind :coverage-schema :provider-version :plist-v1
          :discovery (if unexpanded :partial :complete)
          :dimensions (nreverse dimensions) :unexpanded (nreverse unexpanded))))

(defun coverage-field (record key)
  "Return a field and presence, or :UNKNOWN for a structurally invalid plist."
  (if (plist-structure-error record)
      (values nil :unknown)
      (loop for (name value) on record by #'cddr
            when (eq name key) do (return (values value t))
            finally (return (values nil nil)))))

(defun observe-dimension (dimension bindings)
  "Return hit bucket names, :UNKNOWN, or :NOT-APPLICABLE for saved input bindings."
  (let* ((name (getf dimension :argument))
         (cell (loop for tail on bindings by #'cddr when (eq (car tail) name) return tail))
         (value (second cell))
         (path (getf dimension :field-path))
         (kind (getf dimension :kind)))
    (unless cell (return-from observe-dimension :not-applicable))
    (loop for tail on path
          for key = (car tail)
          for last = (null (cdr tail))
          do (multiple-value-bind (child present) (coverage-field value key)
               (when (eq present :unknown) (return-from observe-dimension :unknown))
               (when (and last (eq kind :field-presence))
                 (return-from observe-dimension (list (if present :present :absent))))
               (unless present (return-from observe-dimension :not-applicable))
               (setf value child)))
    (case kind
      (:extra-key-presence
       (if (plist-structure-error value) :unknown
           (list (if (loop for key in value by #'cddr
                           thereis (not (member key (getf dimension :declared-keys))))
                     :present :absent))))
      (:numeric-boundary
       (let ((lo (getf dimension :minimum)) (hi (getf dimension :maximum)))
         (if (not (integerp value)) :unknown
             (append (when (= value lo) '(:lower)) (when (= value hi) '(:upper))
                     (when (< lo value hi) '(:interior))))))
      (otherwise :unknown))))
