;;;; tests/registry-conformance-test.lisp
;;;;
;;;; The registry-protocol conformance suite in CL-SPEC/SPECS run against
;;;; registries other than the built-in one: an independent alist implementation
;;;; that must conform, and a faulty variant of it that must not.

(defpackage #:cl-spec/tests/registry-conformance-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok #:testing)
  (:import-from #:cl-spec/specs
                #:check-registry-implementation
                #:registry-conformance-names
                #:registry-implementation-p)
  (:import-from #:cl-spec/main
                #:*registry*
                #:list-function-specs
                #:list-properties
                #:make-hash-table-registry
                #:registry-clear
                #:registry-find-function-spec
                #:registry-find-generator
                #:registry-find-property
                #:registry-find-spec
                #:registry-list-function-specs
                #:registry-list-generators
                #:registry-list-properties
                #:registry-list-specs
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-register-function-spec
                #:registry-register-generator
                #:registry-register-property
                #:registry-register-spec)
  (:import-from #:cl-spec/src/backends/check-it))

(in-package #:cl-spec/tests/registry-conformance-test)

(defun sorted-names (names)
  "Return a fresh copy of NAMES sorted by symbol name, then by home package name."
  (sort (copy-list names)
        (lambda (left right)
          (let ((left-name (symbol-name left))
                (right-name (symbol-name right)))
            (or (string< left-name right-name)
                (and (string= left-name right-name)
                     (string< (package-name (symbol-package left))
                              (package-name (symbol-package right)))))))))

(defun alist-lookup (alist name)
  "Return the value under NAME in ALIST and whether it was present."
  (let ((entry (assoc name alist)))
    (values (cdr entry) (and entry t))))

(defun alist-put (alist name value)
  "Return ALIST with NAME bound to VALUE, replacing any previous binding."
  (acons name value (remove name alist :key #'car)))

(defclass alist-registry ()
  ((specs :initform '() :accessor alist-specs)
   (function-specs :initform '() :accessor alist-function-specs)
   (generators :initform '() :accessor alist-generators)
   (properties :initform '() :accessor alist-properties
               :documentation "Name -> (property targets tags).")
   (by-target :initform '() :accessor alist-by-target)
   (by-tag :initform '() :accessor alist-by-tag))
  (:documentation "An independent REGISTRY-* implementation that shares no code with the built-in one."))

(defun make-alist-registry ()
  "Return a fresh, empty alist registry."
  (make-instance 'alist-registry))

(defmethod registry-find-spec ((registry alist-registry) name)
  (alist-lookup (alist-specs registry) name))

(defmethod registry-register-spec ((registry alist-registry) name spec)
  (setf (alist-specs registry) (alist-put (alist-specs registry) name spec))
  spec)

(defmethod registry-list-specs ((registry alist-registry))
  (sorted-names (mapcar #'car (alist-specs registry))))

(defmethod registry-find-function-spec ((registry alist-registry) name)
  (alist-lookup (alist-function-specs registry) name))

(defmethod registry-register-function-spec ((registry alist-registry) name function-spec)
  (setf (alist-function-specs registry)
        (alist-put (alist-function-specs registry) name function-spec))
  function-spec)

(defmethod registry-list-function-specs ((registry alist-registry))
  (sorted-names (mapcar #'car (alist-function-specs registry))))

(defmethod registry-find-generator ((registry alist-registry) name)
  (alist-lookup (alist-generators registry) name))

(defmethod registry-register-generator ((registry alist-registry) name generator)
  (setf (alist-generators registry) (alist-put (alist-generators registry) name generator))
  generator)

(defmethod registry-list-generators ((registry alist-registry))
  (sorted-names (mapcar #'car (alist-generators registry))))

(defmethod registry-find-property ((registry alist-registry) name)
  (let ((entry (assoc name (alist-properties registry))))
    (values (second entry) (and entry t))))

(defun index-remove (index name)
  "Return INDEX with NAME removed from every key, dropping keys left empty."
  (loop for (key . names) in index
        for remaining = (remove name names)
        when remaining collect (cons key remaining)))

(defun index-add (index name keys)
  "Return INDEX with NAME added under each of KEYS."
  (dolist (key keys index)
    (setf index (alist-put index key (adjoin name (cdr (assoc key index)))))))

(defgeneric retract-stale-indexes-p (registry)
  (:documentation "True when re-registration removes the previous definition's index entries.")
  (:method ((registry alist-registry)) t))

(defmethod registry-register-property ((registry alist-registry) name property
                                       &key targets tags)
  (when (retract-stale-indexes-p registry)
    (setf (alist-by-target registry) (index-remove (alist-by-target registry) name)
          (alist-by-tag registry) (index-remove (alist-by-tag registry) name)))
  (setf (alist-properties registry)
        (alist-put (alist-properties registry) name (list property targets tags))
        (alist-by-target registry) (index-add (alist-by-target registry) name targets)
        (alist-by-tag registry) (index-add (alist-by-tag registry) name tags))
  property)

(defmethod registry-list-properties ((registry alist-registry))
  (sorted-names (mapcar #'car (alist-properties registry))))

(defmethod registry-properties-for ((registry alist-registry) target)
  (sorted-names (cdr (assoc target (alist-by-target registry)))))

(defmethod registry-properties-with-tag ((registry alist-registry) tag)
  (sorted-names (cdr (assoc tag (alist-by-tag registry)))))

(defmethod registry-clear ((registry alist-registry))
  (setf (alist-specs registry) '()
        (alist-function-specs registry) '()
        (alist-generators registry) '()
        (alist-properties registry) '()
        (alist-by-target registry) '()
        (alist-by-tag registry) '())
  registry)

(defclass stale-index-registry (alist-registry) ()
  (:documentation "A faulty alist registry: re-registration keeps the old index entries."))

(defmethod retract-stale-indexes-p ((registry stale-index-registry))
  nil)

(defun make-stale-index-registry ()
  "Return a fresh registry that leaks stale reverse-index entries."
  (make-instance 'stale-index-registry))

(defclass half-clear-registry (alist-registry) ()
  (:documentation "A faulty alist registry whose clear forgets the generator store."))

(defmethod registry-clear ((registry half-clear-registry))
  (let ((generators (alist-generators registry)))
    (call-next-method)
    (setf (alist-generators registry) generators)
    registry))

(defun make-half-clear-registry ()
  "Return a fresh registry that keeps its generators across a clear."
  (make-instance 'half-clear-registry))

(defclass unsorted-registry (alist-registry) ()
  (:documentation "A faulty alist registry that lists specs in storage order, unsorted."))

(defmethod registry-list-specs ((registry unsorted-registry))
  (mapcar #'car (alist-specs registry)))

(defun make-unsorted-registry ()
  "Return a fresh registry whose spec listing is not sorted."
  (make-instance 'unsorted-registry))

(defclass silent-write-registry (alist-registry) ()
  (:documentation "A faulty alist registry that stores specs correctly but returns NIL."))

(defmethod registry-register-spec ((registry silent-write-registry) name spec)
  (declare (ignore name spec))
  (call-next-method)
  nil)

(defun make-silent-write-registry ()
  "Return a fresh registry whose spec writes answer NIL instead of the spec."
  (make-instance 'silent-write-registry))

(defclass sticky-spec-registry (alist-registry) ()
  (:documentation "A faulty alist registry whose spec writes keep the first definition."))

(defmethod registry-register-spec ((registry sticky-spec-registry) name spec)
  (unless (nth-value 1 (registry-find-spec registry name))
    (call-next-method))
  spec)

(defun make-sticky-spec-registry ()
  "Return a fresh registry that ignores a second spec written under a name."
  (make-instance 'sticky-spec-registry))

(defclass name-keyed-registry (alist-registry) ()
  (:documentation "A faulty alist registry that keys specs by symbol name alone."))

(defmethod registry-register-spec ((registry name-keyed-registry) name spec)
  (setf (alist-specs registry)
        (acons name spec (remove (symbol-name name) (alist-specs registry)
                                 :key (lambda (entry) (symbol-name (car entry)))
                                 :test #'string=)))
  spec)

(defmethod registry-find-spec ((registry name-keyed-registry) name)
  (let ((entry (assoc (symbol-name name) (alist-specs registry)
                      :key #'symbol-name :test #'string=)))
    (values (cdr entry) (and entry t))))

(defun make-name-keyed-registry ()
  "Return a fresh registry that conflates same-named symbols of different packages."
  (make-instance 'name-keyed-registry))

(defclass partial-registry () ()
  (:documentation "An object implementing only part of the registry protocol."))

(defmethod registry-list-specs ((registry partial-registry))
  '())

(defun failing-names (records)
  "Return the distinct names of RECORDS that did not pass with satisfied evidence."
  (remove-duplicates
   (loop for record in records
         unless (and (eq :passed (getf record :status))
                     (eq :satisfied (getf record :assessment)))
           collect (getf record :name))))

(deftest registry-implementation-predicate-reads-method-applicability
  (ok (registry-implementation-p (make-hash-table-registry)))
  (ok (registry-implementation-p (make-alist-registry)))
  (testing "a partial implementation or a non-registry is refused"
    (ok (not (registry-implementation-p (make-instance 'partial-registry))))
    (ok (not (registry-implementation-p 42)))))

(deftest built-in-registry-conforms
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-hash-table-registry :seeds '(42))
    (ok conforming (prin1-to-string (failing-names records)))))

(deftest independent-registry-conforms
  (let* ((names (registry-conformance-names))
         (outer (make-hash-table-registry))
         (*registry* outer))
    (multiple-value-bind (conforming records)
        (check-registry-implementation #'make-alist-registry :seeds '(1 42))
      (testing "every conformance check passes with satisfied evidence"
        (ok conforming (prin1-to-string (failing-names records))))
      (testing "one record per conformance name and seed"
        (ok (= (* 2 (+ (length (getf names :contracts)) (length (getf names :properties))))
               (length records))))
      (testing "the caller's registry is left untouched"
        (ok (null (list-function-specs outer)))
        (ok (null (list-properties outer)))))))

(deftest stale-index-registry-is-refused
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-stale-index-registry :seeds '(1))
    (ok (not conforming))
    (let ((failing (failing-names records)))
      (testing "the contract and the laws about re-registration are the ones that fail"
        (ok (member 'cl-spec:registry-register-property failing))
        (ok (member 'cl-spec/specs::registry-reverse-indexes-track-redefinition failing))
        (ok (member 'cl-spec/specs::registration-replacement-preserves-unrelated-indexes
                    failing)))
      (testing "laws that never re-register still pass"
        (ok (not (member 'cl-spec/specs::registry-round-trips-definitions failing)))
        (ok (not (member 'cl-spec/specs::registry-clear-empties failing)))))))

(deftest half-clear-registry-is-refused-by-the-clear-law
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-half-clear-registry :seeds '(1))
    (ok (not conforming))
    (ok (equal '(cl-spec/specs::registry-clear-empties) (failing-names records))
        (prin1-to-string (failing-names records)))))

(deftest unsorted-registry-is-refused-by-the-ordering-law
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-unsorted-registry :seeds '(1))
    (ok (not conforming))
    (ok (member 'cl-spec/specs::registry-queries-return-sorted-names (failing-names records))
        (prin1-to-string (failing-names records)))))

(deftest silent-write-registry-is-refused-by-the-round-trip-law
  ;; Storage and listing are correct; only the documented return value is wrong.
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-silent-write-registry :seeds '(1))
    (ok (not conforming))
    (ok (member 'cl-spec/specs::registry-round-trips-definitions (failing-names records))
        (prin1-to-string (failing-names records)))))

(deftest sticky-spec-registry-is-refused-by-the-replacement-law
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-sticky-spec-registry :seeds '(1))
    (ok (not conforming))
    (ok (member 'cl-spec/specs::registry-writes-replace-by-name (failing-names records))
        (prin1-to-string (failing-names records)))))

(deftest name-keyed-registry-is-refused-by-the-symbol-identity-law
  (multiple-value-bind (conforming records)
      (check-registry-implementation #'make-name-keyed-registry :seeds '(1))
    (ok (not conforming))
    (ok (member 'cl-spec/specs::registry-keys-are-symbols-not-names (failing-names records))
        (prin1-to-string (failing-names records)))))

(deftest non-registry-constructor-is-refused-before-any-check
  (ok (handler-case
          (progn (check-registry-implementation
                  (lambda () (make-instance 'partial-registry)))
                 nil)
        (type-error () t))))

(deftest an-empty-run-plan-is-refused
  ;; With no seed nothing would run, and a vacuous run must not report conformance.
  ;; A malformed plan is refused before the constructor builds a single registry,
  ;; so a bad later seed cannot surface only after earlier checks executed.
  (dolist (arguments '((:seeds ()) (:seeds (1 :two)) (:seeds (1 -1)) (:trials 0)
                       ;; Fewer trials than the registration contract's three cases.
                       (:trials 2)))
    (let ((constructed 0))
      (ok (handler-case
              (progn (apply #'check-registry-implementation
                            (lambda () (incf constructed) (make-alist-registry))
                            arguments)
                     nil)
            (type-error () t))
          (prin1-to-string arguments))
      (ok (zerop constructed) (prin1-to-string arguments)))))
