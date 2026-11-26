;;;; ci/definitions-smoke.lisp

(defpackage #:cl-spec/ci/definitions-smoke
  (:use #:cl)
  (:import-from #:cl-spec/definitions
                #:defspec #:defspec-function #:defproperty #:defgenerator
                #:*registry* #:make-hash-table-registry #:find-spec
                #:find-function-spec #:find-property #:find-generator #:register-state-observer)
  (:export #:check-definitions))

(in-package #:cl-spec/ci/definitions-smoke)

(defun assert-definitions-only ()
  "Check that loading and registering definitions leaves the checking systems unloaded."
  (dolist (name '("CL-SPEC" "CL-SPEC/SRC/VALIDATOR" "CL-SPEC/SRC/EXECUTION"
                  "CL-SPEC/SRC/GENERATOR" "CL-SPEC/SRC/PROPERTY-RUNNER"
                  "CL-SPEC/SRC/FUNCTION-SPEC" "CL-SPEC/SRC/STATE-FRAME"
                  "CL-SPEC/SRC/FIXTURE-EXECUTION" "CL-SPEC/SRC/COUNTEREXAMPLE"
                  "CL-SPEC/SRC/UTILS/ARTIFACT-VALUES" "CHECK-IT"))
    (assert (not (find-package name)) () "~A was loaded by the definitions system." name)))

(defun probe-target (value)
  (1+ value))

(defun core-symbol (name)
  "Resolve a public symbol after the full system has been loaded."
  (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
    (assert (eq :external status))
    symbol))

(defun check-definitions ()
  "Register contracts in a fresh definitions image, then check one in the full image."
  (assert-definitions-only)
  (let ((*registry* (make-hash-table-registry))
        (effects nil))
    (defgenerator probe-recipes ()
      (push :draw effects)
      3)
    (defspec probe-input (range integer 1 9) (:generator probe-recipes))
    (defproperty probe-property ((value probe-input))
      (push :property effects)
      (plusp value))
    (register-state-observer :probe-state :version 1
                             :snapshot (constantly nil)
                             :compare (constantly nil)
                             :project (lambda (snapshot key)
                                        (declare (ignore snapshot key))
                                        (values nil nil))
                             :source '(:probe-state))
    (defspec-function probe-target
      (:args (value probe-input))
      (:returns (range integer 2 10))
      (:post (= result (1+ value)))
      (:modifies (:probe-state value))
      (:fixture
        (:isolation :fresh)
        (:version 1)
        (:recipe (recipe probe-input))
        (:setup (context) (push :setup effects) (list recipe))
        (:cleanup (context) (push :cleanup effects))))
    (let ((contract (find-function-spec 'probe-target)))
      (assert contract)
      (assert (find-generator 'probe-recipes))
      (assert (find-spec 'probe-input))
      (assert (find-property 'probe-property))
      (assert (null effects))
      (assert-definitions-only)
      (asdf:load-system "cl-spec")
      (dolist (name '("DEFSPEC" "DEFSPEC-FUNCTION" "DEFPROPERTY" "DEFGENERATOR" "*REGISTRY*"))
        (assert (eq (core-symbol name) (find-symbol name "CL-SPEC/DEFINITIONS"))))
      (assert (eq contract (funcall (core-symbol "FIND-FUNCTION-SPEC") 'probe-target)))
      (let* ((result (funcall (core-symbol "CHECK-FIXTURE") 'probe-target 3))
             (data (funcall (core-symbol "FIXTURE-CHECK-DATA") result)))
        (assert (eq :passed (getf data :status)))
        (assert (equal '(:cleanup :setup) effects)))
      (assert (null (find-package "CHECK-IT")))))
  t)
