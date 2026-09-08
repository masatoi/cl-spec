# cl-spec MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仕様書 §67 の vertical slice を動かす — `defspec` で書いた spec を検証・説明・生成でき、`defproperty` で書いた property を seed 付きで実行して縮小反例を得られる状態にする。

**Architecture:** DSL マクロは構文糖に徹し、`normalize-spec-form` が Semantic IR を組む。IR からは explainer だけをコンパイルし、`validp` はその薄いラッパーとする（両者の判定が構成上一致する）。生成は `*generator-backend*` に注入された check-it backend に委ね、core は check-it を一切参照しない。trial ループと shrink は backend 側、seed と結果の組み立ては core 側。

**Tech Stack:** SBCL / ASDF `package-inferred-system` / Rove / check-it 0.1.0

## Global Constraints

- 設計は `docs/superpowers/specs/2026-09-08-cl-spec-mvp-design.md`。仕様書は `docs/cl-spec-specification-v0.2-draft.md`。
- パッケージ名はファイルパスと一致する（`src/foo.lisp` → `cl-spec/src/foo`）。`.asd` の変更は不要で、依存は `:import-from` から推論される。
- `src/` の中から `cl-spec` というニックネームを参照してはならない。ASDF がルートシステムへの依存とみなし、依存グラフが循環する。
- コア `cl-spec` システムは `check-it` をロードしてはならない。check-it に触れてよいのは `src/backends/check-it.lisp` だけ。
- 新しいテストファイルは必ず `tests.lisp` の `defpackage` に `:import-from` で追加する。追加を忘れたテストは**一度も走らない**。
- スタイル: Google Common Lisp Style Guide、2 スペースインデント、100 桁以内、トップレベルフォーム間に空行1つ、`(:use #:cl)` のみで他は `:import-from`。
- 公開関数・マクロ・クラスには docstring 必須。
- 各ファイルは `;;;; <path>` で始まり、`defpackage`、`(in-package ...)` と続く。
- ランタイム `eval` と動的 `intern` は **`src/` と `main.lisp` で**禁止。テストは、マクロ展開を
  「実行して」契約を確かめる唯一の手段として `eval` / `intern` を使ってよい（`macroexpand-1`
  だけでは契約の後半を証明できない）。既存の `tests/dsl-test.lisp` と `.mallet.lisp` の除外が
  その前例。新たに `eval` を使うテストファイルは `.mallet.lisp` の `:for-paths` に追加すること
  （Task 15 で一括して行う）。
- テスト実行: `rove cl-spec.asd`。単一スイート: `(rove:run :cl-spec/tests/normalize-test)`。
- Rove の `signals` は `restart-case` 内で発生した condition を確実には捕捉しない。本プロジェクトのコードは `restart-case` を使っていないので `signals` を使ってよいが、疑わしい場合は `handler-case` で包む。
- lint（mallet）は advisory。指摘は PR をブロックしない。

---

### Task 1: 新しい condition 3種

**Files:**
- Modify: `src/conditions.lisp`
- Test: `tests/conditions-test.lisp`

**Interfaces:**
- Consumes: 既存の `cl-spec-error`
- Produces: `invalid-spec-form`（`:form` `:reason`、reader `invalid-spec-form-form` / `invalid-spec-form-reason`）、`generator-unavailable`（`:spec` `:reason`、reader `generator-unavailable-spec` / `generator-unavailable-reason`）、`unsupported-seed`（スロットなし）

- [ ] **Step 1: 失敗するテストを書く**

`tests/conditions-test.lisp` の末尾に追加し、`defpackage` の `:import-from #:cl-spec/src/conditions` 節に
`#:invalid-spec-form #:invalid-spec-form-form #:invalid-spec-form-reason #:generator-unavailable
#:generator-unavailable-spec #:generator-unavailable-reason #:unsupported-seed` を足す。

```lisp
(deftest normalization-failures-carry-the-form
  (testing "INVALID-SPEC-FORM keeps the form and the reason"
    (let ((condition (make-condition 'invalid-spec-form
                                     :form '(cons-of a b)
                                     :reason "post-MVP")))
      (ok (equal '(cons-of a b) (invalid-spec-form-form condition)))
      (ok (equal "post-MVP" (invalid-spec-form-reason condition)))
      (ok (typep condition 'cl-spec-error))
      (ok (search "post-MVP" (princ-to-string condition))))))

(deftest generator-failures-name-the-spec
  (testing "GENERATOR-UNAVAILABLE keeps the spec and the reason"
    (let ((condition (make-condition 'generator-unavailable
                                     :spec :placeholder
                                     :reason "NOT has no generation strategy")))
      (ok (eq :placeholder (generator-unavailable-spec condition)))
      (ok (typep condition 'cl-spec-error))
      (ok (search "NOT has no generation strategy" (princ-to-string condition))))))

(deftest unsupported-seed-names-the-implementation
  (testing "UNSUPPORTED-SEED reports which implementation is missing support"
    (let ((condition (make-condition 'unsupported-seed)))
      (ok (typep condition 'cl-spec-error))
      (ok (search (lisp-implementation-type) (princ-to-string condition))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `invalid-spec-form` などが未定義でコンパイルエラー

- [ ] **Step 3: 実装**

`src/conditions.lisp` の `defpackage` の `:export` に
`#:invalid-spec-form #:invalid-spec-form-form #:invalid-spec-form-reason
#:generator-unavailable #:generator-unavailable-spec #:generator-unavailable-reason
#:unsupported-seed` を追加し、ファイル末尾に:

```lisp
(define-condition invalid-spec-form (cl-spec-error)
  ((form :initarg :form
         :reader invalid-spec-form-form
         :documentation "The spec DSL form that could not be normalized.")
   (reason :initarg :reason
           :initform nil
           :reader invalid-spec-form-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (format stream "~S is not a valid spec form~@[: ~A~]."
                     (invalid-spec-form-form condition)
                     (invalid-spec-form-reason condition))))
  (:documentation
   "Signalled when NORMALIZE-SPEC-FORM cannot make sense of a form."))

(define-condition generator-unavailable (cl-spec-error)
  ((spec :initarg :spec
         :reader generator-unavailable-spec
         :documentation "Spec no generator could be derived from.")
   (reason :initarg :reason
           :initform nil
           :reader generator-unavailable-reason
           :documentation "Human readable explanation, or NIL."))
  (:report (lambda (condition stream)
             (format stream "No generator can be derived from ~S~@[: ~A~]."
                     (generator-unavailable-spec condition)
                     (generator-unavailable-reason condition))))
  (:documentation
   "Signalled when an IR node has no generation strategy on this backend."))

(define-condition unsupported-seed (cl-spec-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "Deriving a random state from an integer seed is ~
                             not supported on ~A; reproducible property runs ~
                             currently require SBCL."
                     (lisp-implementation-type))))
  (:documentation
   "Signalled when an integer seed cannot be honoured on this implementation."))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS（全スイート green）

- [ ] **Step 5: コミット**

```bash
git add src/conditions.lisp tests/conditions-test.lisp
git commit -m "feat: add the conditions normalization, generation and seeding need"
```

---

### Task 2: designator の解決（`src/resolve.lisp`）

**Files:**
- Create: `src/resolve.lisp`
- Create: `tests/resolve-test.lisp`
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/registry` の `*registry*` `registry-find-spec` `registry-find-property`、`cl-spec/src/ir` の `spec`、`cl-spec/src/property` の `property`、Task 1 の condition 群
- Produces: `cl-spec/src/resolve` が `resolve-spec (designator registry)`、`resolve-property (designator registry)`、`context-registry (context)` を export

- [ ] **Step 1: 失敗するテストを書く**

`tests/resolve-test.lisp`:

```lisp
;;;; tests/resolve-test.lisp

(defpackage #:cl-spec/tests/resolve-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec
                #:unknown-property)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/property
                #:property)
  (:import-from #:cl-spec/src/registry
                #:make-hash-table-registry
                #:registry-register-spec
                #:registry-register-property)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:resolve-property
                #:context-registry))

(in-package #:cl-spec/tests/resolve-test)

(deftest resolving-a-spec-designator
  (let ((registry (make-hash-table-registry))
        (spec (make-instance 'type-spec :type-specifier 'integer)))
    (registry-register-spec registry 'small spec)
    (testing "a symbol resolves through the registry"
      (ok (eq spec (resolve-spec 'small registry))))
    (testing "a spec object resolves to itself"
      (ok (eq spec (resolve-spec spec registry))))
    (testing "an unregistered symbol signals UNKNOWN-SPEC"
      (ok (signals (resolve-spec 'absent registry) 'unknown-spec)))))

(deftest resolving-a-property-designator
  (let* ((registry (make-hash-table-registry))
         (property (make-instance 'property :name 'p)))
    (registry-register-property registry 'p property)
    (testing "a symbol resolves through the registry"
      (ok (eq property (resolve-property 'p registry))))
    (testing "a property object resolves to itself"
      (ok (eq property (resolve-property property registry))))
    (testing "an unregistered symbol signals UNKNOWN-PROPERTY"
      (ok (signals (resolve-property 'absent registry) 'unknown-property)))))

(deftest context-registry-defaults
  (let ((registry (make-hash-table-registry)))
    (testing "a context plist supplies the registry"
      (ok (eq registry (context-registry (list :registry registry)))))
    (testing "an empty context falls back to *REGISTRY*"
      (ok (eq cl-spec/src/registry:*registry* (context-registry nil))))))
```

`tests.lisp` の `defpackage` に `(:import-from #:cl-spec/tests/resolve-test)` を
`(:import-from #:cl-spec/tests/registry-test)` の直後へ追加する。

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `cl-spec/src/resolve` パッケージが存在しない

- [ ] **Step 3: 実装**

`src/resolve.lisp`:

```lisp
;;;; src/resolve.lisp
;;;;
;;;; Designator resolution.  Validation, explanation, generation, property
;;;; execution and introspection all accept either a name or an object, and all
;;;; of them need the same "resolve or signal" behaviour.  It lives here rather
;;;; than in SRC/REGISTRY.LISP so that the registry keeps knowing nothing about
;;;; the object types stored in it.

(defpackage #:cl-spec/src/resolve
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unknown-spec
                #:unknown-property)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:import-from #:cl-spec/src/property
                #:property)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-find-spec
                #:registry-find-property)
  (:export #:resolve-spec
           #:resolve-property
           #:context-registry))

(in-package #:cl-spec/src/resolve)

(defun resolve-spec (designator registry)
  "Return the spec DESIGNATOR names, signalling UNKNOWN-SPEC when there is none.

DESIGNATOR is either a spec object, which is returned unchanged, or a symbol
looked up in REGISTRY.  The lookup branches on the registry protocol's second
value rather than on the spec itself, so a name registered with a NIL value
stays distinguishable from a name that was never registered."
  (if (typep designator 'spec)
      designator
      (multiple-value-bind (spec foundp) (registry-find-spec registry designator)
        (if foundp
            spec
            (error 'unknown-spec :name designator)))))

(defun resolve-property (designator registry)
  "Return the property DESIGNATOR names, signalling UNKNOWN-PROPERTY otherwise.

DESIGNATOR is either a property object, which is returned unchanged, or a
symbol looked up in REGISTRY.  As with RESOLVE-SPEC, absence is read from the
protocol's found-p value, not from the value found."
  (if (typep designator 'property)
      designator
      (multiple-value-bind (property foundp) (registry-find-property registry designator)
        (if foundp
            property
            (error 'unknown-property :name designator)))))

(defun context-registry (context)
  "Return the registry named by compilation CONTEXT, defaulting to *REGISTRY*.

CONTEXT is the plist passed as :CONTEXT to the COMPILE-* functions.  Keeping
the accessor here means the compilers do not agree on a plist layout by
accident."
  (or (getf context :registry) *registry*))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/resolve.lisp tests/resolve-test.lisp tests.lisp
git commit -m "feat: add designator resolution shared by every entry point"
```

---

### Task 3: normalization — 葉ノード

**Files:**
- Modify: `src/normalize.lisp`
- Test: `tests/normalize-test.lisp`, `tests/dsl-test.lisp`

**Interfaces:**
- Consumes: Task 1 の `invalid-spec-form`、`cl-spec/src/ir` の全 IR クラス
- Produces: `normalize-spec-form (form &key name source-location)` が `type-spec` / `reference-spec` / `predicate-spec` / `member-spec` / `range-spec` / `instance-of-spec` を返す。`*spec-primitives*` から `"CONS-OF"` が消える

- [ ] **Step 1: 失敗するテストを書く**

`tests/normalize-test.lisp` を全面的に書き換える。`defpackage` の `:import-from` に
`#:cl-spec/src/conditions` から `#:invalid-spec-form`、`#:cl-spec/src/ir` から
`#:spec-name #:spec-source-form #:spec-source-location #:spec-kind #:type-spec-type-specifier
#:reference-spec-target #:predicate-spec-predicate #:member-spec-values #:range-spec-base-type
#:range-spec-minimum #:range-spec-maximum #:instance-of-spec-class-name` を足す。

```lisp
(deftest mvp-primitives-are-declared
  (testing "*SPEC-PRIMITIVES* lists exactly the MVP spec head names"
    (ok (equal '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
                 "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "INSTANCE-OF")
               *spec-primitives*)))
  (testing "CONS-OF is gone, matching the MVP spec list in section 52"
    (ok (not (member "CONS-OF" *spec-primitives* :test #'string=)))))

(deftest bare-symbols-split-into-types-and-references
  (testing "a COMMON-LISP type name becomes a TYPE-SPEC"
    (let ((spec (normalize-spec-form 'integer)))
      (ok (eq :type (spec-kind spec)))
      (ok (eq 'integer (type-spec-type-specifier spec)))))
  (testing "NULL is a type, not a reference"
    (ok (eq :type (spec-kind (normalize-spec-form 'null)))))
  (testing "any other symbol becomes a REFERENCE-SPEC"
    (let ((spec (normalize-spec-form 'positive-integer)))
      (ok (eq :reference (spec-kind spec)))
      (ok (eq 'positive-integer (reference-spec-target spec)))))
  (testing "a symbol in another package is a reference even if it names a class"
    (ok (eq :reference (spec-kind (normalize-spec-form 'cl-user::my-class))))))

(deftest explicit-leaf-heads
  (testing "(TYPE ...) wraps a type specifier"
    (ok (equal '(vector fixnum)
               (type-spec-type-specifier (normalize-spec-form '(type (vector fixnum)))))))
  (testing "(SATISFIES ...) records the predicate"
    (ok (eq 'plusp (predicate-spec-predicate (normalize-spec-form '(satisfies plusp))))))
  (testing "(MEMBER ...) keeps its values unnormalized"
    (ok (equal '(:a :b :c) (member-spec-values (normalize-spec-form '(member :a :b :c))))))
  (testing "(INSTANCE-OF ...) records the class name"
    (ok (eq 'my-class
            (instance-of-spec-class-name (normalize-spec-form '(instance-of my-class)))))))

(deftest range-accepts-both-arities
  (testing "two arguments leave the base type unspecified"
    (let ((spec (normalize-spec-form '(range 1 100))))
      (ok (null (range-spec-base-type spec)))
      (ok (eql 1 (range-spec-minimum spec)))
      (ok (eql 100 (range-spec-maximum spec)))))
  (testing "three arguments name the base type"
    (let ((spec (normalize-spec-form '(range integer 1 100))))
      (ok (eq 'integer (range-spec-base-type spec)))))
  (testing "* becomes :UNBOUNDED"
    (let ((spec (normalize-spec-form '(range 1 *))))
      (ok (eql 1 (range-spec-minimum spec)))
      (ok (eq :unbounded (range-spec-maximum spec)))))
  (testing "a non numeric base type is rejected"
    (ok (signals (normalize-spec-form '(range character 1 2)) 'invalid-spec-form))))

(deftest heads-are-matched-by-name-not-identity
  (testing "a head interned in another package still normalizes"
    (let ((head (intern "SATISFIES" (or (find-package "CL-USER") *package*))))
      (ok (eq :predicate (spec-kind (normalize-spec-form (list head 'plusp))))))))

(deftest normalization-records-provenance
  (testing "the top level spec keeps name, source form and location"
    (let ((spec (normalize-spec-form '(satisfies plusp)
                                     :name 'positive
                                     :source-location '(:file "x.lisp" :package "CL-USER"))))
      (ok (eq 'positive (spec-name spec)))
      (ok (equal '(satisfies plusp) (spec-source-form spec)))
      (ok (equal '(:file "x.lisp" :package "CL-USER") (spec-source-location spec))))))

(deftest rejected-forms
  (testing "CONS-OF is reported as post-MVP rather than as an unknown head"
    (let ((condition (handler-case (progn (normalize-spec-form '(cons-of integer integer)) nil)
                       (invalid-spec-form (c) c))))
      (ok condition)
      (ok (search "post-MVP" (princ-to-string condition)))))
  (testing "an unknown head is rejected"
    (ok (signals (normalize-spec-form '(vector-or-list integer)) 'invalid-spec-form)))
  (testing "a non symbol head is rejected"
    (ok (signals (normalize-spec-form '((1 2) 3)) 'invalid-spec-form)))
  (testing "a bare literal is rejected"
    (ok (signals (normalize-spec-form 42) 'invalid-spec-form)))
  (testing "wrong arity is rejected"
    (ok (signals (normalize-spec-form '(satisfies plusp oddp)) 'invalid-spec-form))))

(deftest spec-objects-pass-through
  (testing "an already normalized spec is returned unchanged"
    (let ((spec (normalize-spec-form 'integer)))
      (ok (eq spec (normalize-spec-form spec))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `normalize-spec-form` が `not-implemented` を signal する

- [ ] **Step 3: 実装**

`src/normalize.lisp` の `defpackage` を書き換える。`:import-from #:cl-spec/src/conditions` は
`#:invalid-spec-form` に差し替え（`not-implemented` はもう使わない）、`:import-from
#:cl-spec/src/ir` に `#:spec #:type-spec #:reference-spec #:predicate-spec #:member-spec
#:range-spec #:instance-of-spec #:and-spec #:or-spec #:not-spec #:list-of-spec #:vector-of-spec
#:tuple-spec #:nullable-spec` を並べる（複合ノードは Task 4 で使う）。

`*spec-primitives*` から `"CONS-OF"` を削除し、本体を実装する:

```lisp
(defun cl-type-name-p (symbol)
  "Return true when SYMBOL is a COMMON-LISP symbol usable as a type specifier.

Both halves matter.  Requiring the COMMON-LISP package keeps normalization
independent of the user's CLOS environment: without it, a user class named USER
would silently turn (OR NULL USER) into a type check instead of a reference."
  (and (symbolp symbol)
       (eq (symbol-package symbol) (find-package '#:common-lisp))
       (handler-case (progn (typep nil symbol) t)
         (error () nil))))

(defun unbounded-marker-p (object)
  "Return true when OBJECT is the * that the DSL writes for an open bound."
  (and (symbolp object) (string= (symbol-name object) "*")))

(defun spec-initargs (form name source-location)
  "Return the initargs every IR node receives, whatever its class."
  (list :name name :source-form form :source-location source-location))

(defun require-arity (args count form)
  "Return ARGS, signalling INVALID-SPEC-FORM unless it has exactly COUNT elements."
  (unless (= (length args) count)
    (error 'invalid-spec-form :form form
                              :reason (format nil "expected ~D argument~:P, got ~D"
                                              count (length args))))
  args)

(defun normalize-symbol (form name source-location)
  "Normalize a bare symbol into a TYPE-SPEC or a REFERENCE-SPEC."
  (if (cl-type-name-p form)
      (apply #'make-instance 'type-spec :type-specifier form
             (spec-initargs form name source-location))
      (apply #'make-instance 'reference-spec :target form
             (spec-initargs form name source-location))))

(defun normalize-range (args form name source-location)
  "Normalize the arguments of a RANGE form into a RANGE-SPEC."
  (multiple-value-bind (base-type minimum maximum)
      (cond ((and (= (length args) 3)
                  (symbolp (first args))
                  (not (unbounded-marker-p (first args))))
             (values (first args) (second args) (third args)))
            ((= (length args) 2)
             (values nil (first args) (second args)))
            (t
             (error 'invalid-spec-form :form form
                                       :reason "RANGE takes (range lo hi) or (range type lo hi)")))
    (unless (member base-type '(nil integer real))
      (error 'invalid-spec-form :form form
                                :reason "RANGE is numeric; its base type must be INTEGER or REAL"))
    (flet ((bound (value) (if (unbounded-marker-p value) :unbounded value)))
      (apply #'make-instance 'range-spec
             :base-type base-type
             :minimum (bound minimum)
             :maximum (bound maximum)
             (spec-initargs form name source-location)))))

(defun normalize-compound (form name source-location)
  "Normalize a cons whose head names a spec primitive."
  (let ((head (first form))
        (args (rest form)))
    (unless (symbolp head)
      (error 'invalid-spec-form :form form
                                :reason "the head of a spec form must be a symbol"))
    (let ((head-name (symbol-name head)))
      (cond
        ((string= head-name "TYPE")
         (apply #'make-instance 'type-spec
                :type-specifier (first (require-arity args 1 form))
                (spec-initargs form name source-location)))
        ((string= head-name "SATISFIES")
         (let ((predicate (first (require-arity args 1 form))))
           (unless (symbolp predicate)
             (error 'invalid-spec-form :form form
                                       :reason "SATISFIES takes a symbol naming a predicate"))
           (apply #'make-instance 'predicate-spec :predicate predicate
                  (spec-initargs form name source-location))))
        ((string= head-name "MEMBER")
         (apply #'make-instance 'member-spec :values args
                (spec-initargs form name source-location)))
        ((string= head-name "RANGE")
         (normalize-range args form name source-location))
        ((string= head-name "INSTANCE-OF")
         (let ((class-name (first (require-arity args 1 form))))
           (unless (symbolp class-name)
             (error 'invalid-spec-form :form form
                                       :reason "INSTANCE-OF takes a symbol naming a class"))
           (apply #'make-instance 'instance-of-spec :class-name class-name
                  (spec-initargs form name source-location))))
        ((string= head-name "CONS-OF")
         (error 'invalid-spec-form :form form
                                   :reason "CONS-OF is post-MVP; use TUPLE or LIST-OF"))
        (t
         (error 'invalid-spec-form :form form
                                   :reason "unknown spec head; write (type ...) or ~
                                            (instance-of ...) for a user-defined type, or ~
                                            reference a registered spec by name"))))))

(defun normalize-spec-form (form &key name source-location)
  "Normalize spec DSL FORM into a Semantic IR object.

NAME is the symbol the resulting spec will be registered under, or NIL for an
anonymous inline spec.  SOURCE-LOCATION is a plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION.  Both are attached to
the top level node only; children carry their own source form and nothing else.

The returned spec keeps FORM verbatim in its SPEC-SOURCE-FORM slot."
  (cond
    ((typep form 'spec) form)
    ((symbolp form) (normalize-symbol form name source-location))
    ((consp form) (normalize-compound form name source-location))
    (t (error 'invalid-spec-form
              :form form
              :reason "a spec form is a symbol, a list or a spec object"))))
```

`:export` に `#:cl-type-name-p` は加えない（内部関数）。

- [ ] **Step 4: `tests/dsl-test.lisp` を現状に合わせる**

`dsl-macros-signal-at-runtime` は `(defspec positive-integer (and integer (range 1 *)))` が
`not-implemented` を signal すると assert している。これは normalizer 全体がスタブだった間だけ
真であり、このタスクの後は偽になる。`defspec` の節を削り（残る3マクロはまだスタブなのでそのまま）、
代わりに葉ノードだけを使う登録テストと、複合ヘッドがまだ拒否されることを示すテストを足す:

```lisp
(deftest defspec-registers-a-normalized-spec
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (testing "DEFSPEC normalizes its form and registers the result"
      (eval '(cl-spec/src/dsl:defspec positive (satisfies plusp)))
      (let ((spec (cl-spec/src/registry:find-spec 'positive)))
        (ok spec)
        (ok (eq :predicate (cl-spec/src/ir:spec-kind spec)))
        (ok (eq 'positive (cl-spec/src/ir:spec-name spec)))
        (ok (equal '(satisfies plusp) (cl-spec/src/ir:spec-source-form spec)))))))

(deftest defspec-rejects-a-composite-head-for-now
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (testing "composite heads are not normalized yet"
      (ok (signals (eval '(cl-spec/src/dsl:defspec positive-integer (and integer (range 1 *))))
                   'cl-spec/src/conditions:invalid-spec-form)))))
```

`defspec-rejects-a-composite-head-for-now` は Task 4 で削除する。

- [ ] **Step 5: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS（全ファイル green）

- [ ] **Step 6: コミット**

```bash
git add src/normalize.lisp tests/normalize-test.lisp tests/dsl-test.lisp
git commit -m "feat: normalize the leaf spec forms into Semantic IR"
```

---

### Task 4: normalization — 複合ノードと `defspec` 疎通

**Files:**
- Modify: `src/normalize.lisp`
- Test: `tests/normalize-test.lisp`, `tests/dsl-test.lisp`

**Interfaces:**
- Consumes: Task 3 の `normalize-spec-form` と `spec-initargs` / `require-arity`
- Produces: `and-spec` / `or-spec` / `not-spec` / `list-of-spec` / `vector-of-spec` / `tuple-spec` / `nullable-spec` も返せる `normalize-spec-form`。`defspec` が実際に spec を登録するようになる

- [ ] **Step 1: 失敗するテストを書く**

`tests/normalize-test.lisp` に追加:

```lisp
(deftest composite-heads
  (testing "AND collects normalized children in order"
    (let ((spec (normalize-spec-form '(and integer (range 1 *)))))
      (ok (eq :and (spec-kind spec)))
      (ok (equal '(:type :range) (mapcar #'spec-kind (spec-children spec))))))
  (testing "OR collects normalized children"
    (ok (equal '(:type :reference)
               (mapcar #'spec-kind (spec-children (normalize-spec-form '(or null user)))))))
  (testing "NOT takes exactly one child"
    (ok (equal '(:type) (mapcar #'spec-kind (spec-children (normalize-spec-form '(not integer))))))
    (ok (signals (normalize-spec-form '(not integer string)) 'invalid-spec-form)))
  (testing "LIST-OF and VECTOR-OF take one element spec"
    (ok (eq :list-of (spec-kind (normalize-spec-form '(list-of integer)))))
    (ok (eq :vector-of (spec-kind (normalize-spec-form '(vector-of integer))))))
  (testing "TUPLE keeps one spec per position"
    (let ((spec (normalize-spec-form '(tuple integer string))))
      (ok (eq :tuple (spec-kind spec)))
      (ok (equal '(:type :type) (mapcar #'spec-kind (spec-children spec))))))
  (testing "NULLABLE takes exactly one child"
    (ok (eq :nullable (spec-kind (normalize-spec-form '(nullable integer))))))
  (testing "the empty AND and OR are accepted"
    (ok (null (spec-children (normalize-spec-form '(and)))))
    (ok (null (spec-children (normalize-spec-form '(or)))))))

(deftest children-do-not-inherit-the-name
  (testing "only the top level node carries NAME"
    (let ((spec (normalize-spec-form '(and integer) :name 'positive)))
      (ok (eq 'positive (spec-name spec)))
      (ok (null (spec-name (first (spec-children spec)))))))
  (testing "children keep their own source form"
    (let ((spec (normalize-spec-form '(and (range 1 *)))))
      (ok (equal '(range 1 *) (spec-source-form (first (spec-children spec))))))))
```

`tests/dsl-test.lisp` から Task 3 が置いた `defspec-rejects-a-composite-head-for-now` を削除し、
`defspec-registers-a-normalized-spec` を複合ヘッドを使う形へ広げる（既存の `no-eval` 抑止コメントは
そのまま残す）:

```lisp
(deftest defspec-registers-a-normalized-spec
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (testing "DEFSPEC normalizes and registers"
      (eval '(cl-spec/src/dsl:defspec positive-integer (and integer (range 1 *))))
      (let ((spec (cl-spec/src/registry:find-spec 'positive-integer)))
        (ok spec)
        (ok (eq :and (cl-spec/src/ir:spec-kind spec)))
        (ok (eq 'positive-integer (cl-spec/src/ir:spec-name spec)))
        (ok (equal '(and integer (range 1 *)) (cl-spec/src/ir:spec-source-form spec)))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — 複合ヘッドが `invalid-spec-form`（unknown spec head）になる

- [ ] **Step 3: 実装**

`normalize-compound` の `cond` に、`"CONS-OF"` 節の**前**へ次を追加する:

```lisp
        ((string= head-name "AND")
         (apply #'make-instance 'and-spec
                :children (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location)))
        ((string= head-name "OR")
         (apply #'make-instance 'or-spec
                :children (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location)))
        ((string= head-name "NOT")
         (apply #'make-instance 'not-spec
                :inner-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location)))
        ((string= head-name "LIST-OF")
         (apply #'make-instance 'list-of-spec
                :element-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location)))
        ((string= head-name "VECTOR-OF")
         (apply #'make-instance 'vector-of-spec
                :element-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location)))
        ((string= head-name "TUPLE")
         (apply #'make-instance 'tuple-spec
                :element-specs (mapcar #'normalize-spec-form args)
                (spec-initargs form name source-location)))
        ((string= head-name "NULLABLE")
         (apply #'make-instance 'nullable-spec
                :inner-spec (normalize-spec-form (first (require-arity args 1 form)))
                (spec-initargs form name source-location)))
```

`normalize-spec-form` は `normalize-compound` より後に定義されているので、再帰呼び出しのために
ファイル先頭（`*spec-primitives*` の直後）へ次を置く:

```lisp
(declaim (ftype (function (t &key (:name symbol) (:source-location list)) spec)
                normalize-spec-form))
```

（既存の `declaim` がこの位置にあるので、そのまま使える。）

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/normalize.lisp tests/normalize-test.lisp tests/dsl-test.lisp
git commit -m "feat: normalize composite spec forms and wire up defspec"
```

---

### Task 5: explainer — 葉ノードと `validp` / `validate` / `explain-data`

**Files:**
- Modify: `src/explain.lisp`, `src/validator.lisp`
- Test: `tests/explain-test.lisp`, `tests/validator-test.lisp`

**Interfaces:**
- Consumes: Task 2 の `resolve-spec` / `context-registry`、Task 3 の IR ノード
- Produces: `cl-spec/src/explain` が `compile-explainer (spec &key context)`（`(lambda (value path)` を返し、戻り値はエラー plist のリスト。空リストが valid）、`explain-data (spec-designator value &key registry)`、内部 generic `compile-node (spec context)` と `expected-descriptor (spec)` を提供。`cl-spec/src/validator` が `compile-validator (spec &key context)`、`validp (spec-designator value &key registry)`、`validate (spec-designator value &key registry)` を提供

- [ ] **Step 1: 失敗するテストを書く**

`tests/explain-test.lisp` を書き換える。`defpackage` は rove に加え
`#:cl-spec/src/normalize` から `#:normalize-spec-form`、`#:cl-spec/src/explain` から
`#:compile-explainer #:explain-data #:explain`、`#:cl-spec/src/conditions` から `#:unknown-spec`、
`#:cl-spec/src/registry` から `#:make-hash-table-registry #:registry-register-spec` を import する。

```lisp
(defun errors-for (form value)
  "Compile FORM and return the structured errors it reports for VALUE."
  (funcall (compile-explainer (normalize-spec-form form)) value nil))

(deftest valid-values-produce-no-errors
  (testing "a satisfied leaf reports nothing"
    (ok (null (errors-for 'integer 10)))
    (ok (null (errors-for '(satisfies plusp) 10)))
    (ok (null (errors-for '(member :a :b) :a)))
    (ok (null (errors-for '(range 1 100) 50)))
    (ok (null (errors-for '(range 1 *) 10000)))))

(deftest type-failures
  (testing "a failed type check names the expected type"
    (let ((datum (first (errors-for 'integer "foo"))))
      (ok (eq :type-failed (getf datum :kind)))
      (ok (equal '(:type integer) (getf datum :expected)))
      (ok (equal "foo" (getf datum :actual)))
      (ok (null (getf datum :path))))))

(deftest predicate-failures
  (testing "a predicate returning NIL is reported as :PREDICATE-FAILED"
    (let ((datum (first (errors-for '(satisfies plusp) -1))))
      (ok (eq :predicate-failed (getf datum :kind)))
      (ok (eq 'plusp (getf datum :predicate)))
      (ok (equal '(:satisfies plusp) (getf datum :expected)))))
  (testing "a predicate that signals is reported as :PREDICATE-ERRORED, not propagated"
    (let ((datum (first (errors-for '(satisfies plusp) "foo"))))
      (ok (eq :predicate-errored (getf datum :kind)))
      (ok (getf datum :condition-type))
      (ok (stringp (getf datum :condition-report))))))

(deftest member-and-range-failures
  (testing "MEMBER reports the admissible values"
    (let ((datum (first (errors-for '(member :a :b) :c))))
      (ok (eq :not-member (getf datum :kind)))
      (ok (equal '(:member :a :b) (getf datum :expected)))))
  (testing "RANGE says which bound was violated"
    (ok (eq :minimum (getf (first (errors-for '(range 1 100) 0)) :violated-bound)))
    (ok (eq :maximum (getf (first (errors-for '(range 1 100) 101)) :violated-bound))))
  (testing "RANGE rejects a value of the wrong type before comparing"
    (ok (eq :type-failed (getf (first (errors-for '(range 1 100) "x")) :kind)))))

(deftest instance-of-failures
  (testing "an unrelated value is not an instance"
    (let ((datum (first (errors-for '(instance-of standard-object) 10))))
      (ok (eq :not-an-instance (getf datum :kind))))))

(deftest explain-data-shape
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive
                            (normalize-spec-form '(satisfies plusp) :name 'positive))
    (testing "a failing value produces the section 22 shape"
      (let ((data (explain-data 'positive -100 :registry registry)))
        (ok (null (getf data :valid)))
        (ok (eq 'positive (getf data :spec)))
        (ok (eql -100 (getf data :value)))
        (ok (null (getf data :path)))
        (ok (= 1 (length (getf data :errors))))))
    (testing "a passing value reports :VALID T and no errors"
      (let ((data (explain-data 'positive 1 :registry registry)))
        (ok (eq t (getf data :valid)))
        (ok (null (getf data :errors)))))
    (testing "an unregistered name signals UNKNOWN-SPEC"
      (ok (signals (explain-data 'absent 1 :registry registry) 'unknown-spec)))))
```

`tests/validator-test.lisp` を書き換える。`defpackage` は rove に加え
`#:cl-spec/src/normalize` から `#:normalize-spec-form`、`#:cl-spec/src/validator` から
`#:compile-validator #:validp #:validate`、`#:cl-spec/src/explain` から `#:explain-data`、
`#:cl-spec/src/conditions` から `#:spec-violation #:spec-violation-value #:spec-violation-errors`、
`#:cl-spec/src/registry` から `#:make-hash-table-registry #:registry-register-spec` を import する。

fixture は**葉ノード**の `(range integer 1 *)` を使う。同じ spec の連言形
`(and integer (range 1 *))` が §67 の例だが、複合ノードの explainer は Task 6 なので、
ここでそれを使うとスイートが赤いまま Task 5 が終わってしまう。検査する6つの値に対して
両者の可否は完全に一致する — 非整数は、連言なら `integer` の枝で、葉なら range 自身の
基底型検査で落ちる。Task 6 で連言形へ戻す。

```lisp
(deftest validp-agrees-with-explain-data
  (let ((registry (make-hash-table-registry)))
    ;; Leaf form on purpose: the (AND INTEGER (RANGE 1 *)) spelling of this same
    ;; spec is the section 67 example, and the explain tests exercise it once
    ;; composite nodes exist.  Do not "simplify" it back before then.
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(range integer 1 *)
                                                 :name 'positive-integer))
    (testing "VALIDP is true exactly when EXPLAIN-DATA reports no errors"
      (dolist (value (list 10 -1 0 1 "foo" nil))
        (ok (eq (and (validp 'positive-integer value :registry registry) t)
                (and (getf (explain-data 'positive-integer value :registry registry) :valid) t)))))))

(deftest validate-returns-or-signals
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(range integer 1 *)
                                                 :name 'positive-integer))
    (testing "a valid value is returned unchanged"
      (ok (eql 10 (validate 'positive-integer 10 :registry registry))))
    (testing "an invalid value signals SPEC-VIOLATION carrying the structured errors"
      (let ((condition (handler-case (progn (validate 'positive-integer -1 :registry registry) nil)
                         (spec-violation (c) c))))
        (ok condition)
        (ok (eql -1 (spec-violation-value condition)))
        (ok (spec-violation-errors condition))))))

(deftest compile-validator-produces-a-predicate
  (testing "the compiled function takes one argument and returns a boolean"
    (let ((validator (compile-validator (normalize-spec-form '(range integer 1 *)))))
      (ok (funcall validator 5))
      (ok (not (funcall validator -5))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `compile-explainer` が `not-implemented` を signal する

- [ ] **Step 3: 実装**

`src/explain.lisp` の `defpackage` を差し替える:

```lisp
(defpackage #:cl-spec/src/explain
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:invalid-spec-form
                #:not-implemented)   ; EXPLAIN stays a stub until Task 7
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-kind
                #:spec-source-form
                #:type-spec
                #:type-spec-type-specifier
                #:predicate-spec
                #:predicate-spec-predicate
                #:member-spec
                #:member-spec-values
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:instance-of-spec
                #:instance-of-spec-class-name
                #:reference-spec
                #:reference-spec-target)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/resolve
                #:resolve-spec
                #:context-registry)
  (:export #:compile-explainer
           #:explain-data
           #:explain
           #:compile-node
           #:expected-descriptor
           #:error-datum))

(in-package #:cl-spec/src/explain)
```

本体（`compile-explainer` のスタブを置き換え、`explain` は Task 7 まで `not-implemented` のまま残す）:

```lisp
(defun error-datum (kind path value &rest extra)
  "Build one structured error plist.

PATH is accumulated innermost first and reversed here, so callers always see it
running from the root value down to the failing part."
  (list* :kind kind :path (reverse path) :actual value extra))

(defgeneric expected-descriptor (spec)
  (:documentation "Return a small plist saying what SPEC admits.

This is the shape EXPLAIN renders as a checklist line and the shape an agent
reads to learn what a value should have been."))

(defmethod expected-descriptor ((spec spec))
  (list :kind (spec-kind spec)))

(defmethod expected-descriptor ((spec type-spec))
  (list :type (type-spec-type-specifier spec)))

(defmethod expected-descriptor ((spec predicate-spec))
  (list :satisfies (predicate-spec-predicate spec)))

(defmethod expected-descriptor ((spec member-spec))
  (list* :member (member-spec-values spec)))

(defmethod expected-descriptor ((spec range-spec))
  (list :range :min (range-spec-minimum spec) :max (range-spec-maximum spec)))

(defmethod expected-descriptor ((spec instance-of-spec))
  (list :instance-of (instance-of-spec-class-name spec)))

(defmethod expected-descriptor ((spec reference-spec))
  (list :spec (reference-spec-target spec)))

(defgeneric compile-node (spec context)
  (:documentation "Compile SPEC into a function of (VALUE PATH).

The compiled function returns a list of structured error plists, empty when
VALUE satisfies SPEC.  PATH is the accumulated position, innermost first."))

(defmethod compile-node ((spec spec) context)
  (declare (ignore context))
  (error 'invalid-spec-form
         :form (spec-source-form spec)
         :reason (format nil "~S has no explainer in this version" (spec-kind spec))))

(defmethod compile-node ((spec type-spec) context)
  (declare (ignore context))
  (let ((type-specifier (type-spec-type-specifier spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (unless (typep value type-specifier)
        (list (error-datum :type-failed path value :expected expected))))))

(defmethod compile-node ((spec predicate-spec) context)
  (declare (ignore context))
  (let ((predicate (predicate-spec-predicate spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (handler-case
          (unless (funcall predicate value)
            (list (error-datum :predicate-failed path value
                               :predicate predicate :expected expected)))
        (error (condition)
          ;; A predicate applied to the wrong kind of value is a fact about the
          ;; value, not a bug in the caller: VALIDP must answer NIL rather than
          ;; unwind.
          (list (error-datum :predicate-errored path value
                             :predicate predicate :expected expected
                             :condition-type (type-of condition)
                             :condition-report (princ-to-string condition))))))))

(defmethod compile-node ((spec member-spec) context)
  (declare (ignore context))
  (let ((values (member-spec-values spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (unless (member value values :test #'eql)
        (list (error-datum :not-member path value :expected expected))))))

(defmethod compile-node ((spec range-spec) context)
  (declare (ignore context))
  (let ((base-type (or (range-spec-base-type spec) 'real))
        (minimum (range-spec-minimum spec))
        (maximum (range-spec-maximum spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (cond
        ((not (typep value base-type))
         (list (error-datum :type-failed path value :expected expected)))
        ((and (not (eq minimum :unbounded)) (< value minimum))
         (list (error-datum :out-of-range path value
                            :expected expected :violated-bound :minimum)))
        ((and (not (eq maximum :unbounded)) (> value maximum))
         (list (error-datum :out-of-range path value
                            :expected expected :violated-bound :maximum)))))))

(defmethod compile-node ((spec instance-of-spec) context)
  (declare (ignore context))
  (let ((class-name (instance-of-spec-class-name spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (let ((class (find-class class-name nil)))
        (unless (and class (typep value class))
          (list (error-datum :not-an-instance path value :expected expected)))))))

(defun compile-explainer (spec &key context)
  "Compile SPEC into a function of (VALUE PATH) returning structured errors.

CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The returned function returns an empty list exactly when VALUE satisfies SPEC,
which is what makes VALIDP and EXPLAIN-DATA incapable of disagreeing."
  (compile-node spec context))

(defun explain-data (spec-designator value &key (registry *registry*))
  "Return a plist describing whether VALUE satisfies SPEC-DESIGNATOR and why not.

  (:valid <boolean> :spec <symbol> :value <value> :path () :errors (<plist> ...))

This is the primary representation; EXPLAIN, condition reports and any JSON or
MCP projection are derived from it."
  (let* ((spec (resolve-spec spec-designator registry))
         (errors (funcall (compile-explainer spec :context (list :registry registry))
                          value nil)))
    (list :valid (null errors)
          :spec (if (symbolp spec-designator) spec-designator (spec-name spec))
          :value value
          :path nil
          :errors errors)))
```

`src/validator.lisp` の `defpackage` の `:import-from #:cl-spec/src/conditions` を
`#:spec-violation` に差し替え、`#:cl-spec/src/ir` に `#:spec-name` を足し（`validate` が呼ぶ）、
`#:cl-spec/src/explain` から `#:compile-explainer`、`#:cl-spec/src/registry` から `#:*registry*`、
`#:cl-spec/src/resolve` から `#:resolve-spec` を import する。`declaim` はそのまま。本体:

```lisp
(defun compile-validator (spec &key context)
  "Compile SPEC into a function of one argument returning a generalized boolean.

CONTEXT is a plist; :REGISTRY names the registry references resolve against.
The validator is a thin wrapper over the explainer so that the two can never
disagree about whether a value is admissible."
  (let ((explainer (compile-explainer spec :context context)))
    (lambda (value)
      (null (funcall explainer value nil)))))

(defun validp (spec-designator value &key (registry *registry*))
  "Return true when VALUE satisfies the spec named by SPEC-DESIGNATOR.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
Signals UNKNOWN-SPEC when a symbol resolves to nothing."
  (let ((spec (resolve-spec spec-designator registry)))
    (null (funcall (compile-explainer spec :context (list :registry registry))
                   value nil))))

(defun validate (spec-designator value &key (registry *registry*))
  "Return VALUE when it satisfies SPEC-DESIGNATOR, otherwise signal SPEC-VIOLATION.

The signalled condition carries the structured error list produced by
EXPLAIN-DATA so that callers do not have to re-run the check."
  (let* ((spec (resolve-spec spec-designator registry))
         (errors (funcall (compile-explainer spec :context (list :registry registry))
                          value nil)))
    (when errors
      (error 'spec-violation
             :spec (if (symbolp spec-designator) spec-designator (spec-name spec))
             :value value
             :path nil
             :errors errors))
    value))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/explain.lisp src/validator.lisp tests/explain-test.lisp tests/validator-test.lisp
git commit -m "feat: explain and validate the leaf spec nodes"
```

---

### Task 6: explainer — 複合ノード

**Files:**
- Modify: `src/explain.lisp`
- Test: `tests/explain-test.lisp`

**Interfaces:**
- Consumes: Task 5 の `compile-node` / `expected-descriptor` / `error-datum`
- Produces: `and-spec` / `or-spec` / `not-spec` / `nullable-spec` / `list-of-spec` / `vector-of-spec` / `tuple-spec` / `reference-spec` の `compile-node` メソッド。`and` のエラーは `:kind :conjunct-failed` で `:conjuncts`（各要素は `(:expected <descriptor> :status :satisfied|:failed|:unchecked)`）と `:errors` を持つ

- [ ] **Step 1: 失敗するテストを書く**

`tests/explain-test.lisp` に追加:

```lisp
(deftest and-short-circuits-and-reports-the-checklist
  (testing "a conjunction that holds reports nothing"
    (ok (null (errors-for '(and integer (satisfies plusp)) 10))))
  (testing "the first failing conjunct stops the walk"
    (let* ((datum (first (errors-for '(and integer (satisfies plusp)) "foo")))
           (conjuncts (getf datum :conjuncts)))
      (ok (eq :conjunct-failed (getf datum :kind)))
      (ok (equal '(:failed :unchecked) (mapcar (lambda (c) (getf c :status)) conjuncts)))
      (ok (equal '(:type integer) (getf (first conjuncts) :expected)))))
  (testing "conjuncts before the failure are marked satisfied"
    (let ((conjuncts (getf (first (errors-for '(and integer (satisfies plusp)) -1)) :conjuncts)))
      (ok (equal '(:satisfied :failed) (mapcar (lambda (c) (getf c :status)) conjuncts)))))
  (testing "the failing child's own errors are carried under :ERRORS"
    (let ((datum (first (errors-for '(and integer (satisfies plusp)) -1))))
      (ok (eq :predicate-failed (getf (first (getf datum :errors)) :kind)))))
  (testing "the empty conjunction admits everything"
    (ok (null (errors-for '(and) :anything)))))

(deftest or-collects-every-branch
  (testing "one matching branch is enough"
    (ok (null (errors-for '(or integer string) "x"))))
  (testing "when all branches fail their errors are kept"
    (let ((datum (first (errors-for '(or integer string) :keyword))))
      (ok (eq :no-branch-matched (getf datum :kind)))
      (ok (= 2 (length (getf datum :branches))))
      (ok (every (lambda (branch) (getf branch :errors)) (getf datum :branches)))))
  (testing "the empty disjunction admits nothing"
    (ok (errors-for '(or) :anything))))

(deftest not-and-nullable
  (testing "NOT fails exactly when its child holds"
    (ok (null (errors-for '(not integer) "x")))
    (ok (eq :negation-failed (getf (first (errors-for '(not integer) 1)) :kind))))
  (testing "NULLABLE admits NIL and delegates otherwise"
    (ok (null (errors-for '(nullable integer) nil)))
    (ok (null (errors-for '(nullable integer) 1)))
    (ok (errors-for '(nullable integer) "x"))))

(deftest collections-report-the-failing-position
  (testing "LIST-OF rejects a non list"
    (ok (eq :not-a-list (getf (first (errors-for '(list-of integer) 5)) :kind))))
  (testing "LIST-OF reports the index of every bad element"
    (let ((errors (errors-for '(list-of integer) '(1 "x" 3 "y"))))
      (ok (= 2 (length errors)))
      (ok (equal '((1) (3)) (mapcar (lambda (e) (getf e :path)) errors)))))
  (testing "VECTOR-OF rejects a non vector and reports indices"
    (ok (eq :not-a-vector (getf (first (errors-for '(vector-of integer) '(1 2))) :kind)))
    (ok (equal '((1)) (mapcar (lambda (e) (getf e :path))
                              (errors-for '(vector-of integer) #(1 "x"))))))
  (testing "TUPLE checks the length before the positions"
    (ok (eq :wrong-length (getf (first (errors-for '(tuple integer string) '(1))) :kind)))
    (ok (null (errors-for '(tuple integer string) '(1 "x"))))
    (ok (equal '((0)) (mapcar (lambda (e) (getf e :path))
                              (errors-for '(tuple integer string) '("a" "x"))))))
  (testing "nested collections accumulate the path root first"
    (ok (equal '((1 0))
               (mapcar (lambda (e) (getf e :path))
                       (errors-for '(list-of (list-of integer)) '((1) ("x"))))))))

(deftest references-resolve-at-call-time
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'target (normalize-spec-form 'integer :name 'target))
    (let ((explainer (compile-explainer (normalize-spec-form 'target)
                                        :context (list :registry registry))))
      (testing "the reference resolves through the registry"
        (ok (null (funcall explainer 1 nil)))
        (ok (funcall explainer "x" nil)))
      (testing "redefining the target changes what an existing explainer accepts"
        (registry-register-spec registry 'target (normalize-spec-form 'string :name 'target))
        (ok (funcall explainer 1 nil))
        (ok (null (funcall explainer "x" nil))))
      (testing "an unregistered target signals UNKNOWN-SPEC when checked"
        (let ((other (compile-explainer (normalize-spec-form 'absent)
                                        :context (list :registry registry))))
          (ok (signals (funcall other 1 nil) 'unknown-spec)))))))

(deftest recursive-specs-can-be-checked
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'int-tree
                            (normalize-spec-form '(or integer (tuple int-tree int-tree))
                                                 :name 'int-tree))
    (testing "a self referential spec terminates on well founded values"
      (let ((explainer (compile-explainer (normalize-spec-form 'int-tree)
                                          :context (list :registry registry))))
        (ok (null (funcall explainer 1 nil)))
        (ok (null (funcall explainer '(1 (2 3)) nil)))
        (ok (funcall explainer '(1 "x") nil))))))
```

あわせて `tests/validator-test.lisp` の fixture を、Task 5 が葉ノードに落としていた
`(range integer 1 *)` から §67 の連言形 `(and integer (range 1 *))` へ戻す（3箇所）。
理由を書いた「Leaf form on purpose」のコメントも削除する。

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — 複合ノードが `invalid-spec-form`（no explainer in this version）になる

- [ ] **Step 3: 実装**

`src/explain.lisp` の `defpackage` の `:import-from #:cl-spec/src/ir` に
`#:and-spec #:and-spec-children #:or-spec #:or-spec-children #:not-spec #:not-spec-inner-spec
#:nullable-spec #:nullable-spec-inner-spec #:collection-spec #:collection-spec-element-spec
#:list-of-spec #:vector-of-spec #:tuple-spec #:tuple-spec-element-specs` を追加し、
`:import-from #:cl-spec/src/conditions` に `#:unknown-spec` を、
`:import-from #:cl-spec/src/registry` に `#:registry-find-spec` を追加する。

`compile-explainer` の**前**に置く:

```lisp
(defun proper-list-p (object)
  "Return true when OBJECT is a proper list.

LENGTH and the LOOP list iteration both signal on a dotted list, so collection
explainers ask this before walking a value the caller supplied."
  (loop for tail = object then (cdr tail)
        do (cond ((null tail) (return t))
                 ((not (consp tail)) (return nil)))))

(defmethod compile-node ((spec and-spec) context)
  (let* ((children (and-spec-children spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) children))
         (descriptors (mapcar #'expected-descriptor children)))
    (lambda (value path)
      ;; Short-circuiting is both the safe reading and the one section 22's
      ;; example shows: a later conjunct may only be meaningful once the
      ;; earlier ones hold, as (satisfies plusp) is only meaningful for a number.
      (loop for child-function in compiled
            for index from 0
            for child-errors = (funcall child-function value path)
            when child-errors
              return (list (error-datum
                            :conjunct-failed path value
                            :conjuncts (loop for descriptor in descriptors
                                             for position from 0
                                             collect (list :expected descriptor
                                                           :status (cond ((< position index)
                                                                          :satisfied)
                                                                         ((= position index)
                                                                          :failed)
                                                                         (t :unchecked))))
                            :errors child-errors))))))

(defmethod compile-node ((spec or-spec) context)
  (let* ((children (or-spec-children spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) children))
         (descriptors (mapcar #'expected-descriptor children)))
    (lambda (value path)
      (let ((branch-errors (mapcar (lambda (function) (funcall function value path))
                                   compiled)))
        (unless (some #'null branch-errors)
          (list (error-datum :no-branch-matched path value
                             :branches (mapcar (lambda (descriptor errors)
                                                 (list :expected descriptor :errors errors))
                                               descriptors branch-errors))))))))

(defmethod compile-node ((spec not-spec) context)
  (let ((inner (compile-node (not-spec-inner-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (when (null (funcall inner value path))
        (list (error-datum :negation-failed path value :expected expected))))))

(defmethod compile-node ((spec nullable-spec) context)
  (let ((inner (compile-node (nullable-spec-inner-spec spec) context)))
    (lambda (value path)
      (unless (null value)
        (funcall inner value path)))))

(defmethod compile-node ((spec list-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (proper-list-p value))
          (list (error-datum :not-a-list path value :expected expected))
          (loop for item in value
                for index from 0
                append (funcall element item (cons index path)))))))

(defmethod compile-node ((spec vector-of-spec) context)
  (let ((element (compile-node (collection-spec-element-spec spec) context))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (if (not (vectorp value))
          (list (error-datum :not-a-vector path value :expected expected))
          (loop for index from 0 below (length value)
                append (funcall element (aref value index) (cons index path)))))))

(defmethod compile-node ((spec tuple-spec) context)
  (let* ((element-specs (tuple-spec-element-specs spec))
         (compiled (mapcar (lambda (child) (compile-node child context)) element-specs))
         (arity (length element-specs))
         (expected (expected-descriptor spec)))
    (lambda (value path)
      (cond
        ((not (or (proper-list-p value) (vectorp value)))
         (list (error-datum :not-a-sequence path value :expected expected)))
        ((/= (length value) arity)
         (list (error-datum :wrong-length path value :expected expected
                            :expected-length arity :actual-length (length value))))
        (t
         (loop for function in compiled
               for index from 0
               append (funcall function (elt value index) (cons index path))))))))

(defmethod compile-node ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    ;; Resolving on every call rather than at compile time is what makes forward
    ;; references, redefinition and recursive specs all work: compiling the
    ;; target eagerly would either capture a stale definition or never terminate.
    (lambda (value path)
      (let ((resolved (or (registry-find-spec registry target)
                          (error 'unknown-spec :name target))))
        (funcall (compile-node resolved (list :registry registry)) value path)))))
```

`expected-descriptor` に足りない descriptor を加える（`compile-explainer` の前、既存の
`expected-descriptor` メソッド群の直後）:

```lisp
(defmethod expected-descriptor ((spec list-of-spec))
  (list :list-of (expected-descriptor (collection-spec-element-spec spec))))

(defmethod expected-descriptor ((spec vector-of-spec))
  (list :vector-of (expected-descriptor (collection-spec-element-spec spec))))

(defmethod expected-descriptor ((spec tuple-spec))
  (list* :tuple (mapcar #'expected-descriptor (tuple-spec-element-specs spec))))

(defmethod expected-descriptor ((spec not-spec))
  (list :not (expected-descriptor (not-spec-inner-spec spec))))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/explain.lisp tests/explain-test.lisp
git commit -m "feat: explain the composite spec nodes"
```

---

### Task 7: `explain` の人間向け投影

**Files:**
- Modify: `src/explain.lisp`
- Test: `tests/explain-test.lisp`

**Interfaces:**
- Consumes: Task 5-6 の `explain-data`
- Produces: `explain (spec-designator value &key stream registry)`。`stream` は `&optional` から `&key` へ移る

- [ ] **Step 1: 失敗するテストを書く**

```lisp
(deftest explain-renders-the-checklist
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-money
                            (normalize-spec-form '(and integer (satisfies plusp))
                                                 :name 'positive-money))
    (testing "a failing conjunction prints one line per conjunct"
      (let ((text (with-output-to-string (stream)
                    (explain 'positive-money -100 :stream stream :registry registry))))
        (ok (search "does not satisfy" text))
        (ok (search "POSITIVE-MONEY" text))
        (ok (search "✓ INTEGER" text))
        (ok (search "✗ PLUSP" text))))
    (testing "an unchecked conjunct is marked as such rather than as passing"
      (let ((text (with-output-to-string (stream)
                    (explain 'positive-money "foo" :stream stream :registry registry))))
        (ok (search "✗ INTEGER" text))
        (ok (search "· PLUSP" text))))
    (testing "a passing value says so and returns NIL"
      (let ((text (with-output-to-string (stream)
                    (ok (null (explain 'positive-money 1 :stream stream :registry registry))))))
        (ok (search "satisfies" text))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `explain` が `not-implemented` を signal する

- [ ] **Step 3: 実装**

`src/explain.lisp` の `explain` スタブを次で置き換える。`print-explain-error` は `explain` より
**前**に置くこと（前方参照のスタイル警告を避ける）。

```lisp
(defun format-expected (descriptor)
  "Return the compact rendering of DESCRIPTOR that EXPLAIN prints.

A type, a predicate or a spec name reads better bare than wrapped in its
descriptor, which is why the common cases are unwrapped here."
  (case (first descriptor)
    ((:type :satisfies :spec :instance-of) (format nil "~S" (second descriptor)))
    (t (format nil "~S" descriptor))))

(defun conjunct-mark (status)
  "Return the character EXPLAIN prints for a conjunct STATUS."
  (ecase status
    (:satisfied "✓")
    (:failed "✗")
    (:unchecked "·")))

(defun print-explain-error (datum stream indent)
  "Print one structured error DATUM to STREAM, indented to column INDENT."
  (case (getf datum :kind)
    (:conjunct-failed
     (dolist (conjunct (getf datum :conjuncts))
       (format stream "~vT~A ~A~%"
               indent
               (conjunct-mark (getf conjunct :status))
               (format-expected (getf conjunct :expected))))
     (dolist (child (getf datum :errors))
       (print-explain-error child stream (+ indent 2))))
    (:no-branch-matched
     (format stream "~vTno branch matched~%" indent)
     (dolist (branch (getf datum :branches))
       (format stream "~vT✗ ~A~%" (+ indent 2) (format-expected (getf branch :expected)))))
    (t
     (format stream "~vT✗ ~A~@[ at ~S~]~%"
             indent
             (format-expected (getf datum :expected))
             (getf datum :path)))))

(defun explain (spec-designator value &key (stream *standard-output*) (registry *registry*))
  "Print a human readable rendering of (EXPLAIN-DATA SPEC-DESIGNATOR VALUE).

Writes to STREAM and returns NIL.  This is a projection of EXPLAIN-DATA and
must not compute anything EXPLAIN-DATA does not already report."
  (let ((data (explain-data spec-designator value :registry registry)))
    (if (getf data :valid)
        (format stream "~&~S satisfies ~S~%" value (getf data :spec))
        (progn
          (format stream "~&~S does not satisfy ~S~%" value (getf data :spec))
          (dolist (datum (getf data :errors))
            (print-explain-error datum stream 2)))))
  nil)
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/explain.lisp tests/explain-test.lisp
git commit -m "feat: project explain data into the human readable checklist"
```

---

### Task 8: `spec-data` と公開エクスポート

**Files:**
- Modify: `src/introspection.lisp`, `main.lisp`
- Test: `tests/introspection-test.lisp`, `tests/main-test.lisp`

**Interfaces:**
- Consumes: Task 2 の `resolve-spec`、IR の reader 群、`source-location-file` / `source-location-package`
- Produces: `spec-data (spec-designator &key registry)`、内部の `spec->data (spec)` と `source-location->data (location)` と generic `node-attributes (spec)`。`cl-spec` パッケージが Task 1 の condition 群と `source-location-file` / `source-location-package` を external にする

- [ ] **Step 1: 失敗するテストを書く**

`tests/introspection-test.lisp` の `spec-data` に関するテストを置き換える:

```lisp
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
```

`tests/main-test.lisp` に追加（既存の 24 シンボル検査はそのまま残す）:

```lisp
(deftest new-public-symbols-are-reachable
  (testing "the conditions the MVP added are external in CL-SPEC"
    (dolist (name '("INVALID-SPEC-FORM" "INVALID-SPEC-FORM-FORM" "INVALID-SPEC-FORM-REASON"
                    "GENERATOR-UNAVAILABLE" "GENERATOR-UNAVAILABLE-SPEC"
                    "GENERATOR-UNAVAILABLE-REASON" "UNSUPPORTED-SEED"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok symbol)
        (ok (eq :external status)))))
  (testing "source locations can be read without reaching into an internal package"
    (dolist (name '("SOURCE-LOCATION-FILE" "SOURCE-LOCATION-PACKAGE"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok symbol)
        (ok (eq :external status))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `spec-data` が `not-implemented`、新シンボルが CL-SPEC に無い

- [ ] **Step 3: 実装**

`src/introspection.lisp` の `defpackage` に、`#:cl-spec/src/ir` から
`#:spec #:spec-name #:spec-kind #:spec-source-form #:spec-source-location #:spec-children
#:type-spec #:type-spec-type-specifier #:reference-spec #:reference-spec-target
#:predicate-spec #:predicate-spec-predicate #:member-spec #:member-spec-values
#:range-spec #:range-spec-base-type #:range-spec-minimum #:range-spec-maximum
#:instance-of-spec #:instance-of-spec-class-name`、`#:cl-spec/src/resolve` から
`#:resolve-spec`、`#:cl-spec/src/utils/source-location` から
`#:source-location-file #:source-location-package` を import する。

```lisp
(defun source-location->data (location)
  "Return LOCATION as a plain plist, or NIL when there is no location.

Expanding it here is what keeps the opaque location object out of the public
introspection API."
  (when location
    (list :file (source-location-file location)
          :package (source-location-package location))))

(defgeneric node-attributes (spec)
  (:documentation "Return the SPEC-DATA keys specific to SPEC's node type."))

(defmethod node-attributes ((spec spec))
  nil)

(defmethod node-attributes ((spec type-spec))
  (list :type (type-spec-type-specifier spec)))

(defmethod node-attributes ((spec reference-spec))
  (list :target (reference-spec-target spec)))

(defmethod node-attributes ((spec predicate-spec))
  (list :predicate (predicate-spec-predicate spec)))

(defmethod node-attributes ((spec member-spec))
  (list :values (member-spec-values spec)))

(defmethod node-attributes ((spec range-spec))
  (list :base-type (range-spec-base-type spec)
        :min (range-spec-minimum spec)
        :max (range-spec-maximum spec)))

(defmethod node-attributes ((spec instance-of-spec))
  (list :class-name (instance-of-spec-class-name spec)))

(defun spec->data (spec)
  "Return the SPEC-DATA plist for one IR node, recursing into its children.

Every node carries the same keys whether or not they have a value, so that a
consumer never has to distinguish an absent key from a NIL one."
  (append (list :name (spec-name spec)
                :kind (spec-kind spec))
          (node-attributes spec)
          (list :source-form (spec-source-form spec)
                :source-location (source-location->data (spec-source-location spec)))
          (let ((children (spec-children spec)))
            (when children
              (list :children (mapcar #'spec->data children))))))

(defun spec-data (spec-designator &key (registry *registry*))
  "Return a plist describing the registered spec named by SPEC-DESIGNATOR.

  (:name <symbol> :kind <keyword> <node specific keys>
   :source-form <form> :source-location (:file <string> :package <string>)
   :children (<nested plist> ...))

:CHILDREN is present only on nodes that have children.  This is what the JSON
and MCP projections are built from."
  (spec->data (resolve-spec spec-designator registry)))
```

`main.lisp` を次のように変える。

1. `:import-from #:cl-spec/src/conditions` に `#:invalid-spec-form #:invalid-spec-form-form
   #:invalid-spec-form-reason #:generator-unavailable #:generator-unavailable-spec
   #:generator-unavailable-reason #:unsupported-seed` を追加。
2. 新しい節を足す:

```lisp
  (:import-from #:cl-spec/src/utils/source-location
                #:source-location-file
                #:source-location-package)
```

3. `:export` の Conditions 節に同じ7シンボル、Semantic IR 節の直後に
   `#:source-location-file #:source-location-package` を追加。

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/introspection.lisp main.lisp tests/introspection-test.lisp tests/main-test.lisp
git commit -m "feat: project the IR into spec-data and export the new public symbols"
```

---

### Task 9: seed の移植性シム

**Files:**
- Create: `src/utils/random.lisp`
- Create: `tests/utils/random-test.lisp`
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: Task 1 の `unsupported-seed`
- Produces: `cl-spec/src/utils/random` が `make-seed ()` と `seed->random-state (seed)` を export

- [ ] **Step 1: 失敗するテストを書く**

`tests/utils/random-test.lisp`:

```lisp
;;;; tests/utils/random-test.lisp

(defpackage #:cl-spec/tests/utils/random-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/utils/random
                #:make-seed
                #:seed->random-state))

(in-package #:cl-spec/tests/utils/random-test)

(defun draw (seed count)
  "Return COUNT random integers drawn from the state SEED derives."
  (let ((*random-state* (seed->random-state seed)))
    (loop repeat count collect (random 1000000))))

(deftest the-same-seed-reproduces-the-sequence
  (testing "two states from one seed agree"
    (ok (equal (draw 18372918 20) (draw 18372918 20))))
  (testing "different seeds disagree"
    (ok (not (equal (draw 1 20) (draw 2 20))))))

(deftest seeds-are-usable-integers
  (testing "MAKE-SEED returns a non negative integer"
    (let ((seed (make-seed)))
      (ok (integerp seed))
      (ok (not (minusp seed)))))
  (testing "a generated seed round trips through SEED->RANDOM-STATE"
    (let ((seed (make-seed)))
      (ok (equal (draw seed 5) (draw seed 5))))))

(deftest states-are-independent
  (testing "deriving a state does not disturb the caller's *RANDOM-STATE*"
    (let* ((*random-state* (seed->random-state 7))
           (before (random 1000000)))
      (seed->random-state 99)
      (let ((*random-state* (seed->random-state 7)))
        (ok (eql before (random 1000000)))))))
```

`tests.lisp` の `defpackage` に `(:import-from #:cl-spec/tests/utils/random-test)` を
`(:import-from #:cl-spec/tests/utils/source-location-test)` の直後へ追加。

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `cl-spec/src/utils/random` パッケージが存在しない

- [ ] **Step 3: 実装**

`src/utils/random.lisp`:

```lisp
;;;; src/utils/random.lisp
;;;;
;;;; Seed handling (specification §15).  An integer seed is the public contract
;;;; because that is what section 14's result schema shows and what survives a
;;;; trip through JSON to an agent.  ANSI gives no way to derive a RANDOM-STATE
;;;; from an integer, so the implementation-specific part is confined to this
;;;; file: adding another Lisp means adding one reader conditional here.

(defpackage #:cl-spec/src/utils/random
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:unsupported-seed)
  (:export #:make-seed
           #:seed->random-state))

(in-package #:cl-spec/src/utils/random)

(defconstant +seed-limit+ (expt 2 62)
  "Exclusive upper bound of the seeds MAKE-SEED draws.")

(defun make-seed ()
  "Return a fresh integer seed drawn from the current *RANDOM-STATE*."
  (random +seed-limit+))

(defun seed->random-state (seed)
  "Return a fresh RANDOM-STATE derived deterministically from integer SEED.

The caller binds *RANDOM-STATE* to the result; the current state is left
untouched.  Signals UNSUPPORTED-SEED on implementations with no such mapping."
  (check-type seed (integer 0))
  #+sbcl (sb-ext:seed-random-state seed)
  #-sbcl (error 'unsupported-seed))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/utils/random.lisp tests/utils/random-test.lisp tests.lisp
git commit -m "feat: derive a reproducible random state from an integer seed"
```

---

### Task 10: IR → check-it generator の対応（葉とコレクション）

**Files:**
- Create: `src/backends/check-it-generators.lisp`
- Test: `tests/backends/check-it-test.lisp`

**Interfaces:**
- Consumes: IR ノード、Task 2 の `context-registry`、Task 1 の `generator-unavailable`
- Produces: `cl-spec/src/backends/check-it-generators` が generic `spec-generator (spec context)` を export。戻り値は check-it の generator オブジェクト、または定数（`null` 型は NIL を返す。check-it は非 generator を定数として扱う）

**注:** 設計文書はこの対応表を `src/backends/check-it.lisp` に置いていたが、IR→generator の写像
（このタスク）と backend プロトコルの結線・trial 実行（Task 11、13）は別の責務なので2ファイルに分ける。
`package-inferred-system` なので `.asd` の変更は不要で、`src/backends/check-it.lisp` が
`:import-from` するだけで依存辺ができる。

- [ ] **Step 1: 失敗するテストを書く**

`tests/backends/check-it-test.lisp` に追加する。`defpackage` に `#:cl-spec/src/normalize` から
`#:normalize-spec-form`、`#:cl-spec/src/backends/check-it-generators` から `#:spec-generator #:compile-spec-generator`、
`#:cl-spec/src/conditions` から `#:generator-unavailable`、`#:cl-spec/src/validator` から
`#:validp`、`#:check-it` から `#:generate`、`#:cl-spec/src/registry` から
`#:make-hash-table-registry #:registry-register-spec` を import する。

```lisp
(defun draws-for (form &key (count 30) (registry (make-hash-table-registry)))
  "Generate COUNT values from FORM's generator, honouring the size its bounds need."
  (multiple-value-bind (generator size)
      (compile-spec-generator (normalize-spec-form form) (list :registry registry))
    (let ((check-it:*size* (max check-it:*size* size)))
      (loop repeat count collect (generate generator)))))

(deftest generated-values-satisfy-their-leaf-spec
  (dolist (form '(integer real character string (member :a :b :c)
                  (range 1 100) (range integer 1 100) (range integer 1 *)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest null-and-boolean-types
  (testing "NULL generates NIL"
    (ok (every #'null (draws-for 'null :count 5))))
  (testing "BOOLEAN generates only T and NIL"
    (ok (every (lambda (value) (member value '(t nil))) (draws-for 'boolean)))))

(deftest generated-values-satisfy-their-composite-spec
  (dolist (form '((or integer string) (nullable integer)
                  (tuple integer string) (list-of integer) (vector-of integer)))
    (testing (format nil "~S generates values it admits" form)
      (let ((spec (normalize-spec-form form)))
        (ok (every (lambda (value) (validp spec value)) (draws-for form)))))))

(deftest ranges-wider-than-check-its-default-size-are-honoured
  ;; check-it clamps every numeric limit to CHECK-IT:*SIZE*, which is 10 by
  ;; default.  Without the required-size accounting these two draw 10 and -10,
  ;; both outside the range that was asked for.
  (testing "a positive range that does not straddle zero stays inside itself"
    (ok (every (lambda (value) (<= 20 value 100))
               (draws-for '(range integer 20 100)))))
  (testing "a negative range stays inside itself"
    (ok (every (lambda (value) (<= -100 value -50))
               (draws-for '(range integer -100 -50)))))
  (testing "the widened size does not leak out of the draw"
    (draws-for '(range integer 20 100) :count 1)
    (ok (= 10 check-it:*size*))))

(deftest references-are-followed
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'small
                            (normalize-spec-form '(range integer 1 10) :name 'small))
    (testing "a reference generates through its target"
      (ok (every (lambda (value) (and (integerp value) (<= 1 value 10)))
                 (draws-for 'small :registry registry))))))

(deftest specs-without-a-generation-strategy-say-so
  (dolist (form '((not integer) (satisfies plusp) (instance-of standard-object)
                  (member) (or) (type hash-table)))
    (testing (format nil "~S signals GENERATOR-UNAVAILABLE" form)
      (ok (handler-case (progn (draws-for form :count 1) nil)
            (generator-unavailable () t))))))

(deftest recursive-specs-are-refused-rather-than-hanging
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'int-tree
                            (normalize-spec-form '(or integer (tuple int-tree int-tree))
                                                 :name 'int-tree))
    (testing "a self referential spec signals instead of recursing forever"
      (ok (handler-case (progn (draws-for 'int-tree :count 1 :registry registry) nil)
            (generator-unavailable () t))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `cl-spec/src/backends/check-it-generators` パッケージが存在しない

- [ ] **Step 3: 実装**

`src/backends/check-it-generators.lisp`:

```lisp
;;;; src/backends/check-it-generators.lisp
;;;;
;;;; Semantic IR -> check-it generator (specification §10, §12).  check-it's
;;;; GENERATOR macro expands into MAKE-INSTANCE forms over exported classes, so
;;;; the mapping is built by calling MAKE-INSTANCE directly: no runtime EVAL is
;;;; needed, and the DSL stays out of the compilation path.

(defpackage #:cl-spec/src/backends/check-it-generators
  (:use #:cl)
  (:import-from #:check-it
                #:int-generator
                #:real-generator
                #:char-generator
                #:string-generator
                #:list-generator
                #:tuple-generator
                #:or-generator
                #:guard-generator
                #:mapped-generator)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable
                #:unknown-spec)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-kind
                #:type-spec
                #:type-spec-type-specifier
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:member-spec
                #:member-spec-values
                #:or-spec
                #:or-spec-children
                #:and-spec
                #:and-spec-children
                #:nullable-spec
                #:nullable-spec-inner-spec
                #:tuple-spec
                #:tuple-spec-element-specs
                #:collection-spec
                #:collection-spec-element-spec
                #:list-of-spec
                #:vector-of-spec
                #:reference-spec
                #:reference-spec-target)
  (:import-from #:cl-spec/src/registry
                #:registry-find-spec)
  (:import-from #:cl-spec/src/resolve
                #:context-registry)
  (:import-from #:cl-spec/src/validator
                #:compile-validator)
  (:export #:spec-generator
           #:compile-spec-generator))

(in-package #:cl-spec/src/backends/check-it-generators)

(defvar *required-size* 0
  "Largest bound magnitude seen while compiling the current generator.

check-it clamps every numeric limit to CHECK-IT:*SIZE*, so a range that does not
overlap [-*size*, *size*] silently generates values outside itself: (range
integer 20 100) draws 10.  Compilation records how far *SIZE* has to be raised,
and the caller binds it around GENERATE.")

(defvar *reference-trail* nil
  "Spec names currently being compiled, innermost first.

Compiling a generator walks references eagerly, so a self referential spec
would recurse forever.  The trail turns that into a clear condition.")

(defgeneric spec-generator (spec context)
  (:documentation "Return a check-it generator producing values that satisfy SPEC.

CONTEXT is the compilation plist; :REGISTRY names the registry references
resolve against.  Signals GENERATOR-UNAVAILABLE when SPEC has no generation
strategy.  The result may be an ordinary value rather than a generator object:
check-it's GENERATE treats a non-generator as a constant."))

(defmethod spec-generator ((spec spec) context)
  (declare (ignore context))
  (error 'generator-unavailable
         :spec spec
         :reason (format nil "~S has no generation strategy" (spec-kind spec))))

(defun type-specifier-generator (type-specifier spec)
  "Return a generator for the Common Lisp TYPE-SPECIFIER.

The table is deliberately short.  A type is listed only when check-it produces
values the corresponding TYPEP actually accepts: REAL-GENERATOR yields floats,
so FLOAT and RATIONAL are absent rather than silently wrong."
  (case type-specifier
    ((integer) (make-instance 'int-generator))
    ((real) (make-instance 'real-generator))
    ((character) (make-instance 'char-generator))
    ((string) (make-instance 'string-generator))
    ((null) nil)
    ((boolean) (make-instance 'or-generator :sub-generators (list t nil)))
    (t (error 'generator-unavailable
              :spec spec
              :reason (format nil "no generator is registered for the type ~S"
                              type-specifier)))))

(defmethod spec-generator ((spec type-spec) context)
  (declare (ignore context))
  (type-specifier-generator (type-spec-type-specifier spec) spec))

(defun bounded-generator (base-type minimum maximum spec)
  "Return a numeric generator for BASE-TYPE limited by MINIMUM and MAXIMUM.

:UNBOUNDED is written back as check-it's own open bound marker, *.  Each finite
bound also raises *REQUIRED-SIZE*: without it check-it clamps the bound away and
generates outside the range."
  (dolist (bound (list minimum maximum))
    (unless (eq bound :unbounded)
      (setf *required-size* (max *required-size* (ceiling (abs bound))))))
  (let ((lower (if (eq minimum :unbounded) '* minimum))
        (upper (if (eq maximum :unbounded) '* maximum)))
    (case base-type
      ((integer) (make-instance 'int-generator :lower-limit lower :upper-limit upper))
      ((real) (make-instance 'real-generator :lower-limit lower :upper-limit upper))
      (t (error 'generator-unavailable
                :spec spec
                :reason (format nil "~S cannot carry a numeric range" base-type))))))

(defmethod spec-generator ((spec range-spec) context)
  (declare (ignore context))
  (bounded-generator (or (range-spec-base-type spec) 'real)
                     (range-spec-minimum spec)
                     (range-spec-maximum spec)
                     spec))

(defmethod spec-generator ((spec member-spec) context)
  (declare (ignore context))
  (let ((values (member-spec-values spec)))
    (when (null values)
      (error 'generator-unavailable :spec spec :reason "an empty MEMBER admits nothing"))
    (make-instance 'or-generator :sub-generators (copy-list values))))

(defmethod spec-generator ((spec or-spec) context)
  (let ((children (or-spec-children spec)))
    (when (null children)
      (error 'generator-unavailable :spec spec :reason "an empty OR admits nothing"))
    (make-instance 'or-generator
                   :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                           children))))

(defmethod spec-generator ((spec nullable-spec) context)
  (make-instance 'or-generator
                 :sub-generators
                 (list nil (spec-generator (nullable-spec-inner-spec spec) context))))

(defmethod spec-generator ((spec tuple-spec) context)
  (make-instance 'tuple-generator
                 :sub-generators (mapcar (lambda (child) (spec-generator child context))
                                         (tuple-spec-element-specs spec))))

(defmethod spec-generator ((spec list-of-spec) context)
  (let ((element (collection-spec-element-spec spec)))
    ;; check-it calls the generator function once per element per draw, which is
    ;; what lets it shrink each element independently.
    (make-instance 'list-generator
                   :generator-function (lambda () (spec-generator element context)))))

(defmethod spec-generator ((spec vector-of-spec) context)
  (let ((element (collection-spec-element-spec spec)))
    (make-instance 'mapped-generator
                   :mapping (lambda (items) (coerce items 'vector))
                   :sub-generators
                   (list (make-instance 'list-generator
                                        :generator-function
                                        (lambda () (spec-generator element context)))))))

(defmethod spec-generator ((spec reference-spec) context)
  (let ((target (reference-spec-target spec))
        (registry (context-registry context)))
    (when (member target *reference-trail*)
      (error 'generator-unavailable
             :spec spec
             :reason "recursive specs have no generator in this version"))
    (let ((resolved (or (registry-find-spec registry target)
                        (error 'unknown-spec :name target)))
          (*reference-trail* (cons target *reference-trail*)))
      (spec-generator resolved context))))

(defun compile-spec-generator (spec context)
  "Return (values GENERATOR REQUIRED-SIZE) for SPEC.

REQUIRED-SIZE is what CHECK-IT:*SIZE* has to reach for the generator to respect
the bounds the spec asks for.  The caller binds it around GENERATE; returning it
rather than binding it here lets one binding cover a whole trial loop."
  (let ((*required-size* 0))
    (values (spec-generator spec context) *required-size*)))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS。`(and ...)` はまだ未対応なので、テストに `and` を含めていないことを確認する

- [ ] **Step 5: コミット**

```bash
git add src/backends/check-it-generators.lisp tests/backends/check-it-test.lisp
git commit -m "feat: map the leaf and collection IR nodes onto check-it generators"
```

---

### Task 11: `and` の制約畳み込みと `generator-for` / `sample`

**Files:**
- Modify: `src/backends/check-it-generators.lisp`, `src/backends/check-it.lisp`, `src/generator.lisp`, `main.lisp`
- Test: `tests/backends/check-it-test.lisp`, `tests/generator-test.lisp`

**Interfaces:**
- Consumes: Task 9 の `seed->random-state`、Task 10 の `spec-generator`、Task 2 の `resolve-spec`
- Produces: `and-spec` の `spec-generator` メソッド。`generator-for (spec-designator &key context options registry)`、`sample (spec-designator &key count seed registry)`、generic `backend-default-trials (backend)`。`check-it-backend` の `compile-generator` / `generate-value` / `backend-default-trials` メソッド

- [ ] **Step 1: 失敗するテストを書く**

`tests/backends/check-it-test.lisp` に追加:

```lisp
(deftest and-folds-its-constraints-into-one-generator
  (testing "a type and a range collapse into a bounded generator"
    (let ((values (draws-for '(and integer (range 1 100)))))
      (ok (every (lambda (value) (and (integerp value) (<= 1 value 100))) values))))
  (testing "the section 67 example generates without a rejection loop"
    (ok (every (lambda (value) (and (integerp value) (>= value 1)))
               (draws-for '(and integer (range 1 *))))))
  (testing "overlapping ranges intersect"
    (ok (every (lambda (value) (<= 10 value 20))
               (draws-for '(and integer (range 1 20) (range 10 100))))))
  (testing "a leftover predicate becomes a guard, not a lost constraint"
    (ok (every #'oddp (draws-for '(and integer (range 1 100) (satisfies oddp))))))
  (testing "an AND with nothing to generate from is refused"
    (ok (handler-case (progn (draws-for '(and (satisfies oddp) (satisfies plusp)) :count 1) nil)
          (generator-unavailable () t))))
  (testing "an empty interval is refused rather than looping"
    (ok (handler-case (progn (draws-for '(and integer (range 10 20) (range 30 40)) :count 1) nil)
          (generator-unavailable () t)))))
```

`tests/generator-test.lisp` を書き換える。`defpackage` に `#:cl-spec/src/generator` から
`#:generator-for #:sample #:backend-default-trials #:current-generator-backend`、
`#:cl-spec/src/backends/check-it` から `#:check-it-backend`（backend を load させるため）、
`#:cl-spec/src/registry`、`#:cl-spec/src/normalize`、`#:cl-spec/src/validator` を import する。

```lisp
(deftest sample-produces-values-the-spec-admits
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'positive-integer
                            (normalize-spec-form '(and integer (range 1 *))
                                                 :name 'positive-integer))
    (testing "SAMPLE returns COUNT values"
      (ok (= 10 (length (sample 'positive-integer :registry registry))))
      (ok (= 3 (length (sample 'positive-integer :count 3 :registry registry)))))
    (testing "every sampled value satisfies the spec"
      (ok (every (lambda (value) (validp 'positive-integer value :registry registry))
                 (sample 'positive-integer :count 50 :registry registry))))
    (testing "the same seed reproduces the same sample"
      (ok (equal (sample 'positive-integer :count 20 :seed 4242 :registry registry)
                 (sample 'positive-integer :count 20 :seed 4242 :registry registry))))
    (testing "GENERATOR-FOR returns something GENERATE-VALUE accepts"
      (ok (generator-for 'positive-integer :registry registry))))
  (let ((registry (make-hash-table-registry)))
    (registry-register-spec registry 'wide
                            (normalize-spec-form '(range integer 20 100) :name 'wide))
    (testing "a range wider than check-it's default size is still respected"
      (ok (every (lambda (value) (<= 20 value 100))
                 (sample 'wide :count 50 :registry registry))))))

(deftest the-backend-supplies-a-default-trial-count
  (testing "BACKEND-DEFAULT-TRIALS is a positive integer read from check-it"
    (let ((trials (backend-default-trials (current-generator-backend))))
      (ok (integerp trials))
      (ok (plusp trials))))
  (testing "it is read live rather than snapshotted at load time"
    (ok (= 7 (let ((check-it:*num-trials* 7))
               (backend-default-trials (current-generator-backend)))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `and` が `generator-unavailable`、`sample` が `not-implemented`

- [ ] **Step 3: 実装**

`src/backends/check-it-generators.lisp` の末尾に追加:

```lisp
(defun merge-base-type (current new spec)
  "Return the base type implied by both CURRENT and NEW, signalling on conflict."
  (cond ((null current) new)
        ((null new) current)
        ((eq current new) current)
        ((and (member current '(integer real)) (member new '(integer real))) 'integer)
        (t (error 'generator-unavailable
                  :spec spec
                  :reason (format nil "conflicting base types ~S and ~S" current new)))))

(defun tighter-minimum (current new)
  "Return the greater of two lower bounds, treating :UNBOUNDED as no bound."
  (cond ((eq new :unbounded) current)
        ((eq current :unbounded) new)
        (t (max current new))))

(defun tighter-maximum (current new)
  "Return the lesser of two upper bounds, treating :UNBOUNDED as no bound."
  (cond ((eq new :unbounded) current)
        ((eq current :unbounded) new)
        (t (min current new))))

(defmethod spec-generator ((spec and-spec) context)
  ;; Folding rather than guarding is a correctness requirement, not an
  ;; optimisation: check-it's GUARD-GENERATOR retries by recursing into GENERATE
  ;; with no depth limit, so a guard that rejects often enough overflows the
  ;; stack.  Narrowing the base generator removes the rejection entirely.
  (let ((base-type nil)
        (minimum :unbounded)
        (maximum :unbounded)
        (leftovers '()))
    ;; Classification recurses: a REFERENCE-SPEC is resolved through the registry
    ;; and a nested AND-SPEC is flattened, so that (and integer my-range) folds
    ;; my-range's own bounds into the base rather than leaving them to the guard.
    ;; A flat TYPECASE over the two leaf classes would compile that spec to an
    ;; unbounded base under a guard that rejects every draw, which is the
    ;; unbounded GUARD-GENERATOR recursion this whole design exists to avoid.
    ;; *REFERENCE-TRAIL* guards the recursion, as in the REFERENCE-SPEC method.
    (labels ((classify (child)
               (typecase child
                 (type-spec
                  (setf base-type
                        (merge-base-type base-type (type-spec-type-specifier child) spec)))
                 (range-spec
                  (setf base-type (merge-base-type base-type (range-spec-base-type child) spec)
                        minimum (tighter-minimum minimum (range-spec-minimum child))
                        maximum (tighter-maximum maximum (range-spec-maximum child))))
                 (and-spec (mapc #'classify (and-spec-children child)))
                 (reference-spec
                  (let ((target (reference-spec-target child)))
                    (if (member target *reference-trail*)
                        (push child leftovers)
                        (let ((resolved (registry-find-spec (context-registry context) target))
                              (*reference-trail* (cons target *reference-trail*)))
                          (if resolved
                              (classify resolved)
                              (push child leftovers))))))
                 (t (push child leftovers)))))
      (mapc #'classify (and-spec-children spec)))
    (when (and (null base-type)
               (not (and (eq minimum :unbounded) (eq maximum :unbounded))))
      (setf base-type 'real))
    (when (null base-type)
      (error 'generator-unavailable
             :spec spec
             :reason "an AND needs a type or range conjunct to generate from"))
    (when (and (not (eq minimum :unbounded))
               (not (eq maximum :unbounded))
               (> minimum maximum))
      (error 'generator-unavailable :spec spec :reason "the folded range is empty"))
    (let ((base (if (and (eq minimum :unbounded) (eq maximum :unbounded))
                    (type-specifier-generator base-type spec)
                    (bounded-generator base-type minimum maximum spec))))
      (if leftovers
          (make-instance 'guard-generator
                         :guard (compile-validator spec :context context)
                         :sub-generator base)
          base))))
```

`src/generator.lisp` の `defpackage` に `#:cl-spec/src/registry` から `#:*registry*`、
`#:cl-spec/src/resolve` から `#:resolve-spec`、`#:cl-spec/src/utils/random` から
`#:seed->random-state` を import し、`:export` に `#:backend-default-trials` を追加。
`#:not-implemented` の import は不要になるので外す。本体:

```lisp
(defgeneric backend-default-trials (backend)
  (:documentation "Return the trial count BACKEND uses when a property names none.

The core cannot read check-it's own default, so the backend answers for it."))

(defun generator-for (spec-designator &key context options (registry *registry*))
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
The result is opaque to everything but the backend and GENERATE-VALUE."
  (let ((spec (resolve-spec spec-designator registry)))
    (compile-generator (current-generator-backend) spec
                       :context (or context (list :registry registry))
                       :options options)))

(defun sample (spec-designator &key (count 10) seed (registry *registry*))
  "Return a list of COUNT values generated from SPEC-DESIGNATOR.

SEED, when supplied, makes the whole sequence reproducible.  Intended for
inspecting what a spec admits, from the REPL or from an agent."
  (let ((backend (current-generator-backend))
        (generator (generator-for spec-designator :registry registry)))
    (flet ((draw ()
             (loop repeat count collect (generate-value backend generator))))
      (if seed
          (let ((*random-state* (seed->random-state seed)))
            (draw))
          (draw)))))
```

`src/backends/check-it.lisp` の `defpackage` に `#:check-it` から `#:generate #:*size*`、
`#:cl-spec/src/backends/check-it-generators` から `#:compile-spec-generator`、
`#:cl-spec/src/generator` から `#:backend-default-trials`、
`#:cl-spec/src/utils/random` から `#:seed->random-state` を追加し、
`compile-generator` と `generate-value` のスタブを置き換える:

```lisp
(defstruct (compiled-generator (:constructor make-compiled-generator (generator size)))
  "A check-it generator together with the CHECK-IT:*SIZE* its bounds require.

Pairing the two is what stops check-it from clamping a range away: *SIZE* has to
be raised around GENERATE, and only the compiler knows how far."
  (generator nil :read-only t)
  (size 0 :read-only t))

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator paired with the size its bounds need.

OPTIONS is accepted for protocol compatibility; check-it takes its sizing from
its own specials rather than per-generator options."
  (declare (ignore backend options))
  (multiple-value-bind (generator size) (compile-spec-generator spec context)
    (make-compiled-generator generator size)))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally from a seeded state."
  (declare (ignore backend))
  (flet ((draw ()
           (let ((*size* (max *size* (compiled-generator-size compiled-generator))))
             (generate (compiled-generator-generator compiled-generator)))))
    (if seed
        (let ((*random-state* (seed->random-state seed)))
          (draw))
        (draw))))

(defmethod backend-default-trials ((backend check-it-backend))
  "Return check-it's current default number of trials."
  (declare (ignore backend))
  *num-trials*)
```

`main.lisp` の `:import-from #:cl-spec/src/generator` と `:export` に
`#:backend-default-trials` を追加。

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/backends/check-it-generators.lisp src/backends/check-it.lisp src/generator.lisp \
        main.lisp tests/backends/check-it-test.lisp tests/generator-test.lisp
git commit -m "feat: fold AND constraints into one generator and wire up sample"
```

---

### Task 12: Property IR と `defproperty`

**Files:**
- Modify: `src/property.lisp`, `src/dsl.lisp`, `main.lisp`
- Test: `tests/property-test.lisp`, `tests/dsl-test.lisp`

**Interfaces:**
- Consumes: Task 3-4 の `normalize-spec-form`
- Produces: `property` クラスが `function` スロット（初期化引数 `:function`、reader `property-function`）を持つ。`arguments` は `(VARIABLE SPEC)` のリストで SPEC は正規化済み IR。`defproperty` が実際に property を登録する。`:shrink` は `metadata` に `(:shrink <boolean>)` として入る

- [ ] **Step 1: 失敗するテストを書く**

`tests/property-test.lisp` に追加:

```lisp
(deftest a-property-carries-a-callable-body
  (testing "PROPERTY-FUNCTION returns the compiled predicate"
    (let ((property (make-instance 'property
                                   :name 'p
                                   :function (lambda (x) (plusp x))
                                   :body '((plusp x)))))
      (ok (funcall (property-function property) 1))
      (ok (not (funcall (property-function property) -1))))
    (testing "the source body is kept alongside the compiled function"
      (ok (equal '((plusp x))
                 (property-body (make-instance 'property :body '((plusp x)))))))))
```

`tests/dsl-test.lisp` の `defproperty` に関するテストを書き換える:

```lisp
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
        ;; PROPERTIES-FOR returns names, not objects — see the docstrings on
        ;; REGISTRY-PROPERTIES-FOR and PROPERTIES-FOR in src/registry.lisp.
        (ok (equal '(addition-preserves-order)
                   (cl-spec/src/registry:properties-for '+)))))))

(deftest defproperty-stops-consuming-options-at-the-first-non-option
  (let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
    (eval '(cl-spec/src/dsl:defproperty stops-at-the-body ((x integer))
             (:kind :invariant)
             (integerp x)
             (:not-an-option-keyword x)))
    (testing "forms after the first non option stay in the body"
      (ok (= 2 (length (cl-spec/src/property:property-body
                        (cl-spec/src/registry:find-property 'stops-at-the-body))))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `property-function` が未定義、`defproperty` が `not-implemented`

- [ ] **Step 3: 実装**

`src/property.lisp`: `:export` に `#:property-function` を追加。`arguments` スロットの
docstring を差し替え、`function` スロットを `body` の直前に追加する。

```lisp
   (arguments :initarg :arguments
              :initform nil
              :reader property-arguments
              :documentation "List of (VARIABLE SPEC) bindings the generator
fills in.  SPEC is a normalized Semantic IR object; a spec written as a bare
symbol becomes a REFERENCE-SPEC, so a property may name a spec defined later.")
```

```lisp
   (property-function :initarg :function
                      :initform nil
                      :reader property-function
                      :documentation "The predicate compiled from BODY.
Kept alongside BODY rather than instead of it: a compiled function cannot be
read, and reading the property is half of what it is for (specification §39).")
```

`src/dsl.lisp`: `:import-from #:cl-spec/src/property` に `#:property` を追加し、
`expand-property-definition` と `defproperty` を置き換える。

```lisp
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

(defun expand-property-definition (whole name arguments body source-location)
  "Return the form DEFPROPERTY expands into.

Unlike the other expanders this runs at macroexpansion time, because the
predicate has to be compiled into a real function rather than kept as a list."
  (multiple-value-bind (documentation options forms) (parse-property-body body)
    (let ((shrink-clause (option-clause options :shrink)))
      `(register-property
        (make-instance 'property
                       :name ',name
                       :arguments (list ,@(loop for (variable form) in arguments
                                                collect `(list ',variable
                                                               (normalize-spec-form ',form))))
                       :targets ',(rest (option-clause options :about))
                       :kind ',(second (option-clause options :kind))
                       :tags ',(rest (option-clause options :tags))
                       :trials ',(second (option-clause options :trials))
                       :documentation ,documentation
                       :body ',forms
                       :source-form ',whole
                       :source-location ',source-location
                       :metadata (list :shrink ,(if shrink-clause (second shrink-clause) t))
                       :function (lambda ,(mapcar #'first arguments) ,@forms))))))

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
```

`main.lisp` の `:import-from #:cl-spec/src/property` と `:export` に `#:property-function` を追加。

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/property.lisp src/dsl.lisp main.lisp tests/property-test.lisp tests/dsl-test.lisp
git commit -m "feat: compile defproperty into a registered, callable property"
```

---

### Task 13: Property runner と backend の trial ループ

**Files:**
- Modify: `src/property-runner.lisp`, `src/backends/check-it.lisp`
- Test: `tests/property-runner-test.lisp`

**Interfaces:**
- Consumes: Task 9 の `make-seed` / `seed->random-state`、Task 11 の `backend-default-trials` / `compile-generator`、Task 12 の `property-function`
- Produces: `run-property (property-designator &key profile seed options registry)` が `property-result` を返す。`run-generated-test` は `(:status :passed|:failed|:error :trials <n> :counterexample <値のリスト> :shrunk-counterexample <値のリスト> :condition <condition>)` を返す

- [ ] **Step 1: 失敗するテストを書く**

`tests/property-runner-test.lisp` を書き換える。`defpackage` に `#:cl-spec/src/dsl`、
`#:cl-spec/src/registry`、`#:cl-spec/src/property-runner`、`#:cl-spec/src/backends/check-it`
（backend をロードさせる）を import する。

```lisp
(defmacro with-fresh-registry (&body body)
  "Run BODY against a registry no other test can see."
  `(let ((cl-spec/src/registry:*registry* (cl-spec/src/registry:make-hash-table-registry)))
     ,@body))

(deftest a-passing-property-reports-passed
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty always-holds ((x small))
             (:trials (:normal 25))
             (integerp x)))
    (let ((result (run-property 'always-holds)))
      (testing "the status and trial count are reported"
        (ok (eq :passed (property-result-status result)))
        (ok (= 25 (property-result-trials result))))
      (testing "the seed is recorded even on success"
        (ok (integerp (property-result-seed result))))
      (testing "no counterexample is reported"
        (ok (null (property-result-counterexample result))))
      (testing "the elapsed time is recorded"
        (ok (realp (property-result-elapsed result)))))))

(deftest a-failing-property-reports-a-named-counterexample
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty never-holds ((x small) (y small))
             (:trials (:normal 25))
             (and x y nil)))
    (let ((result (run-property 'never-holds)))
      (testing "the status is :FAILED"
        (ok (eq :failed (property-result-status result))))
      (testing "it stopped at the first failing trial"
        (ok (= 1 (property-result-trials result))))
      (testing "the counterexample is keyed by the argument names"
        (let ((counterexample (property-result-counterexample result)))
          (ok (integerp (getf counterexample 'x)))
          (ok (integerp (getf counterexample 'y))))))))

(deftest a-signalling-property-reports-error-and-keeps-the-condition
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty always-signals ((x small))
             (:trials (:normal 5))
             (error "boom ~S" x)))
    (let ((result (run-property 'always-signals)))
      (testing "the status distinguishes a signalled condition from a NIL result"
        (ok (eq :error (property-result-status result))))
      (testing "the condition itself is kept"
        (ok (typep (property-result-condition result) 'error))
        (ok (search "boom" (princ-to-string (property-result-condition result))))))))

(deftest failures-are-shrunk
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty stays-under-ten ((x small))
             (:trials (:normal 200))
             (< x 10)))
    (let* ((result (run-property 'stays-under-ten))
           (original (getf (property-result-counterexample result) 'x))
           (shrunk (getf (property-result-shrunk-counterexample result) 'x)))
      (testing "the property does fail"
        (ok (eq :failed (property-result-status result))))
      (testing "the shrunk value is no larger than the original"
        (ok (<= shrunk original)))
      (testing "the shrunk value still fails the property"
        (ok (>= shrunk 10)))
      (testing "the original counterexample survives shrinking"
        (ok (>= original 10))))))

(deftest shrinking-can-be-turned-off
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty unshrunk ((x small))
             (:trials (:normal 25))
             (:shrink nil)
             (and x nil)))
    (testing "no shrunk counterexample is produced"
      (ok (null (property-result-shrunk-counterexample (run-property 'unshrunk)))))))

(deftest an-unregistered-property-signals
  (with-fresh-registry
    (testing "RUN-PROPERTY signals UNKNOWN-PROPERTY"
      (ok (signals (run-property 'absent) 'cl-spec/src/conditions:unknown-property)))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `run-property` が `not-implemented`

- [ ] **Step 3: 実装**

`src/backends/check-it.lisp` の `defpackage` に `#:check-it` から `#:cached-value #:shrink
#:tuple-generator`、`#:cl-spec/src/property` から `#:property-arguments #:property-function
#:property-metadata` を追加し、`#:cl-spec/src/conditions` からの `#:not-implemented` の import を
外して（このファイルにスタブが残らなくなる）、`run-generated-test` を置き換える:

```lisp
(defun call-property (function arguments)
  "Apply FUNCTION to ARGUMENTS, returning (values RESULT CONDITION).

A signalled condition is data here rather than a stack unwind: section 13 counts
it as a failure, and the result has to say which kind of failure it was."
  (handler-case (values (apply function arguments) nil)
    (error (condition) (values nil condition))))

(defun copy-generated-value (value)
  "Return a copy of VALUE deep enough to survive check-it's in-place shrinking.

CHECK-IT:SHRINK mutates a list generator's cached value with SETF NTH, and a
tuple's element is the very object its sub-generator cached, so a shallow copy
still loses the original counterexample.  Conses and non-string vectors are the
only shapes this backend's generators produce that check-it mutates; strings
come back fresh from JOIN-LIST and scalars are immutable, so the recursion stops
at both."
  (typecase value
    (cons (mapcar #'copy-generated-value value))
    ((and vector (not string)) (map 'vector #'copy-generated-value value))
    (t value)))

(defun shrinking-test (function)
  "Return the one-argument test CHECK-IT:SHRINK drives.

SHRINK hands the test a whole argument list, and an error during shrinking means
the smaller value still fails."
  (lambda (arguments)
    (handler-case (apply function arguments)
      (error () nil))))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Run PROPERTY through check-it, shrinking any counterexample.

Returns the plist the caller assembles into a PROPERTY-RESULT:

  (:status :passed | :failed | :error
   :trials <integer>
   :counterexample <list of values>
   :shrunk-counterexample <list of values>
   :condition <condition or NIL>)

Counterexamples are positional.  Naming the arguments is the caller's job, which
is what keeps this method from having to know the property's variables."
  (let* ((context (list :registry (getf options :registry)))
         (trials (getf options :trials))
         (function (property-function property))
         (shrink-p (getf (property-metadata property) :shrink t))
         (compiled (loop for (nil spec) in (property-arguments property)
                         collect (compile-generator backend spec :context context)))
         ;; One binding covers generation and shrinking alike, and has to be
         ;; wide enough for the widest bound any argument asks for.
         (*size* (reduce #'max compiled
                         :key #'compiled-generator-size :initial-value *size*))
         (generator (make-instance 'tuple-generator
                                   :sub-generators
                                   (mapcar #'compiled-generator-generator compiled))))
    (loop for trial from 1 to trials
          do (generate generator)
             ;; CHECK-IT:SHRINK rewrites the tuple generator's cached value in
             ;; place, so the counterexample must be copied out before it runs —
             ;; and deeply: for a compound argument the tuple's element is EQ to
             ;; the sub-generator's own cached value, which SHRINK-LIST-GENERATOR
             ;; mutates, so copying only the spine still loses the original.
             (let ((arguments (copy-generated-value (cached-value generator))))
               (multiple-value-bind (result condition) (call-property function arguments)
                 (when (or condition (null result))
                   (return (list :status (if condition :error :failed)
                                 :trials trial
                                 :counterexample arguments
                                 :shrunk-counterexample
                                 (when shrink-p
                                   (copy-generated-value
                                    (shrink generator (shrinking-test function))))
                                 :condition condition)))))
          finally (return (list :status :passed :trials trials)))))
```

`src/property-runner.lisp` の `defpackage` に `#:cl-spec/src/property` から
`#:property-name #:property-arguments #:property-trials`、`#:cl-spec/src/registry` から
`#:*registry*`、`#:cl-spec/src/resolve` から `#:resolve-property`、`#:cl-spec/src/generator` から
`#:current-generator-backend #:run-generated-test #:backend-default-trials`、
`#:cl-spec/src/utils/random` から `#:make-seed #:seed->random-state` を追加する。
`#:not-implemented` の import は Task 14 で最後のスタブが消えるまで残す。
`declaim` に `(:registry t)` を足す:

```lisp
(declaim (ftype (function ((or symbol property)
                           &key (:profile t) (:seed t) (:options t) (:registry t))
                          (values property-result &optional))
                run-property))
```

`run-property` を置き換える:

```lisp
(defun resolve-trials (property profile backend)
  "Return the trial count for PROPERTY under PROFILE (specification §33).

PROPERTY-TRIALS is a plist keyed by profile; a property that names no count for
the profile in effect falls back to the backend's own default."
  (let ((table (property-trials property)))
    (or (and table (getf table (or profile :normal)))
        (backend-default-trials backend))))

(defun name-arguments (property values)
  "Return VALUES as a plist keyed by PROPERTY's argument variables.

The backend reports counterexamples positionally; this is where they become the
{name: value} shape section 14 shows."
  (when values
    (loop for (variable nil) in (property-arguments property)
          for value in values
          append (list variable value))))

(defun run-property (property-designator &key profile seed options (registry *registry*))
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS table (§33).  SEED, when
supplied, reproduces an earlier run; when omitted a fresh seed is drawn and
recorded so the run can be replayed later.  OPTIONS is passed through to the
backend."
  (let* ((property (resolve-property property-designator registry))
         (backend (current-generator-backend))
         (effective-seed (or seed (make-seed)))
         (trials (resolve-trials property profile backend))
         (start (get-internal-real-time))
         ;; One binding covers generation and shrinking alike, because the whole
         ;; trial loop lives inside this single call.
         (outcome (let ((*random-state* (seed->random-state effective-seed)))
                    (run-generated-test backend property
                                        :options (list* :trials trials
                                                        :registry registry
                                                        options))))
         (elapsed (/ (float (- (get-internal-real-time) start))
                     internal-time-units-per-second)))
    (make-instance 'property-result
                   :status (getf outcome :status)
                   :property (property-name property)
                   :trials (getf outcome :trials)
                   :seed effective-seed
                   :counterexample (name-arguments property (getf outcome :counterexample))
                   :shrunk-counterexample (name-arguments
                                           property (getf outcome :shrunk-counterexample))
                   :condition (getf outcome :condition)
                   :elapsed elapsed)))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/property-runner.lisp src/backends/check-it.lisp tests/property-runner-test.lisp
git commit -m "feat: run properties into a structured, seeded, shrunk result"
```

---

### Task 14: `run-properties` / `replay-property` / `property-data`

**Files:**
- Modify: `src/property-runner.lisp`, `src/introspection.lisp`
- Test: `tests/property-runner-test.lisp`, `tests/introspection-test.lisp`

**Interfaces:**
- Consumes: Task 13 の `run-property`、Task 8 の `spec->data`、Task 2 の `resolve-property`
- Produces: `run-properties (designators &key profile options registry)`、`replay-property (designator seed &key options registry)`（`seed` は整数でも `property-result` でもよい）、`property-data (property-designator &key registry)`

- [ ] **Step 1: 失敗するテストを書く**

`tests/property-runner-test.lisp` に追加:

```lisp
(deftest replay-reproduces-a-run
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 1000)))
    ;; The range is wider than check-it's default size on purpose: the run only
    ;; reaches a counterexample if the required-size accounting works.
    (eval '(cl-spec/src/dsl:defproperty replayable ((x small))
             (:trials (:normal 200))
             (< x 500)))
    (let ((first-run (run-property 'replayable)))
      (testing "the property does fail, so there is something to reproduce"
        (ok (eq :failed (property-result-status first-run))))
      (testing "an integer seed reproduces the counterexample"
        (let ((again (replay-property 'replayable (property-result-seed first-run))))
          (ok (equal (property-result-counterexample first-run)
                     (property-result-counterexample again)))
          (ok (= (property-result-trials first-run) (property-result-trials again)))))
      (testing "a result object may be passed in place of its seed"
        (let ((again (replay-property 'replayable first-run)))
          (ok (eql (property-result-seed first-run) (property-result-seed again)))
          (ok (equal (property-result-counterexample first-run)
                     (property-result-counterexample again))))))))

(deftest run-properties-runs-each-one
  (with-fresh-registry
    (eval '(cl-spec/src/dsl:defspec small (range integer 1 100)))
    (eval '(cl-spec/src/dsl:defproperty holds ((x small)) (:trials (:normal 5)) (integerp x)))
    (eval '(cl-spec/src/dsl:defproperty fails ((x small)) (:trials (:normal 5)) (and x nil)))
    (let ((results (run-properties '(holds fails))))
      (testing "one result per designator, in order"
        (ok (= 2 (length results)))
        (ok (equal '(holds fails) (mapcar #'property-result-property results)))
        (ok (equal '(:passed :failed) (mapcar #'property-result-status results)))))))
```

`tests/introspection-test.lisp` に追加:

```lisp
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
          ;; A bare symbol argument spec normalizes to a REFERENCE-SPEC, not to
          ;; the target's own node — that late resolution is what makes forward
          ;; references work.
          (ok (eq :reference (getf (getf (first arguments) :spec) :kind)))
          (ok (eq 'positive-integer (getf (getf (first arguments) :spec) :target)))))
      (testing "the body is readable rather than compiled away"
        (ok (equal '((> (+ x y) x)) (getf data :body)))))))
```

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `run-properties` / `replay-property` / `property-data` が `not-implemented`

- [ ] **Step 3: 実装**

`src/property-runner.lisp` のスタブ2つを置き換え、`#:not-implemented` の import を外す
（このファイルにスタブが残らなくなる）:

```lisp
(defun run-properties (property-designators &key profile options (registry *registry*))
  "Run each property in PROPERTY-DESIGNATORS and return the results in order.

Each run draws its own seed, so one failure can be replayed without re-running
the others."
  (mapcar (lambda (designator)
            (run-property designator :profile profile :options options :registry registry))
          property-designators))

(defun replay-property (property-designator seed &key options (registry *registry*))
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

SEED is either the integer seed of an earlier run or the PROPERTY-RESULT that
run produced, since section 15 shows both spellings and an agent holding a
result should not have to dig the seed out of it."
  (run-property property-designator
                :seed (if (typep seed 'property-result)
                          (property-result-seed seed)
                          seed)
                :options options
                :registry registry))
```

`src/introspection.lisp` の `defpackage` に `#:cl-spec/src/property` から
`#:property-name #:property-arguments #:property-targets #:property-kind #:property-tags
#:property-documentation #:property-body #:property-source-form #:property-source-location
#:property-trials #:property-metadata`、`#:cl-spec/src/resolve` から `#:resolve-property`
を追加し、`property-data` を置き換える:

```lisp
(defun property-data (property-designator &key (registry *registry*))
  "Return a plist describing the registered property named by PROPERTY-DESIGNATOR.

  (:name <symbol> :kind <keyword> :targets (<symbol> ...) :tags (<tag> ...)
   :documentation <string> :trials <plist>
   :arguments ((:variable <symbol> :spec <spec-data plist>) ...)
   :body (<form> ...) :source-form <form>
   :source-location (:file <string> :package <string>) :metadata <plist>)

The body is the author's source rather than the compiled function, because a
compiled function cannot be read (specification §39)."
  (let ((property (resolve-property property-designator registry)))
    (list :name (property-name property)
          :kind (property-kind property)
          :targets (property-targets property)
          :tags (property-tags property)
          :documentation (property-documentation property)
          :trials (property-trials property)
          :arguments (loop for (variable spec) in (property-arguments property)
                           collect (list :variable variable :spec (spec->data spec)))
          :body (property-body property)
          :source-form (property-source-form property)
          :source-location (source-location->data (property-source-location property))
          :metadata (property-metadata property))))
```

- [ ] **Step 4: テストが通ることを確認**

Run: `rove cl-spec.asd`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add src/property-runner.lisp src/introspection.lisp \
        tests/property-runner-test.lisp tests/introspection-test.lisp
git commit -m "feat: add replay, batch runs and property introspection"
```

---

### Task 15: 自己 property、ドキュメント更新、最終検証

**Files:**
- Create: `tests/self-properties-test.lisp`
- Modify: `tests.lisp`, `docs/cl-spec-specification-v0.2-draft.md`, `docs/cl-spec-skeleton-followups.md`, `CLAUDE.md`, `AGENTS.md`, `README.md`

**Interfaces:**
- Consumes: 全タスクの成果
- Produces: §68 の自己 property スイート。仕様書とプロジェクト文書が実装状態と一致する

- [ ] **Step 1: 失敗するテストを書く**

`tests/self-properties-test.lisp`:

```lisp
;;;; tests/self-properties-test.lisp
;;;;
;;;; The framework tested with its own property runner (specification §68).
;;;; These specs and properties register into the global *REGISTRY* under
;;;; SELF- prefixed names, because a property has to be registered to be run.

(defpackage #:cl-spec/tests/self-properties-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defproperty)
  (:import-from #:cl-spec/src/explain
                #:explain-data)
  (:import-from #:cl-spec/src/generator
                #:sample)
  (:import-from #:cl-spec/src/property-runner
                #:run-property
                #:replay-property
                #:property-result-status
                #:property-result-seed
                #:property-result-counterexample)
  (:import-from #:cl-spec/src/registry
                #:find-spec
                #:list-specs)
  (:import-from #:cl-spec/src/validator
                #:validp))

(in-package #:cl-spec/tests/self-properties-test)

(defspec self-positive-integer (and integer (range 1 *)))

(defproperty self-generated-values-satisfy-their-spec ((x self-positive-integer))
  "Whatever the generator produces, the spec it came from admits."
  (:about sample)
  (:kind :invariant)
  (validp 'self-positive-integer x))

(defproperty self-validp-agrees-with-explain-data ((x integer))
  "VALIDP and EXPLAIN-DATA never disagree about the same value."
  (:about validp)
  (:kind :invariant)
  (eq (and (validp 'self-positive-integer x) t)
      (and (getf (explain-data 'self-positive-integer x) :valid) t)))

(defproperty self-and-matches-its-conjuncts ((x integer))
  "A conjunction admits exactly what all of its conjuncts admit."
  (:about validp)
  (:kind :invariant)
  (eq (and (validp 'self-positive-integer x) t)
      (and (integerp x) (>= x 1) t)))

(defproperty self-registry-lookup-is-stable ((x self-positive-integer))
  "Looking a spec up twice returns the same object."
  (:about find-spec)
  (:kind :invariant)
  (and x (eq (find-spec 'self-positive-integer) (find-spec 'self-positive-integer))))

(deftest the-framework-satisfies-its-own-properties
  (dolist (name '(self-generated-values-satisfy-their-spec
                  self-validp-agrees-with-explain-data
                  self-and-matches-its-conjuncts
                  self-registry-lookup-is-stable))
    (testing (format nil "~S passes" name)
      (let ((result (run-property name)))
        (ok (eq :passed (property-result-status result))
            (format nil "~S: ~S" name (property-result-counterexample result)))))))

(deftest sampled-values-satisfy-the-spec-they-came-from
  (testing "every sampled value is admitted by its own spec"
    (ok (every (lambda (value) (validp 'self-positive-integer value))
               (sample 'self-positive-integer :count 100)))))

(defspec self-small-integer (range integer 1 100))

(defproperty self-fails-above-ten ((x self-small-integer))
  "Deliberately false above ten, so that replay has something to reproduce."
  (:kind :invariant)
  (:trials (:normal 200))
  (< x 10))

(deftest a-seed-reproduces-the-same-counterexample
  (let ((first-run (run-property 'self-fails-above-ten)))
    (testing "the property fails, as it is meant to"
      (ok (eq :failed (property-result-status first-run))))
    (testing "replaying from the recorded seed finds the same counterexample"
      (ok (equal (property-result-counterexample first-run)
                 (property-result-counterexample
                  (replay-property 'self-fails-above-ten
                                   (property-result-seed first-run))))))))
```

`tests.lisp` の `defpackage` の末尾に `(:import-from #:cl-spec/tests/self-properties-test)` を追加。

- [ ] **Step 2: 失敗を確認**

Run: `rove cl-spec.asd`
Expected: FAIL — `cl-spec/tests/self-properties-test` パッケージが存在しない（テストファイルを
作った後は PASS するはず。ここで落ちるなら実装に穴がある）

- [ ] **Step 3: ドキュメントを実装状態に合わせる**

`docs/cl-spec-specification-v0.2-draft.md` の §9「初期primitive候補」のコードブロック直後に
一文を足す:

```markdown
`cons-of` はMVPでは実装しない。§52のMVP対応リストにも含まれておらず、§7のIRクラス階層にも
対応ノードが無い。post-MVPとして扱い、`(tuple ...)` または `(list-of ...)` で代替する。
```

§33 の `:trials` の例を plist 記法へ差し替える:

```lisp
(:trials (:smoke 10 :normal 100 :extended 1000 :stress 100000))
```

§67 の `spec-data` の概念結果のコードブロック直後に一文を足す:

```markdown
上の例は説明のため省略している。実際の`spec-data`は全ノードで同じキー集合
（`:name` `:kind` ノード固有キー `:source-form` `:source-location`）を返し、
`:children` は子を持つノードにのみ付く。値によってキーが出没しないほうが、
JSON/MCP投影の消費側を壊しにくい。
```

`docs/cl-spec-skeleton-followups.md` の項目 1、3、5 の見出し直後に、決着した旨と
本設計文書への参照を1行ずつ足す。項目 4 には「`defgenerator` がMVPスコープ外のため未決着」と足す。

`CLAUDE.md` と `AGENTS.md` の "Current status" 段落を書き換える:

```markdown
**Current status: MVP vertical slice.** Normalization, validation, structured
explain, spec introspection, the check-it generator backend, `defproperty` and
the property runner with seed, replay and shrinking are implemented. Function
specs (`defspec-function`, `check-function`), custom generators
(`defgenerator`), the `describe-*` printers, instrumentation and the cl-mcp
adapter are still stubs that signal `not-implemented`.
```

`CLAUDE.md` の "Implementation Order" 節を、次が §70 の step 16（Function Spec IR）である旨へ更新し、
`README.md` に §67 の動く例を載せる。

`.mallet.lisp` の `:for-paths` を、`eval` でマクロ展開を実行検証するテストファイル全部へ広げる:

```lisp
 (:for-paths ("tests/dsl-test.lisp"
              "tests/property-runner-test.lisp"
              "tests/introspection-test.lisp"
              "tests/self-properties-test.lisp")
   (:disable :no-eval))
```

ヘッダコメントも、これが DSL マクロの展開結果を実行して検証するための例外であることを
1ファイルではなく1カテゴリの話として書き直す。

- [ ] **Step 4: 全体を検証**

新しい Lisp プロセスで（開発中の REPL ではなく）:

```bash
ros run --eval '(asdf:compile-system :cl-spec :force :all)' --eval '(uiop:quit 0)'
```
Expected: 警告 0

```bash
ros run --eval '(ql:quickload :cl-spec :silent t)' \
        --eval '(uiop:quit (if (find-package "CHECK-IT") 1 0))'
```
Expected: 終了コード 0（コアが check-it を引き込まない）

```bash
rove cl-spec.asd
```
Expected: 全 test system が green

```bash
mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
```
Expected: 実行できること。指摘は advisory なのでブロッカーではないが、内容を確認して
`docs/cl-spec-skeleton-followups.md` の項目 6 へ追記する。

- [ ] **Step 5: コミット**

```bash
git add tests/self-properties-test.lisp tests.lisp docs CLAUDE.md AGENTS.md README.md .mallet.lisp
git commit -m "test: check the framework with its own properties, and sync the docs"
```
