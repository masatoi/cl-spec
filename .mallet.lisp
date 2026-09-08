;;;; .mallet.lisp
;;;;
;;;; Some test files evaluate DSL macro expansions on purpose, at the top
;;;; level or through EVAL: the framework's contract is that expansion
;;;; succeeds and running it either signals NOT-IMPLEMENTED (skeleton stubs)
;;;; or produces a real, registered spec/property/generator (implemented
;;;; behaviour) -- MACROEXPAND-1 alone cannot show either half.  The rule
;;;; stays on everywhere else.

(:mallet-config
 (:extends :default)
 (:for-paths ("tests/dsl-test.lisp"
              "tests/property-runner-test.lisp"
              "tests/introspection-test.lisp"
              "tests/self-properties-test.lisp")
   (:disable :no-eval)))
