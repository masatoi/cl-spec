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
                #:registry-register-spec)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data))

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
