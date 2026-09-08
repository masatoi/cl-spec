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
