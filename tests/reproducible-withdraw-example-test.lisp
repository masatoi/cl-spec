;;;; tests/reproducible-withdraw-example-test.lisp
(defpackage #:cl-spec/tests/reproducible-withdraw-example-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:ok)
  (:import-from #:cl-spec/main)
  (:import-from #:cl-spec/examples/reproducible-withdraw))
(in-package #:cl-spec/tests/reproducible-withdraw-example-test)

(deftest reproducible-withdraw-example
  (let* ((package (or (find-package "CL-SPEC/EXAMPLES/REPRODUCIBLE-WITHDRAW")
                      (error "Example is not implemented")))
         (registry (funcall (find-symbol "MAKE-EXAMPLE-REGISTRY" package))))
    (funcall (find-symbol "REGISTER-EXAMPLE!" package) registry)
    (let ((data (funcall (find-symbol "DEMO-RECHECK" package) registry)))
      (ok (eq :failed (getf data :status)))
      (ok (equal '(1 7 1) (getf data :shrunk-recipe)))
      (ok (eq :same-failure (getf data :recheck)))
      (ok (= 2 (getf data :artifact-version)))))
  (ok t))