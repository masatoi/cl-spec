;;;; eval/acceptance-registry.lisp
;;;;
;;;; Evaluator-owned acceptance check for the registry-stale-index task.  It is
;;;; independent of specs.lisp: it calls the public registry API directly and
;;;; states the expected index state from the declared input, so a candidate
;;;; cannot make it pass by weakening a self-specification.

(in-package #:cl-user)

(load (merge-pathnames "snapshot-loader.lisp" *load-truename*))
(load-snapshot (snapshot-root) :self-specs nil)

(defun acceptance-property (name)
  (make-instance 'cl-spec:property :name name :arguments '((x integer))
                 :function (lambda (x) (declare (ignore x)) t)))

(let* ((registry (cl-spec:make-hash-table-registry))
       (subject 'acceptance-subject)
       (sentinel 'acceptance-sentinel)
       (shared-target 'acceptance-shared-target)
       (old-target 'acceptance-old-target)
       (new-target 'acceptance-new-target)
       (shared-tag 'acceptance-shared-tag)
       (old-tag 'acceptance-old-tag)
       (new-tag 'acceptance-new-tag))
  (cl-spec:registry-register-property registry sentinel (acceptance-property sentinel)
    :targets (list shared-target) :tags (list shared-tag))
  (cl-spec:registry-register-property registry subject (acceptance-property subject)
    :targets (list shared-target old-target) :tags (list shared-tag old-tag))
  (let ((replacement (acceptance-property subject))
        (names-before (cl-spec:list-properties registry)))
    (cl-spec:registry-register-property registry subject replacement
      :targets (list new-target shared-target) :tags (list new-tag shared-tag))
    (let ((ok (and (eq replacement
                       (nth-value 0 (cl-spec:registry-find-property registry subject)))
                   (= (length names-before) (length (cl-spec:list-properties registry)))
                   (null (set-exclusive-or names-before
                                           (cl-spec:list-properties registry)))
                   (null (cl-spec:properties-for old-target registry))
                   (null (cl-spec:properties-with-tag old-tag registry))
                   (member subject (cl-spec:properties-for new-target registry))
                   (member subject (cl-spec:properties-for shared-target registry))
                   (member sentinel (cl-spec:properties-for shared-target registry))
                   (member subject (cl-spec:properties-with-tag new-tag registry))
                   (member sentinel (cl-spec:properties-with-tag shared-tag registry)))))
      (format t "ACCEPTANCE-RESULT registry-stale-index ~A~%" (if ok "PASS" "FAIL"))
      (finish-output)
      (uiop:quit (if ok 0 1)))))
