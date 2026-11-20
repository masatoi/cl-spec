;;;; src/coverage-plist.lisp
(defpackage #:cl-spec/src/coverage-plist
  (:use #:cl)
  (:import-from #:cl-spec/src/ir
                #:spec-children #:spec-generator-name #:and-spec #:or-spec #:collection-spec
                #:reference-spec #:reference-spec-target
                #:range-spec #:range-spec-base-type #:range-spec-minimum #:range-spec-maximum)
  (:import-from #:cl-spec/src/call-schema #:call-arguments-spec)
  (:import-from #:cl-spec/src/field-spec
                #:field-spec #:plist-spec #:field-spec-fields #:field-spec-closed-p
                #:field-key #:field-value-spec #:field-required-p #:plist-structure-error)
  (:import-from #:cl-spec/src/utils/numbers #:finite-real-p)
  (:import-from #:cl-spec/src/resolve #:resolve-spec)
  (:export #:plist-coverage-schema #:observe-dimension #:*plist-observation-indexes*))
(in-package #:cl-spec/src/coverage-plist)

(defun integer-boundaries (range)
  "Return the inward-rounded endpoints of a finite integer range."
  (let ((minimum (range-spec-minimum range))
        (maximum (range-spec-maximum range)))
    (when (and (eq 'integer (range-spec-base-type range))
               (finite-real-p minimum) (finite-real-p maximum))
      (values (ceiling minimum) (floor maximum)))))

(defun plist-coverage-schema (roots registry dimension-limit depth-limit)
  "Describe statically accessible plist dimensions without invoking readers or predicates."
  (let ((dimensions nil) (unexpanded nil) (count 0))
    (labels ((omit (path reason)
               (push (list :path path :reason reason) unexpanded)
               (when (or (eq reason :dimension-limit) (>= (length unexpanded) dimension-limit))
                 (throw 'discovery-limit nil)))
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
                 ((and path (typep node 'range-spec))
                  (multiple-value-bind (lo hi) (integer-boundaries node)
                    (if (and lo (<= lo hi))
                        (add name path :numeric-boundary '(:lower :upper :interior)
                             (list :minimum lo :maximum hi
                                   :inapplicable-buckets
                                   (when (<= (- hi lo) 1) '(:interior))
                                   :targetable
                                   (and targetable (null (spec-generator-name node)))))
                        (omit (cons name path) :unsupported-boundary))))
                 ((typep node 'plist-spec)
                  (let* ((fields (field-spec-fields node))
                         (keys (mapcar #'field-key fields))
                         (targetable (and targetable (null (spec-generator-name node)))))
                    (unless (field-spec-closed-p node)
                      (add name path :extra-key-presence '(:present :absent)
                           (list :declared-keys keys :targetable targetable)))
                    (dolist (field fields)
                      (let ((child (field-value-spec field))
                             (child-path (append path (list (field-key field)))))
                        (unless (field-required-p field)
                          (add name child-path :field-presence '(:present :absent)
                               (list :targetable targetable)))
                        (walk child name child-path (cons node ancestors) (1+ depth)
                              targetable)))))
                 ((or (typep node '(or field-spec collection-spec and-spec or-spec
                                       call-arguments-spec))
                      (spec-children node))
                  (omit (cons name path) :unsupported-composite)))))
      (catch 'discovery-limit
        (dolist (root roots) (walk (second root) (first root) nil nil 0 t))))
    (list :schema-version 1 :record-kind :coverage-schema :provider-version :plist-v1
          :discovery (if unexpanded :partial :complete)
          :dimensions (nreverse dimensions) :unexpanded (nreverse unexpanded))))

(defvar *plist-observation-indexes* nil
  "When bound, an EQ table of checked indexes for the duration of one input capture.
A present NIL entry records a malformed plist.")

(defun observation-index (record)
  "Return the checked field index of RECORD, or NIL for a malformed plist."
  (if *plist-observation-indexes*
      (multiple-value-bind (index found) (gethash record *plist-observation-indexes*)
        (if found index
            (setf (gethash record *plist-observation-indexes*)
                  (nth-value 2 (plist-structure-error record)))))
      (nth-value 2 (plist-structure-error record))))

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
          for index = (observation-index value)
          unless index do (return-from observe-dimension :unknown)
          do (multiple-value-bind (child present) (gethash key index)
               (when (and last (eq kind :field-presence))
                 (return-from observe-dimension (list (if present :present :absent))))
               (unless present (return-from observe-dimension :not-applicable))
               (setf value child)))
    (case kind
      (:extra-key-presence
       (let ((index (observation-index value)))
         (if index
             (let ((declared-present
                     (loop for key in (getf dimension :declared-keys)
                           count (nth-value 1 (gethash key index)))))
               (list (if (> (hash-table-count index) declared-present) :present :absent)))
             :unknown)))
      (:numeric-boundary
       (let ((lo (getf dimension :minimum)) (hi (getf dimension :maximum)))
         (if (not (integerp value)) :unknown
             (append (when (= value lo) '(:lower)) (when (= value hi) '(:upper))
                     (when (< lo value hi) '(:interior))))))
      (otherwise :unknown))))
