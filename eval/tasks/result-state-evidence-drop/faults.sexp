((:file "src/property-runner.lisp"
  :old "       (when state (list :state state))))))
"
  :new "       (when (and state nil) (list :state state))))))
"))
