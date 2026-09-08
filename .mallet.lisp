;;;; .mallet.lisp
;;;;
;;;; tests/dsl-test.lisp evaluates the DSL macros' expansions on purpose: the
;;;; skeleton's contract is that expansion succeeds while the expansion's
;;;; execution signals NOT-IMPLEMENTED, and MACROEXPAND-1 alone cannot show the
;;;; second half.  The rule stays on everywhere else.

(:mallet-config
 (:extends :default)
 (:for-paths ("tests/dsl-test.lisp")
   (:disable :no-eval)))
