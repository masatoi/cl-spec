;;;; eval/acceptance-capture.lisp
;;;;
;;;; Evaluator-owned acceptance check for the function-spec-capture-drop task.
;;;; It declares a capture in a fresh registry and states the projection it
;;;; expects, without consulting specs.lisp.

(in-package #:cl-user)

(load (merge-pathnames "snapshot-loader.lisp" *load-truename*))
(load-snapshot (snapshot-root) :self-specs nil)

(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
  (cl-spec:defgenerator acceptance-amounts () (list 1))
  (cl-spec:defspec-function acceptance-capture-target
    "Acceptance fixture: one declared capture binding."
    (:args (n integer))
    (:args-generator acceptance-amounts)
    (:capture (n-before n))
    (:returns integer))
  (let* ((data (cl-spec:function-spec-data 'acceptance-capture-target))
         (capture (getf data :capture))
         (ok (and (= 1 (length capture))
                  (eq 'n-before (getf (first capture) :name))
                  (equal 'n (getf (first capture) :form)))))
    (format t "ACCEPTANCE-RESULT function-spec-capture-drop ~A (capture=~S)~%"
            (if ok "PASS" "FAIL") capture)
    (finish-output)
    (uiop:quit (if ok 0 1))))
