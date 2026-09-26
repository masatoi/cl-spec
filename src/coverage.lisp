;;;; src/coverage.lisp
(defpackage #:cl-spec/src/coverage
  (:use #:cl)
  (:import-from #:cl-spec/src/registry #:*registry*)
  (:import-from #:cl-spec/src/coverage-plist #:plist-coverage-schema)
  (:export #:coverage-schema #:coverage-data #:coverage-inputs #:coverage-bindings
           #:normalize-coverage-options #:copy-coverage-data
           #:invalid-coverage-options #:invalid-coverage-options-reason
           #:unsupported-coverage-operation #:unsupported-coverage-operation-reason
           #:backend-coverage-protocol #:backend-coverage-capabilities))
(in-package #:cl-spec/src/coverage)

(define-condition invalid-coverage-options (error)
  ((reason :initarg :reason :reader invalid-coverage-options-reason))
  (:documentation "Malformed or unsupported coverage options.")
  (:report (lambda (c s) (format s "Invalid coverage options: ~A"
                                (invalid-coverage-options-reason c)))))

(defgeneric invalid-coverage-options-reason (condition)
  (:documentation "Return the reason coverage options were refused."))

(define-condition unsupported-coverage-operation (error)
  ((reason :initarg :reason :reader unsupported-coverage-operation-reason))
  (:documentation "The requested execution path cannot perform this coverage operation.")
  (:report (lambda (c s) (format s "Unsupported coverage operation: ~A"
                                (unsupported-coverage-operation-reason c)))))

(defgeneric unsupported-coverage-operation-reason (condition)
  (:documentation "Return the unsupported coverage operation's reason."))

(defun bounded-list-p (value limit)
  "Recognize proper finite lists without following unbounded or circular data."
  (loop repeat limit while (consp value) do (setf value (cdr value))
        finally (return (null value))))

(defun copy-coverage-data (data)
  "Copy protocol-owned acyclic lists and strings without copying application objects."
  (typecase data
    (cons (loop for value in data collect (copy-coverage-data value)))
    (string (copy-seq data))
    (t data)))

(defun normalize-coverage-options (options &key direct)
  "Validate closed bounded options and return an independent canonical plist."
  (unless options (return-from normalize-coverage-options nil))
  (flet ((refuse (reason) (error 'invalid-coverage-options :reason reason)))
    (unless (and (bounded-list-p options 8) (evenp (length options)))
      (refuse :malformed-options))
    (let ((seen nil))
      (loop for key in options by #'cddr
            do (unless (and (member key '(:mode :extra-keys :dimension-limit :depth-limit))
                            (not (member key seen)))
                 (refuse :unknown-or-duplicate-option))
               (push key seen)))
    (let* ((mode (getf options :mode))
           (limit (getf options :dimension-limit 1024))
           (depth (getf options :depth-limit 32))
           (keys (getf options :extra-keys '(:coverage-extra :probe-extra))))
      (unless (and (member mode '(:observe :exercise))
                   (typep limit '(integer 1 65536)) (typep depth '(integer 1 256)))
        (refuse :invalid-mode-or-limit))
      (when (and (eq mode :observe)
                 (loop for key in options by #'cddr thereis (eq key :extra-keys)))
        (refuse :extra-keys-require-exercise))
      (when (and direct (eq mode :exercise))
        (error 'unsupported-coverage-operation :reason :direct-check-does-not-generate))
      (unless (and (bounded-list-p keys 64) (every #'keywordp keys)
                   (= (length keys) (length (remove-duplicates keys))))
        (refuse :invalid-extra-keys))
      (list :mode mode :dimension-limit limit :depth-limit depth
            :extra-keys (when (eq mode :exercise) (copy-list keys))))))

(defgeneric coverage-inputs (definition)
  (:documentation "Return ordered (name spec) roots for the definition's call arguments."))

(defgeneric coverage-bindings (definition arguments)
  (:documentation "Return supplied argument bindings without validation or application code."))

(defgeneric coverage-data (result)
  (:documentation "Return copied saved coverage facts without executing or resolving definitions."))

(defgeneric backend-coverage-protocol (backend)
  (:documentation "Return :COVERAGE-V1 when ordinary generation is explicitly instrumented.")
  (:method ((backend t)) nil))

(defgeneric backend-coverage-capabilities (backend schema options)
  (:documentation "Describe generator capabilities separately from observed coverage.")
  (:method ((backend t) schema options)
    (declare (ignore options))
    (loop for d in (getf schema :dimensions)
          collect (list :id (getf d :id) :generation :unknown :targeting :unknown
                        :reason :unmeasured-backend))))

(defun coverage-schema (definition &key (registry *registry*))
  "Describe statically observable input dimensions of a property or function spec."
  (copy-coverage-data (plist-coverage-schema (coverage-inputs definition) registry 1024 32)))
