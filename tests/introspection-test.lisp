;;;; tests/introspection-test.lisp

(defpackage #:cl-spec/tests/introspection-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:not-implemented-operator
                #:unknown-spec)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec
                #:registry-register-function-spec
                #:registry-register-property
                #:register-spec
                #:properties-for)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  ;; No symbols imported: the body reaches CL-SPEC/SRC/DSL:DEFSPEC and
  ;; CL-SPEC/SRC/DSL:DEFPROPERTY through package-qualified references inside
  ;; EVAL, but package-inferred-system only infers a dependency from
  ;; DEFPACKAGE's :USE/:IMPORT-FROM clauses, so the edge still has to be
  ;; declared here.
  (:import-from #:cl-spec/src/dsl)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:register-function-spec)
  (:import-from #:cl-spec/src/property
                #:property
                #:register-property)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data
                #:function-spec-data
                #:semantic-data))

(in-package #:cl-spec/tests/introspection-test)

(defun signalled-operator (thunk)
  "Call THUNK and return the operator named by the NOT-IMPLEMENTED condition it
signals, or NIL if it signals no such condition."
  (handler-case (progn (funcall thunk) nil)
    (not-implemented (condition) (not-implemented-operator condition))))

(deftest introspection-entry-points-exist
  (testing "the four introspection entry points are defined"
    (ok (fboundp 'describe-spec))
    (ok (fboundp 'describe-property))
    (ok (fboundp 'spec-data))
    (ok (fboundp 'property-data))))

(deftest introspection-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (describe-spec 'positive-integer) 'not-implemented))
    (ok (signals (describe-property 'addition-preserves-order)
                 'not-implemented))))

(deftest introspection-entry-points-name-themselves
  (testing "the signalled condition's operator names the entry point that signalled it"
    (ok (eq 'describe-spec
            (signalled-operator (lambda () (describe-spec 'positive-integer)))))
    (ok (eq 'describe-property
            (signalled-operator
             (lambda () (describe-property 'addition-preserves-order)))))))

(deftest spec-data-projects-the-ir
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form
                             '(and integer (range 1 *))
                             :name 'positive-integer
                             :source-location '(:file "x.lisp" :package "CL-USER")))
    (let ((data (spec-data 'positive-integer :registry registry)))
      (testing "the top level carries name, kind and the author's source form"
        (ok (eq 'positive-integer (getf data :name)))
        (ok (eq :and (getf data :kind)))
        (ok (equal '(and integer (range 1 *)) (getf data :source-form))))
      (testing "the source location is expanded rather than opaque"
        (ok (equal '(:file "x.lisp" :package "CL-USER") (getf data :source-location))))
      (testing "children are projected recursively with node specific keys"
        (let ((children (getf data :children)))
          (ok (= 2 (length children)))
          (ok (eq :type (getf (first children) :kind)))
          (ok (eq 'integer (getf (first children) :type)))
          (ok (eq :range (getf (second children) :kind)))
          (ok (eql 1 (getf (second children) :min)))
          (ok (eq :unbounded (getf (second children) :max)))))
      (testing "a leaf carries no :CHILDREN key"
        (ok (not (member :children (first (getf data :children)))))))
    (testing "an unregistered name signals UNKNOWN-SPEC"
      (ok (signals (spec-data 'absent :registry registry) 'unknown-spec)))))

(deftest property-data-projects-the-property
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defspec positive-integer (and integer (range 1 *))))
    (eval '(cl-spec/src/dsl:defproperty addition-preserves-order
               ((x positive-integer) (y positive-integer))
             "Adding a positive integer only ever grows a positive integer."
             (:about +)
             (:kind :monotonicity)
             (> (+ x y) x)))
    (let ((data (property-data 'addition-preserves-order)))
      (testing "the identifying fields are present"
        (ok (eq 'addition-preserves-order (getf data :name)))
        (ok (eq :monotonicity (getf data :kind)))
        (ok (equal '(+) (getf data :targets)))
        (ok (stringp (getf data :documentation))))
      (testing "each argument carries its variable and its projected spec"
        (let ((arguments (getf data :arguments)))
          (ok (= 2 (length arguments)))
          (ok (eq 'x (getf (first arguments) :variable)))
          ;; A bare symbol argument spec stays a reference-spec because the
          ;; property stores a reference to the named spec, not an inlined copy.
          (ok (eq :reference (getf (getf (first arguments) :spec) :kind)))
          (ok (eq 'positive-integer (getf (getf (first arguments) :spec) :target)))))
      (testing "the body is readable rather than compiled away"
        (ok (equal '((> (+ x y) x)) (getf data :body)))))))

(deftest function-spec-data-projects-the-contract
  (let ((cl-spec/src/registry:*registry* (make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defspec small-integer (range integer -100 100)))
    (eval '(cl-spec/src/dsl:defspec-function widen
            "Widen a value away from zero."
            (:args (value small-integer) (by small-integer))
            (:pre (plusp by))
            (:returns small-integer)
            (:post (>= (abs result) (abs value)))))
    (let ((data (function-spec-data 'widen)))
      (testing "the contract's own identity is reported"
        (ok (eq 'widen (getf data :name)))
        (ok (equal "Widen a value away from zero." (getf data :documentation))))
      (testing "which inputs are accepted, as IR rather than as designators"
        (let ((arguments (getf data :arguments)))
          (ok (equal '(value by) (mapcar (lambda (a) (getf a :variable)) arguments)))
          (ok (eq :reference (getf (getf (first arguments) :spec) :kind)))
          (ok (eq 'small-integer (getf (getf (first arguments) :spec) :target))))
        (ok (equal '((plusp by)) (getf data :preconditions))))
      (testing "which output is required"
        (ok (eq :reference (getf (getf data :returns) :kind)))
        (ok (equal '((>= (abs result) (abs value))) (getf data :postconditions))))
      (testing "every key is present whatever its value, as SPEC-DATA promises"
        ;; A key that appears and disappears with its value breaks a JSON
        ;; consumer, which is the whole audience for this projection.
        (dolist (key '(:name :documentation :arguments :returns :preconditions
                       :postconditions :source-form :source-location :metadata))
          ;; The tail, not the value: :METADATA's value is legitimately NIL,
          ;; and a presence check that reads the value would call it absent.
          (ok (nth-value 2 (get-properties data (list key)))))))))

(deftest semantic-data-reports-everything-registered-about-a-symbol
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'foo
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'foo
                                                 :source-location '(:file "x.lisp")))
    (register-function-spec (make-instance 'function-spec :name 'foo) registry)
    (register-property (make-instance 'property
                                      :name 'foo-preserves-total :function (constantly t)
                                      :targets '(foo))
                       registry)
    (register-property (make-instance 'property
                                      :name 'failed-foo-is-noop :function (constantly t)
                                      :targets '(foo))
                       registry)
    (let ((data (semantic-data 'foo :registry registry)))
      (testing "every key is correct for a symbol with a spec, function spec and properties"
        (ok (eq 'foo (getf data :symbol)))
        (ok (equal (package-name (symbol-package 'foo)) (getf data :package)))
        (ok (eq 'foo (getf data :spec)))
        (ok (eq 'foo (getf data :function-spec)))
        (ok (null (getf data :property)))
        (ok (equal (properties-for 'foo registry) (getf data :properties-about)))))))

(deftest semantic-data-on-an-unregistered-symbol-is-all-nil-and-does-not-signal
  (let* ((registry (make-hash-table-registry))
         (data (semantic-data 'nothing-known-about-this :registry registry)))
    (testing "SEMANTIC-DATA returns the full shape rather than signalling"
      (ok (eq 'nothing-known-about-this (getf data :symbol)))
      (ok (equal (package-name (symbol-package 'nothing-known-about-this))
                (getf data :package)))
      (ok (null (getf data :spec)))
      (ok (null (getf data :function-spec)))
      (ok (null (getf data :property)))
      (ok (null (getf data :properties-about))))
    (testing "every key is present even though every value is empty"
      (ok (member :symbol data))
      (ok (member :package data))
      (ok (member :spec data))
      (ok (member :function-spec data))
      (ok (member :property data))
      (ok (member :properties-about data)))))

(deftest semantic-data-distinguishes-property-name-from-property-target
  (let ((registry (make-hash-table-registry)))
    (register-property (make-instance 'property :name 'bar :function (constantly t) :targets '(baz)) registry)
    (register-property (make-instance 'property :name 'qux :function (constantly t) :targets '(bar)) registry)
    (let ((data (semantic-data 'bar :registry registry)))
      (testing ":PROPERTY is BAR's own registration; :PROPERTIES-ABOUT is what targets BAR"
        (ok (eq 'bar (getf data :property)))
        (ok (equal '(qux) (getf data :properties-about)))))))

(deftest semantic-data-on-an-uninterned-symbol-has-no-package-and-does-not-signal
  (let* ((registry (make-hash-table-registry))
         (symbol (make-symbol "TRANSIENT"))
         (data (semantic-data symbol :registry registry)))
    (testing "an uninterned symbol reports no package and nothing signals"
      (ok (eq symbol (getf data :symbol)))
      (ok (null (symbol-package symbol)))
      (ok (null (getf data :package)))
      (ok (null (getf data :spec)))
      (ok (null (getf data :function-spec)))
      (ok (null (getf data :property)))
      (ok (null (getf data :properties-about))))))

(deftest semantic-data-does-not-mistake-a-registered-nil-value-for-absent
  (let ((registry (make-hash-table-registry)))
    (register-spec 'nil-spec nil registry)
    (registry-register-function-spec registry 'nil-function-spec nil)
    (registry-register-property registry 'nil-property nil)
    (testing "a NIL spec value still reads as registered, via found-p"
      (ok (eq 'nil-spec (getf (semantic-data 'nil-spec :registry registry) :spec))))
    (testing "a NIL function spec value still reads as registered, via found-p"
      (ok (eq 'nil-function-spec
              (getf (semantic-data 'nil-function-spec :registry registry) :function-spec))))
    (testing "a NIL property value still reads as registered, via found-p"
      (ok (eq 'nil-property
              (getf (semantic-data 'nil-property :registry registry) :property))))))

(deftest semantic-data-designators-resolve-through-spec-data-and-property-data
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'foo
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'foo
                                                 :source-location '(:file "x.lisp")))
    (register-property (make-instance 'property
                                      :name 'foo-preserves-total :function (constantly t)
                                      :targets '(foo))
                       registry)
    (register-property (make-instance 'property
                                      :name 'failed-foo-is-noop :function (constantly t)
                                      :targets '(foo))
                       registry)
    (let ((data (semantic-data 'foo :registry registry)))
      (testing "the :SPEC designator resolves through SPEC-DATA"
        (ok (eq 'foo (getf (spec-data (getf data :spec) :registry registry) :name))))
      (testing "each :PROPERTIES-ABOUT designator resolves through PROPERTY-DATA"
        (dolist (name (getf data :properties-about))
          (ok (eq name (getf (property-data name :registry registry) :name))))))))
