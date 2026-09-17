;;;; eval/acceptance-state.lisp
;;;;
;;;; Evaluator-owned acceptance check for the result-state-evidence-drop task.
;;;; It runs a small state-observing contract whose state-post must fail and
;;;; states the evidence the public projection has to keep.

(in-package #:cl-user)

(load (merge-pathnames "snapshot-loader.lisp" *load-truename*))
(load-snapshot (snapshot-root) :self-specs nil)

(defvar *acceptance-balance* 10)
(defvar *acceptance-inputs* nil)

(defun acceptance-state-target (amount)
  "Return the receipt without changing the balance, so the state-post fails."
  (declare (ignore amount))
  3)

(let ((cl-spec:*registry* (cl-spec:make-hash-table-registry)))
  (cl-spec:defgenerator acceptance-amounts ()
    (list (pop *acceptance-inputs*)))
  (cl-spec:defspec-function acceptance-state-target
    "Acceptance fixture: a declared state-post that must be violated."
    (:args (amount (range integer 1 10)))
    (:args-generator acceptance-amounts)
    (:capture (balance-before *acceptance-balance*))
    (:returns integer)
    (:state-post (= *acceptance-balance* (- balance-before amount))))
  (let* ((*acceptance-balance* 10)
         (*acceptance-inputs* '(3))
         (result (cl-spec:check-function 'acceptance-state-target :trials 1 :seed 1))
         (data (cl-spec:result-data result))
         (state (getf (getf data :failure) :state))
         (state-post (getf state :state-post))
         (ok (and (eq :failed (getf data :status))
                  (eq :state-post (getf data :failure-phase))
                  (eq :state-postcondition (getf data :failure-reason))
                  (eq :violation (getf state-post :status))
                  (eql 0 (getf state-post :index)))))
    (format t "ACCEPTANCE-RESULT result-state-evidence-drop ~A (state=~S)~%"
            (if ok "PASS" "FAIL") state)
    (finish-output)
    (uiop:quit (if ok 0 1))))
