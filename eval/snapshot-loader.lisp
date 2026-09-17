;;;; eval/snapshot-loader.lisp
;;;;
;;;; Shared loader: register and load the cl-spec source snapshot named by the
;;;; CL_SPEC_ROOT environment variable.  The snapshot has no version-control
;;;; history, so a fresh process always compiles what the work copy holds.

(in-package #:cl-user)

(require :asdf)

(defun snapshot-root ()
  "Return CL_SPEC_ROOT, signalling when it is unset or empty."
  (let ((value (uiop:getenv "CL_SPEC_ROOT")))
    (if (and value (plusp (length value)))
        value
        (error "CL_SPEC_ROOT is not set"))))

(defun load-snapshot (root &key (self-specs t))
  "Register and load the cl-spec snapshot at ROOT.

SELF-SPECS loads the optional bundle as well; an evaluator-owned acceptance
check passes NIL so it stays independent of the bundle and still loads in a
condition-A work copy, where the bundle is absent."
  (let ((asd (merge-pathnames "cl-spec.asd" (uiop:ensure-directory-pathname root))))
    (unless (probe-file asd)
      (error "No cl-spec.asd under ~A" root))
    (asdf:load-asd asd)
    (asdf:load-system "cl-spec/check-it")
    (when self-specs
      (asdf:load-system "cl-spec/specs"))))
