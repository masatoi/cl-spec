;;;; src/utils/source-location.lisp
;;;;
;;;; Definition-site metadata (specification §31).  A source location is an
;;;; opaque plist so that richer position information can be added later
;;;; without breaking the introspection API.

(defpackage #:cl-spec/src/utils/source-location
  (:use #:cl)
  (:export #:current-source-location
           #:source-location-file
           #:source-location-package))

(in-package #:cl-spec/src/utils/source-location)

(defun current-source-location ()
  "Return a source location plist describing where this form is being read.

Call this at macroexpansion time and embed the result in the expansion so that
the location survives into the compiled image.  The plist carries:

  :FILE     namestring of the file being compiled or loaded, or NIL
  :PACKAGE  name of *PACKAGE* at expansion time

Treat the result as opaque and read it with the accessors in this package."
  (list :file (let ((truename (or *compile-file-truename* *load-truename*)))
                (and truename (namestring truename)))
        :package (package-name *package*)))

(defun source-location-file (location)
  "Return the file namestring recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned."
  (getf location :file))

(defun source-location-package (location)
  "Return the package name recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned."
  (getf location :package))
