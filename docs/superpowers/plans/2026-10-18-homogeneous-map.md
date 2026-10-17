# 同種マップ spec（`hash-table-of` / `alist-of`）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** すべてのキーが K、すべての値が V を満たす任意キーのマップを `(hash-table-of K V ...)` / `(alist-of K V ...)` として宣言でき、検証・説明・introspection・生成・縮小まで動くようにする。

**Architecture:** `field-spec` / `collection-spec` から独立した IR ファミリー（抽象 `map-of-spec` と2つの具象クラス）を `src/map-spec.lisp` に置く。検証・説明は `explain.lisp`、introspection は `introspection.lisp`、digest は `schema.lisp`、生成・縮小は `backends/check-it-generators.lisp` と `backends/check-it.lisp` に、既存の `tagged-by` と同じ配置で足す。キーの引き直しだけが generation request の共有予算を使う。

**Tech Stack:** Common Lisp (SBCL)、ASDF package-inferred-system、Rove、check-it。

**設計書:** `docs/superpowers/specs/2026-10-18-homogeneous-map-design.md`

## Global Constraints

- core system（`cl-spec`）は check-it を読み込まない。生成器のコードは `src/backends/` にだけ置く。
- `src/` の中から `cl-spec` nickname を参照しない（ASDF の依存が循環する）。
- 新しいファイルは `;;;; <path>` → `defpackage` → `(in-package ...)` で始める。`(:use #:cl)` のみ、他は `:import-from`。
- 公開関数・マクロ・クラスには docstring を書く。2 スペースインデント、100 桁以内、トップレベル form の間に空行。
- 新しいテストファイルは必ず `tests.lisp` に `:import-from` で登録する（しないと実行されない）。
- Lisp ソースの読み書きは cl-mcp ツール（`lisp-read-file`、`lisp-edit-form`、`lisp-patch-form`、新規ファイルだけ `fs-write-file`）で行う。shell は `git` と `mallet` だけに使う。
- テストの実行：
  - 1 スイート：`repl-eval` で `(rove:run :cl-spec/tests/map-spec-test)`（事前に `load-system` で `cl-spec/tests` を読み込む）。
  - 1 テスト：`run-tests` に `{"system": "cl-spec/tests", "test": "cl-spec/tests/map-spec-test::<name>"}`。
  - 全体：`run-tests` に `{"system": "cl-spec/tests"}`。
- lint（mallet）の指摘は現状 advisory。テスト失敗とは別に扱う。
- 既存の契約（テスト）を、通すために弱めない。

## 前提（Task 1 の前に必ず確認）

作業ツリーに、この機能とは無関係の未コミットの変更（`CLAUDE.md`、`tests.lisp`、`examples/sqlite-transfer.lisp`、`tests/sqlite-transfer-example-test.lisp`）がある。Task 1・Task 4 は `tests.lisp` を、Task 6 は `CLAUDE.md` を編集するので、混ざったままでは対象の差分だけをコミットできない。**実行前に、ユーザーにこれらの扱い（別ブランチへのコミットか stash）を決めてもらう。** git worktree は使わない。ASDF は `~/.roswell/local-projects/cl-spec` の `cl-spec.asd` を解決するので、worktree で編集してもテストは元のツリーに対して走る。

作業ブランチは `design/homogeneous-map`（設計書のコミットが乗っている）。

## ファイル構成

| ファイル | 種別 | 責務 |
|---|---|---|
| `src/map-spec.lisp` | 新規 | IR クラス、スロット検査、key-test の正規化、count 制約の plist |
| `src/normalize.lisp` | 変更 | `hash-table-of` / `alist-of` の head と options の正規化 |
| `src/field-spec.lisp` | 変更 | `alist-structure-error` の重複検査を線形にする |
| `src/explain.lisp` | 変更 | `compile-node`、`expected-descriptor`、`:entry-path` |
| `src/function-spec.lisp` | 変更 | `*failure-shape-keys*` に新しいキーを分類 |
| `src/introspection.lisp` | 変更 | `node-attributes` |
| `src/schema.lisp` | 変更 | `definition-constraints`、`definition-description-complete-p` |
| `src/generation-request.lisp` | 変更 | `generation-candidate-available-p` を追加 |
| `src/backends/check-it-generators.lisp` | 変更 | 生成器クラス、キーの抽選と予算計上、縮小 |
| `src/backends/check-it.lisp` | 変更 | `generator-shrink-strategy-p` の分岐 |
| `tests/map-spec-test.lisp` | 新規 | 正規化・定義検査・検証・説明・識別子・introspection・digest・coverage・codec |
| `tests/backends/map-generator-test.lisp` | 新規 | 生成・予算計上・独立性・縮小・capability |
| `tests/normalize-test.lisp` | 変更 | `*spec-primitives*` の期待値 |
| `tests/function-spec-test.lisp` | 変更 | エラーキー分類テストにマップの形と値を追加 |
| `tests/backends/and-generation-test.lisp` | 変更 | `generation-candidate-available-p` のテスト |
| `tests.lisp` | 変更 | 新しい2つのテストパッケージを登録 |
| `docs/cl-spec-specification-v0.2-draft.md` | 変更 | §0.2 状況表、§9 一覧、新 §9.6、予算の節 |
| `CLAUDE.md`、`AGENTS.md` | 変更 | Current status への追記（両方に同じ段落がある） |

---

### Task 1: IR と正規化

**Files:**
- Create: `src/map-spec.lisp`
- Modify: `src/normalize.lisp`（package の import、`*spec-primitives*`、新しい関数2つ、`normalize-compound` の分岐）
- Create: `tests/map-spec-test.lisp`
- Modify: `tests/normalize-test.lisp`（`mvp-primitives-are-declared`）
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/field-spec:key-test-designator`（keyword または通常の symbol から `:eq`/`:eql`/`:equal`/`:equalp` を返す。不明なら NIL）。
- Produces（package `cl-spec/src/map-spec`）:
  - クラス `map-of-spec`（抽象）、`hash-table-of-spec`（`spec-kind` → `:hash-table-of`）、`alist-of-spec`（`spec-kind` → `:alist-of`）。initargs：`:key-spec`、`:value-spec`、`:key-test`（既定 `:eql`）、`:min-count`（既定 0）、`:max-count`（既定 `:unbounded`）。
  - reader：`map-spec-key-spec`、`map-spec-value-spec`、`map-spec-key-test`（常に正規の keyword）、`map-spec-min-count`、`map-spec-max-count`。
  - `(map-count-constraint-plist spec)` → 既定値でない count 制約だけの plist（例 `(:min-count 1)`、両方既定なら NIL）。
  - `spec-children` は `(key-spec value-spec)`。

- [ ] **Step 1: テストファイルを作り、`tests.lisp` に登録する**

`fs-write-file` で `tests/map-spec-test.lisp` を作る（後の Task で使う import もここで全部宣言しておく）：

```lisp
;;;; tests/map-spec-test.lisp

(defpackage #:cl-spec/tests/map-spec-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/map-spec
                #:hash-table-of-spec #:alist-of-spec
                #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
                #:map-spec-min-count #:map-spec-max-count)
  (:import-from #:cl-spec/src/ir #:type-spec)
  (:import-from #:cl-spec/src/definition-validation #:validate-definition)
  (:import-from #:cl-spec/src/explain #:expected-descriptor)
  (:import-from #:cl-spec/src/function-spec #:failure-signature)
  (:import-from #:cl-spec/src/schema #:definition-constraints)
  (:import-from #:cl-spec/src/coverage-plist #:plist-coverage-schema)
  (:import-from #:cl-spec/src/utils/artifact-values
                #:encode-artifact-value #:artifact-value-error)
  (:import-from #:cl-spec/main
                #:normalize-spec-form #:invalid-spec-form #:validp #:explain-data
                #:spec-data #:definition-digest #:*registry*))

(in-package #:cl-spec/tests/map-spec-test)

(defun refuses-form-p (form)
  "Recognize declaration refusal without catching unrelated errors."
  (handler-case (progn (normalize-spec-form form) nil)
    (invalid-spec-form () t)))

(defun make-table (test &rest entries)
  "Build a hash table with TEST holding (KEY . VALUE) ENTRIES in order."
  (let ((table (make-hash-table :test test)))
    (loop for (key . value) in entries
          do (setf (gethash key table) value))
    table))

(defun errors-of (form value)
  "Return the structured errors of VALUE against the DSL FORM."
  (getf (explain-data (normalize-spec-form form) value) :errors))

(deftest map-forms-normalize-into-the-ir
  (let ((table (normalize-spec-form '(hash-table-of string integer)))
        (alist (normalize-spec-form '(alist-of keyword (list-of string)
                                      :test equal :min-count 1 :max-count 4))))
    (testing "a map without options uses EQL and no count bounds"
      (ok (typep table 'hash-table-of-spec))
      (ok (typep (map-spec-key-spec table) 'type-spec))
      (ok (typep (map-spec-value-spec table) 'type-spec))
      (ok (eq :eql (map-spec-key-test table)))
      (ok (zerop (map-spec-min-count table)))
      (ok (eq :unbounded (map-spec-max-count table))))
    (testing "declared options reach the IR"
      (ok (typep alist 'alist-of-spec))
      (ok (eq :equal (map-spec-key-test alist)))
      (ok (= 1 (map-spec-min-count alist)))
      (ok (= 4 (map-spec-max-count alist))))
    (testing "a keyword and a plain symbol name the same test; * is unbounded"
      (ok (eq :equalp (map-spec-key-test (normalize-spec-form '(hash-table-of t t :test :equalp)))))
      (ok (eq :unbounded
              (map-spec-max-count (normalize-spec-form '(alist-of t t :max-count *))))))))

(deftest malformed-map-declarations-are-refused
  (dolist (form '((hash-table-of)
                  (hash-table-of string)
                  (alist-of string integer :test)
                  (alist-of string integer :test bogus)
                  (alist-of string integer :test equal :test eql)
                  (alist-of string integer :min-count -1)
                  (alist-of string integer :min-count 1.5)
                  (alist-of string integer :max-count -1)
                  (alist-of string integer :max-count many)
                  (alist-of string integer :min-count 3 :max-count 2)
                  (hash-table-of string integer :unique t)
                  (hash-table-of string integer extra)))
    (ok (refuses-form-p form) (format nil "~S is refused" form))))

(deftest programmatic-map-specs-are-validated
  (let ((child (normalize-spec-form 'integer)))
    (flet ((refused-p (&rest initargs)
             (handler-case (progn (apply #'make-instance 'hash-table-of-spec initargs) nil)
               (invalid-spec-form () t))))
      (ok (refused-p :key-spec child))
      (ok (refused-p :key-spec child :value-spec :not-a-spec))
      (ok (refused-p :key-spec child :value-spec child :key-test :frobnicate))
      (ok (refused-p :key-spec child :value-spec child :min-count -1))
      (ok (refused-p :key-spec child :value-spec child :max-count 'many))
      (ok (refused-p :key-spec child :value-spec child :min-count 2 :max-count 1)))
    (testing "a plain symbol key test is stored as the canonical keyword"
      (let ((spec (make-instance 'alist-of-spec :key-spec child :value-spec child
                                                :key-test 'equal)))
        (ok (eq :equal (map-spec-key-test spec)))
        (ok (eq spec (validate-definition spec)))))
    (testing "a refused reinitialization leaves the slots unchanged"
      (let ((spec (make-instance 'alist-of-spec :key-spec child :value-spec child
                                                :max-count 3)))
        (ok (handler-case (progn (reinitialize-instance spec :min-count 4) nil)
              (invalid-spec-form () t)))
        (ok (zerop (map-spec-min-count spec)))
        (ok (= 3 (map-spec-max-count spec)))))))
```

`tests.lisp` の `defpackage` で、`(:import-from #:cl-spec/tests/collection-constraints-test)` の直後に1行足す（`lisp-patch-form`、form_type `defpackage`、form_name `cl-spec/tests`）：

```lisp
  (:import-from #:cl-spec/tests/map-spec-test)
```

`tests/normalize-test.lisp` の `mvp-primitives-are-declared` の期待リストを次に置き換える：

```lisp
    (ok (equal '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
                 "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "PLIST" "ALIST"
                 "HASH-TABLE" "HASH-TABLE-OF" "ALIST-OF" "OBJECT-OF" "TAGGED-BY"
                 "INSTANCE-OF")
               *spec-primitives*)))
```

- [ ] **Step 2: テストが失敗することを確認する**

`load-system` `cl-spec/tests`。package `cl-spec/src/map-spec` が無いので読み込みが失敗する。これが期待どおりの失敗。

- [ ] **Step 3: `src/map-spec.lisp` を作る**

`fs-write-file`：

```lisp
;;;; src/map-spec.lisp
;;;;
;;;; Homogeneous maps (specification §9.6).  A map spec constrains every key with
;;;; one spec and every value with another under a declared key test, instead of
;;;; naming fields the way the keyed field specs of src/field-spec.lisp do.

(defpackage #:cl-spec/src/map-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions #:invalid-spec-form)
  (:import-from #:cl-spec/src/definition-validation
                #:validate-definition #:definition-validation-slots)
  (:import-from #:cl-spec/src/ir #:spec #:spec-kind #:spec-children)
  (:import-from #:cl-spec/src/field-spec #:key-test-designator)
  (:export #:map-of-spec #:hash-table-of-spec #:alist-of-spec
           #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
           #:map-spec-min-count #:map-spec-max-count
           #:map-count-constraint-plist))

(in-package #:cl-spec/src/map-spec)

(defclass map-of-spec (spec)
  ((key-spec :initarg :key-spec
             :initform nil
             :reader map-spec-key-spec
             :documentation "Spec every key must satisfy.")
   (value-spec :initarg :value-spec
               :initform nil
               :reader map-spec-value-spec
               :documentation "Spec every value must satisfy.")
   (key-test :initarg :key-test
             :initform :eql
             :reader map-spec-key-test
             :documentation "Canonical keyword naming the comparison used for keys.")
   (min-count :initarg :min-count
              :initform 0
              :reader map-spec-min-count
              :documentation "Smallest accepted entry count, inclusive.")
   (max-count :initarg :max-count
              :initform :unbounded
              :reader map-spec-max-count
              :documentation "Largest accepted entry count, inclusive, or :UNBOUNDED."))
  (:documentation "Abstract parent of maps whose keys and values each satisfy one spec.

Keys are compared with the declared test, so they are distinct under it.  No key
is named: a map key is data, which is the difference from the keyed field specs."))

(defmethod spec-children ((spec map-of-spec))
  (list (map-spec-key-spec spec) (map-spec-value-spec spec)))

(defclass hash-table-of-spec (map-of-spec)
  ()
  (:documentation "A hash table using the declared test whose entries all satisfy one key spec
and one value spec."))

(defmethod spec-kind ((spec hash-table-of-spec))
  :hash-table-of)

(defclass alist-of-spec (map-of-spec)
  ()
  (:documentation "An association list of (KEY . VALUE) conses, keys unique under the declared
test, whose entries all satisfy one key spec and one value spec."))

(defmethod spec-kind ((spec alist-of-spec))
  :alist-of)

(defun validate-map-layout (key-spec value-spec key-test min-count max-count)
  "Check one map spec's candidate slot values and return the canonical key test.

The values are passed in rather than read from a spec because reinitialization
validates before the slots change."
  (unless (and (typep key-spec 'spec) (typep value-spec 'spec))
    (error 'invalid-spec-form
           :form (list :key-spec key-spec :value-spec value-spec)
           :reason "A map spec needs a key spec and a value spec."))
  (let ((canonical (key-test-designator key-test)))
    (unless canonical
      (error 'invalid-spec-form
             :form (list :key-test key-test)
             :reason "The key test must name EQ, EQL, EQUAL or EQUALP."))
    (unless (and (integerp min-count) (not (minusp min-count)))
      (error 'invalid-spec-form
             :form (list :min-count min-count)
             :reason "MIN-COUNT must be a nonnegative integer"))
    (unless (or (eq max-count :unbounded)
                (and (integerp max-count) (not (minusp max-count))))
      (error 'invalid-spec-form
             :form (list :max-count max-count)
             :reason "MAX-COUNT must be a nonnegative integer or :UNBOUNDED"))
    (when (and (integerp max-count) (> min-count max-count))
      (error 'invalid-spec-form
             :form (list :min-count min-count :max-count max-count)
             :reason "MIN-COUNT must not exceed MAX-COUNT"))
    canonical))

(defmethod validate-definition ((spec map-of-spec))
  (validate-map-layout (map-spec-key-spec spec) (map-spec-value-spec spec)
                       (map-spec-key-test spec) (map-spec-min-count spec)
                       (map-spec-max-count spec))
  spec)

(defmethod definition-validation-slots append ((spec map-of-spec))
  '(key-spec value-spec key-test min-count max-count))

(defmethod shared-initialize :around
    ((spec map-of-spec) slot-names &rest initargs
     &key (key-spec nil key-spec-p) (value-spec nil value-spec-p)
          (key-test nil key-test-p) (min-count nil min-count-p)
          (max-count nil max-count-p))
  "Validate the candidate slot values before changing SPEC, then store the canonical test.

A caller may write the key test as a plain symbol; every later consumer --
introspection, digest, explainer and generator -- sees one keyword."
  (declare (ignore slot-names initargs))
  (flet ((candidate (supplied-p value slot default)
           (cond (supplied-p value)
                 ((slot-boundp spec slot) (slot-value spec slot))
                 (t default))))
    (let ((canonical
            (validate-map-layout (candidate key-spec-p key-spec 'key-spec nil)
                                 (candidate value-spec-p value-spec 'value-spec nil)
                                 (candidate key-test-p key-test 'key-test :eql)
                                 (candidate min-count-p min-count 'min-count 0)
                                 (candidate max-count-p max-count 'max-count :unbounded))))
      (prog1 (call-next-method)
        (setf (slot-value spec 'key-test) canonical)))))

(defun map-count-constraint-plist (spec)
  "Return SPEC's non-default entry count bounds as a plist.

A map with neither bound returns NIL, so the bounds' existence does not change
the digest or the introspection record of an unbounded map."
  (append (unless (zerop (map-spec-min-count spec))
            (list :min-count (map-spec-min-count spec)))
          (unless (eq :unbounded (map-spec-max-count spec))
            (list :max-count (map-spec-max-count spec)))))
```

- [ ] **Step 4: 正規化を足す**

`src/normalize.lisp` の `defpackage` に import を1つ足す（`(:import-from #:cl-spec/src/tagged-union ...)` の直後）：

```lisp
  (:import-from #:cl-spec/src/map-spec
                #:hash-table-of-spec #:alist-of-spec)
```

`*spec-primitives*` を置き換える（docstring はそのまま）：

```lisp
(defparameter *spec-primitives*
  '("TYPE" "SATISFIES" "AND" "OR" "NOT" "MEMBER" "RANGE"
    "LIST-OF" "VECTOR-OF" "TUPLE" "NULLABLE" "PLIST" "ALIST" "HASH-TABLE"
    "HASH-TABLE-OF" "ALIST-OF" "OBJECT-OF" "TAGGED-BY"
    "INSTANCE-OF")
```

`normalize-collection` の直後に2つの関数を足す（`lisp-edit-form` insert_after、form_type `defun`、form_name `normalize-collection`）：

```lisp
(defun normalize-map-options (options form)
  "Return (values KEY-TEST MIN-COUNT MAX-COUNT) for a map's OPTIONS.

OPTIONS is the tail after the key and value specs.  Values are checked here so a
malformed declaration is refused before an IR object exists."
  (unless (evenp (length options))
    (error 'invalid-spec-form :form form :reason "map options are keyword/value pairs"))
  (let ((key-test :eql)
        (min-count 0)
        (max-count :unbounded)
        (seen nil))
    (loop for (key value) on options by #'cddr
          do (when (member key seen)
               (error 'invalid-spec-form :form form
                                         :reason (format nil "~S appears more than once" key)))
             (push key seen)
             (case key
               (:test
                (setf key-test
                      (or (key-test-designator value)
                          (error 'invalid-spec-form
                                 :form form
                                 :reason ":test must name EQ, EQL, EQUAL or EQUALP"))))
               (:min-count
                (unless (and (integerp value) (not (minusp value)))
                  (error 'invalid-spec-form :form form
                                            :reason ":min-count must be a nonnegative integer"))
                (setf min-count value))
               (:max-count
                (cond ((unbounded-marker-p value) (setf max-count :unbounded))
                      ((and (integerp value) (not (minusp value))) (setf max-count value))
                      (t (error 'invalid-spec-form
                                :form form
                                :reason ":max-count must be a nonnegative integer or *"))))
               (otherwise
                (error 'invalid-spec-form :form form
                                          :reason (format nil "~S is not a map option; the ~
                                                               options are :test, :min-count ~
                                                               and :max-count"
                                                          key)))))
    (when (and (integerp max-count) (> min-count max-count))
      (error 'invalid-spec-form :form form
                                :reason ":min-count must not exceed :max-count"))
    (values key-test min-count max-count)))

(defun normalize-map (args form name source-location generator class)
  "Normalize the arguments of a HASH-TABLE-OF or ALIST-OF form into CLASS."
  (unless (>= (length args) 2)
    (error 'invalid-spec-form :form form :reason "expected a key spec and a value spec"))
  (multiple-value-bind (key-test min-count max-count)
      (normalize-map-options (cddr args) form)
    (apply #'make-instance class
           :key-spec (normalize-spec-form (first args))
           :value-spec (normalize-spec-form (second args))
           :key-test key-test :min-count min-count :max-count max-count
           (spec-initargs form name source-location generator))))
```

`normalize-compound` の `cond` で、`TUPLE` の節の直前に2つの節を足す（`lisp-patch-form`、form_type `defun`、form_name `normalize-compound`）。old_text：

```lisp
        ((string= head-name "TUPLE")
```

new_text：

```lisp
        ((string= head-name "HASH-TABLE-OF")
         (normalize-map args form name source-location generator 'hash-table-of-spec))
        ((string= head-name "ALIST-OF")
         (normalize-map args form name source-location generator 'alist-of-spec))
        ((string= head-name "TUPLE")
```

- [ ] **Step 5: テストが通ることを確認する**

`load-system` `cl-spec/tests`、続けて `repl-eval`：

```lisp
(list (rove:run :cl-spec/tests/map-spec-test) (rove:run :cl-spec/tests/normalize-test))
```

Expected: `(T T)`。`map-forms-normalize-into-the-ir`、`malformed-map-declarations-are-refused`、`programmatic-map-specs-are-validated`、`mvp-primitives-are-declared` がすべて PASS。

- [ ] **Step 6: コミット**

```bash
git add src/map-spec.lisp src/normalize.lisp tests/map-spec-test.lisp tests/normalize-test.lisp tests.lisp
git commit -m "feat: add hash-table-of and alist-of map specs to the IR"
```

---

### Task 2: 検証・説明・識別子

**Files:**
- Modify: `src/field-spec.lisp`（`alist-structure-error`）
- Modify: `src/explain.lisp`（package の import、`expected-descriptor` メソッド、helper 3つ、`compile-node` メソッド2つ）
- Modify: `src/function-spec.lisp`（`*failure-shape-keys*` と `failure-shape` の docstring）
- Modify: `tests/map-spec-test.lisp`（テスト追加）
- Modify: `tests/function-spec-test.lisp`（`every-explained-error-key-is-classified`）

**Interfaces:**
- Consumes: Task 1 の reader と `map-count-constraint-plist`。既存の `alist-structure-error (value key-test)` → `(values kind key)`、`hash-table-structure-error (value key-test)` → `(values kind actual-test)`、`error-datum (kind path value &rest extra)`（path は内側が先、関数内で反転）。
- Produces:
  - 新しいエラー種別 `:too-few-entries`（`:minimum-count`、`:actual-count`）、`:too-many-entries`（`:maximum-count`、`:actual-count`）。
  - エラー datum の新キー `:entry-path`：外側のマップから順に `:key` / `:value` を並べた list。
  - expected 記述 `(:kind :hash-table-of|:alist-of :test KW :key DESC :value DESC [:min-count N] [:max-count M])`。

- [ ] **Step 1: 失敗するテストを書く**

`tests/map-spec-test.lisp` の末尾に追加：

```lisp
(defclass unprintable-key ()
  ()
  (:documentation "A hash-table key whose printer signals, for the no-print test."))

(defmethod print-object ((object unprintable-key) stream)
  (declare (ignore object stream))
  (error "print boom"))

(deftest map-validation-accepts-and-refuses
  (ok (validp (normalize-spec-form '(hash-table-of string integer :test equal))
              (make-table 'equal (cons "a" 1) (cons "b" 2))))
  (ok (validp (normalize-spec-form '(alist-of keyword integer)) '((:a . 1) (:b . 2))))
  (ok (validp (normalize-spec-form '(alist-of keyword integer)) nil))
  (ok (not (validp (normalize-spec-form '(alist-of keyword integer)) '((:a . "bad")))))
  (ok (not (validp (normalize-spec-form '(alist-of keyword integer)) '(("a" . 1)))))
  (ok (not (validp (normalize-spec-form '(hash-table-of string integer :test equal))
                   (make-table 'eql (cons "a" 1))))))

(deftest map-structure-errors-reuse-the-keyed-kinds
  (ok (eq :not-a-hash-table (getf (first (errors-of '(hash-table-of t t) 42)) :kind)))
  (let ((datum (first (errors-of '(hash-table-of t t :test equal) (make-table 'eql)))))
    (ok (eq :wrong-key-test (getf datum :kind)))
    (ok (eq 'eql (getf datum :actual-test))))
  (ok (eq :not-an-alist (getf (first (errors-of '(alist-of t t) 42)) :kind)))
  (ok (eq :bad-association
          (getf (first (errors-of '(alist-of t t) '((:a . 1) :atom))) :kind)))
  (let ((errors (errors-of '(alist-of string integer :test equal)
                           (list (cons (copy-seq "a") "bad") (cons (copy-seq "a") 2)))))
    (testing "a structure error stops before any entry is checked"
      (ok (= 1 (length errors)))
      (ok (eq :duplicate-key (getf (first errors) :kind)))
      (ok (equal '("a") (getf (first errors) :path))))))

(deftest map-count-errors-are-structured
  (let ((few (first (errors-of '(alist-of t t :min-count 2) '((:a . 1)))))
        (many (first (errors-of '(hash-table-of t t :max-count 1)
                                (make-table 'eql (cons :a 1) (cons :b 2))))))
    (ok (eq :too-few-entries (getf few :kind)))
    (ok (= 2 (getf few :minimum-count)))
    (ok (= 1 (getf few :actual-count)))
    (ok (eq :too-many-entries (getf many :kind)))
    (ok (= 1 (getf many :maximum-count)))
    (ok (= 2 (getf many :actual-count)))))

(deftest map-entry-errors-name-the-side
  (let ((errors (errors-of '(alist-of keyword integer) '((:ok . 1) ("k" . "v")))))
    (testing "one entry can fail on its key and its value; the key comes first"
      (ok (= 2 (length errors)))
      (ok (equal '(:key) (getf (first errors) :entry-path)))
      (ok (equal '("k") (getf (first errors) :path)))
      (ok (equal '(:value) (getf (second errors) :entry-path)))
      (ok (equal '("k") (getf (second errors) :path)))))
  (testing "nested maps stack the side of each level, outermost first"
    (let ((datum (first (errors-of '(alist-of keyword (alist-of keyword integer))
                                   '((:outer . (("inner" . 1))))))))
      (ok (equal '(:value :key) (getf datum :entry-path)))
      (ok (equal '(:outer "inner") (getf datum :path)))))
  (testing "a hash table reports every key error before any value error"
    (let ((errors (errors-of '(hash-table-of string integer :test equal)
                             (make-table 'equal (cons "ok" "bad") (cons 1 2)))))
      (ok (equal '((:key) (:value))
                 (mapcar (lambda (datum) (getf datum :entry-path)) errors))))))

(deftest map-failure-identity-separates-key-and-value
  (flet ((signature (form value)
           (failure-signature :return-spec
                              (explain-data (normalize-spec-form form) value) nil)))
    (let ((form '(alist-of string string :test equal)))
      (testing "with one spec on both sides, :ENTRY-PATH still tells key from value"
        (ok (not (equal (signature form '((1 . "v"))) (signature form '(("k" . 1)))))))
      (testing "the same violation under a different key is one failure"
        (ok (equal (signature form '(("a" . 1))) (signature form '(("b" . 1)))))))
    (testing "count bounds are part of the shape"
      (ok (not (equal (signature '(alist-of t t :min-count 2) nil)
                      (signature '(alist-of t t :min-count 3) nil)))))))

(deftest map-expected-descriptor-names-both-sides
  (let ((descriptor (expected-descriptor
                     (normalize-spec-form
                      '(hash-table-of string integer :test equal :min-count 1)))))
    (ok (eq :hash-table-of (getf descriptor :kind)))
    (ok (eq :equal (getf descriptor :test)))
    (ok (equal '(:type string) (getf descriptor :key)))
    (ok (equal '(:type integer) (getf descriptor :value)))
    (ok (= 1 (getf descriptor :min-count)))
    (ok (null (getf descriptor :max-count)))))

(deftest map-validation-never-prints-keys
  (let ((table (make-table 'eql (cons (make-instance 'unprintable-key) "bad"))))
    (ok (= 1 (length (errors-of '(hash-table-of t integer) table))))))

(deftest alist-duplicate-detection-follows-the-key-test
  (ok (validp (normalize-spec-form '(alist-of string t :test eq))
              (list (cons (copy-seq "a") 1) (cons (copy-seq "a") 2))))
  (ok (not (validp (normalize-spec-form '(alist-of string t :test equal))
                   (list (cons (copy-seq "a") 1) (cons (copy-seq "a") 2)))))
  (ok (not (validp (normalize-spec-form '(alist-of string t :test equalp))
                   (list (cons "a" 1) (cons "A" 2)))))
  (ok (validp (normalize-spec-form '(alist-of integer integer))
              (loop for key from 0 below 20000 collect (cons key key)))))
```

`tests/function-spec-test.lisp` の `every-explained-error-key-is-classified` を3か所変える（`lisp-patch-form`、form_type `deftest`、form_name `every-explained-error-key-is-classified`）。

value-derived のリストに `:actual-count` を足す。old_text：

```lisp
          (value-derived '(:actual :actual-length :path :condition-report :key
                           :actual-test :observed-tag)))
```

new_text：

```lisp
          (value-derived '(:actual :actual-length :path :condition-report :key
                           :actual-test :observed-tag :actual-count)))
```

forms の最後（`tagged-by` の form の直後）にマップの形を2つ足す。old_text：

```lisp
                        (:right (plist (:required (:kind (member :right)) (:value string))
                                       (:closed t))))))
```

new_text：

```lisp
                        (:right (plist (:required (:kind (member :right)) (:value string))
                                       (:closed t))))
                      (hash-table-of keyword integer :min-count 1 :max-count 1)
                      (alist-of keyword (alist-of keyword integer) :max-count 1)))
```

値の最後に4つ足す。old_text：

```lisp
                              (hash-table-with 'eql '((:a . ((:b . "bad")))))))
```

new_text：

```lisp
                              (hash-table-with 'eql '((:a . ((:b . "bad")))))
                              '((:a . 1) (:b . 2)) '(("s" . 1)) '((:a . ((:b . "bad"))))
                              (hash-table-with 'eql '((:a . 1) (:b . 2)))
                              (hash-table-with 'eql '(("s" . "bad")))))
```

- [ ] **Step 2: テストが失敗することを確認する**

`repl-eval`：`(rove:run :cl-spec/tests/map-spec-test)`
Expected: FAIL。`compile-node` に map-of-spec のメソッドが無いため、検証・説明のテストは `spec-kind` だけの既定経路か no-applicable-method で失敗する。

- [ ] **Step 3: `alist-structure-error` を線形にする**

`src/field-spec.lisp` の `alist-structure-error` を置き換える：

```lisp
(defun alist-structure-error (value key-test)
  "Return (values KIND KEY) after checking that VALUE is a well-formed alist.

KIND and KEY describe malformed structure and are NIL on success.  An entry is a
cons whose CAR is the key and whose CDR is the value, so the value of (:id . NIL)
is present but NIL, exactly as ASSOC reads it.  Keys are unique under KEY-TEST.
Every accepted test is also a hash-table test, so the duplicate check is one
pass over a table rather than a pairwise MEMBER walk."
  (unless (finite-list-p value)
    (return-from alist-structure-error (values :not-an-alist nil)))
  (let ((seen (make-hash-table :test (key-test-name (key-test-designator key-test)))))
    (dolist (entry value)
      (unless (consp entry)
        (return-from alist-structure-error (values :bad-association entry)))
      (let ((key (car entry)))
        (when (nth-value 1 (gethash key seen))
          (return-from alist-structure-error (values :duplicate-key key)))
        (setf (gethash key seen) t)))
    (values nil nil)))
```

- [ ] **Step 4: explain を足す**

`src/explain.lisp` の `defpackage` に import を足す（`(:import-from #:cl-spec/src/tagged-union ...)` の直前）：

```lisp
  (:import-from #:cl-spec/src/map-spec
                #:map-of-spec #:hash-table-of-spec #:alist-of-spec
                #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
                #:map-spec-min-count #:map-spec-max-count #:map-count-constraint-plist)
```

`expected-descriptor ((spec tagged-union-spec))` の直後に足す：

```lisp
(defmethod expected-descriptor ((spec map-of-spec))
  (list* :kind (spec-kind spec) :test (map-spec-key-test spec)
         :key (expected-descriptor (map-spec-key-spec spec))
         :value (expected-descriptor (map-spec-value-spec spec))
         (map-count-constraint-plist spec)))
```

`compile-node ((spec hash-table-spec) context)` の直後に足す：

```lisp
(defun entry-path-errors (errors part)
  "Return ERRORS with PART (:KEY or :VALUE) prepended to each datum's :ENTRY-PATH.

:ENTRY-PATH says which side of an entry failed at each map level.  It comes from
the spec, so failure identity keeps it even when the key and value specs are the
same; the map key itself is data and stays in :PATH only."
  (loop for datum in errors
        collect (let ((copy (copy-list datum)))
                  (setf (getf copy :entry-path) (cons part (getf datum :entry-path)))
                  copy)))

(defun map-count-errors (spec count path value expected)
  "Return a :too-few-entries or :too-many-entries datum for a map of COUNT entries, or NIL."
  (let ((minimum (map-spec-min-count spec))
        (maximum (map-spec-max-count spec)))
    (cond ((< count minimum)
           (list (error-datum :too-few-entries path value :expected expected
                              :minimum-count minimum :actual-count count)))
          ((and (integerp maximum) (> count maximum))
           (list (error-datum :too-many-entries path value :expected expected
                              :maximum-count maximum :actual-count count))))))

(defun map-entry-errors (key-check value-check key item path)
  "Return (values KEY-ERRORS VALUE-ERRORS) for one entry located at (KEY . PATH)."
  (values (entry-path-errors (funcall key-check key (cons key path)) :key)
          (entry-path-errors (funcall value-check item (cons key path)) :value)))

(defmethod compile-node ((spec alist-of-spec) context)
  (let ((key-check (compile-node (map-spec-key-spec spec) context))
        (value-check (compile-node (map-spec-value-spec spec) context))
        (key-test (map-spec-key-test spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (multiple-value-bind (kind key) (alist-structure-error value key-test)
        (if kind
            (list (error-datum kind (if (eq kind :duplicate-key) (cons key path) path)
                               value :expected expected))
            (append (map-count-errors spec (length value) path value expected)
                    (loop for (key . item) in value
                          append (multiple-value-bind (key-errors value-errors)
                                     (map-entry-errors key-check value-check key item path)
                                   (append key-errors value-errors)))))))))

(defmethod compile-node ((spec hash-table-of-spec) context)
  (let ((key-check (compile-node (map-spec-key-spec spec) context))
        (value-check (compile-node (map-spec-value-spec spec) context))
        (key-test (map-spec-key-test spec))
        (expected (expected-descriptor spec)))
    (lambda (value path)
      (multiple-value-bind (kind actual) (hash-table-structure-error value key-test)
        (cond
          ((eq kind :wrong-key-test)
           (list (error-datum kind path value :expected expected :actual-test actual)))
          (kind (list (error-datum kind path value :expected expected)))
          (t
           ;; MAPHASH order is unspecified and arbitrary keys may have a
           ;; signalling or nonterminating printer, so entries are reported in
           ;; that order rather than sorted by a printed key: every key error
           ;; first, then every value error.
           (let ((key-errors nil)
                 (value-errors nil))
             (maphash (lambda (key item)
                        (multiple-value-bind (key-part value-part)
                            (map-entry-errors key-check value-check key item path)
                          (push key-part key-errors)
                          (push value-part value-errors)))
                      value)
             (append (map-count-errors spec (hash-table-count value) path value expected)
                     (loop for errors in (nreverse key-errors) append errors)
                     (loop for errors in (nreverse value-errors) append errors)))))))))
```

- [ ] **Step 5: 新しいキーを識別子に分類する**

`src/function-spec.lisp` の `*failure-shape-keys*` を置き換える（docstring の最後の1文だけ足す）：

```lisp
(defparameter *failure-shape-keys*
  '(:kind :expected :violated-bound :predicate :condition-type :expected-length
    :minimum-length :maximum-length :minimum-count :maximum-count :status
    :tuple-path :field-path :entry-path
    :branch :branch-path :known-tags)
  "The EXPLAIN-DATA error keys FAILURE-SHAPE keeps, because they come from the SPEC.

A whitelist, not a list of keys to strip.  Stripping by name failed three times in
review: :ACTUAL first, then :ACTUAL-LENGTH (a tuple's actual arity) and :PATH (a
position inside the value), then :CONDITION-REPORT (a condition's text, which
embeds the value).  Each varies with the input, so two instances of one failure
compared unequal and a legitimate reduction was thrown away.  A key derived from
the spec is safe to compare; a new EXPLAIN-DATA key is treated as value-derived
until someone classifies it here, and EVERY-EXPLAINED-ERROR-KEY-IS-CLASSIFIED
fails until they do. :FIELD-PATH contains only declared parent/field keys;
Unknown input key names in :KEY and :PATH are value-derived and remain discarded.
:ENTRY-PATH names only the key or value side of each map level, never a map key,
and :ACTUAL-COUNT is value-derived.")
```

`failure-shape` の docstring の `fixed :TUPLE-PATH and declared :FIELD-PATH -- stays in.` を `fixed :TUPLE-PATH, declared :FIELD-PATH and a map's :ENTRY-PATH -- stays in.` に変える（`lisp-patch-form`）。

- [ ] **Step 6: テストが通ることを確認する**

`load-system` `cl-spec/tests`、`repl-eval`：

```lisp
(list (rove:run :cl-spec/tests/map-spec-test)
      (rove:run :cl-spec/tests/function-spec-test)
      (rove:run :cl-spec/tests/field-representations-test)
      (rove:run :cl-spec/tests/explain-test))
```

Expected: `(T T T T)`。`field-representations-test` は `alist-structure-error` を書き換えても既存の alist の挙動が変わっていないことの確認。

- [ ] **Step 7: コミット**

```bash
git add src/field-spec.lisp src/explain.lisp src/function-spec.lisp tests/map-spec-test.lisp tests/function-spec-test.lisp
git commit -m "feat: validate and explain map specs with key/value entry paths"
```

---

### Task 3: introspection・digest・coverage・codec

**Files:**
- Modify: `src/introspection.lisp`（import、`node-attributes` メソッド）
- Modify: `src/schema.lisp`（import、`definition-constraints` メソッド、`definition-description-complete-p` の whitelist）
- Modify: `tests/map-spec-test.lisp`（テスト追加）

**Interfaces:**
- Consumes: Task 1 の reader と `map-count-constraint-plist`。
- Produces: `spec-data` が `:test`、既定値でないときの `:min-count` / `:max-count`、`:key-child-index 0`、`:value-child-index 1` を持つ。`definition-constraints` が `(:test KW [:min-count N] [:max-count M])` を返す。digest は complete。

- [ ] **Step 1: 失敗するテストを書く**

`tests/map-spec-test.lisp` の末尾に追加：

```lisp
(deftest map-introspection-projects-both-children
  (let* ((form '(alist-of keyword integer :test eq :max-count 8))
         (data (spec-data (normalize-spec-form form))))
    (ok (eq :alist-of (getf data :kind)))
    (ok (eq :eq (getf data :test)))
    (ok (null (getf data :min-count)))
    (ok (= 8 (getf data :max-count)))
    (ok (= 0 (getf data :key-child-index)))
    (ok (= 1 (getf data :value-child-index)))
    (ok (equal '(keyword integer)
               (mapcar (lambda (child) (getf child :type)) (getf data :children))))
    (ok (equal form (getf data :source-form)))
    (ok (getf data :definition-digest-complete))))

(deftest map-digests-cover-every-declared-part
  (let ((digest (definition-digest (normalize-spec-form '(hash-table-of string integer)))))
    (dolist (other '((alist-of string integer)
                     (hash-table-of integer string)
                     (hash-table-of string integer :test equal)
                     (hash-table-of string integer :min-count 1)
                     (hash-table-of string integer :max-count 5)))
      (ok (not (equal digest (definition-digest (normalize-spec-form other))))
          (format nil "~S has its own digest" other))))
  (ok (equal '(:test :eql) (definition-constraints (normalize-spec-form '(alist-of t t)))))
  (ok (equal '(:test :equal :min-count 1 :max-count 2)
             (definition-constraints
              (normalize-spec-form '(alist-of t t :test equal :min-count 1 :max-count 2))))))

(deftest map-nodes-are-reported-as-unexpanded-coverage
  (let ((data (plist-coverage-schema
               (list (list 'payload (normalize-spec-form
                                     '(hash-table-of keyword (plist (:optional (:a t)))))))
               *registry* 1024 32)))
    (ok (null (getf data :dimensions)))
    (ok (eq :partial (getf data :discovery)))
    (ok (equal '((:path (payload) :reason :unsupported-composite))
               (getf data :unexpanded)))))

(deftest map-values-meet-the-artifact-codec-as-before
  (testing "an alist of encodable keys and values can be saved"
    (ok (encode-artifact-value (list (cons "a" 1) (cons "b" 2)))))
  (testing "a hash table is refused, exactly as for the keyed HASH-TABLE spec"
    (ok (handler-case (progn (encode-artifact-value (make-table 'equal (cons "a" 1))) nil)
          (artifact-value-error () t)))))
```

- [ ] **Step 2: テストが失敗することを確認する**

`repl-eval`：`(rove:run :cl-spec/tests/map-spec-test)`
Expected: FAIL。`:test` などが `spec-data` に無く、`:definition-digest-complete` が NIL。coverage と codec のテストは、既存の挙動のまま PASS してよい。

- [ ] **Step 3: introspection を足す**

`src/introspection.lisp` の `defpackage` に足す（`(:import-from #:cl-spec/src/tagged-union ...)` の直後）：

```lisp
  (:import-from #:cl-spec/src/map-spec
                #:map-of-spec #:map-spec-key-test #:map-count-constraint-plist)
```

`node-attributes ((spec tagged-union-spec))` の直後に足す：

```lisp
(defmethod node-attributes ((spec map-of-spec))
  (append (list :test (map-spec-key-test spec))
          (map-count-constraint-plist spec)
          (list :key-child-index 0 :value-child-index 1)
          (call-next-method)))
```

- [ ] **Step 4: schema を足す**

`src/schema.lisp` の `defpackage` に足す（`(:import-from #:cl-spec/src/tagged-union ...)` の直後）：

```lisp
  (:import-from #:cl-spec/src/map-spec
                #:map-of-spec #:hash-table-of-spec #:alist-of-spec
                #:map-spec-key-test #:map-count-constraint-plist)
```

`definition-constraints ((definition tagged-union-spec))` の直後に足す：

```lisp
(defmethod definition-constraints ((definition map-of-spec))
  (append (list :test (map-spec-key-test definition))
          (map-count-constraint-plist definition)))
```

`definition-description-complete-p ((definition spec))` の whitelist に3つのクラスを足す。old_text：

```lisp
                       object-spec tagged-union-spec
```

new_text：

```lisp
                       object-spec tagged-union-spec
                       map-of-spec hash-table-of-spec alist-of-spec
```

- [ ] **Step 5: テストが通ることを確認する**

`load-system` `cl-spec/tests`、`repl-eval`：

```lisp
(list (rove:run :cl-spec/tests/map-spec-test)
      (rove:run :cl-spec/tests/schema-test)
      (rove:run :cl-spec/tests/introspection-test))
```

Expected: `(T T T)`。

- [ ] **Step 6: コミット**

```bash
git add src/introspection.lisp src/schema.lisp tests/map-spec-test.lisp
git commit -m "feat: introspect and digest map specs"
```

---

### Task 4: 生成（キーの抽選と予算計上）

**Files:**
- Modify: `src/generation-request.lisp`（`generation-candidate-available-p` と export）
- Modify: `tests/backends/and-generation-test.lisp`（import とテスト1つ）
- Modify: `src/backends/check-it-generators.lisp`（import/export、`draw-collection-count`、bounded の `generate` を helper 経由に、生成器クラスと `spec-generator` メソッド）
- Create: `tests/backends/map-generator-test.lisp`
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: Task 1 の IR。既存の `reserve-generation-candidate (path spec)`（予算が尽きていれば `:budget-exhausted` を記録して `generation-budget-exhausted` を通知）、`record-generation-rejection ()`、`effective-generator-name (spec context)`、`finite-integer-range (spec context)`、`enumerable-values (spec context)`、`shuffle-list`、`sample-distinct-integers (min max count)`、`*required-size*`、`key-test-function`（`field-spec`）。
- Produces:
  - `cl-spec/src/generation-request:generation-candidate-available-p ()` → 有効な request があり、あと1単位予約できれば T。予約も記録もしない。
  - `cl-spec/src/backends/check-it-generators` の export：`map-value-generator`、`map-generator-min-count`、`map-generator-max-count`、`map-generator-domain-size`、`map-generator-key-probe`、`map-generator-value-probe`（Task 5 の capability 判定が使う）。
  - 内部：`map-entry` 構造体（`key`、`value`、`key-child`、`value-child`、`copy-map-entry`）、`map-generator-entries`（現在の draw の `map-entry` list）、`map-generator-key-validator`、`map-generator-value-validator`、`map-generator-key-test`、`encode-map-entries (generator entries)`（Task 5 の縮小が使う）。
  - 予約が拒否されたときの `:exhausted-at` は `(:map-key)`。

- [ ] **Step 1: `generation-candidate-available-p` のテストを書く**

`tests/backends/and-generation-test.lisp` の `defpackage` で、`cl-spec/src/generation-request` の import に `#:generation-candidate-available-p` を足す。old_text：

```lisp
                #:record-generation-interruption #:reserve-generation-candidate)
```

new_text：

```lisp
                #:record-generation-interruption #:reserve-generation-candidate
                #:generation-candidate-available-p)
```

ファイル末尾にテストを足す：

```lisp
(deftest candidate-availability-is-asked-without-reserving
  (testing "outside a request nothing can be reserved"
    (let ((*generation-request* nil))
      (ok (not (generation-candidate-available-p)))))
  (let ((*generation-request* (make-generation-request :planned 1 :budget 1)))
    (ok (generation-candidate-available-p))
    (ok (generation-candidate-available-p) "asking twice reserves nothing")
    (reserve-generation-candidate nil nil)
    (ok (not (generation-candidate-available-p)))
    (let ((report (generation-request-report *generation-request*)))
      (ok (= 1 (getf report :attempts)))
      (ok (eq :completed (getf report :termination))))))
```

- [ ] **Step 2: 失敗を確認し、実装する**

`load-system` `cl-spec/tests` は、`generation-candidate-available-p` が無いので import で失敗する。

`src/generation-request.lisp` の export に `#:generation-candidate-available-p` を足し（`#:reserve-generation-candidate` の直後）、`reserve-generation-candidate` の直前に関数を足す：

```lisp
(defun generation-candidate-available-p ()
  "Return true when the active request could reserve one more candidate.

Asking reserves nothing and records nothing, so a caller that may stop early --
a map that already holds MIN-COUNT keys -- can decline to redraw without a denied
reservation marking the request :BUDGET-EXHAUSTED.  Outside a request there is
nothing to reserve from, and the answer is NIL."
  (let ((request *generation-request*))
    (and request
         (< (generation-request-attempts request)
            (generation-request-budget request)))))
```

`repl-eval`：`(rove:run :cl-spec/tests/backends/and-generation-test)` → Expected: `T`。

- [ ] **Step 3: 生成のテストファイルを作り、登録する**

`fs-write-file` で `tests/backends/map-generator-test.lisp`：

```lisp
;;;; tests/backends/map-generator-test.lisp

(defpackage #:cl-spec/tests/backends/map-generator-test
  (:use #:cl)
  (:import-from #:rove #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/map-spec #:alist-of-spec)
  (:import-from #:cl-spec/src/ir #:member-spec)
  (:import-from #:cl-spec/src/normalize #:normalize-spec-form)
  (:import-from #:cl-spec/src/validator #:validp)
  (:import-from #:cl-spec/src/registry #:*registry* #:make-hash-table-registry)
  (:import-from #:cl-spec/src/generator #:sample #:backend-capabilities)
  (:import-from #:cl-spec/src/generation-request #:generation-report-p)
  (:import-from #:cl-spec/src/backends/check-it #:check-it-backend)
  (:import-from #:cl-spec/src/backends/check-it-generators #:compile-spec-generator)
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable #:generator-unavailable-reason
                #:generation-budget-exhausted
                #:generation-budget-exhausted-attempts
                #:generation-budget-exhausted-rejections
                #:generation-budget-exhausted-path)
  (:import-from #:cl-spec/src/dsl #:defspec #:defgenerator #:defproperty)
  (:import-from #:cl-spec/src/property-runner
                #:run-property #:property-result-status
                #:property-result-shrunk-counterexample))

(in-package #:cl-spec/tests/backends/map-generator-test)

(defvar *key-counter* 0
  "Source of always-fresh keys for the collision-free test.")

(defvar *scripted-keys* nil
  "Keys the scripted generator hands out, in order.")

(defun sample-form (form &rest args)
  "Return (VALUES VALUES REPORT) for the normalized FORM."
  (apply #'sample (normalize-spec-form form) args))

(defun alist-keys (alist)
  "Return the keys of ALIST in order."
  (mapcar #'car alist))

(defun distinct-under-p (keys test)
  "Return true when no two of KEYS are equal under TEST."
  (= (length keys) (length (remove-duplicates keys :test test))))

(deftest generated-maps-satisfy-their-spec
  (dolist (form '((hash-table-of string integer)
                  (hash-table-of string integer :test equal :min-count 1 :max-count 6)
                  (hash-table-of character (list-of integer))
                  (hash-table-of string string :test equalp)
                  (alist-of string integer :test eq)
                  (alist-of (range integer 0 9) string :min-count 2 :max-count 4)
                  (alist-of (member :a :b :c) (nullable integer))
                  (alist-of string (alist-of string integer :test equal)
                            :test equal :max-count 3)))
    (let ((spec (normalize-spec-form form)))
      (ok (every (lambda (value) (validp spec value)) (sample spec :count 50 :seed 11))
          (format nil "samples of ~S satisfy it" form)))))

(deftest generated-tables-carry-the-declared-test
  (ok (every (lambda (table) (eq 'equalp (hash-table-test table)))
             (sample-form '(hash-table-of string integer :test equalp) :count 10 :seed 3))))

(deftest map-generation-is-reproducible-from-a-seed
  (ok (equal (sample-form '(alist-of string integer :test equal) :count 20 :seed 9)
             (sample-form '(alist-of string integer :test equal) :count 20 :seed 9))))

(deftest finite-key-domains-are-sampled-without-repeats
  (let ((alists (sample-form '(alist-of (member :a :b :c) integer :min-count 2)
                             :count 50 :seed 5)))
    (ok (every (lambda (alist) (<= 2 (length alist) 3)) alists))
    (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'eql)) alists)))
  (testing "the declared test decides which enumerated keys are distinct"
    (ok (every (lambda (table) (= 1 (hash-table-count table)))
               (sample-form '(hash-table-of (member "a" "A") integer :test equalp :min-count 1)
                            :count 20 :seed 5)))
    (ok (handler-case
            (progn (sample-form '(hash-table-of (member "a" "A") integer
                                  :test equalp :min-count 2)
                                :count 1)
                   nil)
          (generator-unavailable () t))))
  (testing "a finite integer range is sampled, and its width bounds MIN-COUNT"
    (ok (every (lambda (alist)
                 (and (= 5 (length alist)) (distinct-under-p (alist-keys alist) #'eql)))
               (sample-form '(alist-of (range integer 0 4) null :min-count 5) :count 10 :seed 5)))
    (ok (handler-case
            (progn (sample-form '(alist-of (range integer 0 4) null :min-count 6) :count 1) nil)
          (generator-unavailable () t)))))

(deftest drawn-keys-are-distinct-under-the-test
  (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'equal))
             (sample-form '(alist-of string integer :test equal) :count 50 :seed 2)))
  (ok (every (lambda (alist) (distinct-under-p (alist-keys alist) #'equalp))
             (sample-form '(alist-of string integer :test equalp) :count 50 :seed 2))))

(deftest custom-key-generators-win-over-enumeration
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator always-z () :z)
    (defspec custom-key (member :a :b) (:generator always-z))
    (flet ((keys-of (spec)
             (loop for alist in (sample spec :count 20 :seed 1) append (alist-keys alist))))
      (ok (every (lambda (key) (eq key :z))
                 (keys-of (normalize-spec-form '(alist-of custom-key null)))))
      (ok (every (lambda (key) (member key '(:z nil)))
                 (keys-of (normalize-spec-form '(alist-of (nullable custom-key) null)))))
      (testing "a generator on a directly constructed member node is honoured"
        (ok (every (lambda (key) (eq key :z))
                   (keys-of (make-instance 'alist-of-spec
                                           :key-spec (make-instance 'member-spec
                                                                    :values '(:a :b)
                                                                    :generator 'always-z)
                                           :value-spec (normalize-spec-form 'null)))))))))

(deftest unavailable-children-name-their-side
  (flet ((reason (form)
           (handler-case (progn (sample-form form :count 1) nil)
             (generator-unavailable (condition) (generator-unavailable-reason condition)))))
    (ok (search "map key spec" (reason '(hash-table-of (satisfies consp) integer))))
    (ok (search "map value spec" (reason '(alist-of string (satisfies consp))))))
  (testing "a map that admits no entry needs no child generator"
    (ok (equal '(nil nil nil)
               (sample-form '(alist-of (satisfies consp) (satisfies consp) :max-count 0)
                            :count 3 :seed 1)))))

(deftest collision-free-maps-consume-no-budget
  (let ((*registry* (make-hash-table-registry))
        (*key-counter* 0))
    (defgenerator fresh-key () (incf *key-counter*))
    (defspec counter-key integer (:generator fresh-key))
    (multiple-value-bind (values report)
        (sample-form '(hash-table-of counter-key (hash-table-of counter-key integer))
                     :count 20 :seed 4)
      (ok (= 20 (length values)))
      (ok (generation-report-p report))
      (ok (zerop (getf report :attempts)))
      (ok (zerop (getf report :rejections)))
      (ok (eq :completed (getf report :termination))))))

(deftest each-redraw-reserves-and-only-colliding-redraws-are-rejected
  (let ((*registry* (make-hash-table-registry))
        (*scripted-keys* (list 1 1 1 2)))
    (defgenerator scripted-key () (pop *scripted-keys*))
    (defspec script-key integer (:generator scripted-key))
    (multiple-value-bind (values report)
        (sample-form '(alist-of script-key null :min-count 2 :max-count 2) :count 1 :seed 4)
      (testing "the first draw of each slot is free; each redraw reserves one candidate"
        (ok (equal '(1 2) (alist-keys (first values))))
        (ok (= 2 (getf report :attempts)))
        (ok (= 1 (getf report :rejections)))
        (ok (eq :completed (getf report :termination)))))))

(deftest a-map-stops-early-once-min-count-holds
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator constant-key () 1)
    (defspec same-key integer (:generator constant-key))
    (testing "eight consecutive collisions end the map; its seven redraws are all rejected"
      (multiple-value-bind (values report)
          (sample-form '(alist-of same-key null :min-count 1 :max-count 3) :count 30 :seed 6)
        (ok (every (lambda (alist) (equal '(1) (alist-keys alist))) values))
        (ok (plusp (getf report :attempts)))
        (ok (= (getf report :attempts) (getf report :rejections)))
        (ok (zerop (mod (getf report :attempts) 7)))
        (ok (eq :completed (getf report :termination)))))
    (testing "with no budget, a map holding MIN-COUNT keys stops without reserving"
      (multiple-value-bind (values report)
          (sample-form '(alist-of same-key null :min-count 1 :max-count 3)
                       :count 30 :seed 6 :generation-budget 0)
        (ok (every (lambda (alist) (equal '(1) (alist-keys alist))) values))
        (ok (zerop (getf report :attempts)))
        (ok (eq :completed (getf report :termination)))))
    (testing "below MIN-COUNT, redraws continue until the budget is exhausted"
      (ok (handler-case
              (progn (sample-form '(alist-of same-key null :min-count 2)
                                  :count 1 :generation-budget 5)
                     nil)
            (generation-budget-exhausted (condition)
              (and (= 5 (generation-budget-exhausted-attempts condition))
                   (= 5 (generation-budget-exhausted-rejections condition))
                   (equal '(:map-key) (generation-budget-exhausted-path condition)))))))))

(deftest key-filters-share-the-request-budget
  (multiple-value-bind (values report)
      (sample-form '(alist-of (and (range integer 0 1) (satisfies evenp)) null :max-count 3)
                   :count 20 :seed 8)
    (ok (every (lambda (alist) (every #'zerop (alist-keys alist))) values))
    (ok (generation-report-p report))
    (ok (plusp (getf report :attempts)))
    (ok (<= (getf report :rejections) (getf report :attempts)))))

(deftest a-bare-generate-outside-a-request-terminates
  (let ((*registry* (make-hash-table-registry)))
    (defgenerator constant-key () 1)
    (defspec same-key integer (:generator constant-key))
    (let ((generator (compile-spec-generator
                      (normalize-spec-form '(alist-of same-key null :min-count 2))
                      (list :registry *registry*))))
      (ok (handler-case (progn (check-it:generate generator) nil)
            (generation-budget-exhausted () t))))))

(deftest each-draw-returns-a-fresh-container
  (destructuring-bind (first second)
      (sample-form '(hash-table-of (member :a) integer :min-count 1) :count 2 :seed 1)
    (ok (not (eq first second)))
    (setf (gethash :added first) 0)
    (ok (not (nth-value 1 (gethash :added second)))))
  (destructuring-bind (first second)
      (sample-form '(alist-of (member :a) integer :min-count 1) :count 2 :seed 1)
    (ok (not (eq first second)))
    (ok (not (eq (first first) (first second))))))
```

`tests.lisp` の `defpackage` で、`(:import-from #:cl-spec/tests/backends/keyed-generator-test)` の直後に足す：

```lisp
  (:import-from #:cl-spec/tests/backends/map-generator-test)
```

- [ ] **Step 4: テストが失敗することを確認する**

`load-system` `cl-spec/tests`、`repl-eval`：`(rove:run :cl-spec/tests/backends/map-generator-test)`
Expected: FAIL。`spec-generator` に map のメソッドが無いので、`(spec spec)` の既定メソッドが `generator-unavailable`（"has no generation strategy"）を通知する。

- [ ] **Step 5: package を更新する**

`src/backends/check-it-generators.lisp` の `defpackage` を4か所変える。

`cl-spec/src/field-spec` の import に `#:key-test-function` を足す：

```lisp
  (:import-from #:cl-spec/src/field-spec
                #:plist-spec #:alist-spec #:hash-table-spec #:object-spec
                #:field-spec-fields #:field-key-test #:key-test-name #:key-test-function
                #:field-key #:field-value-spec #:field-required-p)
```

`cl-spec/src/tagged-union` の import の直後に足す：

```lisp
  (:import-from #:cl-spec/src/map-spec
                #:hash-table-of-spec #:alist-of-spec
                #:map-spec-key-spec #:map-spec-value-spec #:map-spec-key-test
                #:map-spec-min-count #:map-spec-max-count)
```

conditions と generation-request の import を置き換える：

```lisp
  (:import-from #:cl-spec/src/conditions
                #:generator-unavailable #:generator-unavailable-reason
                #:generation-budget-exhausted)
```

```lisp
  (:import-from #:cl-spec/src/generation-request
                #:*generation-request*
                #:make-generation-request
                #:reserve-generation-candidate
                #:record-generation-rejection
                #:generation-candidate-available-p
                #:with-generation-phase)
```

export の最後（`#:compile-spec-generator` の直前）に足す：

```lisp
           #:map-value-generator #:map-generator-min-count #:map-generator-max-count
           #:map-generator-domain-size #:map-generator-key-probe #:map-generator-value-probe
```

- [ ] **Step 6: エントリ数の helper を共通化する**

`eql-duplicates-p` の直後に足す：

```lisp
(defun draw-collection-count (minimum maximum)
  "Draw an element or entry count from [MINIMUM, MAXIMUM], capped by CHECK-IT:*SIZE*.

MAXIMUM may be :UNBOUNDED.  *SIZE* is raised to MINIMUM first, so a declared
minimum is always reachable."
  (let* ((size (max *size* minimum))
         (upper (if (eq maximum :unbounded) size (min maximum size))))
    (if (>= upper minimum)
        (+ minimum (random (1+ (- upper minimum))))
        minimum)))
```

`generate ((generator bounded-collection-generator))` の `let*` の先頭を、この helper を使う形にする（乱数の消費順は変わらない）。old_text：

```lisp
  (let* ((minimum (bounded-generator-min-length generator))
         (maximum (bounded-generator-max-length generator))
         (size (max check-it:*size* minimum))
         (upper (if (eq maximum :unbounded) size (min maximum size)))
         (count (if (>= upper minimum)
                    (+ minimum (random (1+ (- upper minimum))))
                    minimum))
```

new_text：

```lisp
  (let* ((count (draw-collection-count (bounded-generator-min-length generator)
                                       (bounded-generator-max-length generator)))
```

`repl-eval`：`(rove:run :cl-spec/tests/collection-constraints-test)` → Expected: `T`（この書き換えで既存の挙動が変わらないことの確認）。

- [ ] **Step 7: 生成器を足す**

`spec-generator ((spec vector-of-spec) context)` の直後に足す：

```lisp
(defparameter *map-key-collision-limit* 8
  "Consecutive key collisions after which a map holding MIN-COUNT keys stops.

The first draw for a slot counts, so a slot makes at most this many draws once
MIN-COUNT is met.  Below MIN-COUNT the slot keeps redrawing until the request's
candidate budget runs out instead.")

(defstruct (map-entry
             (:constructor make-map-entry (key value key-child value-child)))
  "One generated map entry and the generators that produced it.
KEY-CHILD is NIL for a key sampled from a finite domain, which has no generator
to shrink with."
  key value key-child value-child)

(defclass map-value-generator (generator)
  ((key-spec :initarg :key-spec :reader map-generator-key-spec
             :documentation "Key spec, named when a key redraw's reservation is denied.")
   (key-test :initarg :key-test :reader map-generator-key-test
             :documentation "Canonical keyword naming the key comparison.")
   (min-count :initarg :min-count :reader map-generator-min-count)
   (max-count :initarg :max-count :reader map-generator-max-count)
   (key-generator :initarg :key-generator :initform nil :reader map-generator-key-generator
                  :documentation "Function of no arguments returning a fresh key generator,
or NIL when keys are sampled from ENUMERATED or DISTINCT-RANGE.")
   (value-generator :initarg :value-generator :initform nil
                    :reader map-generator-value-generator
                    :documentation "Function of no arguments returning a fresh value generator.")
   (key-validator :initarg :key-validator :initform nil :reader map-generator-key-validator)
   (value-validator :initarg :value-validator :initform nil
                    :reader map-generator-value-validator)
   (key-probe :initarg :key-probe :initform nil :reader map-generator-key-probe
              :documentation "Eagerly compiled key generator, kept only to report whether
key-wise shrinking is possible.")
   (value-probe :initarg :value-probe :initform nil :reader map-generator-value-probe
                :documentation "Eagerly compiled value generator, kept for the same report.")
   (enumerated :initarg :enumerated :initform nil :reader map-generator-enumerated
               :documentation "Finite key domain as a vector already distinct under the key
test, or NIL.  A present but empty vector is an empty domain.")
   (distinct-range :initarg :distinct-range :initform nil
                   :reader map-generator-distinct-range
                   :documentation "Inclusive integer key bounds sampled without
materializing them, or NIL.")
   (entries :initform nil :accessor map-generator-entries
            :documentation "MAP-ENTRY list of the current draw, in insertion order."))
  (:documentation "Generate a homogeneous map and shrink it within its count bounds.

Subclasses only encode entries into their representation; key selection, the
budget accounting of key redraws and shrinking are shared."))

(defclass alist-map-generator (map-value-generator)
  ()
  (:documentation "Generate fresh alists whose keys are distinct under the declared test."))

(defclass hash-table-map-generator (map-value-generator)
  ()
  (:documentation "Generate fresh hash tables that use the declared key test."))

(defgeneric encode-map-entries (generator entries)
  (:documentation "Return ENTRIES, a MAP-ENTRY list, as a fresh value of GENERATOR's
representation.  Only the container is fresh: keys and values are the objects the
child generators returned."))

(defmethod encode-map-entries ((generator alist-map-generator) entries)
  (loop for entry in entries
        collect (cons (map-entry-key entry) (map-entry-value entry))))

(defmethod encode-map-entries ((generator hash-table-map-generator) entries)
  (let ((table (make-hash-table :test (key-test-name (map-generator-key-test generator)))))
    (dolist (entry entries table)
      (setf (gethash (map-entry-key entry) table) (map-entry-value entry)))))

(defun map-generator-domain-size (generator)
  "Return the finite key domain size of GENERATOR, or NIL when it draws keys."
  (let ((enumerated (map-generator-enumerated generator)))
    (if enumerated
        (length enumerated)
        (let ((range (map-generator-distinct-range generator)))
          (and range (1+ (- (cdr range) (car range))))))))

(defun draw-distinct-keys (generator count)
  "Draw up to COUNT keys distinct under the key test, as (KEY . KEY-CHILD) pairs.

The first draw for each slot is free.  Every redraw first reserves one candidate
from the active generation request and records a rejection when it collides
again, so REJECTIONS never exceeds ATTEMPTS.  Once MIN-COUNT keys are placed, a
slot gives up after *MAP-KEY-COLLISION-LIMIT* consecutive collisions, or when no
candidate remains -- asked without reserving, so stopping early never marks the
request exhausted -- and the map keeps the keys it has.  Below MIN-COUNT the slot
keeps redrawing until the reservation signals GENERATION-BUDGET-EXHAUSTED."
  (let ((seen (make-hash-table :test (key-test-name (map-generator-key-test generator))))
        (minimum (map-generator-min-count generator))
        (placed nil)
        (placed-count 0))
    (loop while (< placed-count count)
          do (let ((collisions 0))
               (loop
                 (let ((redraw-p (plusp collisions)))
                   (when redraw-p
                     (when (and (>= placed-count minimum)
                                (or (>= collisions *map-key-collision-limit*)
                                    (not (generation-candidate-available-p))))
                       (return-from draw-distinct-keys (nreverse placed)))
                     (reserve-generation-candidate '(:map-key)
                                                   (map-generator-key-spec generator)))
                   (let* ((child (funcall (map-generator-key-generator generator)))
                          (key (generate child)))
                     (if (nth-value 1 (gethash key seen))
                         (progn (when redraw-p (record-generation-rejection))
                                (incf collisions))
                         (progn (setf (gethash key seen) t)
                                (push (cons key child) placed)
                                (incf placed-count)
                                (return))))))))
    (nreverse placed)))

(defun draw-map-keys (generator count)
  "Return up to COUNT distinct keys for GENERATOR as (KEY . KEY-CHILD) pairs.
A key sampled from a finite domain has no KEY-CHILD."
  (let ((range (map-generator-distinct-range generator))
        (enumerated (map-generator-enumerated generator)))
    (cond
      (range
       (mapcar (lambda (key) (cons key nil))
               (sample-distinct-integers (car range) (cdr range) count)))
      (enumerated
       (let ((pool (shuffle-list enumerated)))
         (mapcar (lambda (key) (cons key nil))
                 (subseq pool 0 (min count (length pool))))))
      (t (draw-distinct-keys generator count)))))

(defmethod generate ((generator map-value-generator))
  "Draw a fresh map: an entry count, distinct keys, then one fresh value generator per key.

A draw outside every public boundary gets its own finite request, as a bounded
filter's does, so a key redraw always has a budget to reserve from."
  (flet ((draw ()
           (let* ((count (draw-collection-count (map-generator-min-count generator)
                                                (map-generator-max-count generator)))
                  (entries
                    (loop for (key . key-child) in (draw-map-keys generator count)
                          collect (let ((value-child
                                          (funcall (map-generator-value-generator generator))))
                                    (make-map-entry key (generate value-child)
                                                    key-child value-child)))))
             (setf (map-generator-entries generator) entries
                   (cached-value generator) (encode-map-entries generator entries)))))
    (if *generation-request*
        (draw)
        (let ((*generation-request* (make-generation-request :planned 1)))
          (draw)))))

(defun map-child-generator (spec child side context)
  "Compile CHILD's generator, naming SIDE (\"key\" or \"value\") of SPEC when it has none."
  (handler-case (spec-generator child context)
    (generation-budget-exhausted (condition) (error condition))
    (generator-unavailable (condition)
      (error 'generator-unavailable
             :spec spec
             :reason (format nil "the map ~A spec cannot be generated~@[: ~A~]"
                             side (generator-unavailable-reason condition))))))

(defun finite-key-domain (spec context)
  "Return (VALUES ENUMERATED DISTINCT-RANGE) for SPEC's keys, both NIL when keys are drawn.

A custom generator owns its distribution, so a key spec that names one -- even
under a reference, NULLABLE or OR -- is drawn from it rather than enumerated:
ENUMERABLE-VALUES answers for a MEMBER node that carries a generator.  An
enumerated domain is deduplicated again under the map's key test, and a domain
smaller than MIN-COUNT is refused here, where its size is known exactly."
  (let ((key-spec (map-spec-key-spec spec))
        (minimum (map-spec-min-count spec)))
    (flet ((refuse (size)
             (error 'generator-unavailable
                    :spec spec
                    :reason (format nil "the key domain admits ~D distinct key~:P, fewer ~
                                         than MIN-COUNT ~D"
                                    size minimum))))
      (if (effective-generator-name key-spec context)
          (values nil nil)
          (multiple-value-bind (low high) (finite-integer-range key-spec context)
            (if low
                (let ((width (1+ (- high low))))
                  (when (< width minimum) (refuse width))
                  (values nil (cons low high)))
                (multiple-value-bind (keys enumerable-p) (enumerable-values key-spec context)
                  (if (not enumerable-p)
                      (values nil nil)
                      (let ((distinct (remove-duplicates
                                       keys :test (key-test-function (map-spec-key-test spec)))))
                        (when (< (length distinct) minimum) (refuse (length distinct)))
                        (values (coerce distinct 'vector) nil))))))))))

(defun compile-map-generator (spec context class)
  "Compile a generator for the homogeneous map SPEC as an instance of CLASS."
  (let ((key-spec (map-spec-key-spec spec))
        (value-spec (map-spec-value-spec spec))
        (minimum (map-spec-min-count spec))
        (maximum (map-spec-max-count spec)))
    (flet ((build (&rest initargs)
             (apply #'make-instance class
                    :key-spec key-spec :key-test (map-spec-key-test spec)
                    :min-count minimum :max-count maximum initargs)))
      (if (eql maximum 0)
          ;; No entry can be drawn, so neither child need compile: the empty map
          ;; is the only admissible value.
          (build :enumerated (vector))
          (multiple-value-bind (enumerated distinct-range) (finite-key-domain spec context)
            (let* ((sampled-p (or enumerated distinct-range))
                   ;; Compiling each drawn child once, eagerly, raises
                   ;; *REQUIRED-SIZE* to its bounds and refuses an ungeneratable
                   ;; child now.  A sampled key domain is not compiled: its range
                   ;; width would otherwise inflate *REQUIRED-SIZE*.
                   (key-probe (unless sampled-p
                                (map-child-generator spec key-spec "key" context)))
                   (value-probe (map-child-generator spec value-spec "value" context)))
              (setf *required-size* (max *required-size* minimum))
              (build :key-generator (unless sampled-p
                                      (lambda () (spec-generator key-spec context)))
                     :value-generator (lambda () (spec-generator value-spec context))
                     :key-validator (compile-validator key-spec :context context)
                     :value-validator (compile-validator value-spec :context context)
                     :key-probe key-probe :value-probe value-probe
                     :enumerated enumerated :distinct-range distinct-range)))))))

(defmethod spec-generator ((spec alist-of-spec) context)
  (compile-map-generator spec context 'alist-map-generator))

(defmethod spec-generator ((spec hash-table-of-spec) context)
  (compile-map-generator spec context 'hash-table-map-generator))
```

- [ ] **Step 8: テストが通ることを確認する**

`load-system` `cl-spec/tests`、`repl-eval`：

```lisp
(list (rove:run :cl-spec/tests/backends/map-generator-test)
      (rove:run :cl-spec/tests/backends/and-generation-test)
      (rove:run :cl-spec/tests/collection-constraints-test))
```

Expected: `(T T T)`。

- [ ] **Step 9: コミット**

```bash
git add src/generation-request.lisp src/backends/check-it-generators.lisp tests/backends/map-generator-test.lisp tests/backends/and-generation-test.lisp tests.lisp
git commit -m "feat: generate map specs with budgeted distinct-key redraws"
```

---

### Task 5: 縮小と capability

**Files:**
- Modify: `src/backends/check-it-generators.lisp`（`replace-nth`、`shrink` メソッド）
- Modify: `src/backends/check-it.lisp`（import、`generator-shrink-strategy-p` の分岐）
- Modify: `tests/backends/map-generator-test.lisp`（テスト追加）

**Interfaces:**
- Consumes: Task 4 の `map-entry`（`copy-map-entry`）、`map-generator-entries`、`map-generator-key-validator`、`map-generator-value-validator`、`map-generator-key-test`、`encode-map-entries`、export した `map-value-generator` と `map-generator-*`。
- Produces: `shrink` が「エントリ削除 → 値 → 引いたキー」の順で縮小する。capability は削除の余地か子の縮小手段があれば `:available`。

- [ ] **Step 1: 失敗するテストを書く**

`tests/backends/map-generator-test.lisp` の末尾に追加：

```lisp
(deftest map-generation-capabilities
  (let ((backend (make-instance 'check-it-backend)))
    (dolist (entry '(((hash-table-of string integer) :available)
                     ((alist-of (member :a) null :min-count 1 :max-count 1) :none)
                     ((alist-of (member :a :b) null :min-count 1 :max-count 2) :available)
                     ((alist-of (satisfies consp) (satisfies consp) :max-count 0) :none)))
      (ok (equal (list :generation :available :shrinking (second entry))
                 (backend-capabilities backend (normalize-spec-form (first entry))))
          (format nil "Capabilities for ~S" (first entry))))))

(deftest map-shrinking-removes-entries-and-reduces-values
  (let ((*registry* (make-hash-table-registry)))
    (defproperty small-values
        ((counts (alist-of string (range integer 0 100) :test equal)))
      (:trials (:normal 200))
      (every (lambda (entry) (< (cdr entry) 50)) counts))
    (let* ((result (run-property 'small-values :seed 42))
           (shrunk (getf (property-result-shrunk-counterexample result) 'counts)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 1 (length shrunk)))
      (ok (= 50 (cdr (first shrunk))))
      (testing "a drawn key shrinks too"
        (ok (string= "" (car (first shrunk))))))))

(deftest map-shrinking-keeps-min-count-and-distinct-keys
  (let ((*registry* (make-hash-table-registry)))
    (defproperty never-holds
        ((table (hash-table-of string (range integer 50 100) :test equal :min-count 2)))
      (:trials (:normal 20))
      (not (hash-table-p table)))
    (defproperty never-holds-alist
        ((pairs (alist-of string null :test equal :min-count 2)))
      (:trials (:normal 20))
      (not (listp pairs)))
    (let* ((result (run-property 'never-holds :seed 7))
           (shrunk (getf (property-result-shrunk-counterexample result) 'table)))
      (ok (eq :failed (property-result-status result)))
      (testing "two keys never shrink into one"
        (ok (= 2 (hash-table-count shrunk))))
      (ok (eq 'equal (hash-table-test shrunk)))
      (testing "value shrinks never leave the value spec"
        (ok (loop for value being the hash-values of shrunk always (<= 50 value 100)))))
    (let* ((result (run-property 'never-holds-alist :seed 7))
           (shrunk (getf (property-result-shrunk-counterexample result) 'pairs)))
      (ok (eq :failed (property-result-status result)))
      (ok (= 2 (length shrunk)))
      (ok (distinct-under-p (alist-keys shrunk) #'equal)))))
```

- [ ] **Step 2: テストが失敗することを確認する**

`repl-eval`：`(rove:run :cl-spec/tests/backends/map-generator-test)`
Expected: FAIL。capability は既定の `(t t)` 分岐で常に `:available` になるので `:none` の2件が失敗する。縮小テストは、`map-value-generator` に `shrink` メソッドが無いため、失敗した property の縮小で no-applicable-method などのエラーになる。

- [ ] **Step 3: 縮小を足す**

`src/backends/check-it-generators.lisp` の `spec-generator ((spec hash-table-of-spec) context)` の直前（`compile-map-generator` の直後）に足す：

```lisp
(defun replace-nth (list index item)
  "Return a fresh copy of LIST with the element at INDEX replaced by ITEM."
  (loop for element in list
        for position from 0
        collect (if (= position index) item element)))

(defmethod shrink ((generator map-value-generator) test)
  "Remove entries while MIN-COUNT holds, then shrink each value, then each drawn key.

TEST returns NIL while a candidate still fails the property, so a candidate
replaces the current draw exactly when it is valid and still failing.  Some
check-it shrinkers return an untested transformed value, so only a value or key
the callback observed is kept; one its child spec rejects, and a key that
collides with another under the key test, is refused before the callback runs."
  (let ((minimum (map-generator-min-count generator))
        (same-key-p (key-test-function (map-generator-key-test generator))))
    (labels ((entries () (map-generator-entries generator))
             (try (entries)
               ;; Offer ENTRIES and adopt them when the property still fails.
               (let ((candidate (encode-map-entries generator entries)))
                 (if (funcall test candidate)
                     t
                     (progn (setf (map-generator-entries generator) entries
                                  (cached-value generator) candidate)
                            nil))))
             (remove-one ()
               (loop for index from 0 below (length (entries))
                     thereis (not (try (append (subseq (entries) 0 index)
                                               (subseq (entries) (1+ index)))))))
             (shrink-part (index child validator rebuild)
               ;; REBUILD returns the entry list with the new part, or NIL to refuse it.
               (shrink child
                       (lambda (part)
                         (if (and validator (not (funcall validator part)))
                             t
                             (let ((entries (funcall rebuild index part)))
                               (if entries (try entries) t)))))))
      (loop while (and (> (length (entries)) minimum) (remove-one)))
      (loop for index from 0 below (length (entries))
            for child = (map-entry-value-child (nth index (entries)))
            when (typep child 'generator)
              do (shrink-part index child (map-generator-value-validator generator)
                              (lambda (index value)
                                (let ((entry (copy-map-entry (nth index (entries)))))
                                  (setf (map-entry-value entry) value)
                                  (replace-nth (entries) index entry)))))
      (loop for index from 0 below (length (entries))
            for child = (map-entry-key-child (nth index (entries)))
            when (typep child 'generator)
              do (shrink-part index child (map-generator-key-validator generator)
                              (lambda (index key)
                                (let ((current (entries)))
                                  (unless (loop for other in current
                                                for position from 0
                                                thereis (and (/= position index)
                                                             (funcall same-key-p key
                                                                      (map-entry-key other))))
                                    (let ((entry (copy-map-entry (nth index current))))
                                      (setf (map-entry-key entry) key)
                                      (replace-nth current index entry)))))))
      (cached-value generator))))
```

- [ ] **Step 4: capability の分岐を足す**

`src/backends/check-it.lisp` の `cl-spec/src/backends/check-it-generators` の import に足す（`#:bounded-generator-element-probe` の直後）：

```lisp
                #:map-value-generator #:map-generator-min-count #:map-generator-max-count
                #:map-generator-domain-size #:map-generator-key-probe
                #:map-generator-value-probe
```

`generator-shrink-strategy-p` の `typecase` で、`bounded-collection-generator` の節の直後に足す：

```lisp
    (map-value-generator
     (let* ((minimum (map-generator-min-count generator))
            (maximum (map-generator-max-count generator))
            (domain (map-generator-domain-size generator))
            ;; Generation truncates the drawn count to a finite key domain.
            (upper (cond ((null domain) maximum)
                         ((eq maximum :unbounded) domain)
                         (t (min maximum domain)))))
       (or (eq upper :unbounded)
           (> upper minimum)
           (some (lambda (probe)
                   (and (typep probe 'check-it:generator)
                        (generator-shrink-strategy-p probe)))
                 (list (map-generator-key-probe generator)
                       (map-generator-value-probe generator))))))
```

- [ ] **Step 5: テストが通ることを確認する**

`load-system` `cl-spec/tests`、`repl-eval`：

```lisp
(list (rove:run :cl-spec/tests/backends/map-generator-test)
      (rove:run :cl-spec/tests/backends/keyed-generator-test)
      (rove:run :cl-spec/tests/collection-constraints-test))
```

Expected: `(T T T)`。

- [ ] **Step 6: コミット**

```bash
git add src/backends/check-it-generators.lisp src/backends/check-it.lisp tests/backends/map-generator-test.lisp
git commit -m "feat: shrink map specs and report their shrink capability"
```

---

### Task 6: ドキュメントと最終確認

**Files:**
- Modify: `docs/cl-spec-specification-v0.2-draft.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1〜5 で実装した挙動。仕様書の記述はそれに一致させる。

- [ ] **Step 1: 仕様書 §0.2 の状況表に行を足す**

`| フィールド付き構造化spec | 実装済み | ...` の行の直後に1行足す：

```markdown
| 同種マップspec | 実装済み | `hash-table-of`・`alist-of`。全キーをK、全値をVで検査し、`:test`・`:min-count`・`:max-count`を取る。キー違反と値違反は`:entry-path`で区別し、生成はキーを`:test`で区別して引く。キーの引き直しは生成予算を消費する（§9.6） |
```

- [ ] **Step 2: §9 の primitive 一覧と §9.6 を書く**

§9 の「初期primitive候補」の text block で、`hash-table` の行の直後に2行足す：

```text
hash-table-of
alist-of
```

`# 10. Generator生成` の直前（§9.5 の末尾の `---` の後）に新しい節を足す：

````markdown
# 9.6 同種マップ spec

実装済みの記法：

```lisp
(defspec word-counts
  (hash-table-of string (range integer 0 *) :test equal :min-count 1))

(defspec headers
  (alist-of string (list-of string) :test equal :max-count 64))
```

`(hash-table-of K V &rest options)`と`(alist-of K V &rest options)`は、すべてのキーが
K、すべての値がVを満たすマップを表す。キーを宣言する§9.2・§9.3のフィールド付きspec
とは異なり、マップのキーはデータであって宣言されたフィールドではない。

optionsは`:test`（`eq`・`eql`・`equal`・`equalp`、省略時`eql`）、`:min-count`
（非負整数、省略時0）、`:max-count`（非負整数または`*`、省略時は無制限）である。
未知のoption、重複、奇数個のoptions、K・Vの欠落、`:min-count`が`:max-count`を超える
宣言は登録前に`invalid-spec-form`とする。直接構築したIRも同じ検査を受け、
`:test`は正規のkeywordとして保持する。

構造検査は子specより先に行い、§9.3と同じkindを使う（`:not-a-hash-table`、
`:wrong-key-test`、`:not-an-alist`、`:bad-association`、`:duplicate-key`）。
構造不正なら1件だけ報告する。エントリ数の違反は`:too-few-entries`
（`:minimum-count`）・`:too-many-entries`（`:maximum-count`）で、どちらも
`:actual-count`を持つ。各エントリはまずキーをK、次に値をVで検査し、両方の違反を
報告する。`:path`はどちらも`(KEY . 親path)`である。キー違反か値違反かは
`:entry-path`が示し、マップの階層ごとに外側から`:key`または`:value`を並べる。
`:entry-path`はspec由来でfailure identityに含まれ、マップのキー自身は
`:field-path`にもidentityにも入らない。`alist-of`はlistの順、`hash-table-of`は
キー違反をすべて報告してから値違反を報告し、各群は`maphash`の順である。キーを印字して
並べ替えることはしない。異なるshapeで違反するエントリが複数あると、元のtableと縮小候補で
順序が入れ替わりうるが、その候補は別の失敗として捨てられ、別の失敗を縮小結果とする
ことはない。

`spec-data`は`:test`、既定値でないときの`:min-count`・`:max-count`、
`:key-child-index 0`・`:value-child-index 1`を返す。digestは`:test`とcount制約を含む。

check-it backendは、エントリ数を`[min-count, min(max-count, max(*size*, min-count))]`
から引く。Kがcustom generatorに分布を委ねていればその生成器から引く。そうでなく
有限domainを持てば（整数rangeまたは列挙可能）、宣言した`:test`で重複を除いた
domainから重複なしで抽選し、domainが`:min-count`未満なら`generator-unavailable`
とする。それ以外はKの生成器から引き、`:test`で衝突したら引き直す。各枠の最初の抽選は
予算を消費せず、引き直しは1回ごとにgeneration requestの候補を1単位予約し、
衝突した引き直しだけを棄却として数える。`:min-count`を満たした後は、8回続けて
衝突するか予算が残っていなければ、予約せずに少ないエントリ数で確定する。
`:min-count`に届く前に予算が尽きれば`generation-budget-exhausted`となる。
`hash-table-of`は宣言したtestの新しいtable、`alist-of`は新しいlistを毎回返すが、
キーと値は子の生成器が返したオブジェクトであり、その独立性は生成器とfixtureの責務
である。縮小はエントリ削除（`:min-count`まで）、値の縮小、引いたキーの縮小の順に行い、
子specに違反する候補と`:test`で衝突するキーは採用しない。

反例artifactは、`alist-of`の値をキーと値がcodecで扱える型なら保存できる。
`hash-table-of`の値は`hash-table`と同じくcodecが扱わない。coverage schemaは
マップを`:unsupported-composite`として`:unexpanded`に記録する。宣言フィールドと
任意キーの混在は扱わない。`(and (hash-table ...) (hash-table-of ...))`で書けるのは、
固定フィールドの値も共通のK・V制約に従う場合に限る。

---
````

- [ ] **Step 3: 予算の節を更新する**

`One request is one \`sample\` call or one \`run-generated-test\` invocation.` で始まる段落の末尾（`Finite candidate counts are not a wall-clock timeout.` の直後）に足す：

```markdown
A homogeneous map's key redraw (§9.6) is also a bounded-filter source call: the
key generator is the source and "not equal under the declared test to a placed
key" is the filter. The first draw for each key slot is not reserved; each
redraw reserves one unit before it calls the key generator and records a
rejection when it collides again, so `rejections ≤ attempts` holds. A map that
already holds `:min-count` keys asks whether a unit remains without reserving
one and stops instead of exhausting the request; a denied reservation records
`:exhausted-at (:map-key)`.
```

- [ ] **Step 4: `CLAUDE.md` と `AGENTS.md` を更新する**

両ファイルとも同じ Current status の段落を持つ。それぞれの段落で、`let \`sample :branch\` target one branch.` の直後に足す：

```markdown
Homogeneous maps (`hash-table-of`, `alist-of`) constrain every key with one spec
and every value with another under a declared `:test`, with optional
`:min-count`/`:max-count`; they validate, report key and value violations through
`:entry-path`, introspect, and generate and shrink with keys distinct under the
test, where a key redraw consumes the request's generation budget.
```

- [ ] **Step 5: 新しいプロセスでコンパイルの警告を確認する**

`pool-kill-worker` を `{"reset": true}` で呼び、新しい worker で cl-spec を読み込む前に `repl-eval`：

```lisp
(progn (asdf:compile-system :cl-spec :force :all)
       (asdf:compile-system :cl-spec/check-it :force :all)
       :done)
```

Expected: `:done`、`stderr` に新しいファイル由来の WARNING / STYLE-WARNING が無い。

- [ ] **Step 6: 全体のテストと lint**

`run-tests` に `{"system": "cl-spec/tests"}`。Expected: 失敗 0。

```bash
mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
```

新しいファイルの指摘は直す。既存ファイルの既存の指摘は advisory のまま残す。

- [ ] **Step 7: コミット**

```bash
git add docs/cl-spec-specification-v0.2-draft.md CLAUDE.md AGENTS.md
git commit -m "docs: specify homogeneous map specs"
```
