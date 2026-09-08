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
                #:invalid-property-form)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:register-spec)
  (:import-from #:cl-spec/src/property
                #:property
                #:register-property)
  (:import-from #:cl-spec/src/function-spec
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

(defun expand-function-spec-definition (name clauses source-location)
  "Build a FUNCTION-SPEC from the CLAUSES of a DEFSPEC-FUNCTION form.

CLAUSES are the :ARGS, :RETURNS, :PRE and :POST clauses as written.

Not implemented yet."
  (declare (ignore name clauses source-location))
  (error 'not-implemented :operator 'defspec-function))

(defmacro defspec-function (name &body clauses)
  "Attach a contract to the existing function NAME without redefining it.

  (defspec-function transfer
    (:args (from account) (to account) (amount positive-money))
    (:returns transaction))"
  (let ((location (current-source-location)))
    `(register-function-spec
      (expand-function-spec-definition ',name ',clauses ',location))))

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
