;;;; eval/apply-faults.lisp
;;;;
;;;; Apply one task's limited faulty edit to a throwaway work copy.  Each fault
;;;; is an exact single-occurrence text replacement, so it cannot silently apply
;;;; to the wrong place: a missing or ambiguous anchor is a hard error and the
;;;; copy is left untouched.  The user's tree is never modified; CL_SPEC_ROOT
;;;; must point at the disposable copy.
;;;;
;;;; Environment:
;;;;   CL_SPEC_ROOT      work copy to modify (required)
;;;;   CL_SPEC_TASK_DIR  task directory holding faults.sexp (required)

(in-package #:cl-user)

(require :asdf)

(defun fault-env (name)
  (let ((value (uiop:getenv name)))
    (if (and value (plusp (length value)))
        value
        (error "~A is not set" name))))

(defun apply-one-fault (root file old new)
  "Replace OLD with NEW once in ROOT/FILE, refusing a missing or ambiguous anchor."
  (let ((path (merge-pathnames file (uiop:ensure-directory-pathname root))))
    (unless (probe-file path)
      (error "No ~A under ~A" file root))
    (let* ((text (uiop:read-file-string path :external-format :utf-8))
           (first (search old text)))
      (unless first
        (error "Fault anchor not found in ~A" file))
      (when (search old text :start2 (1+ first))
        (error "Fault anchor is not unique in ~A" file))
      (let ((updated (concatenate 'string
                                  (subseq text 0 first)
                                  new
                                  (subseq text (+ first (length old))))))
        (with-open-file (out path :direction :output :if-exists :supersede
                                  :external-format :utf-8)
          (write-string updated out))
        (format t "FAULT-APPLIED ~A~%" file)
        (finish-output)))))

(let* ((root (fault-env "CL_SPEC_ROOT"))
       (task-dir (uiop:ensure-directory-pathname (fault-env "CL_SPEC_TASK_DIR")))
       (faults (with-open-file (in (merge-pathnames "faults.sexp" task-dir))
                 (read in))))
  (dolist (fault faults)
    (destructuring-bind (&key file old new) fault
      (unless (and file old new)
        (error "A fault entry needs :FILE, :OLD and :NEW: ~S" fault))
      (apply-one-fault root file old new))))
