;;;; tests/dsl-test.lisp

(defpackage #:cl-spec/tests/dsl-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form
                #:invalid-generator-form)
  (:import-from #:cl-spec/src/ir
                #:spec-kind
                #:spec-name
                #:spec-source-form
                #:spec-generator-name)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-spec
                #:find-generator)
  (:import-from #:cl-spec/src/introspection
                #:spec-data)
  (:import-from #:cl-spec/src/generator-definition
                #:custom-generator
                #:custom-generator-name
                #:custom-generator-function
                #:custom-generator-documentation
                #:register-generator)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator
                #:register-spec
                #:normalize-spec-form
                #:register-function-spec
                #:function-spec))

(in-package #:cl-spec/tests/dsl-test)

(deftest dsl-macros-are-macros
  (testing "the four DSL entry points are macros, not functions"
    (ok (macro-function 'defspec))
    (ok (macro-function 'defspec-function))
    (ok (macro-function 'defproperty))
    (ok (macro-function 'defgenerator))))

(deftest dsl-macros-expand-without-error
  (testing "macroexpansion produces the expected call shape"
    (let ((expansion (macroexpand-1
                       '(defspec positive-integer (and integer (range 1 *))))))
      (ok (eq 'register-spec (first expansion)))
      (ok (eq 'positive-integer (second (second expansion))))
      (ok (eq 'normalize-spec-form (first (third expansion)))))
    (let ((expansion (macroexpand-1
                       '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction)))))
      (ok (eq 'register-function-spec (first expansion)))
      (ok (eq 'make-instance (first (second expansion))))
      (ok (eq 'function-spec (second (second (second expansion)))))
      (ok (eq 'transfer (second (getf (cddr (second expansion)) :name)))))
    (let ((expansion (macroexpand-1
                       '(defgenerator small-integer () (random 100)))))
      (ok (eq 'register-generator (first expansion)))
      (ok (eq 'make-instance (first (second expansion))))
      (ok (eq 'custom-generator (second (second (second expansion)))))
      (ok (eq 'small-integer (second (getf (cddr (second expansion)) :name)))))))

(deftest dsl-macros-signal-at-runtime
  (testing "a DEFGENERATOR this version cannot honour is refused, not registered"
    ;; A generator with parameters would need a syntax for a spec to pass them,
    ;; and §11 defines none.  Accepting one would call the body without the
    ;; bindings its author wrote.
    (ok (signals (eval '(defgenerator parametrised (n) (* 2 n)))
                 'invalid-generator-form)))
  (testing "and a name that is not a symbol is refused too"
    ;; The registry keys with EQ and sorts generator names by SYMBOL-NAME, so a
    ;; non-symbol key made LIST-GENERATORS signal a TYPE-ERROR once there were two.
    (ok (signals (eval '(defgenerator "aa" () 1))
                 'invalid-generator-form))))

(deftest defspec-registers-a-normalized-spec
  (let ((*registry* (make-hash-table-registry)))
    (testing "DEFSPEC normalizes and registers"
      (eval '(defspec positive-integer (and integer (range 1 *))))
      (let ((spec (find-spec 'positive-integer)))
        (ok spec)
        (ok (eq :and (spec-kind spec)))
        (ok (eq 'positive-integer (spec-name spec)))
        (ok (equal '(and integer (range 1 *)) (spec-source-form spec)))))))

(deftest defproperty-registers-a-normalized-property
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defspec positive-integer (and integer (range 1 *))))
    (eval '(cl-spec/src/dsl:defproperty addition-preserves-order
               ((x positive-integer) (y positive-integer))
             "Adding a positive integer only ever grows a positive integer."
             (:about +)
             (:kind :monotonicity)
             (:tags :arithmetic)
             (> (+ x y) x)))
    (let ((property (cl-spec/src/registry:find-property 'addition-preserves-order)))
      (testing "the property is registered under its own name"
        (ok property)
        (ok (eq 'addition-preserves-order (cl-spec/src/property:property-name property))))
      (testing "the option clauses are parsed"
        (ok (equal '(+) (cl-spec/src/property:property-targets property)))
        (ok (eq :monotonicity (cl-spec/src/property:property-kind property)))
        (ok (equal '(:arithmetic) (cl-spec/src/property:property-tags property)))
        (ok (stringp (cl-spec/src/property:property-documentation property))))
      (testing "the arguments carry normalized IR, not designators"
        (let ((arguments (cl-spec/src/property:property-arguments property)))
          (ok (equal '(x y) (mapcar #'first arguments)))
          (ok (every (lambda (argument) (typep (second argument) 'cl-spec/src/ir:spec))
                     arguments))))
      (testing "the body is both callable and readable"
        (ok (funcall (cl-spec/src/property:property-function property) 1 2))
        (ok (equal '((> (+ x y) x)) (cl-spec/src/property:property-body property))))
      (testing "the whole form is kept for introspection"
        (ok (eq 'cl-spec/src/dsl:defproperty
                (first (cl-spec/src/property:property-source-form property)))))
      (testing "shrinking defaults to on"
        (ok (getf (cl-spec/src/property:property-metadata property) :shrink)))
      (testing "the reverse index finds it from its target"
        (ok (equal (list (cl-spec/src/property:property-name property))
                   (cl-spec/src/registry:properties-for '+)))))))

(deftest defproperty-stops-consuming-options-at-the-first-non-option
  (testing "a keyword-headed form after the first predicate is body, not an option"
    ;; The parser is exercised directly: compiling the body would call the
    ;; keyword, which the compiler reports as an undefined function.  The
    ;; parser is what decides whether a form is an option.
    (multiple-value-bind (documentation options forms)
        (cl-spec/src/dsl::parse-property-body
         '((:kind :invariant) (integerp x) (:not-an-option-keyword x)))
      (declare (ignore documentation))
      (ok (equal '((:kind :invariant)) options))
      (ok (equal '((integerp x) (:not-an-option-keyword x)) forms))))
  (testing "the registered property keeps only the forms before the boundary"
    (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
      (eval '(cl-spec/src/dsl:defproperty stops-at-the-body ((x integer))
               (:kind :invariant)
               (integerp x)))
      (let ((property (cl-spec/src/registry:find-property 'stops-at-the-body)))
        (ok (equal :invariant (cl-spec/src/property:property-kind property)))
        (ok (equal '((integerp x)) (cl-spec/src/property:property-body property)))))))

(deftest defproperty-validates-its-trials-clause
  (testing "(:trials 25), a plausible mis-write for a flat trial count, is rejected"
    ;; Left unvalidated, 25 reaches RESOLVE-TRIALS's GETF and signals an
    ;; unrelated SIMPLE-TYPE-ERROR instead of naming the actual problem.
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-trials ((x integer))
                          (:trials 25)
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form)))
  (testing "a well formed :TRIALS plist is accepted"
    (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
      (eval '(cl-spec/src/dsl:defproperty good-trials ((x integer))
              (:trials (:smoke 5 :normal 200))
              (integerp x)))
      (ok (equal '(:smoke 5 :normal 200)
                 (cl-spec/src/property:property-trials
                  (cl-spec/src/registry:find-property 'good-trials)))))))

(deftest defproperty-rejects-extra-values-on-single-value-clauses
  (testing "(:trials (:smoke 5) (:normal 200)), a plausible mis-write for a two
profile plist, is a clause with three elements; unvalidated, (second clause)
is the well formed (:smoke 5) alone and (:normal 200) is silently dropped"
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-trials-profiles ((x integer))
                          (:trials (:smoke 5) (:normal 200))
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form)))
  (testing ":KIND takes exactly one value; an extra element is rejected the same way"
    (ok (signals (eval '(cl-spec/src/dsl:defproperty bad-kind ((x integer))
                          (:kind :invariant :extra)
                          (integerp x)))
                 'cl-spec/src/conditions:invalid-property-form))))

(deftest defproperty-keeps-supported-empty-and-dynamic-options
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry))
        (shrink-p nil))
    (cl-spec/src/dsl:defproperty supported ()
      (:about) (:tags) (:kind nil) (:trials (:normal 0 :smoke 2)) (:shrink shrink-p)
      t)
    (cl-spec/src/dsl:defproperty empty-trials () (:trials nil) t)
    (ok (null (cl-spec/src/property:property-trials
               (cl-spec/src/registry:find-property 'empty-trials))))
    (cl-spec/src/dsl:defproperty string-body () "A truthy predicate.")
    (cl-spec/src/dsl:defproperty nil-body () nil)
    (let ((property (cl-spec/src/registry:find-property 'supported)))
      (ok (null (cl-spec/src/property:property-arguments property)))
      (ok (equal '(:normal 0 :smoke 2) (cl-spec/src/property:property-trials property)))
      (ok (not (getf (cl-spec/src/property:property-metadata property) :shrink)))
      (ok (funcall (cl-spec/src/property:property-function property))))
    (ok (equal "A truthy predicate."
               (funcall (cl-spec/src/property:property-function
                         (cl-spec/src/registry:find-property 'string-body)))))
    (ok (not (funcall (cl-spec/src/property:property-function
                       (cl-spec/src/registry:find-property 'nil-body)))))))

(deftest invalid-property-replacement-preserves-the-registry
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (cl-spec/src/dsl:defproperty unchanged ((x integer))
      (:about +) (:trials (:normal 1)) (integerp x))
    (let ((original (cl-spec/src/registry:find-property 'unchanged)))
      (ok (signals (eval
                    '(cl-spec/src/dsl:defproperty unchanged ((x integer dropped))
                      (:about -) nil))
                   'cl-spec/src/conditions:invalid-property-form))
      (ok (eq original (cl-spec/src/registry:find-property 'unchanged)))
      (ok (equal '(unchanged) (cl-spec/src/registry:properties-for '+)))
      (ok (null (cl-spec/src/registry:properties-for '-))))))

(deftest property-options-end-at-the-first-predicate
  (multiple-value-bind (documentation options forms)
      (cl-spec/src/dsl::parse-property-body '(t (:trials (:normal 7))))
    (ok (null documentation))
    (ok (null options))
    (ok (equal '(t (:trials (:normal 7))) forms))))

(deftest defproperty-requires-symbol-targets
  (dolist (target '(42 "target" (setf target)))
    (let ((condition
            (handler-case
                (progn (macroexpand-1
                        (list 'defproperty 'bad-target nil (list :about target) t))
                       nil)
              (cl-spec/src/conditions:invalid-property-form (condition) condition))))
      (ok condition)
      (when condition
        (ok (search ":ABOUT"
                    (cl-spec/src/conditions:invalid-property-form-reason condition)))))))

(deftest declaration-parsers-refuse-improper-outer-lists
  (dolist (tail '(tail nil))
    (let ((clauses (list '(:args (x integer)))))
      (setf (cdr clauses) (or tail clauses))
      (ok (signals (cl-spec/src/dsl::parse-function-spec-clauses 'target clauses)
                   'cl-spec/src/conditions:invalid-function-spec-form)))
    (let ((options (list '(:generator source))))
      (setf (cdr options) (or tail options))
      (ok (signals (cl-spec/src/dsl::spec-generator-option options)
                   'cl-spec/src/conditions:invalid-spec-form)))))

(deftest property-refusals-identify-the-offending-option
  (dolist (case '((((:kind)) ":KIND")
                  (((:shrink nil) (:shrink t)) ":SHRINK")
                  (((:timeout 10)) ":TIMEOUT")
                  (((:trials (:normal -1))) ":TRIALS")))
    (destructuring-bind (options diagnostic) case
      (let ((condition
              (handler-case
                  (progn
                    (macroexpand-1
                     (list* 'defproperty 'bad-options nil (append options '(t))))
                    nil)
                (cl-spec/src/conditions:invalid-property-form (condition) condition))))
        (ok condition)
        (when condition
          (ok (search diagnostic
                      (string-upcase
                       (cl-spec/src/conditions:invalid-property-form-reason condition)))))))))

(deftest defproperty-requires-a-name-and-predicate
  (dolist (form '((cl-spec/src/dsl:defproperty nil () t)
                  (cl-spec/src/dsl:defproperty :bad () t)
                  (cl-spec/src/dsl:defproperty 12 () t)
                  (cl-spec/src/dsl:defproperty empty ())
                  (cl-spec/src/dsl:defproperty empty () "Documentation." (:kind :invariant))))
    (ok (signals (macroexpand-1 form) 'cl-spec/src/conditions:invalid-property-form))))

(deftest defproperty-rejects-duplicate-and-malformed-options
  (dolist (case '((((:trials (:normal 1)) (:trials (:normal 99))) "more than once")
                  (((:about +) (:about -)) "more than once")
                  (((:tags :one) (:tags :two)) "more than once")
                  (((:kind :one) (:kind :two)) "more than once")
                  (((:shrink nil) (:shrink t)) "more than once")
                  (((:kind)) "exactly one") (((:shrink)) "exactly one")
                  (((:trials)) "exactly one")
                  (((:kind . :invariant)) "finite proper list")
                  (((:about . +)) "finite proper list")
                  (((:trials (:normal -1))) "nonnegative integer")
                  (((:trials (:normal 1.5))) "nonnegative integer")
                  (((:trials (:normal 1 :normal 99))) "unique keyword")
                  (((:trials (:normal 1 . tail))) "unique keyword")
                  (((:trials (normal 1))) "unique keyword")
                  (((:trials (:normal))) "unique keyword")
                  (((:timeout 10)) "unknown")))
    (destructuring-bind (options reason-fragment) case
      (let ((condition
              (handler-case
                  (progn
                    (macroexpand-1
                     (list* 'defproperty 'invalid-option '((x integer))
                            (append options '((integerp x)))))
                    nil)
                (cl-spec/src/conditions:invalid-property-form (condition) condition))))
        (ok condition)
        (when condition
          (ok (search reason-fragment
                      (cl-spec/src/conditions:invalid-property-form-reason condition))))))))

(deftest defproperty-rejects-malformed-bindings
  (dolist (arguments '(((x integer ignored)) ((x)) (x) ((x . integer))
                       ((x integer) (x string)) ((nil integer)) ((t integer))
                       ((:x integer)) ((42 integer)) ((&optional integer))
                       (&rest (x integer)) ((x integer) . tail)))
    (ok (signals (macroexpand-1
                  (list 'cl-spec/src/dsl:defproperty 'invalid-binding arguments t))
                 'cl-spec/src/conditions:invalid-property-form))))

(deftest defproperty-refuses-circular-declarations
  (let ((arguments (list '(x integer)))
        (binding (list 'x 'integer))
        (clause (list :tags :one))
        (trials (list :normal 1)))
    (setf (cdr arguments) arguments
          (cddr binding) binding
          (cddr clause) clause
          (cddr trials) trials)
    (dolist (form (list (list 'defproperty 'cycle arguments t)
                       (list 'defproperty 'cycle (list binding) t)
                       (list 'defproperty 'cycle nil clause t)
                       (list 'defproperty 'cycle nil (list :trials trials) t)))
      (ok (signals (macroexpand-1 form) 'cl-spec/src/conditions:invalid-property-form)))))

(deftest defgenerator-registers-and-defspec-names-it
  (let ((*registry* (make-hash-table-registry)))
    (eval '(defgenerator an-even-number ()
             "Draw an even number below ten."
             (* 2 (random 5))))
    (eval '(defspec even-number (and integer (range 0 8))
             (:generator an-even-number)))
    (testing "the generator is registered under its own name, with its prose"
      (let ((generator (find-generator 'an-even-number)))
        (ok generator)
        (ok (eq 'an-even-number (custom-generator-name generator)))
        (ok (string= "Draw an even number below ten."
                     (custom-generator-documentation generator)))
        (ok (functionp (custom-generator-function generator)))))
    (testing "the spec carries the name, and introspection reports it"
      (ok (eq 'an-even-number (spec-generator-name (find-spec 'even-number))))
      (ok (eq 'an-even-number (getf (spec-data 'even-number) :generator))))
    (testing "and SPEC-DATA reports it on every node type, not only the base one"
      ;; The attribute is emitted by SPEC->DATA rather than by NODE-ATTRIBUTES:
      ;; the node-specific methods replace the base method, so an attribute added
      ;; there survives only on node kinds that have no method of their own
      ;; (PR review).
      (dolist (pair '((covered-type integer)
                      (covered-range (range 1 10))
                      (covered-member (member 1 2 3))
                      (covered-predicate (satisfies oddp))
                      (covered-instance (instance-of standard-object))
                      (covered-reference an-even-number)))
        (destructuring-bind (name form) pair
          (eval `(defspec ,name ,form (:generator an-even-number)))
          (testing (format nil "~S keeps the generator" form)
            (ok (eq 'an-even-number (getf (spec-data name) :generator)))))))
    (testing "an option DEFSPEC does not know is refused, not ignored"
      ;; A definition that named a generator and lost the clause would look like
      ;; a spec drawing from it while the backend derived values from the DSL.
      (ok (signals (eval '(defspec odd-spec integer (:shrink :always)))
                   'invalid-spec-form)))
    (testing "and so is (:generator ...) naming something that is not a symbol"
      (ok (signals (eval '(defspec odd-spec integer (:generator "even")))
                   'invalid-spec-form)))
    (testing "a spec object cannot take one after the fact"
      (ok (signals (normalize-spec-form (normalize-spec-form 'integer)
                                        :generator 'an-even-number)
                   'invalid-spec-form)))))
