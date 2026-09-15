;;;; src/dsl.lisp
;;;;
;;;; Surface macros (specification §37).  The macros are syntax sugar only:
;;;; they capture the source form and location and hand everything else to the
;;;; normalizer and the registry.  Keeping them thin is what lets the DSL
;;;; change without disturbing the Semantic IR or the introspection API.
;;;;
;;;; Malformed declarations are refused during macroexpansion. Spec normalization
;;;; runs when the expansion is evaluated, before the definition is registered.

(defpackage #:cl-spec/src/dsl
  (:use #:cl)
  (:import-from #:cl-spec/src/utils/lists #:finite-list-p)
  (:import-from #:cl-spec/src/definition-validation #:finite-definition-form-p)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form
                #:invalid-property-form
                #:invalid-function-spec-form
                #:invalid-function-spec-form-form
                #:invalid-function-spec-form-reason
                #:invalid-generator-form)
  (:import-from #:cl-spec/src/call-schema
                #:validate-call-declarations #:call-declaration-variables
                #:normalize-return-declaration)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:register-spec)
  (:import-from #:cl-spec/src/property
                #:property
                #:register-property)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:register-function-spec #:validate-post-value-variables)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator
                #:register-generator)
  (:import-from #:cl-spec/src/utils/source-location
                #:current-source-location)
  (:export #:defspec
           #:defspec-function
           #:defproperty
           #:defgenerator))

(in-package #:cl-spec/src/dsl)

(defun proper-list-p (value)
  "Use the shared cycle-safe proper-list check."
  (finite-list-p value))

(defparameter *spec-option-keywords* '(:generator)
  "Keywords that may head an option clause in a DEFSPEC form.

Deliberately short: §52 keeps the MVP spec syntax to a form and this one clause,
and a clause DEFSPEC does not know is refused rather than ignored -- a definition
that named a generator and lost the clause would look like a spec drawing from
that generator while the backend went on deriving values from the DSL.")

(defun spec-generator-option (options)
  "Return the custom generator named by the DEFSPEC OPTIONS, or NIL.

Only (:GENERATOR NAME) is accepted, and anything else is refused for the reason
§17 refuses an unknown contract clause: a definition that named a generator and
had the clause silently dropped would look like a spec drawing from it while the
backend derived values from the DSL instead."
  (unless (proper-list-p options)
    (error 'invalid-spec-form :form options
                              :reason "options must be a finite proper list"))
  (let ((generator nil))
    (dolist (option options)
      (unless (and (consp option)
                   (proper-list-p option)
                   (keywordp (first option)))
        (error 'invalid-spec-form :form option
                                  :reason "expected a clause headed by a keyword"))
      (let ((head (first option)))
        (unless (member head *spec-option-keywords*)
          (error 'invalid-spec-form
                 :form option
                 :reason (format nil "~S is not a DEFSPEC option; the only one is ~
                                      (:generator NAME)"
                                 head)))
        (unless (= 2 (length option))
          (error 'invalid-spec-form :form option
                                    :reason ":generator takes exactly one name"))
        (when generator
          (error 'invalid-spec-form :form option
                                    :reason ":generator appears more than once"))
        (let ((name (second option)))
          (unless (and name (symbolp name) (not (keywordp name)))
            (error 'invalid-spec-form
                   :form option
                   :reason ":generator takes a symbol naming a generator"))
          (setf generator name))))
    generator))

(defmacro defspec (name form &body options)
  "Define a spec named NAME from spec DSL FORM.

FORM is normalized into a Semantic IR object and registered in *REGISTRY*.
The original form and the definition site are kept on the resulting spec.

  (defspec positive-integer
    (and integer (range 1 *)))

OPTIONS is a list of clauses.  The only one this version accepts is
(:GENERATOR NAME), naming a DEFGENERATOR generator whose values the backend draws
instead of deriving them from FORM (specification §11).  For an AND, a generator
on the whole AND wins.  Otherwise a unique conjunct that carries a custom
generator is used as the generation source and the whole AND filters its draws;
two or more such conjuncts signal GENERATOR-UNAVAILABLE, because the backend never
silently picks one or ignores one.  See the bounded-AND addendum in §73.5."
  (let ((location (current-source-location))
        (generator (spec-generator-option options)))
    `(register-spec ',name
                    (normalize-spec-form ',form
                                         :name ',name
                                         :generator ',generator
                                         :source-location ',location))))

(defparameter *function-spec-clause-keywords*
  '(:args :args-generator :pre :returns :post :post-values :signals)
  "Clause heads DEFSPEC-FUNCTION accepts (specification §17, §73.1 D1).")

(defun function-spec-error (form reason)
  "Signal INVALID-FUNCTION-SPEC-FORM for FORM with REASON."
  (error 'invalid-function-spec-form :form form :reason reason))

(defun lambda-list-keyword-name-p (object)
  "Return true when OBJECT is a symbol whose name begins with an ampersand."
  (let ((name (and object (symbolp object) (symbol-name object))))
    (and name (plusp (length name)) (char= #\& (char name 0)))))

(defun symbol-occurs-p (symbol tree)
  "Return true when SYMBOL appears in TREE somewhere it could be a variable.

Quoted subforms are skipped.  A symbol under QUOTE is data -- a type name, a
member of a list, a mode keyword -- and can never be a variable reference, so
counting it refused (:pre (not (eq mode 'result))) as a contract that touches
the return value."
  (cond ((eq symbol tree) t)
        ((and (consp tree) (eq 'quote (car tree))) nil)
        ((consp tree)
         (or (symbol-occurs-p symbol (car tree))
             (symbol-occurs-p symbol (cdr tree))))
        (t nil)))

(defun result-named-symbols (tree)
  "Return the distinct symbols named \"RESULT\" occurring in TREE as variables."
  (let ((found '()))
    (labels ((walk (node)
               (cond ((and (consp node) (eq 'quote (car node))))
                     ((consp node) (walk (car node)) (walk (cdr node)))
                     ((and node (symbolp node) (not (constantp node))
                           (string= (symbol-name node) "RESULT"))
                      (pushnew node found)))))
      (walk tree))
    found))

(defun return-value-symbol (variables)
  "Return the symbol RESULT denotes for a contract over VARIABLES, or NIL.

§17 writes the return value as an unqualified RESULT, so the symbol meant is
whichever one that name resolves to in the package the contract's own text was
read in -- FIND-SYMBOL, never INTERN, which §60 forbids.

The parameters locate that package, rather than *PACKAGE* at macroexpansion
time.  They come from the same form as the :POST body, so they follow it; the
expansion-time package does not.  A DEFSPEC-FUNCTION generated by another macro
expands wherever that macro is used, so keying on *PACKAGE* compiled one source
into two different contracts -- in the second the binding was a gensym and the
author's RESULT was a free variable, registered on a compiler warning.

Comparing SYMBOL-NAME across the whole form, which came before either, took any
symbol so named wherever it came from: a postcondition reading another package's
variable had that variable bound as the return value, so a claim false for every
input compiled into a tautology."
  (let ((home (if variables
                  (symbol-package (first variables))
                  *package*)))
    (and home (find-symbol "RESULT" home))))

(defun parse-function-spec-clauses (name clauses)
  "Split clauses into documentation, arguments, pre/returns/post, generator, signals and post names.

Every clause is checked here rather than at check time, so a contract the
checker could not honour never reaches the registry.  A NIL RETURNS therefore
means the contract named no return spec: (:returns nil) is refused, so the two
cannot be confused."
  (unless (and name (symbolp name) (not (keywordp name)))
    (function-spec-error name "the specified function must be named by a symbol"))
  (unless (proper-list-p clauses)
    (function-spec-error clauses "clauses must be a finite proper list"))
  (let ((documentation nil)
        (seen '())
        (args nil)
        (pre nil)
        (returns nil)
        (post nil)
        (post-values :primary)
        (signals nil)
        (argument-generator nil))
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
          (:args-generator
           (unless (and (= 2 (length clause))
                        (second clause) (symbolp (second clause))
                        (not (keywordp (second clause))))
             (function-spec-error clause ":args-generator takes one generator name"))
           (setf argument-generator (second clause)))
          (:pre (setf pre (rest clause)))
          (:post (setf post (rest clause)))
          (:post-values
           (unless (and (>= (length clause) 3) (proper-list-p (second clause)))
             (function-spec-error clause ":post-values requires a names list and predicate forms"))
           (setf post-values (second clause) post (cddr clause)))
          (:signals
           (unless (and (= 2 (length clause)) (second clause))
             (function-spec-error clause ":signals takes exactly one non-NIL spec form"))
           (setf signals (second clause)))
          (:returns
           (unless (= 2 (length clause))
             (function-spec-error clause ":returns takes exactly one spec form"))
           (let ((form (second clause)))
              (when (and (consp form) (symbolp (first form))
                         (string= "VALUES" (symbol-name (first form))))
                (normalize-return-declaration form))
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
    (when (and (member :post seen) (member :post-values seen))
      (function-spec-error clauses ":post and :post-values are exclusive"))
    (when (and signals (or (member :returns seen) (member :post seen) (member :post-values seen)))
      (function-spec-error clauses ":signals cannot coexist with returns or postconditions"))
    (unless (eq post-values :primary)
      (unless (and (proper-list-p returns) (symbolp (first returns))
                    (string= "VALUES" (symbol-name (first returns))))
        (function-spec-error
         clauses ":post-values requires a fixed (values ...) return declaration"))
      (validate-post-value-variables post-values (length (rest returns))
                                     (call-declaration-variables args)))
    (values documentation args pre returns post argument-generator signals post-values)))

(defun parse-required-spec-arguments (args)
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
  (unless (proper-list-p args)
    (function-spec-error args "arguments must be a finite proper list"))
  (let ((variables '()))
    (dolist (entry args)
      (when (lambda-list-keyword-name-p entry)
        (function-spec-error
         entry
         (format nil "~S is not supported; :args takes required parameters only"
                 entry)))
      (unless (and (consp entry) (proper-list-p entry) (= 2 (length entry)))
        (function-spec-error entry "expected (parameter spec-form)"))
      (let ((name (first entry)))
        (when (lambda-list-keyword-name-p name)
          (function-spec-error
           entry
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
          (function-spec-error entry (format nil "~S is specified twice as a parameter" name)))
        (push name variables)))
    args))

(defun parse-function-spec-arguments (args)
  "Validate positional, rest and explicit keyword declarations before macro expansion."
  (validate-call-declarations args))

(defun expand-postcondition-forms (forms &optional (index 0))
  "Compile short-circuiting FORMS with an internal failure index.
The primary value remains the predicate result. Only a false result carries the
tagged secondary values consumed by the function checker; no form runs twice."
  (let ((value (gensym "POST-VALUE")))
    `(let ((,value ,(first forms)))
       (if ,value
           ,(if (rest forms)
                (expand-postcondition-forms (rest forms) (1+ index))
                value)
           (values nil ,index :cl-spec-post-form-failure)))))

(defun expand-function-spec-definition (whole name clauses source-location)
  "Return the form DEFSPEC-FUNCTION expands into.

Like DEFPROPERTY's expander this runs at macroexpansion time, because the :PRE
and :POST forms have to be compiled into real functions: §60 forbids runtime
EVAL, so a contract kept only as a list could be read but never checked."
  (multiple-value-bind (documentation args pre returns post argument-generator signals post-values)
      (parse-function-spec-clauses name clauses)
    (parse-function-spec-arguments args)
    (let* ((variables (call-declaration-variables args))
           (candidate (return-value-symbol variables))
           (parameterp (and candidate (member candidate variables) t))
           (in-post (and candidate (symbol-occurs-p candidate post)))
           (in-pre (and candidate (symbol-occurs-p candidate pre)))
           (result (if (and in-post (not parameterp)) candidate (gensym "RESULT"))))
      ;; Every symbol named RESULT that occurs has to be the one being bound.
      ;; The candidate is found through the parameters, which is a proxy for
      ;; the package the :POST text was read in and not always a good one: a
      ;; parameter named by a COMMON-LISP symbol (COUNT, LIST, TYPE) sends the
      ;; lookup to a package with no RESULT at all, and one written in another
      ;; package sends it somewhere the author never meant.  Both used to end
      ;; the same way -- the return value bound to a gensym, the author's
      ;; RESULT left free or, worse, some other package's variable captured and
      ;; the claim compiled into a tautology.  Neither is detectable from the
      ;; result.  Refusing is not the whole answer, but it is never the silent
      ;; one.
      (let ((occurring (result-named-symbols post)))
        (when (and occurring (not (equal occurring (list candidate))))
          (function-spec-error
           (cons :post post)
           (format nil "cannot tell which symbol names the return value: ~
:post uses ~{~S~^ and ~}, and the contract's own package resolves RESULT to ~
~:[nothing~;~:*~S~].  Rename the parameter, or write the postcondition in the ~
package the return value's name belongs to"
                   occurring candidate))))
      (when (and in-post parameterp)
        ;; The :POST predicate binds the return value ahead of the parameters,
        ;; so a parameter of the same name produced (LAMBDA (RESULT RESULT) ...)
        ;; and a compiler error about a lambda list the author never wrote.
        ;; It is also genuinely ambiguous: the reader cannot tell which of the
        ;; two the postcondition means.
        (function-spec-error
         (cons :post post)
         (format nil "~S is both a parameter and the name :post uses for the ~
return value"
                 candidate)))
      (when (and in-pre (not parameterp))
        ;; Only when it is not a parameter: a precondition about a parameter
        ;; the contract itself named RESULT is an ordinary precondition, and
        ;; refusing it said something about the return value that the form
        ;; does not do.
        (function-spec-error
         (cons :pre pre)
         (format nil ":pre runs before the call, so it cannot refer to ~S"
                 candidate)))
      `(register-function-spec
        (make-instance 'function-spec
                       :name ',name
                       :argument-specs
                       ',args
                       :argument-generator ',argument-generator
                       :signal-spec ,(when signals `(normalize-spec-form ',signals))
                       :return-spec ',returns
                       :post-value-variables ',post-values
                       :preconditions ',pre
                       :postconditions ',post
                       :precondition-function
                       ,(when pre
                          `(lambda ,variables
                             (declare (ignorable ,@variables))
                             (and ,@pre)))
                       :postcondition-function
                       ,(when post
                          (if (eq post-values :primary)
                              `(lambda (,result ,@variables)
                                 (declare (ignorable ,result ,@variables))
                                 ,(expand-postcondition-forms post))
                              (let ((returned (gensym "RETURNED")))
                                `(lambda (,returned ,@variables)
                                   (declare (ignorable ,@variables))
                                   (let ((,result (first ,returned))
                                         ,@(loop for name in post-values for index from 0
                                                 collect `(,name (nth ,index ,returned))))
                                     (declare (ignorable ,result ,@post-values))
                                     ,(expand-postcondition-forms post))))))
                       :documentation ,documentation
                       :source-form ',whole
                       :source-location ',source-location)))))

(defmacro defspec-function (&whole whole name &body clauses)
  "Attach a contract to the existing function NAME without redefining it.

CLAUSES may start with a docstring, then any of (:ARGS (PARAMETER SPEC) ...),
(:ARGS-GENERATOR NAME), (:PRE FORM ...), (:RETURNS SPEC), (:POST FORM ...),
(:POST-VALUES (NAME ...) FORM ...), or (:SIGNALS SPEC),
each at most once. :ARGS-GENERATOR names a DEFGENERATOR returning the whole proper
argument list. Its output is validated before :PRE and the target; it has no
automatic shrink strategy.  :PRE
sees the parameters. :POST sees them and RESULT, the primary returned value.
(:RETURNS (VALUES SPEC ...)) checks an exact return count, including zero.
:POST-VALUES is exclusive with :POST and requires one unique name per fixed return.
It binds the returned values and keeps RESULT as the primary value. Missing values
bind to NIL if a consumer runs the post predicate without return validation.

:SIGNALS requires an error escaping the target to satisfy SPEC. Normal return
fails; :SIGNALS cannot coexist with :RETURNS or :POST. Warnings and non-error
signals keep their ordinary behavior and do not satisfy this clause.
PROGRAM-ERROR and UNDEFINED-FUNCTION (including subclasses) always remain
:CONDITION failures, even if SPEC would accept them.

Required, optional, rest and explicit keyword parameters are supported.
&OPTIONAL permits (PARAMETER SPEC [SUPPLIED-P]);
&REST takes one (PARAMETER WHOLE-LIST-SPEC) before any &KEY declarations.
Its predicate variable holds the raw remaining tail, including keyword pairs.
&KEY permits ((:KEY PARAMETER) SPEC [SUPPLIED-P]). A terminal &ALLOW-OTHER-KEYS
permits undeclared keywords. Predicates see NIL for omitted values and a boolean
supplied flag when declared. The first duplicate keyword value wins. Target
defaults are evaluated only by the target. Other lambda list keywords
and unknown clauses signal
INVALID-FUNCTION-SPEC-FORM rather than registering an unchecked claim
(specification §17, §73.1 D1).

  (defspec-function ranged-random
    (:args (start integer) (end integer))
    (:pre (< start end))
    (:returns integer)
    (:post (and (>= result start) (< result end))))"
  (expand-function-spec-definition whole name clauses (current-source-location)))

(defparameter *property-option-keywords* '(:about :kind :tags :trials :shrink)
  "Keywords that may head an option clause in a DEFPROPERTY body.")

(defun property-form-error (form reason)
  "Refuse a malformed property declaration before it can reach the registry."
  (error 'invalid-property-form :form form :reason reason))

(defun parse-property-arguments (arguments)
  "Validate the same required bindings accepted by function contracts.
Translate only declaration refusals, preserving the offending fragment and the
specific explanation for constants, lambda-list keywords, and malformed pairs."
  (handler-case (parse-required-spec-arguments arguments)
    (invalid-function-spec-form (condition)
      (property-form-error (invalid-function-spec-form-form condition)
                           (invalid-function-spec-form-reason condition)))))

(defun parse-property-body (body)
  "Split BODY into documentation, validated unique options, and predicate forms.
A lone string remains a predicate. Unknown leading keyword clauses are refused,
since silently treating a misspelled option as code loses its intended meaning.
After the first non-option form, all remaining forms are ordinary Lisp code."
  (unless (proper-list-p body)
    (property-form-error body "body must be a finite proper list"))
  (let ((documentation nil)
        (options nil)
        (forms body))
    (when (and (stringp (first forms)) (rest forms))
      (setf documentation (pop forms)))
    (loop while (and (consp (first forms)) (keywordp (first (first forms))))
          do (let* ((clause (pop forms))
                    (keyword (first clause)))
               (unless (proper-list-p clause)
                 (property-form-error clause
                                      (format nil "~S clause must be a finite proper list"
                                              keyword)))
               (unless (member keyword *property-option-keywords*)
                 (property-form-error
                  clause (format nil "~S is unknown; expected one of ~{~S~^, ~}"
                                 keyword *property-option-keywords*)))
               (when (find keyword options :key #'first)
                 (property-form-error clause (format nil "~S appears more than once" keyword)))
               (push clause options)))
    (unless forms
      (property-form-error body "at least one predicate form is required"))
    (values documentation (nreverse options) forms)))

(defun option-clause (options keyword)
  "Return the clause in OPTIONS headed by KEYWORD, or NIL."
  (find keyword options :key #'first))

(defun check-single-value-clause (clause)
  "Require one explicit value for :KIND, :TRIALS and :SHRINK clauses.
A missing value must not look like an explicit NIL, and extra values must not
be silently discarded by SECOND when constructing the registered property."
  (when (and clause (/= 2 (length clause)))
    (property-form-error clause (format nil "~S takes exactly one value" (first clause)))))

(defun trials-plist-p (value)
  "Recognize a finite plist of unique keyword profiles and nonnegative budgets.
Duplicate profiles make GETF silently ignore a budget; a negative or fractional
count cannot describe executed trials. NIL remains a valid empty table."
  (and (proper-list-p value)
       (evenp (length value))
       (let ((seen nil))
         (loop for (profile count) on value by #'cddr
               always (and (keywordp profile) (not (member profile seen))
                           (integerp count) (>= count 0)
                           (progn (push profile seen) t))))))

(defun expand-property-definition (whole name arguments body source-location)
  "Return the form DEFPROPERTY expands into.

Unlike the other expanders this runs at macroexpansion time, because the
predicate has to be compiled into a real function rather than kept as a list."
  (unless (and name (symbolp name) (not (keywordp name)))
    (property-form-error name "property must be named by a non-keyword symbol"))
  (parse-property-arguments arguments)
  (multiple-value-bind (documentation options forms) (parse-property-body body)
    (let ((shrink-clause (option-clause options :shrink))
          (kind-clause (option-clause options :kind))
          (trials-clause (option-clause options :trials)))
      (let ((about-clause (option-clause options :about)))
        (unless (every #'symbolp (rest about-clause))
          (property-form-error about-clause ":ABOUT takes symbols naming its targets")))
      (check-single-value-clause shrink-clause)
      (check-single-value-clause kind-clause)
      (check-single-value-clause trials-clause)
      (when (and trials-clause (not (trials-plist-p (second trials-clause))))
        (error 'invalid-property-form
               :form trials-clause
               :reason ":TRIALS requires unique keyword profiles and nonnegative integer budgets"))
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

Bindings must be exact pairs with distinct, bindable required variables.
Each leading option appears at most once; unknown leading keyword options,
missing/extra single-option values and malformed trial tables are refused with
INVALID-PROPERTY-FORM at macroexpansion. Trial budgets are nonnegative integers
with unique keyword profiles. At least one predicate form is required.
After the first non-option form, remaining forms are ordinary Lisp code.

  (defproperty addition-preserves-order
      ((x positive-integer) (y positive-integer))
    (:about +)
    (:kind :monotonicity)
    (> (+ x y) x))"
  (expand-property-definition whole name arguments body (current-source-location)))

(defun parse-generator-body (body)
  "Split optional documentation and a leading shrink clause from generator draw forms."
  (unless (and (finite-list-p body) (finite-definition-form-p body))
    (error 'invalid-generator-form :form nil :reason :invalid-body))
  (let ((documentation (when (and (stringp (first body)) (rest body)) (pop body)))
        (shrinker nil))
    (when (and (consp (first body)) (eq (caar body) :shrink))
      (let ((clause (pop body)))
        (unless (and (finite-list-p clause) (>= (length clause) 3))
          (error 'invalid-generator-form :form clause :reason :invalid-shrink-clause))
        (let ((binding (second clause)))
          (unless (and (finite-list-p binding) (= (length binding) 1)
                       (first binding) (symbolp (first binding)) (not (constantp (first binding)))
                       (not (lambda-list-keyword-name-p (first binding))))
            (error 'invalid-generator-form :form clause :reason :invalid-shrink-clause))
          (setf shrinker `(lambda ,binding ,@(cddr clause))))))
    (dolist (form body)
      (when (and (consp form) (eq (car form) :shrink))
        (error 'invalid-generator-form :form form
               :reason (if shrinker :duplicate-shrink-clause :misplaced-shrink-clause))))
    (values documentation shrinker body)))

(defmacro defgenerator (&whole whole name lambda-list &body body)
  "Define a custom generator named NAME (specification §11).

Use this when a spec cannot express how values should be produced, for example
when generation must satisfy a global invariant:

  (defgenerator small-integer ()
    (random 100))

  (defspec small (and integer (range 0 100)) (:generator small-integer))

BODY produces one value per draw and is compiled into a function of no
arguments, so LAMBDA-LIST must be empty.  A generator that took parameters would
need a syntax for a spec to pass them and §11 defines none, and accepting one
would call the body without the bindings its author wrote.

For DEFSPEC uses, the value is not re-validated against the spec that names it.
For DEFSPEC-FUNCTION's :ARGS-GENERATOR, the whole argument list is validated
before the precondition or target runs.  A generator that
draws outside its spec makes a property report a counterexample the contract
refuses, which is a true statement about the generator rather than a silent pass;
the AND generator's residual filter is bounded by a shared candidate budget and
signals GENERATION-BUDGET-EXHAUSTED instead of retrying without limit.

An optional leading (:SHRINK (VALUE) BODY...) clause after documentation supplies
an ordered finite list of candidate values. Its one binding must be a valid variable.
A leading string in BODY is documentation when anything follows it, and the
generated value when the string is the whole body -- the rule DEFPROPERTY uses.
BODY is called for a value, so a body that returns a check-it generator produces
that object as the value rather than drawing from it."
  (unless (and name (symbolp name) (not (keywordp name)))
    (error 'invalid-generator-form
           :form whole
           :reason (format nil "the generator must be named by a symbol, but ~S was given"
                           name)))
  (unless (null lambda-list)
    (error 'invalid-generator-form
           :form whole
           :reason (format nil "LAMBDA-LIST must be empty, but ~S was given"
                           lambda-list)))
  (multiple-value-bind (documentation shrinker draw-forms) (parse-generator-body body)
    (let ((location (current-source-location)))
      `(register-generator
        (make-instance 'custom-generator
                       :name ',name
                       :function (lambda ,lambda-list ,@draw-forms)
                       :shrinker ,shrinker
                       :documentation ,documentation
                       :source-form ',whole
                       :source-location ',location)))))
