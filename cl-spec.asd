;;;; cl-spec.asd

(asdf:defsystem "cl-spec"
  :class :package-inferred-system
  :description "Executable semantic IR and property framework for Common Lisp programs"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec/main")
  :in-order-to ((test-op (test-op "cl-spec/tests"))))

(asdf:defsystem "cl-spec/check-it"
  :description "check-it based generator and property execution backend for cl-spec"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec"
               "check-it"
               "cl-spec/src/backends/check-it"))

(asdf:defsystem "cl-spec/instrument"
  :description "Runtime function instrumentation for cl-spec function specs"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec"
               "cl-spec/src/instrument"))

;;; CL-SPEC/EXAMPLES/STRUCTURED-DATA is an inferred subsystem of the
;;; package-inferred primary system above: examples/structured-data.lisp defines
;;; package CL-SPEC/EXAMPLES/STRUCTURED-DATA, and ASDF derives the system and its
;;; dependencies from that file.  Declaring it again here would be ignored (ASDF
;;; prefers the inferred subsystem whenever the system name maps to an existing
;;; source file), so its only dependency beyond cl-spec/main -- the check-it
;;; generator backend -- is declared by the bare :IMPORT-FROM in the example's
;;; own DEFPACKAGE.
