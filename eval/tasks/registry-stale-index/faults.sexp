((:file "src/registry.lisp"
  :old "    (let ((previous (gethash name (registry-properties registry))))
      (when previous
        (unindex-property registry name
                          (property-entry-targets previous)
                          (property-entry-tags previous))))
    (setf (gethash name (registry-properties registry))
"
  :new "    (setf (gethash name (registry-properties registry))
"))
