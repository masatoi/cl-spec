;;;; src/dsl.lisp
;;;;
;;;; Surface macros (specification §37).  The macros are syntax sugar only:
;;;; they capture the source form and location and hand everything else to the
;;;; normalizer and the registry.  Keeping them thin is what lets the DSL
;;;; change without disturbing the Semantic IR or the introspection API.
;;;;
;;;; Each macro expands successfully even while the normalizer is a stub, so a
;;;; file using the DSL still compiles; the NOT-IMPLEMENTED condition is
;;;; signalled when the expansion runs.

(defpackage #:cl-spec/src/dsl
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:invalid-property-form
                #:invalid-function-spec-form)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:register-spec)
  (:import-from #:cl-spec/src/property
                #:property
                #:register-property)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:register-function-spec)
  (:import-from #:cl-spec/src/utils/source-location
                #:current-source-location)
  (:export #:defspec
           #:defspec-function
           #:defproperty
           #:defgenerator))

(in-package #:cl-spec/src/dsl)

(defmacro defspec (name form)
  "Define a spec named NAME from spec DSL FORM.

FORM is normalized into a Semantic IR object and registered in *REGISTRY*.
The original form and the definition site are kept on the resulting spec.

  (defspec positive-integer
    (and integer (range 1 *)))"
  (let ((location (current-source-location)))
    `(register-spec ',name
                    (normalize-spec-form ',form
                                         :name ',name
                                         :source-location ',location))))

(defparameter *function-spec-clause-keywords* '(:args :pre :returns :post)
  "Clause heads DEFSPEC-FUNCTION accepts in the MVP (specification §17, §73.1 D1).

:SIGNALS is deliberately absent.  §17 lists it as something a function spec
should eventually describe, and the checker cannot honour it yet, so a form
using it is refused rather than accepted with that half of the contract
silently dropped.")

(defun function-spec-error (form reason)
  "Signal INVALID-FUNCTION-SPEC-FORM for FORM with REASON."
  (error 'invalid-function-spec-form :form form :reason reason))

(defun proper-list-p (object)
  "Return true when OBJECT is a proper list.

A dotted clause is not one, and nothing downstream survives it: (:args . a)
reached DOLIST as a non-list and gave a bare TYPE-ERROR instead of the
condition this parser promises, and (:pre . b) expanded into (AND . B), which
is not a form at all."
  (and (listp object)
       (null (cdr (last object)))))

(defun lambda-list-keyword-name-p (object)
  "Return true when OBJECT is a symbol whose name begins with an ampersand."
  (let ((name (and object (symbolp object) (symbol-name object))))
    (and name (plusp (length name)) (char= #\& (char name 0)))))

(defun collect-result-symbols (tree)
  "Return the distinct bindable symbols named \"RESULT\" appearing in TREE.

:POST names the return value with an unqualified RESULT (§17), which the reader
has already interned into the definition's own package by the time this macro
runs.  Binding the symbol found here, rather than one this code interns, keeps
the DSL working in any package without INTERN, which §60 forbids.

Bindable is the operative word.  Matching on the name alone also caught the
keyword :RESULT, which is an ordinary plist key: a :POST reading
(getf entries :result) had it lifted into the lambda list, where SBCL refused
it, and one using both spellings was rejected with a message claiming the
contract named the return value twice."
  (let ((found '()))
    (labels ((walk (node)
               (cond ((consp node)
                      (walk (car node))
                      (walk (cdr node)))
                     ((and node
                           (symbolp node)
                           (not (constantp node))
                           (string= (symbol-name node) "RESULT"))
                      (pushnew node found)))))
      (walk tree))
    found))

(defun function-spec-result-symbol (post-forms whole)
  "Return the symbol :POST uses for the return value, or NIL when it uses none.

Signals INVALID-FUNCTION-SPEC-FORM when POST-FORMS name two different RESULT
symbols, because only one of them could be bound and the other would read as an
unrelated free variable."
  (let ((candidates (collect-result-symbols post-forms)))
    (when (rest candidates)
      (function-spec-error
       whole
       (format nil "~S names the return value with more than one RESULT symbol; ~
only one of them can be bound"
               candidates)))
    (first candidates)))

(defun parse-function-spec-clauses (name clauses whole)
  "Split CLAUSES into (values DOCUMENTATION ARGS PRE RETURNS POST).

Every clause is checked here rather than at check time, so a contract the
checker could not honour never reaches the registry.  A NIL RETURNS therefore
means the contract named no return spec: (:returns nil) is refused, so the two
cannot be confused."
  (unless (and name (symbolp name) (not (keywordp name)))
    (function-spec-error whole "the specified function must be named by a symbol"))
  (let ((documentation nil)
        (seen '())
        (args nil)
        (pre nil)
        (returns nil)
        (post nil))
    ;; No "and there is more after it" guard, unlike PARSE-PROPERTY-BODY: a
    ;; lone string there is the predicate, so consuming it would leave the
    ;; property with no body.  DEFSPEC-FUNCTION has no body forms and a string
    ;; can never be a clause, so a leading one is documentation whether or not
    ;; anything follows -- and refusing (defspec-function ping "Ping.") while
    ;; accepting both (defspec-function ping) and the same form with a clause
    ;; after the string is an inconsistency, not a check.
    (when (stringp (first clauses))
      (setf documentation (pop clauses)))
    (dolist (clause clauses)
      (unless (and (consp clause) (keywordp (first clause)))
        (function-spec-error clause "expected a clause headed by a keyword"))
      (unless (proper-list-p clause)
        (function-spec-error clause "a clause must be a proper list"))
      (let ((head (first clause)))
        (unless (member head *function-spec-clause-keywords*)
          (function-spec-error
           clause
           (format nil "~S is not supported; DEFSPEC-FUNCTION accepts ~{~S~^, ~}"
                   head *function-spec-clause-keywords*)))
        (when (member head seen)
          (function-spec-error clause (format nil "~S appears more than once" head)))
        (push head seen)
        (ecase head
          (:args (setf args (rest clause)))
          (:pre (setf pre (rest clause)))
          (:post (setf post (rest clause)))
          (:returns
           (unless (= 2 (length clause))
             (function-spec-error clause ":returns takes exactly one spec form"))
           (let ((form (second clause)))
             (when (and (consp form) (eq 'values (first form)))
               (function-spec-error
                clause
                "multiple values are not supported; :returns describes one value"))
             (when (null form)
               ;; NIL as a type specifier is the type with no members, so this
               ;; contract reports every return value as a violation --
               ;; including the NIL its author meant.
               ;; A plain string, not a format control: FUNCTION-SPEC-ERROR
               ;; stores it and the report prints it with ~A, so a ~ here
               ;; would reach the reader literally.
               (function-spec-error
                clause
                "nothing satisfies the empty type NIL; write NULL instead"))
             (setf returns form))))))
    (values documentation args pre returns post)))

(defun parse-function-spec-arguments (args whole)
  "Return ARGS unchanged after refusing the :ARGS syntax §17 defers.

The MVP checks required positional parameters only.  A lambda list keyword is
named in the refusal rather than dropped, because a contract that quietly
ignored &KEY would report a verified result for arguments nothing generated --
and it is checked in the parameter position as well as on its own, because
(&optional integer) reads as a well formed pair whose parameter is named
&OPTIONAL.  That registered, and reported :PASSED over 25 trials, for a
signature nothing had checked.

A parameter name also has to be bindable: the :PRE and :POST predicates are
compiled into lambdas over these names, and a constant such as T emitted into a
lambda list is a compiler error about a form the author never wrote."
  (let ((variables '()))
    (dolist (entry args)
      (when (lambda-list-keyword-name-p entry)
        (function-spec-error
         whole
         (format nil "~S is not supported; :args takes required parameters only"
                 entry)))
      (unless (and (consp entry) (proper-list-p entry) (= 2 (length entry)))
        (function-spec-error entry "expected (parameter spec-form)"))
      (let ((name (first entry)))
        (when (lambda-list-keyword-name-p name)
          (function-spec-error
           whole
           (format nil "~S is not supported; :args takes required parameters only"
                   name)))
        (unless (and name (symbolp name) (not (keywordp name)))
          (function-spec-error entry "expected (parameter spec-form)"))
        (when (constantp name)
          (function-spec-error
           entry
           (format nil "~S names a constant and cannot be bound as a parameter"
                   name)))
        (when (member name variables)
          (function-spec-error entry "the same parameter is specified twice"))
        (push name variables)))
    args))

(defun expand-function-spec-definition (whole name clauses source-location)
  "Return the form DEFSPEC-FUNCTION expands into.

Like DEFPROPERTY's expander this runs at macroexpansion time, because the :PRE
and :POST forms have to be compiled into real functions: §60 forbids runtime
EVAL, so a contract kept only as a list could be read but never checked."
  (multiple-value-bind (documentation args pre returns post)
      (parse-function-spec-clauses name clauses whole)
    (parse-function-spec-arguments args whole)
    (when (collect-result-symbols pre)
      (function-spec-error
       whole ":pre runs before the call, so it cannot refer to RESULT"))
    (let ((variables (mapcar #'first args))
          (result (or (function-spec-result-symbol post whole) (gensym "RESULT"))))
      (when (member result variables)
        ;; The :POST predicate binds RESULT ahead of the parameters, so a
        ;; parameter of the same name produced (LAMBDA (RESULT RESULT) ...)
        ;; and a compiler error about a lambda list the author never wrote.
        (function-spec-error
         whole
         (format nil "~S is both a parameter and the name :post uses for the ~
return value"
                 result)))
      `(register-function-spec
        (make-instance 'function-spec
                       :name ',name
                       :argument-specs
                       (list ,@(loop for (variable form) in args
                                     collect `(list ',variable
                                                    (normalize-spec-form ',form))))
                       :return-spec ,(when returns `(normalize-spec-form ',returns))
                       :preconditions ',pre
                       :postconditions ',post
                       :precondition-function
                       ,(when pre
                          `(lambda ,variables
                             (declare (ignorable ,@variables))
                             (and ,@pre)))
                       :postcondition-function
                       ,(when post
                          `(lambda (,result ,@variables)
                             (declare (ignorable ,result ,@variables))
                             (and ,@post)))
                       :documentation ,documentation
                       :source-form ',whole
                       :source-location ',source-location)))))

(defmacro defspec-function (&whole whole name &body clauses)
  "Attach a contract to the existing function NAME without redefining it.

CLAUSES may start with a docstring, then any of (:ARGS (PARAMETER SPEC) ...),
(:PRE FORM ...), (:RETURNS SPEC) and (:POST FORM ...), each at most once.  :PRE
sees the parameters, :POST sees them and RESULT, the value the call returned.

The MVP checks required positional parameters and one return value.  Anything
else -- a lambda list keyword, (:returns (values ...)), an unknown clause such
as (:signals ...) -- signals INVALID-FUNCTION-SPEC-FORM rather than registering
a contract whose unchecked half would still be reported as verified
(specification §17, §73.1 D1).

  (defspec-function ranged-random
    (:args (start integer) (end integer))
    (:pre (< start end))
    (:returns integer)
    (:post (and (>= result start) (< result end))))"
  (expand-function-spec-definition whole name clauses (current-source-location)))

(defparameter *property-option-keywords* '(:about :kind :tags :trials :shrink)
  "Keywords that may head an option clause in a DEFPROPERTY body.")

(defun parse-property-body (body)
  "Split a DEFPROPERTY BODY into (values DOCUMENTATION OPTIONS PREDICATE-FORMS).

A leading string is documentation unless it is the entire body.  Option clauses
are conses headed by one of *PROPERTY-OPTION-KEYWORDS*, and the first form that
is not one ends them: an unrecognised keyword clause becomes part of the
predicate rather than being silently dropped, so adding a keyword later cannot
quietly swallow an existing property's first body form."
  (let ((documentation nil)
        (options '())
        (forms body))
    (when (and (stringp (first forms)) (rest forms))
      (setf documentation (first forms)
            forms (rest forms)))
    (loop while (and (consp (first forms))
                     (member (first (first forms)) *property-option-keywords*))
          do (push (pop forms) options))
    (values documentation (nreverse options) forms)))

(defun option-clause (options keyword)
  "Return the clause in OPTIONS headed by KEYWORD, or NIL."
  (find keyword options :key #'first))

(defun check-single-value-clause (clause)
  "Signal INVALID-PROPERTY-FORM when CLAUSE carries more than the one value its
keyword accepts.

(:kind :invariant), (:trials ...) and (:shrink ...) each take exactly one
value; a clause with an extra element, e.g.
(:trials (:smoke 5) (:normal 200)) -- a plausible mis-write for a two profile
:TRIALS plist -- would otherwise pass CLAUSE's well formed first value through
while silently dropping the rest."
  (when (and clause (cddr clause))
    (error 'invalid-property-form
           :form clause
           :reason (format nil "~S takes exactly one value, but ~S was given"
                            (first clause) clause))))

(defun trials-plist-p (value)
  "Return true when VALUE is a well formed :TRIALS plist.

A well formed plist alternates a profile keyword and its integer trial count,
for example (:SMOKE 5 :NORMAL 200).  (:TRIALS 25) -- a plausible mis-write for
a flat trial count -- is not one: VALUE is 25 here, not a list at all, and
would otherwise reach RESOLVE-TRIALS's GETF and signal an unrelated
SIMPLE-TYPE-ERROR."
  (and (listp value)
       (evenp (length value))
       (loop for (profile count) on value by #'cddr
             always (and (keywordp profile) (integerp count)))))

(defun expand-property-definition (whole name arguments body source-location)
  "Return the form DEFPROPERTY expands into.

Unlike the other expanders this runs at macroexpansion time, because the
predicate has to be compiled into a real function rather than kept as a list."
  (multiple-value-bind (documentation options forms) (parse-property-body body)
    (let ((shrink-clause (option-clause options :shrink))
          (kind-clause (option-clause options :kind))
          (trials-clause (option-clause options :trials)))
      (check-single-value-clause shrink-clause)
      (check-single-value-clause kind-clause)
      (check-single-value-clause trials-clause)
      (when (and trials-clause (not (trials-plist-p (second trials-clause))))
        (error 'invalid-property-form
               :form trials-clause
               :reason "expected a plist, e.g. (:trials (:smoke 5 :normal 100))"))
      `(register-property
        (make-instance 'property
                       :name ',name
                       :arguments (list ,@(loop for (variable form) in arguments
                                                collect `(list ',variable
                                                               (normalize-spec-form ',form))))
                       :targets ',(rest (option-clause options :about))
                       :kind ',(second kind-clause)
                       :tags ',(rest (option-clause options :tags))
                       :trials ',(second trials-clause)
                       :documentation ,documentation
                       :body ',forms
                       :source-form ',whole
                       :source-location ',source-location
                       :metadata (list :shrink ,(if shrink-clause (second shrink-clause) t))
                       :function (lambda ,(mapcar #'first arguments)
                                   ;; Not every argument is necessarily read by
                                   ;; the predicate body (e.g. a property about
                                   ;; a function's return value alone), and the
                                   ;; project's CI gate is a zero warning
                                   ;; compile.
                                   (declare (ignorable ,@(mapcar #'first arguments)))
                                   ,@forms))))))

(defmacro defproperty (&whole whole name arguments &body body)
  "Define a property named NAME over generated ARGUMENTS.

ARGUMENTS is a list of (VARIABLE SPEC-FORM) bindings.  BODY may start with a
docstring, then option clauses (:ABOUT ...), (:KIND ...), (:TAGS ...),
(:TRIALS ...) and (:SHRINK ...), followed by the forms of the predicate.  A NIL
result or a signalled condition counts as a failure.

  (defproperty addition-preserves-order
      ((x positive-integer) (y positive-integer))
    (:about +)
    (:kind :monotonicity)
    (> (+ x y) x))"
  (expand-property-definition whole name arguments body (current-source-location)))

(defun expand-generator-definition (name lambda-list body source-location)
  "Register a user-defined generator built from a DEFGENERATOR form.

Not implemented yet."
  (declare (ignore name lambda-list body source-location))
  (error 'not-implemented :operator 'defgenerator))

(defmacro defgenerator (name lambda-list &body body)
  "Define a custom generator named NAME (specification §11).

Use this when a spec cannot express how values should be produced, for example
when generation must satisfy a global invariant.

  (defgenerator small-integer ()
    (random 100))"
  (let ((location (current-source-location)))
    `(expand-generator-definition ',name ',lambda-list ',body ',location)))
