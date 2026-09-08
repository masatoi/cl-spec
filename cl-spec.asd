(defsystem "cl-spec"
  :version "0.1.0"
  :author ""
  :license ""
  :depends-on ()
  :components ((:module "src"
                :components
                ((:file "main"))))
  :description ""
  :in-order-to ((test-op (test-op "cl-spec/tests"))))

(defsystem "cl-spec/tests"
  :author ""
  :license ""
  :depends-on ("cl-spec"
               "rove")
  :components ((:module "tests"
                :components
                ((:file "main"))))
  :description "Test system for cl-spec"
  :perform (test-op (op c) (symbol-call :rove :run c)))
