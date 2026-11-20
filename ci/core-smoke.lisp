;;;; ci/core-smoke.lisp

(defpackage #:cl-spec/ci/core-smoke
  (:use #:cl)
  (:import-from #:cl-spec #:*registry* #:make-hash-table-registry #:defspec #:validp
                #:defspec-function #:check-call #:call-check-result-status))

(in-package #:cl-spec/ci/core-smoke)

(defun quotient-and-remainder (n)
  (floor n 3))

(defun check-core ()
  (let ((*registry* (make-hash-table-registry)))
    (defspec small-index (range integer 0 2))
    (assert (validp 'small-index 2))
    (assert (not (validp 'small-index 3)))
    (defspec-function quotient-and-remainder
      (:args (n integer))
      (:returns (values integer (range integer 0 2)))
      (:post-values (q r) (= n (+ (* 3 q) r))))
    (assert (eq :passed (call-check-result-status (check-call 'quotient-and-remainder '(7)))))
    (assert (null (find-package "CHECK-IT")))))

(check-core)
