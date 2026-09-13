;;;; api-docs.lisp
;;;;
;;;; Generated API reference.  This system is a development tool, not part of
;;;; the runtime: it walks the exported symbols of the public packages,
;;;; collects their docstrings (function, type, variable, or class slot), and
;;;; renders Markdown under docs/api/.  CI regenerates and commits the result
;;;; after every push to main (.github/workflows/docs.yml); run it by hand with
;;;; (cl-spec/api-docs:generate-api-docs).

(defpackage #:cl-spec/api-docs
  (:use #:cl)
  ;; These IMPORTS are what pull the public systems in: a package-inferred
  ;; system derives its dependencies from its DEFPACKAGE form, and this bundle
  ;; documents their exported symbols.  PUBLIC-SYSTEMS-LOADED-P uses them, so
  ;; they are not dead names.
  (:import-from #:cl-spec/src/instrument
                #:instrumentation-status)
  (:import-from #:cl-spec/specs
                #:register-specifications)
  (:import-from #:cl-spec/src/backends/check-it
                #:install-check-it-backend)
  (:export #:public-api-packages
           #:public-systems-loaded-p
           #:collect-public-api
           #:undocumented-public-symbols
           #:api-doc-files
           #:generate-api-docs))

(in-package #:cl-spec/api-docs)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; FUNCTION-LAMBDA-LIST is the only reliable way to recover a compiled
  ;; function's lambda list.  The rest of the file degrades gracefully without
  ;; it, so its absence is not fatal.
  #+sbcl (require :sb-introspect))

(defparameter +public-packages+
  '(("cl-spec" "CL-SPEC/MAIN" "cl-spec"
     "Semantic IR, validation, structured explain, introspection, registry and the DSL.")
    ("cl-spec/instrument" "CL-SPEC/INSTRUMENT" "cl-spec/instrument"
     "Runtime instrumentation that checks registered contracts at call sites.")
    ("cl-spec/specs" "CL-SPEC/SPECS" "cl-spec/specs"
     "Optional executable specifications of cl-spec's own APIs and semantic laws.")
    ("cl-spec/check-it" "CL-SPEC/SRC/BACKENDS/CHECK-IT" "cl-spec/check-it"
     "check-it based generator construction and property execution backend."))
  "Public systems, as (TITLE PACKAGE SYSTEM DESCRIPTION).

TITLE names the reference file and the index row.  PACKAGE is the package whose
external symbols are documented; it may be a nickname.")

(defparameter +kind-order+
  '(:macro :function :generic-function :accessor :class :condition :structure
    :variable :unknown)
  "Section order of the generated reference, and of its contents list.")

(defun public-api-packages ()
  "Return the documented public packages as plists.

Each plist has :TITLE, :PACKAGE, :SYSTEM and :DESCRIPTION."
  (loop for (title package system description) in +public-packages+
        collect (list :title title :package package :system system
                      :description description)))

(defun public-systems-loaded-p ()
  "Return true when every system whose API this bundle documents is loaded."
  (every #'fboundp '(instrumentation-status
                     register-specifications
                     install-check-it-backend)))

;;;; Reading documentation

(defun slot-documentation (slot)
  "Return SLOT's :documentation, or NIL when this port cannot read it."
  (declare (ignorable slot))
  #+sbcl
  (let ((reader (find-symbol "%SLOT-DEFINITION-DOCUMENTATION" '#:sb-pcl)))
    (when (and reader (fboundp reader))
      (ignore-errors (funcall reader slot))))
  #-sbcl nil)

#+sbcl
(defun slot-documentation-table ()
  "Return a hash table mapping each slot reader/writer to (CLASS-NAME . DOC)."
  (let ((table (make-hash-table :test #'eq))
        (seen (make-hash-table :test #'eq)))
    (dolist (package (list-all-packages))
      (when (cl-spec-package-p package)
        (do-symbols (symbol package)
          (when (eq (symbol-package symbol) package)
            (let ((class (and (not (gethash symbol seen))
                              (ignore-errors (find-class symbol nil)))))
              (when class
                (setf (gethash symbol seen) t)
                (dolist (slot (ignore-errors (sb-mop:class-direct-slots class)))
                  (let ((doc (slot-documentation slot)))
                    (when doc
                      (dolist (reader (sb-mop:slot-definition-readers slot))
                        (setf (gethash reader table)
                              (cons (class-name class) doc)))
                      (dolist (writer (sb-mop:slot-definition-writers slot))
                        (setf (gethash writer table)
                              (cons (class-name class) doc))))))))))))
    table))

#-sbcl
(defun slot-documentation-table ()
  "Return an empty table: slot documentation needs a MOP this port lacks."
  (make-hash-table :test #'eq))

(defun cl-spec-package-p (package)
  "Return true when PACKAGE belongs to the cl-spec checkout."
  (let ((name (package-name package)))
    (and (<= 7 (length name))
         (string= "CL-SPEC" name :end2 7))))

(defun condition-class-p (class)
  "Return true when CLASS is CONDITION or inherits from it."
  (let ((name (class-name class)))
    (and name (ignore-errors (subtypep name 'condition)) t)))

(defun symbol-kind (symbol)
  "Classify SYMBOL's public definition."
  (cond ((macro-function symbol) :macro)
        ((and (fboundp symbol)
              (typep (fdefinition symbol) 'generic-function))
         :generic-function)
        ((fboundp symbol) :function)
        ((let ((class (find-class symbol nil)))
           (cond ((null class) nil)
                 ((condition-class-p class) :condition)
                 ((typep class 'structure-class) :structure)
                 (t :class))))
        ((boundp symbol) :variable)
        (t :unknown)))

(defun symbol-documentation (symbol kind)
  "Return SYMBOL's docstring for KIND, or NIL."
  (case kind
    ((:macro :function :generic-function) (documentation symbol 'function))
    (:variable (documentation symbol 'variable))
    ((:class :condition :structure) (documentation symbol 'type))
    (t nil)))

(defun write-arglist (object stream)
  "Write OBJECT as an argument list with unqualified, downcased names.

Display only: the names are the symbols FUNCTION-LAMBDA-LIST returned, and
dropping their packages keeps implementation packages such as SB-PCL out of a
public signature."
  (cond ((keywordp object)
         (write-char #\: stream)
         (write-string (string-downcase (symbol-name object)) stream))
        ((symbolp object)
         (write-string (string-downcase (symbol-name object)) stream))
        ((consp object)
         (write-char #\( stream)
         (write-arglist (car object) stream)
         (let ((tail (cdr object)))
           (loop while (consp tail)
                 do (write-char #\Space stream)
                    (write-arglist (car tail) stream)
                    (setf tail (cdr tail)))
           (when tail
             (write-string " . " stream)
             (write-arglist tail stream)))
         (write-char #\) stream))
        (t (format stream "~S" object))))

(defun arglist-string (lambda-list)
  "Return LAMBDA-LIST printed by WRITE-ARGLIST."
  (with-output-to-string (out)
    (write-arglist lambda-list out)))

(defun function-arglist (symbol)
  "Return SYMBOL's lambda list as a string, or NIL when it cannot be read."
  (let ((function (or (macro-function symbol)
                      (and (fboundp symbol) (fdefinition symbol)))))
    (when function
      #+sbcl
      (ignore-errors
        (let ((lambda-list (sb-introspect:function-lambda-list function)))
          (when lambda-list (arglist-string lambda-list))))
      #-sbcl nil)))

(defun class-supers (symbol)
  "Return SYMBOL's direct superclass names, minus the universal defaults."
  #+sbcl
  (let ((class (find-class symbol nil)))
    (when class
      (loop for super in (ignore-errors
                           (sb-mop:class-direct-superclasses class))
            for name = (class-name super)
            unless (member name '(standard-object structure-object))
              collect (string-downcase (symbol-name name)))))
  #-sbcl nil)

(defun nonempty-string-p (value)
  "Return VALUE when it is a string with non-whitespace content."
  (and (stringp value)
       (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
       value))

(defun collect-symbol (symbol table)
  "Return the reference entry for SYMBOL, using TABLE for accessor docs."
  (let* ((name (symbol-name symbol))
         (kind (symbol-kind symbol))
         (slot (gethash symbol table))
         (function-doc (symbol-documentation symbol kind))
         (doc (or function-doc (and slot (cdr slot)))))
    (when (and slot (null function-doc))
      (setf kind :accessor))
    (list :name name
          :display (string-downcase name)
          :anchor (anchor-for name)
          :kind kind
          :kind-label (kind-label kind)
          :signature (and (member kind '(:macro :function :generic-function
                                         :accessor))
                          (function-arglist symbol))
          :supers (and (member kind '(:class :condition :structure))
                       (class-supers symbol))
          :owner (and (eq kind :accessor) slot
                      (string-downcase (symbol-name (car slot))))
          :documentation doc
          :documented-p (not (null (nonempty-string-p doc))))))

(defun collect-package-symbols (package table)
  "Return the sorted reference entries for PACKAGE's external symbols."
  (let ((entries nil))
    (do-external-symbols (symbol package)
      (push (collect-symbol symbol table) entries))
    (sort entries #'string< :key (lambda (entry) (getf entry :name)))))

(defun collect-public-api (&optional (packages (public-api-packages)))
  "Return the public API as one plist per package, each with :SYMBOLS.

Every entry in :SYMBOLS is a plist as produced by COLLECT-SYMBOL."
  (unless (public-systems-loaded-p)
    (error "Load CL-SPEC/API-DOCS through ASDF so every public system is present."))
  (let ((table (slot-documentation-table)))
    (loop for package in packages
          for home = (find-package (getf package :package))
          do (unless home
               (error "Public package ~A is not loaded." (getf package :package)))
          collect (append package
                          (list :symbols (collect-package-symbols home table))))))

(defun undocumented-public-symbols (&optional (packages (public-api-packages)))
  "Return (TITLE . NAME) for every public symbol with no documentation.

This is the check the generator runs before writing anything: an entry it would
have to leave blank is a defect, not a rendering choice."
  (loop for package in (collect-public-api packages)
        append (loop for entry in (getf package :symbols)
                     unless (getf entry :documented-p)
                       collect (cons (getf package :title)
                                     (getf entry :name)))))

;;;; Rendering Markdown

(defun anchor-for (name)
  "Return a stable in-page anchor for the symbol named NAME."
  (string-downcase
   (remove-if-not (lambda (char)
                    (or (alphanumericp char)
                        (char= char #\-)
                        (char= char #\_)))
                  name)))

(defun kind-label (kind)
  "Return the human readable label for KIND."
  (case kind
    (:macro "Macro")
    (:function "Function")
    (:generic-function "Generic function")
    (:accessor "Accessor")
    (:class "Class")
    (:condition "Condition")
    (:structure "Structure")
    (:variable "Variable")
    (t "Definition")))

(defun kind-section-title (kind)
  "Return the plural section heading for KIND."
  (case kind
    (:macro "Macros")
    (:function "Functions")
    (:generic-function "Generic functions")
    (:accessor "Accessors")
    (:class "Classes")
    (:condition "Conditions")
    (:structure "Structures")
    (:variable "Variables")
    (t "Other definitions")))

(defun title-slug (title)
  "Return TITLE as a file-name component."
  (string-downcase (substitute #\- #\/ title)))

(defun escape-inline (text)
  "Escape TEXT for use outside a code block."
  (with-output-to-string (out)
    (loop for char across text
          do (case char
               (#\< (write-string "&lt;" out))
               (#\> (write-string "&gt;" out))
               (#\& (write-string "&amp;" out))
               (t (write-char char out))))))

(defun split-docstring (text)
  "Return TEXT's first paragraph and its remainder, both trimmed."
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (break (search (format nil "~%~%") trimmed)))
    (if break
        (values (subseq trimmed 0 break)
                (string-left-trim '(#\Newline) (subseq trimmed (+ break 2))))
        (values trimmed nil))))

(defun render-docstring (text)
  "Render TEXT as a Markdown summary paragraph plus a verbatim block.

The remainder is fenced rather than reformatted because docstrings carry DSL
examples and placeholder shapes like <symbol> that Markdown would otherwise
reflow or swallow."
  (multiple-value-bind (summary body) (split-docstring text)
    (with-output-to-string (out)
      (format out "~A~%" (escape-inline summary))
      (when body
        (terpri out)
        (write-string "```text" out)
        (terpri out)
        (write-string body out)
        (terpri out)
        (write-string "```" out)
        (terpri out)))))

(defun render-meta-line (entry)
  "Return the italic kind and signature line for ENTRY."
  (with-output-to-string (out)
    (format out "*~A*" (getf entry :kind-label))
    (when (getf entry :owner)
      (format out " of `~A`" (getf entry :owner)))
    (when (getf entry :signature)
      (format out " · `~A`" (getf entry :signature)))
    (when (getf entry :supers)
      (format out " · extends ~{~A~^, ~}" (getf entry :supers)))))

(defun render-entry (entry)
  "Render one symbol ENTRY as a Markdown section."
  (with-output-to-string (out)
    (format out "<a name=\"~A\"></a>~%" (getf entry :anchor))
    (format out "### ~A~%~%" (getf entry :display))
    (format out "~A~%" (render-meta-line entry))
    (let ((doc (getf entry :documentation)))
      (when doc
        (format out "~%~A" (render-docstring doc))))))

(defun render-contents (symbols)
  "Return the per-kind contents list for the collected SYMBOLS."
  (with-output-to-string (out)
    (write-string "## Contents" out)
    (terpri out)
    (dolist (kind +kind-order+)
      (let ((group (remove-if-not (lambda (entry) (eq (getf entry :kind) kind))
                                  symbols)))
        (when group
          (format out "~%**~A**: ~{~A~^ · ~}~%"
                  (kind-section-title kind)
                  (mapcar (lambda (entry)
                            (format nil "[`~A`](#~A)"
                                    (getf entry :display) (getf entry :anchor)))
                          group)))))))

(defun render-package (package)
  "Render the Markdown reference for one collected PACKAGE plist."
  (let ((symbols (getf package :symbols)))
    (with-output-to-string (out)
      (format out "# ~A~%~%" (getf package :title))
      (format out "~A~%~%" (getf package :description))
      (format out "System `~A`, ~D exported symbols. Docstrings are reproduced ~
                   from the source; accessor entries use their class slot's ~
                   documentation, and a leading summary paragraph is followed ~
                   by the rest of the docstring verbatim.~%"
              (getf package :system) (length symbols))
      (terpri out)
      (write-string (render-contents symbols) out)
      (dolist (kind +kind-order+)
        (let ((group (remove-if-not (lambda (entry) (eq (getf entry :kind) kind))
                                    symbols)))
          (when group
            (format out "~%## ~A~%~%" (kind-section-title kind))
            (dolist (entry group)
              (write-string (render-entry entry) out)
              (terpri out))))))))

(defun render-index (packages)
  "Render the docs/api/README.md index from the collected PACKAGES."
  (with-output-to-string (out)
    (write-string "# cl-spec API reference" out)
    (terpri out) (terpri out)
    (write-string "Generated from the docstrings of cl-spec's public API by " out)
    (write-string "[`api-docs.lisp`](../../api-docs.lisp)." out)
    (terpri out)
    (write-string "Do not edit this directory by hand: the `API docs` workflow" out)
    (terpri out)
    (write-string "regenerates and commits it after every push to `main`." out)
    (terpri out) (terpri out)
    (write-string "Regenerate locally with:" out)
    (terpri out) (terpri out)
    (write-string "```lisp" out) (terpri out)
    (write-string "(asdf:load-system \"cl-spec/api-docs\")" out) (terpri out)
    (write-string "(cl-spec/api-docs:generate-api-docs)" out) (terpri out)
    (write-string "```" out) (terpri out) (terpri out)
    (write-string "| Package | System | Symbols | Reference |" out) (terpri out)
    (write-string "|---|---|---:|---|" out) (terpri out)
    (dolist (package packages)
      (let ((slug (title-slug (getf package :title))))
        (format out "| `~A` | `~A` | ~D | [`~A.md`](~A.md) |~%"
                (getf package :title) (getf package :system)
                (length (getf package :symbols)) slug slug)))))

(defun api-doc-files (&optional (packages (public-api-packages)))
  "Return (RELATIVE-PATH . MARKDOWN) pairs for the whole reference.

Paths are relative to the cl-spec checkout; the index comes first.  Signals
when a public symbol has no documentation, so a run can never publish a
reference with a silent hole."
  (let* ((collected (collect-public-api packages))
         (missing (loop for package in collected
                        append (loop for entry in (getf package :symbols)
                                     unless (getf entry :documented-p)
                                       collect (format nil "~A:~A"
                                                       (getf package :title)
                                                       (getf entry :name))))))
    (when missing
      (error "Public API symbols without documentation:~%~{  ~A~%~}" missing))
    (cons (cons "docs/api/README.md" (render-index collected))
          (loop for package in collected
                collect (cons (format nil "docs/api/~A.md"
                                      (title-slug (getf package :title)))
                              (render-package package))))))

;;;; Writing the reference

(defun project-root ()
  "Return the cl-spec checkout root, or the current directory."
  (or (ignore-errors (asdf:system-source-directory "cl-spec"))
      *default-pathname-defaults*))

(defun write-text-file (path text)
  "Write TEXT to PATH as UTF-8 and return PATH."
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream))
  path)

(defun generate-api-docs (&key (root (project-root)))
  "Write the API reference under ROOT and return the written pathnames.

ROOT defaults to the cl-spec checkout.  Signals when a public symbol has no
documentation, so a partial reference is never written."
  (loop for (relative . content) in (api-doc-files)
        for path = (merge-pathnames relative root)
        collect (write-text-file path content)))
