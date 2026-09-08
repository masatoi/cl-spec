# cl-spec スケルトン実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cl-spec` を `package-inferred-system` 化し、仕様書 §50 の 4 system 構成・全モジュールのファイル・宣言的骨格の実装・変換ロジックのスタブ・rove テスト・CI を備えた、実装を開始できる状態のリポジトリ骨格を作る。

**Architecture:** ASDF `package-inferred-system` により「パッケージ名 = ファイルパス」で 1 ファイル 1 責務に分割する。core system `cl-spec` は `check-it` に依存せず、generator backend は `cl-spec/src/generator` の動的変数 `*generator-backend*` を通じて別 system `cl-spec/check-it` から注入する。condition 階層・Semantic IR の CLOS 階層・registry protocol と hash-table backend・公開 API の export 一覧は実装し、DSL 正規化から property 実行までの変換ロジックは `not-implemented` を signal するスタブとする。

**Tech Stack:** SBCL / Roswell、ASDF `package-inferred-system`、rove（ユニットテスト）、check-it（PBT backend、別 system）、mallet（lint）

**設計文書:** `docs/superpowers/specs/2026-09-08-cl-spec-skeleton-design.md`
**上位仕様書:** `docs/cl-spec-specification-v0.2-draft.md`（以下「仕様書」。§ は仕様書の節番号）

## Global Constraints

- ASDF system は `:class :package-inferred-system`。パッケージ名はファイルパスと完全一致させる（`src/ir.lisp` → `cl-spec/src/ir`、`tests/ir-test.lisp` → `cl-spec/tests/ir-test`）。
- core system `cl-spec` の依存は `("cl-spec/main")` のみ。`check-it` と `cl-mcp` を core の依存グラフに入れてはならない。package-inferred-system は `:import-from` から依存を推論するので、後で alexandria 等を使い始めても `.asd` を触る必要はない。
- `:author "Satoshi Imai"`、`:license "MIT"`、`:version "0.1.0"`。
- コードスタイル: Google Common Lisp Style Guide。インデント 2 スペース、100 桁以内、トップレベルフォーム間に空行、小文字 lisp-case（`*special*` / `+constant+` / `something-p`）。
- 各ソースファイルは `;;;; <リポジトリ相対パス>` コメント → `defpackage` → `(in-package ...)` の順で始める。
- `defpackage` は `(:use #:cl)` を先頭に置き、他パッケージのシンボルは `:import-from` で個別に取り込む。`:use` で他パッケージを取り込まない。
- 公開関数・マクロ・クラスには docstring を付ける。スタブも例外としない。
- `defclass` のスロット名に CL のシンボル（`values` / `class-name` / `condition` /
  `documentation`）を使わない。initarg と reader は設計どおりの名前を保ち、
  スロット名だけ別名にする（`admissible-values` / `target-class` /
  `signalled-condition` / `documentation-string`）。
- スタブ本体は `(error 'not-implemented :operator '<関数名>)` とし、未使用引数は `(declare (ignore ...))` する。
- 全テストは rove。`tests/<module>-test.lisp` にミラー配置する。
- `rove:signals` は単体ではアサーションにならず真偽値を返すだけなので、必ず
  `(ok (signals (form) 'condition-type))` の形で `ok` に包む。
- lint は `mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp` が "No problems found" であること（そのタスクまでに存在するファイルのみを対象にする）。
- 内部モジュールから nickname `cl-spec` を参照しない（ASDF が root system `cl-spec` への依存と解釈して循環するため）。

## コマンド早見表

```bash
# 単一テストパッケージを実行（TDD の赤/緑確認用）
ros run --eval '(ql:quickload :cl-spec/tests/<NAME>-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/<NAME>-test) 0 1))'

# 全テスト
rove cl-spec.asd

# 全ファイル強制コンパイル（警告検出）
ros run --eval '(ql:quickload :cl-spec :silent t)' \
        --eval '(asdf:compile-system :cl-spec :force :all)' \
        --eval '(uiop:quit 0)'

# lint
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
```

`cl-spec` は `~/.roswell/local-projects/cl-spec` にあるため Quicklisp から `ql:quickload` で直接ロードできる。新しい `.asd` を追加した直後にシステムが見つからない場合は `(ql:register-local-projects)` を実行する。

---

## ファイル構成

このプランで作成・変更・削除するファイルと責務。

| ファイル | 責務 |
|---|---|
| `cl-spec.asd` | 4 system 定義。Task 1 で core、Task 8 で `/check-it`、Task 9 で `/instrument` を追加 |
| `main.lisp` | `cl-spec/main`（nickname `cl-spec`）。公開 API の集約と re-export のみ。ロジックを書かない |
| `tests.lisp` | `cl-spec/tests`。全テストパッケージを import し `asdf:perform :after` で rove を起動 |
| `src/conditions.lisp` | condition 階層。他の全モジュールが依存する葉ノード |
| `src/utils/source-location.lisp` | 定義位置 plist の取得と読み取り |
| `src/ir.lisp` | Semantic IR の CLOS 階層（§7）と `spec-kind` / `spec-children` |
| `src/registry.lisp` | registry protocol、`hash-table-registry`、`*registry*`、default registry 前面 API |
| `src/normalize.lisp` | DSL フォーム → Semantic IR（スタブ） |
| `src/validator.lisp` | validator compiler と `validp` / `validate`（スタブ） |
| `src/explain.lisp` | explainer compiler と `explain-data` / `explain`（スタブ） |
| `src/generator.lisp` | generator backend protocol と `*generator-backend*`（protocol は実装、`generator-for` / `sample` はスタブ） |
| `src/property.lisp` | Property IR クラスと registry への登録 |
| `src/property-runner.lisp` | `property-result` クラス（実装）と `run-property` 系（スタブ） |
| `src/function-spec.lisp` | Function Spec IR クラス（実装）と `check-function`（スタブ） |
| `src/introspection.lisp` | `describe-spec` / `spec-data` 系（スタブ） |
| `src/dsl.lisp` | `defspec` / `defspec-function` / `defproperty` / `defgenerator`（展開は成功、実行時にスタブ） |
| `src/backends/check-it.lisp` | check-it backend クラスと `*generator-backend*` への注入 |
| `src/instrument.lisp` | runtime instrumentation（スタブ） |
| `tests/*.lisp` | 上記のミラー |
| 削除 | `src/main.lisp`、`tests/main.lisp`、`README.org`、`README.markdown`（cl-project 生成物） |

---

## Task 1: package-inferred-system 化と condition 階層

**Files:**
- Modify: `cl-spec.asd`（全面置換）
- Modify: `.gitignore`（全面置換）
- Create: `LICENCE`
- Create: `README.md`
- Create: `main.lisp`
- Create: `tests.lisp`
- Create: `src/conditions.lisp`
- Test: `tests/conditions-test.lisp`
- Delete: `src/main.lisp`, `tests/main.lisp`, `README.org`, `README.markdown`

**Interfaces:**
- Consumes: なし
- Produces: パッケージ `cl-spec/src/conditions` が `cl-spec-error`（`error` の派生）、`not-implemented`（スロット `operator`、reader `not-implemented-operator`）、`spec-violation`（スロット `spec` / `value` / `path` / `errors`、reader `spec-violation-spec` / `-value` / `-path` / `-errors`）、`unknown-spec`（`name`、`unknown-spec-name`）、`unknown-property`（`name`、`unknown-property-name`）、`no-generator-backend`（スロットなし）を export する。以降の全タスクがこれらを使う。

- [ ] **Step 1: 旧 cl-project 生成物を削除**

```bash
git rm -q src/main.lisp tests/main.lisp README.org README.markdown
```

- [ ] **Step 2: `cl-spec.asd` を package-inferred-system に置き換える**

`cl-spec.asd` の内容を丸ごと以下にする。

```lisp
;;;; cl-spec.asd

(asdf:defsystem "cl-spec"
  :class :package-inferred-system
  :description "Executable semantic IR and property framework for Common Lisp programs"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec/main")
  :in-order-to ((test-op (test-op "cl-spec/tests"))))
```

- [ ] **Step 3: `.gitignore` を置き換える**

```
.DS_Store
*~
.#*

*.fasl
*.dx32fsl
*.dx64fsl
*.lx32fsl
*.lx64fsl
*.x86f

.serena/
.cache/
.direnv/
.mcp.json
.qlot/
```

- [ ] **Step 4: `LICENCE` を作成**

```
MIT License

Copyright (c) 2026 Satoshi Imai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5: `README.md` を作成**

```markdown
# cl-spec

An executable semantic IR and property framework for Common Lisp programs,
designed for both humans and LLM coding agents.

**Status: skeleton.** The module structure, the Semantic IR class hierarchy and
the registry are in place; the DSL normalization, validator, explainer,
generator and property runner are stubs that signal `not-implemented`.

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, structured explain, introspection | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/tests` | test suite | `rove` |

`cl-spec` never loads `check-it`. Load `cl-spec/check-it` to install a generator
backend into `cl-spec:*generator-backend*`.

## Usage

```lisp
(asdf:load-system :cl-spec)
(asdf:load-system :cl-spec/check-it)
```

## Testing

```bash
rove cl-spec.asd
```

## Documentation

- `docs/cl-spec-specification-v0.2-draft.md` — the specification
- `docs/superpowers/specs/` — design documents

## License

MIT
```

- [ ] **Step 6: 失敗するテストを書く**

`tests/conditions-test.lisp`:

```lisp
;;;; tests/conditions-test.lisp

(defpackage #:cl-spec/tests/conditions-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:not-implemented
                #:not-implemented-operator
                #:spec-violation
                #:spec-violation-spec
                #:spec-violation-value
                #:spec-violation-path
                #:spec-violation-errors
                #:unknown-spec
                #:unknown-spec-name
                #:unknown-property
                #:unknown-property-name
                #:no-generator-backend))

(in-package #:cl-spec/tests/conditions-test)

(deftest condition-hierarchy
  (testing "every framework condition inherits from CL-SPEC-ERROR"
    (ok (subtypep 'cl-spec-error 'error))
    (ok (subtypep 'not-implemented 'cl-spec-error))
    (ok (subtypep 'spec-violation 'cl-spec-error))
    (ok (subtypep 'unknown-spec 'cl-spec-error))
    (ok (subtypep 'unknown-property 'cl-spec-error))
    (ok (subtypep 'no-generator-backend 'cl-spec-error))))

(deftest not-implemented-reports-operator
  (testing "NOT-IMPLEMENTED carries and prints the stubbed operator"
    (let ((condition (make-condition 'not-implemented :operator 'normalize-spec-form)))
      (ok (eq 'normalize-spec-form (not-implemented-operator condition)))
      (ok (search "NORMALIZE-SPEC-FORM" (princ-to-string condition))))))

(deftest spec-violation-carries-context
  (testing "SPEC-VIOLATION keeps spec, value, path and structured errors"
    (let ((condition (make-condition 'spec-violation
                                     :spec 'positive-money
                                     :value -100
                                     :path '(transfer amount)
                                     :errors '((:kind :predicate-failed
                                                :predicate plusp)))))
      (ok (eq 'positive-money (spec-violation-spec condition)))
      (ok (eql -100 (spec-violation-value condition)))
      (ok (equal '(transfer amount) (spec-violation-path condition)))
      (ok (equal '((:kind :predicate-failed :predicate plusp))
                 (spec-violation-errors condition))))))

(deftest spec-violation-defaults
  (testing "PATH and ERRORS default to NIL"
    (let ((condition (make-condition 'spec-violation :spec 'money :value 1)))
      (ok (null (spec-violation-path condition)))
      (ok (null (spec-violation-errors condition))))))

(deftest lookup-conditions-name-the-missing-entry
  (testing "UNKNOWN-SPEC and UNKNOWN-PROPERTY report the name that was not found"
    (let ((spec-condition (make-condition 'unknown-spec :name 'missing-spec))
          (property-condition (make-condition 'unknown-property :name 'missing-property)))
      (ok (eq 'missing-spec (unknown-spec-name spec-condition)))
      (ok (eq 'missing-property (unknown-property-name property-condition)))
      (ok (search "MISSING-SPEC" (princ-to-string spec-condition)))
      (ok (search "MISSING-PROPERTY" (princ-to-string property-condition))))))

(deftest no-generator-backend-points-at-check-it
  (testing "the report tells the user which system installs a backend"
    (ok (search "CL-SPEC/CHECK-IT"
                (princ-to-string (make-condition 'no-generator-backend))))))
```

- [ ] **Step 7: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/conditions-test :silent t)' \
        --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/conditions` システムが見つからずロードに失敗する。

- [ ] **Step 8: `src/conditions.lisp` を実装**

```lisp
;;;; src/conditions.lisp
;;;;
;;;; Condition hierarchy for cl-spec (specification §21, §47).  Every condition
;;;; the framework signals inherits from CL-SPEC-ERROR so that callers can trap
;;;; the framework as a whole.

(defpackage #:cl-spec/src/conditions
  (:use #:cl)
  (:export #:cl-spec-error
           #:not-implemented
           #:not-implemented-operator
           #:spec-violation
           #:spec-violation-spec
           #:spec-violation-value
           #:spec-violation-path
           #:spec-violation-errors
           #:unknown-spec
           #:unknown-spec-name
           #:unknown-property
           #:unknown-property-name
           #:no-generator-backend))

(in-package #:cl-spec/src/conditions)

(define-condition cl-spec-error (error)
  ()
  (:documentation "Root of every condition signalled by cl-spec."))

(define-condition not-implemented (cl-spec-error)
  ((operator :initarg :operator
             :reader not-implemented-operator
             :documentation "Symbol naming the operator that is still a stub."))
  (:report (lambda (condition stream)
             (format stream "~S is not implemented yet."
                     (not-implemented-operator condition))))
  (:documentation
   "Signalled by skeleton stubs that carry a settled signature but no body."))

(define-condition spec-violation (cl-spec-error)
  ((spec :initarg :spec
         :reader spec-violation-spec
         :documentation "Spec designator the value was checked against.")
   (value :initarg :value
          :reader spec-violation-value
          :documentation "Value that failed the check.")
   (path :initarg :path
         :initform nil
         :reader spec-violation-path
         :documentation "Path from the root value down to the failing part.")
   (errors :initarg :errors
           :initform nil
           :reader spec-violation-errors
           :documentation "Structured error list as produced by EXPLAIN-DATA."))
  (:report (lambda (condition stream)
             (format stream "~S does not satisfy ~S~@[ at path ~S~]."
                     (spec-violation-value condition)
                     (spec-violation-spec condition)
                     (spec-violation-path condition))))
  (:documentation "Signalled when a value fails to satisfy a spec."))

(define-condition unknown-spec (cl-spec-error)
  ((name :initarg :name
         :reader unknown-spec-name
         :documentation "Symbol that is not registered as a spec."))
  (:report (lambda (condition stream)
             (format stream "No spec named ~S is registered."
                     (unknown-spec-name condition))))
  (:documentation "Signalled when a spec designator resolves to nothing."))

(define-condition unknown-property (cl-spec-error)
  ((name :initarg :name
         :reader unknown-property-name
         :documentation "Symbol that is not registered as a property."))
  (:report (lambda (condition stream)
             (format stream "No property named ~S is registered."
                     (unknown-property-name condition))))
  (:documentation "Signalled when a property designator resolves to nothing."))

(define-condition no-generator-backend (cl-spec-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "No generator backend is installed. ~
                             Load the CL-SPEC/CHECK-IT system to install one.")))
  (:documentation
   "Signalled when generation is requested while *GENERATOR-BACKEND* is NIL."))
```

- [ ] **Step 9: `main.lisp` を作成**

この時点では conditions のみを re-export する。以降のタスクで拡張していく。

```lisp
;;;; main.lisp
;;;;
;;;; Public API of cl-spec.  This file only re-exports; it contains no logic.

(defpackage #:cl-spec/main
  (:nicknames #:cl-spec)
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:cl-spec-error
                #:not-implemented
                #:not-implemented-operator
                #:spec-violation
                #:spec-violation-spec
                #:spec-violation-value
                #:spec-violation-path
                #:spec-violation-errors
                #:unknown-spec
                #:unknown-spec-name
                #:unknown-property
                #:unknown-property-name
                #:no-generator-backend)
  (:export ;; Conditions
           #:cl-spec-error
           #:not-implemented
           #:not-implemented-operator
           #:spec-violation
           #:spec-violation-spec
           #:spec-violation-value
           #:spec-violation-path
           #:spec-violation-errors
           #:unknown-spec
           #:unknown-spec-name
           #:unknown-property
           #:unknown-property-name
           #:no-generator-backend))

(in-package #:cl-spec/main)
```

- [ ] **Step 10: `tests.lisp` を作成**

```lisp
;;;; tests.lisp
;;;;
;;;; Aggregate test system.  Every test package must be listed here; the
;;;; PERFORM :AFTER method below derives the packages to run from the inferred
;;;; dependency list, so an unlisted test file is silently never run.

(defpackage #:cl-spec/tests
  (:use #:cl)
  (:import-from #:rove)
  (:import-from #:cl-spec/tests/conditions-test))

(in-package #:cl-spec/tests)

(defmethod asdf:perform :after ((op asdf:test-op)
                                (system (eql (asdf:find-system :cl-spec/tests))))
  (let ((test-packages (remove-if-not
                        (lambda (dependency)
                          (and (stringp dependency)
                               (uiop:string-prefix-p "cl-spec/tests/" dependency)))
                        (asdf:system-depends-on system))))
    (rove:run test-packages)))
```

- [ ] **Step 11: テストが通ることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/conditions-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/conditions-test) 0 1))'
rove cl-spec.asd
```

Expected: 両方 PASS。`rove cl-spec.asd` が 6 テスト green。

- [ ] **Step 12: lint**

```bash
mallet src/*.lisp tests/*.lisp main.lisp tests.lisp
```

Expected: `✓ No problems found.`

- [ ] **Step 13: コミット**

```bash
git add -A
git commit -m "feat: convert cl-spec to package-inferred-system with condition hierarchy"
```

---

## Task 2: source location ユーティリティ

**Files:**
- Create: `src/utils/source-location.lisp`
- Test: `tests/utils/source-location-test.lisp`
- Modify: `tests.lisp`（import 追加）

**Interfaces:**
- Consumes: なし
- Produces: `cl-spec/src/utils/source-location` が `current-source-location`（引数なし、`(:file <namestring or nil> :package <string>)` の plist を返す）、`source-location-file`、`source-location-package` を export する。Task 5 以降の normalize / property / dsl が定義位置メタデータとして使う。

- [ ] **Step 1: 失敗するテストを書く**

`tests/utils/source-location-test.lisp`:

```lisp
;;;; tests/utils/source-location-test.lisp

(defpackage #:cl-spec/tests/utils/source-location-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/utils/source-location
                #:current-source-location
                #:source-location-file
                #:source-location-package))

(in-package #:cl-spec/tests/utils/source-location-test)

(deftest current-source-location-shape
  (testing "returns a plist carrying :FILE and :PACKAGE"
    (let ((location (current-source-location)))
      (ok (listp location))
      (ok (evenp (length location)))
      (ok (equal (package-name *package*) (getf location :package))))))

(deftest source-location-readers
  (testing "readers project the plist without knowing its layout"
    (let ((location (list :file "/tmp/example.lisp" :package "EXAMPLE")))
      (ok (equal "/tmp/example.lisp" (source-location-file location)))
      (ok (equal "EXAMPLE" (source-location-package location))))))

(deftest source-location-readers-tolerate-nil
  (testing "a missing location reads as NIL rather than signalling"
    (ok (null (source-location-file nil)))
    (ok (null (source-location-package nil)))))

(deftest current-source-location-file-outside-a-file
  (testing "evaluated outside COMPILE-FILE and LOAD the file entry is NIL"
    (let ((*compile-file-truename* nil)
          (*load-truename* nil))
      (ok (null (source-location-file (current-source-location)))))))
```

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/utils/source-location-test :silent t)' \
        --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/utils/source-location` が見つからない。

- [ ] **Step 3: `src/utils/source-location.lisp` を実装**

```lisp
;;;; src/utils/source-location.lisp
;;;;
;;;; Definition-site metadata (specification §31).  A source location is an
;;;; opaque plist so that richer position information can be added later
;;;; without breaking the introspection API.

(defpackage #:cl-spec/src/utils/source-location
  (:use #:cl)
  (:export #:current-source-location
           #:source-location-file
           #:source-location-package))

(in-package #:cl-spec/src/utils/source-location)

(defun current-source-location ()
  "Return a source location plist describing where this form is being read.

Call this at macroexpansion time and embed the result in the expansion so that
the location survives into the compiled image.  The plist carries:

  :FILE     namestring of the file being compiled or loaded, or NIL
  :PACKAGE  name of *PACKAGE* at expansion time

Treat the result as opaque and read it with the accessors in this package."
  (list :file (let ((truename (or *compile-file-truename* *load-truename*)))
                (and truename (namestring truename)))
        :package (package-name *package*)))

(defun source-location-file (location)
  "Return the file namestring recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned."
  (getf location :file))

(defun source-location-package (location)
  "Return the package name recorded in LOCATION, or NIL.
LOCATION may be NIL, in which case NIL is returned."
  (getf location :package))
```

- [ ] **Step 4: `tests.lisp` に import を追加**

`(:import-from #:cl-spec/tests/conditions-test)` の下に追加する。

```lisp
  (:import-from #:cl-spec/tests/utils/source-location-test)
```

- [ ] **Step 5: テストが通ることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/utils/source-location-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/utils/source-location-test) 0 1))'
rove cl-spec.asd
```

Expected: 両方 PASS。

- [ ] **Step 6: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add source location utility"
```

---

## Task 3: Semantic IR クラス階層

**Files:**
- Create: `src/ir.lisp`
- Test: `tests/ir-test.lisp`
- Modify: `main.lisp`（IR API の re-export 追加）
- Modify: `tests.lisp`（import 追加）

**Interfaces:**
- Consumes: `cl-spec/src/utils/source-location`（型の説明のみ、import はしない）
- Produces: `cl-spec/src/ir` が基底クラス `spec`（スロット `name` / `description` / `source-form` / `source-location` / `metadata`、reader `spec-name` / `spec-description` / `spec-source-form` / `spec-source-location` / `spec-metadata`）と 14 の派生クラス、generic function `spec-kind`（spec → keyword）と `spec-children`（spec → spec のリスト）を export する。Task 4 以降の registry / normalize / validator / explain / generator がこの階層を扱う。

派生クラスと `spec-kind` の対応（仕様書 §7）:

| クラス | `spec-kind` | 固有スロットと reader |
|---|---|---|
| `reference-spec` | `:reference` | `target` / `reference-spec-target` |
| `predicate-spec` | `:predicate` | `predicate` / `predicate-spec-predicate` |
| `type-spec` | `:type` | `type-specifier` / `type-spec-type-specifier` |
| `and-spec` | `:and` | `children` / `and-spec-children` |
| `or-spec` | `:or` | `children` / `or-spec-children` |
| `not-spec` | `:not` | `inner-spec` / `not-spec-inner-spec` |
| `member-spec` | `:member` | `values` / `member-spec-values` |
| `range-spec` | `:range` | `base-type` / `minimum` / `maximum`、`range-spec-base-type` / `range-spec-minimum` / `range-spec-maximum` |
| `collection-spec` | （抽象） | `element-spec` / `collection-spec-element-spec` |
| `list-of-spec` | `:list-of` | 継承のみ |
| `vector-of-spec` | `:vector-of` | 継承のみ |
| `tuple-spec` | `:tuple` | `element-specs` / `tuple-spec-element-specs` |
| `nullable-spec` | `:nullable` | `inner-spec` / `nullable-spec-inner-spec` |
| `instance-of-spec` | `:instance-of` | `class-name` / `instance-of-spec-class-name` |
| `custom-spec` | `:custom` | `handler` / `custom-spec-handler` |

- [ ] **Step 1: 失敗するテストを書く**

`tests/ir-test.lisp`:

```lisp
;;;; tests/ir-test.lisp

(defpackage #:cl-spec/tests/ir-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-description
                #:spec-source-form
                #:spec-source-location
                #:spec-metadata
                #:spec-kind
                #:spec-children
                #:reference-spec
                #:reference-spec-target
                #:predicate-spec
                #:predicate-spec-predicate
                #:type-spec
                #:type-spec-type-specifier
                #:and-spec
                #:and-spec-children
                #:or-spec
                #:or-spec-children
                #:not-spec
                #:not-spec-inner-spec
                #:member-spec
                #:member-spec-values
                #:range-spec
                #:range-spec-base-type
                #:range-spec-minimum
                #:range-spec-maximum
                #:collection-spec
                #:collection-spec-element-spec
                #:list-of-spec
                #:vector-of-spec
                #:tuple-spec
                #:tuple-spec-element-specs
                #:nullable-spec
                #:nullable-spec-inner-spec
                #:instance-of-spec
                #:instance-of-spec-class-name
                #:custom-spec
                #:custom-spec-handler))

(in-package #:cl-spec/tests/ir-test)

(defparameter *leaf-classes*
  '(reference-spec predicate-spec type-spec and-spec or-spec not-spec
    member-spec range-spec collection-spec list-of-spec vector-of-spec
    tuple-spec nullable-spec instance-of-spec custom-spec)
  "Every class the Semantic IR hierarchy defines below SPEC.")

(deftest every-ir-class-is-a-spec
  (testing "all IR classes are subclasses of SPEC"
    (dolist (class-name *leaf-classes*)
      (ok (subtypep class-name 'spec)))))

(deftest collection-classes-share-a-parent
  (testing "LIST-OF, VECTOR-OF and TUPLE specialise COLLECTION-SPEC"
    (ok (subtypep 'list-of-spec 'collection-spec))
    (ok (subtypep 'vector-of-spec 'collection-spec))
    (ok (subtypep 'tuple-spec 'collection-spec))))

(deftest base-slots-are-readable-and-default-to-nil
  (testing "SPEC carries name, description, source form, location and metadata"
    (let ((instance (make-instance 'type-spec :type-specifier 'integer)))
      (ok (null (spec-name instance)))
      (ok (null (spec-description instance)))
      (ok (null (spec-source-form instance)))
      (ok (null (spec-source-location instance)))
      (ok (null (spec-metadata instance)))))
  (testing "base slots accept initargs"
    (let ((instance (make-instance 'type-spec
                                   :type-specifier 'integer
                                   :name 'small-integer
                                   :description "an integer"
                                   :source-form '(type integer)
                                   :source-location '(:file "/tmp/a.lisp")
                                   :metadata '(:tag :numeric))))
      (ok (eq 'small-integer (spec-name instance)))
      (ok (equal "an integer" (spec-description instance)))
      (ok (equal '(type integer) (spec-source-form instance)))
      (ok (equal '(:file "/tmp/a.lisp") (spec-source-location instance)))
      (ok (equal '(:tag :numeric) (spec-metadata instance))))))

(deftest spec-kind-identifies-each-class
  (testing "SPEC-KIND returns the canonical keyword for each IR class"
    (ok (eq :reference (spec-kind (make-instance 'reference-spec :target 'money))))
    (ok (eq :predicate (spec-kind (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (eq :type (spec-kind (make-instance 'type-spec :type-specifier 'integer))))
    (ok (eq :and (spec-kind (make-instance 'and-spec :children '()))))
    (ok (eq :or (spec-kind (make-instance 'or-spec :children '()))))
    (ok (eq :not (spec-kind (make-instance 'not-spec :inner-spec nil))))
    (ok (eq :member (spec-kind (make-instance 'member-spec :values '(:a :b)))))
    (ok (eq :range (spec-kind (make-instance 'range-spec))))
    (ok (eq :list-of (spec-kind (make-instance 'list-of-spec))))
    (ok (eq :vector-of (spec-kind (make-instance 'vector-of-spec))))
    (ok (eq :tuple (spec-kind (make-instance 'tuple-spec))))
    (ok (eq :nullable (spec-kind (make-instance 'nullable-spec :inner-spec nil))))
    (ok (eq :instance-of
            (spec-kind (make-instance 'instance-of-spec :class-name 'account))))
    (ok (eq :custom (spec-kind (make-instance 'custom-spec :handler nil))))))

(deftest spec-children-walks-the-tree
  (testing "leaf specs have no children"
    (ok (null (spec-children (make-instance 'type-spec :type-specifier 'integer))))
    (ok (null (spec-children (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (null (spec-children (make-instance 'reference-spec :target 'money)))))
  (testing "compound specs expose their children in definition order"
    (let* ((first-child (make-instance 'type-spec :type-specifier 'integer))
           (second-child (make-instance 'predicate-spec :predicate 'plusp))
           (conjunction (make-instance 'and-spec
                                       :children (list first-child second-child))))
      (ok (equal (list first-child second-child) (spec-children conjunction)))))
  (testing "NOT and NULLABLE expose their single inner spec as a one-element list"
    (let* ((inner (make-instance 'type-spec :type-specifier 'string))
           (negation (make-instance 'not-spec :inner-spec inner))
           (nullable (make-instance 'nullable-spec :inner-spec inner)))
      (ok (equal (list inner) (spec-children negation)))
      (ok (equal (list inner) (spec-children nullable)))))
  (testing "collections expose their element spec, tuples their element specs"
    (let* ((element (make-instance 'type-spec :type-specifier 'integer))
           (list-of (make-instance 'list-of-spec :element-spec element))
           (tuple (make-instance 'tuple-spec :element-specs (list element element))))
      (ok (equal (list element) (spec-children list-of)))
      (ok (equal (list element element) (spec-children tuple)))))
  (testing "a collection without an element spec has no children"
    (ok (null (spec-children (make-instance 'vector-of-spec))))))

(deftest range-bounds-default-to-unbounded
  (testing "RANGE-SPEC bounds default to :UNBOUNDED and accept numbers"
    (let ((open (make-instance 'range-spec))
          (closed (make-instance 'range-spec
                                 :base-type 'integer :minimum 1 :maximum 100)))
      (ok (eq :unbounded (range-spec-minimum open)))
      (ok (eq :unbounded (range-spec-maximum open)))
      (ok (null (range-spec-base-type open)))
      (ok (eq 'integer (range-spec-base-type closed)))
      (ok (eql 1 (range-spec-minimum closed)))
      (ok (eql 100 (range-spec-maximum closed))))))

(deftest class-specific-readers
  (testing "each specialised class exposes its own slot"
    (ok (eq 'money (reference-spec-target
                    (make-instance 'reference-spec :target 'money))))
    (ok (eq 'plusp (predicate-spec-predicate
                    (make-instance 'predicate-spec :predicate 'plusp))))
    (ok (eq 'integer (type-spec-type-specifier
                      (make-instance 'type-spec :type-specifier 'integer))))
    (ok (equal '(:a :b) (member-spec-values
                         (make-instance 'member-spec :values '(:a :b)))))
    (ok (eq 'account (instance-of-spec-class-name
                      (make-instance 'instance-of-spec :class-name 'account))))
    (ok (null (custom-spec-handler (make-instance 'custom-spec :handler nil))))
    (ok (null (and-spec-children (make-instance 'and-spec))))
    (ok (null (or-spec-children (make-instance 'or-spec))))
    (ok (null (not-spec-inner-spec (make-instance 'not-spec))))
    (ok (null (nullable-spec-inner-spec (make-instance 'nullable-spec))))
    (ok (null (collection-spec-element-spec (make-instance 'list-of-spec))))
    (ok (null (tuple-spec-element-specs (make-instance 'tuple-spec))))))
```

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/ir-test :silent t)' --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/ir` が見つからない。

- [ ] **Step 3: `src/ir.lisp` を実装**

```lisp
;;;; src/ir.lisp
;;;;
;;;; Semantic IR for cl-spec (specification §7).  The IR is the stable core of
;;;; the framework: the DSL macros normalize into these objects, and the
;;;; validator, explainer, generator and introspection layers all compile from
;;;; them.  The IR performs no validation itself.

(defpackage #:cl-spec/src/ir
  (:use #:cl)
  (:export #:spec
           #:spec-name
           #:spec-description
           #:spec-source-form
           #:spec-source-location
           #:spec-metadata
           #:spec-kind
           #:spec-children
           #:reference-spec
           #:reference-spec-target
           #:predicate-spec
           #:predicate-spec-predicate
           #:type-spec
           #:type-spec-type-specifier
           #:and-spec
           #:and-spec-children
           #:or-spec
           #:or-spec-children
           #:not-spec
           #:not-spec-inner-spec
           #:member-spec
           #:member-spec-values
           #:range-spec
           #:range-spec-base-type
           #:range-spec-minimum
           #:range-spec-maximum
           #:collection-spec
           #:collection-spec-element-spec
           #:list-of-spec
           #:vector-of-spec
           #:tuple-spec
           #:tuple-spec-element-specs
           #:nullable-spec
           #:nullable-spec-inner-spec
           #:instance-of-spec
           #:instance-of-spec-class-name
           #:custom-spec
           #:custom-spec-handler))

(in-package #:cl-spec/src/ir)

(defclass spec ()
  ((name :initarg :name
         :initform nil
         :reader spec-name
         :documentation "Package-qualified symbol this spec is registered under,
or NIL for an anonymous inline spec.")
   (description :initarg :description
                :initform nil
                :reader spec-description
                :documentation "Human readable description, or NIL.")
   (source-form :initarg :source-form
                :initform nil
                :reader spec-source-form
                :documentation "Original DSL s-expression this spec was
normalized from.  Kept verbatim so introspection can show what the author
wrote rather than what the normalizer produced.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader spec-source-location
                    :documentation "Source location plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION, or NIL.")
   (metadata :initarg :metadata
             :initform nil
             :reader spec-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "Base class of every Semantic IR node."))

(defgeneric spec-kind (spec)
  (:documentation "Return the canonical keyword identifying SPEC's node type.

The keyword is part of the public introspection contract: SPEC-DATA and the
MCP/JSON projections use it as the discriminator, so it must stay stable even
if class names change."))

(defgeneric spec-children (spec)
  (:documentation "Return the child specs of SPEC as a list, in definition order.

Leaf nodes return NIL.  Callers use this to walk the IR without knowing which
slot a particular class stores its children in."))

(defmethod spec-children ((spec spec))
  "Leaf nodes have no children."
  nil)

(defclass reference-spec (spec)
  ((target :initarg :target
           :initform nil
           :reader reference-spec-target
           :documentation "Symbol naming another registered spec."))
  (:documentation "A reference to a spec registered under another name."))

(defmethod spec-kind ((spec reference-spec))
  :reference)

(defclass predicate-spec (spec)
  ((predicate :initarg :predicate
              :initform nil
              :reader predicate-spec-predicate
              :documentation "Symbol naming a one-argument predicate function."))
  (:documentation "A SATISFIES-style spec built from a predicate function."))

(defmethod spec-kind ((spec predicate-spec))
  :predicate)

(defclass type-spec (spec)
  ((type-specifier :initarg :type-specifier
                   :initform nil
                   :reader type-spec-type-specifier
                   :documentation "Common Lisp type specifier."))
  (:documentation "A spec delegating to a Common Lisp type specifier."))

(defmethod spec-kind ((spec type-spec))
  :type)

(defclass and-spec (spec)
  ((children :initarg :children
             :initform nil
             :reader and-spec-children
             :documentation "Specs that must all hold."))
  (:documentation "Conjunction of specs."))

(defmethod spec-kind ((spec and-spec))
  :and)

(defmethod spec-children ((spec and-spec))
  (and-spec-children spec))

(defclass or-spec (spec)
  ((children :initarg :children
             :initform nil
             :reader or-spec-children
             :documentation "Specs of which at least one must hold."))
  (:documentation "Disjunction of specs."))

(defmethod spec-kind ((spec or-spec))
  :or)

(defmethod spec-children ((spec or-spec))
  (or-spec-children spec))

(defclass not-spec (spec)
  ((inner-spec :initarg :inner-spec
               :initform nil
               :reader not-spec-inner-spec
               :documentation "Spec that must not hold."))
  (:documentation "Negation of a spec."))

(defmethod spec-kind ((spec not-spec))
  :not)

(defmethod spec-children ((spec not-spec))
  (let ((inner (not-spec-inner-spec spec)))
    (and inner (list inner))))

(defclass member-spec (spec)
  ((admissible-values :initarg :values
                      :initform nil
                      :reader member-spec-values
                      :documentation "Admissible values, compared with EQL."))
  (:documentation "A spec admitting one of an explicit set of values."))

(defmethod spec-kind ((spec member-spec))
  :member)

(defclass range-spec (spec)
  ((base-type :initarg :base-type
              :initform nil
              :reader range-spec-base-type
              :documentation "Type specifier the range is taken over, or NIL.")
   (minimum :initarg :minimum
            :initform :unbounded
            :reader range-spec-minimum
            :documentation "Inclusive lower bound, or :UNBOUNDED.")
   (maximum :initarg :maximum
            :initform :unbounded
            :reader range-spec-maximum
            :documentation "Inclusive upper bound, or :UNBOUNDED."))
  (:documentation "A numeric range.  The DSL writes an open bound as *."))

(defmethod spec-kind ((spec range-spec))
  :range)

(defclass collection-spec (spec)
  ((element-spec :initarg :element-spec
                 :initform nil
                 :reader collection-spec-element-spec
                 :documentation "Spec every element must satisfy."))
  (:documentation "Abstract parent of homogeneous and positional collections."))

(defmethod spec-children ((spec collection-spec))
  (let ((element (collection-spec-element-spec spec)))
    (and element (list element))))

(defclass list-of-spec (collection-spec)
  ()
  (:documentation "A list whose elements all satisfy one spec."))

(defmethod spec-kind ((spec list-of-spec))
  :list-of)

(defclass vector-of-spec (collection-spec)
  ()
  (:documentation "A vector whose elements all satisfy one spec."))

(defmethod spec-kind ((spec vector-of-spec))
  :vector-of)

(defclass tuple-spec (collection-spec)
  ((element-specs :initarg :element-specs
                  :initform nil
                  :reader tuple-spec-element-specs
                  :documentation "One spec per position, in order."))
  (:documentation "A fixed-length sequence with a spec per position."))

(defmethod spec-kind ((spec tuple-spec))
  :tuple)

(defmethod spec-children ((spec tuple-spec))
  (tuple-spec-element-specs spec))

(defclass nullable-spec (spec)
  ((inner-spec :initarg :inner-spec
               :initform nil
               :reader nullable-spec-inner-spec
               :documentation "Spec the value satisfies when it is not NIL."))
  (:documentation "A spec that additionally admits NIL."))

(defmethod spec-kind ((spec nullable-spec))
  :nullable)

(defmethod spec-children ((spec nullable-spec))
  (let ((inner (nullable-spec-inner-spec spec)))
    (and inner (list inner))))

(defclass instance-of-spec (spec)
  ((target-class :initarg :class-name
                 :initform nil
                 :reader instance-of-spec-class-name
                 :documentation "Symbol naming a class the value must be an
instance of."))
  (:documentation "A spec asserting CLOS class membership."))

(defmethod spec-kind ((spec instance-of-spec))
  :instance-of)

(defclass custom-spec (spec)
  ((handler :initarg :handler
            :initform nil
            :reader custom-spec-handler
            :documentation "Object supplying user-defined validation,
explanation and generation behaviour."))
  (:documentation "Escape hatch for specs the built-in node types cannot express."))

(defmethod spec-kind ((spec custom-spec))
  :custom)
```

- [ ] **Step 4: `main.lisp` に IR API を追加**

`(:import-from #:cl-spec/src/conditions ...)` の下に以下を追加し、同じシンボル群を `:export` にも追加する。

```lisp
  (:import-from #:cl-spec/src/ir
                #:spec
                #:spec-name
                #:spec-description
                #:spec-source-form
                #:spec-source-location
                #:spec-metadata
                #:spec-kind
                #:spec-children)
```

`:export` に追加する行:

```lisp
           ;; Semantic IR
           #:spec
           #:spec-name
           #:spec-description
           #:spec-source-form
           #:spec-source-location
           #:spec-metadata
           #:spec-kind
           #:spec-children
```

派生クラス名は `cl-spec/src/ir` から直接使う想定なので `main.lisp` では再 export しない。

- [ ] **Step 5: `tests.lisp` に import を追加**

```lisp
  (:import-from #:cl-spec/tests/ir-test)
```

- [ ] **Step 6: テストが通ることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/ir-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/ir-test) 0 1))'
rove cl-spec.asd
```

Expected: 両方 PASS。

- [ ] **Step 7: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add Semantic IR class hierarchy"
```

---

## Task 4: registry protocol と hash-table backend

**Files:**
- Create: `src/registry.lisp`
- Test: `tests/registry-test.lisp`
- Modify: `main.lisp`
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/conditions`（`unknown-spec` / `unknown-property`）
- Produces: `cl-spec/src/registry` が以下を export する。

  protocol（第一引数は registry オブジェクト）:
  `registry-find-spec (registry name)` → `(values spec foundp)`、
  `registry-register-spec (registry name spec)` → `spec`、
  `registry-list-specs (registry)` → 名前のソート済みリスト、
  `registry-find-function-spec` / `registry-register-function-spec` / `registry-list-function-specs`（spec 版と同形）、
  `registry-find-property (registry name)` → `(values property foundp)`、
  `registry-register-property (registry name property &key targets tags)` → `property`、
  `registry-list-properties (registry)`、
  `registry-properties-for (registry target)` → 名前のソート済みリスト、
  `registry-properties-with-tag (registry tag)`、
  `registry-clear (registry)` → `registry`

  backend: `hash-table-registry`、`make-hash-table-registry ()`

  default registry 前面 API（`*registry*` を既定値に取る）:
  `*registry*`、`find-spec (name &optional registry)`、`list-specs (&optional registry)`、
  `register-spec (name spec &optional registry)`、`find-function-spec`、`list-function-specs`、
  `find-property`、`list-properties`、`properties-for`、`properties-with-tag`、`clear-registry`

  `register-property` と `register-function-spec` は前面 API に置かない。property / function-spec オブジェクトから targets と tags を取り出す責務はそれぞれ `src/property.lisp` と `src/function-spec.lisp` にあるため。

- [ ] **Step 1: 失敗するテストを書く**

`tests/registry-test.lisp`:

```lisp
;;;; tests/registry-test.lisp

(defpackage #:cl-spec/tests/registry-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/registry
                #:hash-table-registry
                #:make-hash-table-registry
                #:registry-find-spec
                #:registry-register-spec
                #:registry-list-specs
                #:registry-find-function-spec
                #:registry-register-function-spec
                #:registry-list-function-specs
                #:registry-find-property
                #:registry-register-property
                #:registry-list-properties
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-clear
                #:*registry*
                #:find-spec
                #:list-specs
                #:register-spec
                #:find-property
                #:properties-for
                #:clear-registry))

(in-package #:cl-spec/tests/registry-test)

(deftest spec-round-trip
  (testing "a registered spec is found again, unregistered names are not"
    (let ((registry (make-hash-table-registry)))
      (ok (typep registry 'hash-table-registry))
      (registry-register-spec registry 'positive-money :spec-object)
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'positive-money)
        (ok (eq :spec-object spec))
        (ok (eq t foundp)))
      (multiple-value-bind (spec foundp) (registry-find-spec registry 'nothing-here)
        (ok (null spec))
        (ok (null foundp))))))

(deftest registering-a-spec-returns-it
  (testing "REGISTRY-REGISTER-SPEC returns the spec so it can be used inline"
    (let ((registry (make-hash-table-registry)))
      (ok (eq :spec-object (registry-register-spec registry 'money :spec-object))))))

(deftest re-registering-a-spec-replaces-it
  (testing "the second definition wins and the name is listed once"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'money :first)
      (registry-register-spec registry 'money :second)
      (ok (eq :second (registry-find-spec registry 'money)))
      (ok (equal '(money) (registry-list-specs registry))))))

(deftest listing-specs-is-deterministic
  (testing "REGISTRY-LIST-SPECS sorts by symbol name so output is stable"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'zebra :z)
      (registry-register-spec registry 'apple :a)
      (registry-register-spec registry 'mango :m)
      (ok (equal '(apple mango zebra) (registry-list-specs registry))))))

(deftest function-specs-have-their-own-index
  (testing "function specs do not collide with value specs of the same name"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'transfer :value-spec)
      (registry-register-function-spec registry 'transfer :function-spec)
      (ok (eq :value-spec (registry-find-spec registry 'transfer)))
      (ok (eq :function-spec (registry-find-function-spec registry 'transfer)))
      (ok (equal '(transfer) (registry-list-function-specs registry))))))

(deftest properties-are-indexed-by-target-and-tag
  (testing "a property is reachable by name, by target symbol and by tag"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'transfer-preserves-balance :property
                                  :targets '(transfer)
                                  :tags '(:money :invariant))
      (ok (eq :property (registry-find-property registry 'transfer-preserves-balance)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-for registry 'transfer)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-with-tag registry :money)))
      (ok (equal '(transfer-preserves-balance)
                 (registry-properties-with-tag registry :invariant)))
      (ok (null (registry-properties-for registry 'withdraw))))))

(deftest re-registering-a-property-drops-stale-index-entries
  (testing "changing targets and tags removes the old reverse index entries"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'balance-property :first
                                  :targets '(transfer) :tags '(:money))
      (registry-register-property registry 'balance-property :second
                                  :targets '(withdraw) :tags '(:audit))
      (ok (eq :second (registry-find-property registry 'balance-property)))
      (ok (null (registry-properties-for registry 'transfer)))
      (ok (null (registry-properties-with-tag registry :money)))
      (ok (equal '(balance-property) (registry-properties-for registry 'withdraw)))
      (ok (equal '(balance-property)
                 (registry-properties-with-tag registry :audit)))
      (ok (equal '(balance-property) (registry-list-properties registry))))))

(deftest several-properties-share-one-target
  (testing "the reverse index accumulates and stays sorted"
    (let ((registry (make-hash-table-registry)))
      (registry-register-property registry 'zulu :p1 :targets '(transfer))
      (registry-register-property registry 'alpha :p2 :targets '(transfer))
      (ok (equal '(alpha zulu) (registry-properties-for registry 'transfer))))))

(deftest clearing-empties-every-index
  (testing "REGISTRY-CLEAR removes specs, function specs and properties"
    (let ((registry (make-hash-table-registry)))
      (registry-register-spec registry 'money :spec)
      (registry-register-function-spec registry 'transfer :function-spec)
      (registry-register-property registry 'invariant :property
                                  :targets '(transfer) :tags '(:money))
      (ok (eq registry (registry-clear registry)))
      (ok (null (registry-list-specs registry)))
      (ok (null (registry-list-function-specs registry)))
      (ok (null (registry-list-properties registry)))
      (ok (null (registry-properties-for registry 'transfer)))
      (ok (null (registry-properties-with-tag registry :money))))))

(deftest default-registry-front-end
  (testing "the front-end functions operate on *REGISTRY* and accept an override"
    (let ((*registry* (make-hash-table-registry)))
      (register-spec 'money :spec-object)
      (ok (eq :spec-object (find-spec 'money)))
      (ok (equal '(money) (list-specs)))
      (registry-register-property *registry* 'invariant :property
                                  :targets '(transfer))
      (ok (eq :property (find-property 'invariant)))
      (ok (equal '(invariant) (properties-for 'transfer)))
      (clear-registry)
      (ok (null (list-specs)))))
  (testing "an explicit registry argument overrides *REGISTRY*"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry)))
      (register-spec 'money :in-other other)
      (ok (null (find-spec 'money)))
      (ok (eq :in-other (find-spec 'money other))))))

(deftest default-registry-exists-at-load-time
  (testing "*REGISTRY* is bound to a usable registry without any setup"
    (ok (typep *registry* 'hash-table-registry))))
```

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/registry-test :silent t)' --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/registry` が見つからない。

- [ ] **Step 3: `src/registry.lisp` を実装**

```lisp
;;;; src/registry.lisp
;;;;
;;;; Registry protocol and the default hash-table backend (specification §8).
;;;; The registry is deliberately a protocol rather than a single global table
;;;; so that tests, ASDF reloads and LLM-generated candidate definitions can
;;;; each work against an isolated registry.
;;;;
;;;; Package-qualified symbols are the canonical identifiers, so every index is
;;;; keyed with EQ.
;;;;
;;;; This file knows nothing about property or function-spec objects: callers
;;;; pass targets and tags explicitly, which keeps the dependency edge pointing
;;;; from those modules to this one and not back.

(defpackage #:cl-spec/src/registry
  (:use #:cl)
  (:export #:registry-find-spec
           #:registry-register-spec
           #:registry-list-specs
           #:registry-find-function-spec
           #:registry-register-function-spec
           #:registry-list-function-specs
           #:registry-find-property
           #:registry-register-property
           #:registry-list-properties
           #:registry-properties-for
           #:registry-properties-with-tag
           #:registry-clear
           #:hash-table-registry
           #:make-hash-table-registry
           #:*registry*
           #:find-spec
           #:list-specs
           #:register-spec
           #:find-function-spec
           #:list-function-specs
           #:find-property
           #:list-properties
           #:properties-for
           #:properties-with-tag
           #:clear-registry))

(in-package #:cl-spec/src/registry)

(defgeneric registry-find-spec (registry name)
  (:documentation "Return the spec registered in REGISTRY under NAME.
Returns two values: the spec (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-spec (registry name spec)
  (:documentation "Register SPEC in REGISTRY under NAME, replacing any previous
definition.  Returns SPEC."))

(defgeneric registry-list-specs (registry)
  (:documentation "Return the names of every spec in REGISTRY, sorted."))

(defgeneric registry-find-function-spec (registry name)
  (:documentation "Return the function spec registered in REGISTRY under NAME.
Returns two values: the function spec (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-function-spec (registry name function-spec)
  (:documentation "Register FUNCTION-SPEC in REGISTRY under NAME, replacing any
previous definition.  Returns FUNCTION-SPEC."))

(defgeneric registry-list-function-specs (registry)
  (:documentation "Return the names of every function spec in REGISTRY, sorted."))

(defgeneric registry-find-property (registry name)
  (:documentation "Return the property registered in REGISTRY under NAME.
Returns two values: the property (NIL when absent) and a found-p boolean."))

(defgeneric registry-register-property (registry name property &key targets tags)
  (:documentation "Register PROPERTY in REGISTRY under NAME.

TARGETS is a list of symbols the property is about; TAGS is a list of tag
designators.  Both are indexed for reverse lookup.  Re-registering a name
replaces the previous definition and drops its stale index entries.
Returns PROPERTY."))

(defgeneric registry-list-properties (registry)
  (:documentation "Return the names of every property in REGISTRY, sorted."))

(defgeneric registry-properties-for (registry target)
  (:documentation "Return the names of properties registered against TARGET,
sorted."))

(defgeneric registry-properties-with-tag (registry tag)
  (:documentation "Return the names of properties carrying TAG, sorted."))

(defgeneric registry-clear (registry)
  (:documentation "Remove every entry from REGISTRY and return REGISTRY."))

(defstruct (property-entry (:constructor make-property-entry (property targets tags)))
  "A property together with the index keys it was registered under, so that
re-registration can retract the previous keys."
  (property nil)
  (targets nil :type list)
  (tags nil :type list))

(defclass hash-table-registry ()
  ((specs :initform (make-hash-table :test #'eq)
          :reader registry-specs
          :documentation "Symbol -> spec.")
   (function-specs :initform (make-hash-table :test #'eq)
                   :reader registry-function-specs
                   :documentation "Symbol -> function spec.")
   (properties :initform (make-hash-table :test #'eq)
               :reader registry-properties
               :documentation "Symbol -> PROPERTY-ENTRY.")
   (properties-by-target :initform (make-hash-table :test #'eq)
                         :reader registry-properties-by-target
                         :documentation "Target symbol -> list of property names.")
   (properties-by-tag :initform (make-hash-table :test #'eq)
                      :reader registry-properties-by-tag
                      :documentation "Tag -> list of property names."))
  (:documentation "In-image registry backed by hash tables.  The default backend."))

(defun make-hash-table-registry ()
  "Return a fresh empty HASH-TABLE-REGISTRY."
  (make-instance 'hash-table-registry))

(defvar *registry* (make-hash-table-registry)
  "Registry the front-end functions in this package operate on by default.
Rebind it to isolate specs and properties, for example in tests.")

(defun symbol-sort-key (symbol)
  "Return a string that orders SYMBOL deterministically across packages."
  (let ((package (symbol-package symbol)))
    (concatenate 'string
                 (symbol-name symbol)
                 "|"
                 (if package (package-name package) ""))))

(defun sorted-symbols (symbols)
  "Return SYMBOLS sorted by name and then by home package name."
  (sort (copy-list symbols)
        #'string<
        :key #'symbol-sort-key))

(defun hash-table-keys-sorted (table)
  "Return the keys of TABLE as a sorted list of symbols."
  (let ((keys '()))
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sorted-symbols keys)))

(defmethod registry-find-spec ((registry hash-table-registry) name)
  (gethash name (registry-specs registry)))

(defmethod registry-register-spec ((registry hash-table-registry) name spec)
  (setf (gethash name (registry-specs registry)) spec)
  spec)

(defmethod registry-list-specs ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-specs registry)))

(defmethod registry-find-function-spec ((registry hash-table-registry) name)
  (gethash name (registry-function-specs registry)))

(defmethod registry-register-function-spec ((registry hash-table-registry)
                                            name function-spec)
  (setf (gethash name (registry-function-specs registry)) function-spec)
  function-spec)

(defmethod registry-list-function-specs ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-function-specs registry)))

(defmethod registry-find-property ((registry hash-table-registry) name)
  (let ((entry (gethash name (registry-properties registry))))
    (if entry
        (values (property-entry-property entry) t)
        (values nil nil))))

(defun index-property (registry name targets tags)
  "Add NAME to REGISTRY's reverse indexes for TARGETS and TAGS."
  (dolist (target targets)
    (pushnew name (gethash target (registry-properties-by-target registry))))
  (dolist (tag tags)
    (pushnew name (gethash tag (registry-properties-by-tag registry)))))

(defun unindex-property (registry name targets tags)
  "Remove NAME from REGISTRY's reverse indexes for TARGETS and TAGS.
Index keys that end up empty are dropped so that lookups return NIL."
  (dolist (target targets)
    (let ((remaining (remove name (gethash target
                                           (registry-properties-by-target registry)))))
      (if remaining
          (setf (gethash target (registry-properties-by-target registry)) remaining)
          (remhash target (registry-properties-by-target registry)))))
  (dolist (tag tags)
    (let ((remaining (remove name (gethash tag
                                           (registry-properties-by-tag registry)))))
      (if remaining
          (setf (gethash tag (registry-properties-by-tag registry)) remaining)
          (remhash tag (registry-properties-by-tag registry))))))

(defmethod registry-register-property ((registry hash-table-registry) name property
                                       &key targets tags)
  (let ((previous (gethash name (registry-properties registry))))
    (when previous
      (unindex-property registry name
                        (property-entry-targets previous)
                        (property-entry-tags previous))))
  (setf (gethash name (registry-properties registry))
        (make-property-entry property targets tags))
  (index-property registry name targets tags)
  property)

(defmethod registry-list-properties ((registry hash-table-registry))
  (hash-table-keys-sorted (registry-properties registry)))

(defmethod registry-properties-for ((registry hash-table-registry) target)
  (sorted-symbols (gethash target (registry-properties-by-target registry))))

(defmethod registry-properties-with-tag ((registry hash-table-registry) tag)
  (sorted-symbols (gethash tag (registry-properties-by-tag registry))))

(defmethod registry-clear ((registry hash-table-registry))
  (clrhash (registry-specs registry))
  (clrhash (registry-function-specs registry))
  (clrhash (registry-properties registry))
  (clrhash (registry-properties-by-target registry))
  (clrhash (registry-properties-by-tag registry))
  registry)

(defun find-spec (name &optional (registry *registry*))
  "Return the spec registered under NAME in REGISTRY, and a found-p second value."
  (registry-find-spec registry name))

(defun list-specs (&optional (registry *registry*))
  "Return the names of every spec in REGISTRY, sorted."
  (registry-list-specs registry))

(defun register-spec (name spec &optional (registry *registry*))
  "Register SPEC under NAME in REGISTRY and return SPEC."
  (registry-register-spec registry name spec))

(defun find-function-spec (name &optional (registry *registry*))
  "Return the function spec registered under NAME in REGISTRY, and found-p."
  (registry-find-function-spec registry name))

(defun list-function-specs (&optional (registry *registry*))
  "Return the names of every function spec in REGISTRY, sorted."
  (registry-list-function-specs registry))

(defun find-property (name &optional (registry *registry*))
  "Return the property registered under NAME in REGISTRY, and found-p."
  (registry-find-property registry name))

(defun list-properties (&optional (registry *registry*))
  "Return the names of every property in REGISTRY, sorted."
  (registry-list-properties registry))

(defun properties-for (target &optional (registry *registry*))
  "Return the names of properties registered against TARGET in REGISTRY, sorted."
  (registry-properties-for registry target))

(defun properties-with-tag (tag &optional (registry *registry*))
  "Return the names of properties carrying TAG in REGISTRY, sorted."
  (registry-properties-with-tag registry tag))

(defun clear-registry (&optional (registry *registry*))
  "Remove every entry from REGISTRY and return REGISTRY."
  (registry-clear registry))
```

`registry-find-spec` の hash-table 実装が `(gethash name table)` をそのまま返すことで、`gethash` の第二返り値がそのまま found-p になる。

- [ ] **Step 4: `main.lisp` に registry API を追加**

`:import-from` に追加:

```lisp
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:hash-table-registry
                #:make-hash-table-registry
                #:registry-find-spec
                #:registry-register-spec
                #:registry-list-specs
                #:registry-find-function-spec
                #:registry-register-function-spec
                #:registry-list-function-specs
                #:registry-find-property
                #:registry-register-property
                #:registry-list-properties
                #:registry-properties-for
                #:registry-properties-with-tag
                #:registry-clear
                #:find-spec
                #:list-specs
                #:register-spec
                #:find-function-spec
                #:list-function-specs
                #:find-property
                #:list-properties
                #:properties-for
                #:properties-with-tag
                #:clear-registry)
```

`:export` に追加:

```lisp
           ;; Registry
           #:*registry*
           #:hash-table-registry
           #:make-hash-table-registry
           #:registry-find-spec
           #:registry-register-spec
           #:registry-list-specs
           #:registry-find-function-spec
           #:registry-register-function-spec
           #:registry-list-function-specs
           #:registry-find-property
           #:registry-register-property
           #:registry-list-properties
           #:registry-properties-for
           #:registry-properties-with-tag
           #:registry-clear
           #:find-spec
           #:list-specs
           #:register-spec
           #:find-function-spec
           #:list-function-specs
           #:find-property
           #:list-properties
           #:properties-for
           #:properties-with-tag
           #:clear-registry
```

- [ ] **Step 5: `tests.lisp` に import を追加**

```lisp
  (:import-from #:cl-spec/tests/registry-test)
```

- [ ] **Step 6: テストが通ることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/registry-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/registry-test) 0 1))'
rove cl-spec.asd
```

Expected: 両方 PASS。

- [ ] **Step 7: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add registry protocol and hash-table backend"
```

---

## Task 5: normalize / validator / explain のスタブ

**Files:**
- Create: `src/normalize.lisp`, `src/validator.lisp`, `src/explain.lisp`
- Test: `tests/normalize-test.lisp`, `tests/validator-test.lisp`, `tests/explain-test.lisp`
- Modify: `main.lisp`, `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/conditions`（`not-implemented`）、`cl-spec/src/ir`（`spec` を戻り値型として）
- Produces:
  `cl-spec/src/normalize`: `normalize-spec-form (form &key name source-location)` → `spec`、`*spec-primitives*`
  `cl-spec/src/validator`: `compile-validator (spec &key context)` → 1 引数関数、`validp (spec-designator value)` → boolean、`validate (spec-designator value)` → value（不適合なら `spec-violation` を signal）
  `cl-spec/src/explain`: `compile-explainer (spec &key context)` → 1 引数関数、`explain-data (spec-designator value)` → plist、`explain (spec-designator value &optional stream)` → NIL

- [ ] **Step 1: 失敗するテストを 3 本書く**

`tests/normalize-test.lisp`:

```lisp
;;;; tests/normalize-test.lisp

(defpackage #:cl-spec/tests/normalize-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form
                #:*spec-primitives*))

(in-package #:cl-spec/tests/normalize-test)

(deftest mvp-primitives-are-declared
  (testing "*SPEC-PRIMITIVES* lists exactly the MVP spec heads"
    (ok (equal '(type satisfies and or not member range list-of vector-of
                 cons-of tuple nullable instance-of)
               *spec-primitives*))))

(deftest normalize-is-a-stub
  (testing "NORMALIZE-SPEC-FORM signals NOT-IMPLEMENTED until it is written"
    (ok (signals (normalize-spec-form '(and integer (satisfies plusp)))
                 'not-implemented))))
```

`tests/validator-test.lisp`:

```lisp
;;;; tests/validator-test.lisp

(defpackage #:cl-spec/tests/validator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate))

(in-package #:cl-spec/tests/validator-test)

(deftest validator-entry-points-exist
  (testing "the public validation entry points are defined"
    (ok (fboundp 'compile-validator))
    (ok (fboundp 'validp))
    (ok (fboundp 'validate))))

(deftest validator-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (compile-validator
                  (make-instance 'type-spec :type-specifier 'integer))
                 'not-implemented))
    (ok (signals (validp 'positive-integer 10) 'not-implemented))
    (ok (signals (validate 'positive-integer 10) 'not-implemented))))
```

`tests/explain-test.lisp`:

```lisp
;;;; tests/explain-test.lisp

(defpackage #:cl-spec/tests/explain-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:type-spec)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain))

(in-package #:cl-spec/tests/explain-test)

(deftest explain-entry-points-exist
  (testing "the public explanation entry points are defined"
    (ok (fboundp 'compile-explainer))
    (ok (fboundp 'explain-data))
    (ok (fboundp 'explain))))

(deftest explain-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (compile-explainer
                  (make-instance 'type-spec :type-specifier 'integer))
                 'not-implemented))
    (ok (signals (explain-data 'positive-integer -1) 'not-implemented))
    (ok (signals (explain 'positive-integer -1) 'not-implemented))))
```

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/normalize-test :silent t)' --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/normalize` が見つからない。

- [ ] **Step 3: `src/normalize.lisp` を実装**

```lisp
;;;; src/normalize.lisp
;;;;
;;;; Spec DSL -> Semantic IR (specification §9, §37).  The macros in
;;;; SRC/DSL.LISP are pure syntax sugar; all meaning is assigned here, so the
;;;; DSL can change without disturbing the IR or the introspection API.

(defpackage #:cl-spec/src/normalize
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:normalize-spec-form
           #:*spec-primitives*))

(in-package #:cl-spec/src/normalize)

(defparameter *spec-primitives*
  '(type satisfies and or not member range list-of vector-of cons-of tuple
    nullable instance-of)
  "Spec DSL heads the MVP normalizer accepts (specification §9, §52).
Anything else is either a reference to a registered spec or an error.")

(declaim (ftype (function (t &key (:name symbol) (:source-location list)) spec)
                normalize-spec-form))

(defun normalize-spec-form (form &key name source-location)
  "Normalize spec DSL FORM into a Semantic IR object.

NAME is the symbol the resulting spec will be registered under, or NIL for an
anonymous inline spec.  SOURCE-LOCATION is a plist as produced by
CL-SPEC/SRC/UTILS/SOURCE-LOCATION:CURRENT-SOURCE-LOCATION.

The returned spec keeps FORM verbatim in its SPEC-SOURCE-FORM slot.

Not implemented yet."
  (declare (ignore form name source-location))
  (error 'not-implemented :operator 'normalize-spec-form))
```

- [ ] **Step 4: `src/validator.lisp` を実装**

```lisp
;;;; src/validator.lisp
;;;;
;;;; Validator compiler and the value-checking entry points (specification
;;;; §9.1, §20).  The public architecture is a compiler rather than a recursive
;;;; interpreter so that validation artifacts can be cached and specialised per
;;;; backend, even though the first implementation may simply interpret.

(defpackage #:cl-spec/src/validator
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:compile-validator
           #:validp
           #:validate))

(in-package #:cl-spec/src/validator)

(declaim (ftype (function (spec &key (:context t)) function) compile-validator))

(defun compile-validator (spec &key context)
  "Compile SPEC into a function of one argument returning a generalized boolean.

CONTEXT carries compilation options such as the registry to resolve references
against.  The returned function performs no explanation; use COMPILE-EXPLAINER
when structured failure data is needed.

Not implemented yet."
  (declare (ignore spec context))
  (error 'not-implemented :operator 'compile-validator))

(defun validp (spec-designator value)
  "Return true when VALUE satisfies the spec named by SPEC-DESIGNATOR.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.
Signals UNKNOWN-SPEC when a symbol resolves to nothing.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'validp))

(defun validate (spec-designator value)
  "Return VALUE when it satisfies SPEC-DESIGNATOR, otherwise signal SPEC-VIOLATION.

The signalled condition carries the structured error list produced by
EXPLAIN-DATA so that callers do not have to re-run the check.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'validate))
```

- [ ] **Step 5: `src/explain.lisp` を実装**

```lisp
;;;; src/explain.lisp
;;;;
;;;; Structured explanation (specification §22).  The structured plist is the
;;;; primary representation; the human readable rendering, the condition report
;;;; and any JSON/MCP projection are all derived from it.

(defpackage #:cl-spec/src/explain
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:compile-explainer
           #:explain-data
           #:explain))

(in-package #:cl-spec/src/explain)

(declaim (ftype (function (spec &key (:context t)) function) compile-explainer))

(defun compile-explainer (spec &key context)
  "Compile SPEC into a function of one argument returning structured explain data.

CONTEXT carries compilation options such as the registry to resolve references
against.  The returned function always produces a plist, whether or not the
value is valid.

Not implemented yet."
  (declare (ignore spec context))
  (error 'not-implemented :operator 'compile-explainer))

(defun explain-data (spec-designator value)
  "Return a plist describing whether VALUE satisfies SPEC-DESIGNATOR and why not.

The plist has the shape

  (:valid <boolean> :spec <symbol> :value <value> :path <list>
   :errors ((:kind <keyword> :predicate <symbol>
             :expected <form> :actual <value>) ...))

and is the representation every other explanation surface is derived from.

Not implemented yet."
  (declare (ignore spec-designator value))
  (error 'not-implemented :operator 'explain-data))

(defun explain (spec-designator value &optional (stream *standard-output*))
  "Print a human readable rendering of (EXPLAIN-DATA SPEC-DESIGNATOR VALUE).

Writes to STREAM and returns NIL.  This is a projection of EXPLAIN-DATA and
must not compute anything EXPLAIN-DATA does not already report.

Not implemented yet."
  (declare (ignore spec-designator value stream))
  (error 'not-implemented :operator 'explain))
```

- [ ] **Step 6: `main.lisp` に追加**

`:import-from`:

```lisp
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form
                #:*spec-primitives*)
  (:import-from #:cl-spec/src/validator
                #:compile-validator
                #:validp
                #:validate)
  (:import-from #:cl-spec/src/explain
                #:compile-explainer
                #:explain-data
                #:explain)
```

`:export`:

```lisp
           ;; Normalization
           #:normalize-spec-form
           #:*spec-primitives*
           ;; Validation
           #:compile-validator
           #:validp
           #:validate
           ;; Structured explain
           #:compile-explainer
           #:explain-data
           #:explain
```

- [ ] **Step 7: `tests.lisp` に import を 3 行追加**

```lisp
  (:import-from #:cl-spec/tests/normalize-test)
  (:import-from #:cl-spec/tests/validator-test)
  (:import-from #:cl-spec/tests/explain-test)
```

- [ ] **Step 8: テストが通ることを確認**

```bash
rove cl-spec.asd
```

Expected: PASS。

- [ ] **Step 9: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add normalize, validator and explain module stubs"
```

---

## Task 6: generator protocol と property / property-runner

**Files:**
- Create: `src/generator.lisp`, `src/property.lisp`, `src/property-runner.lisp`
- Test: `tests/generator-test.lisp`, `tests/property-test.lisp`, `tests/property-runner-test.lisp`
- Modify: `main.lisp`, `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/conditions`、`cl-spec/src/ir`、`cl-spec/src/registry`
- Produces:
  `cl-spec/src/generator`: `*generator-backend*`（既定 NIL）、`current-generator-backend ()`（未設定なら `no-generator-backend` を signal）、generic `compile-generator (backend spec &key context options)` / `generate-value (backend compiled-generator &key seed)` / `run-generated-test (backend property &key options)`、スタブ `generator-for (spec-designator &key context options)` / `sample (spec-designator &key count seed)`
  `cl-spec/src/property`: クラス `property`（スロット `name` / `arguments` / `targets` / `kind` / `tags` / `documentation` / `body` / `source-form` / `source-location` / `trials` / `metadata`、reader は `property-` 接頭辞）、`register-property (property &optional registry)`
  `cl-spec/src/property-runner`: クラス `property-result`（reader `property-result-status` / `-property` / `-trials` / `-seed` / `-counterexample` / `-shrunk-counterexample` / `-condition` / `-elapsed`）、スタブ `run-property` / `run-properties` / `replay-property`

- [ ] **Step 1: 失敗するテストを 3 本書く**

`tests/generator-test.lisp`:

```lisp
;;;; tests/generator-test.lisp

(defpackage #:cl-spec/tests/generator-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:no-generator-backend)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:generator-for
                #:sample))

(in-package #:cl-spec/tests/generator-test)

(deftest backend-protocol-is-generic
  (testing "the three backend operations are generic functions"
    (ok (typep #'compile-generator 'generic-function))
    (ok (typep #'generate-value 'generic-function))
    (ok (typep #'run-generated-test 'generic-function))))

(deftest missing-backend-is-reported
  (testing "CURRENT-GENERATOR-BACKEND signals when no backend is installed"
    (let ((*generator-backend* nil))
      (ok (signals (current-generator-backend) 'no-generator-backend)))))

(deftest installed-backend-is-returned
  (testing "CURRENT-GENERATOR-BACKEND returns whatever is bound"
    (let ((*generator-backend* :fake-backend))
      (ok (eq :fake-backend (current-generator-backend))))))

(deftest generator-front-end-is-a-stub
  (testing "GENERATOR-FOR and SAMPLE signal NOT-IMPLEMENTED"
    (let ((*generator-backend* :fake-backend))
      (ok (signals (generator-for 'positive-integer) 'not-implemented))
      (ok (signals (sample 'positive-integer) 'not-implemented)))))
```

`tests/property-test.lisp`:

```lisp
;;;; tests/property-test.lisp

(defpackage #:cl-spec/tests/property-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-property
                #:list-properties
                #:properties-for
                #:properties-with-tag)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
                #:property-targets
                #:property-kind
                #:property-tags
                #:property-documentation
                #:property-body
                #:property-source-form
                #:property-source-location
                #:property-trials
                #:property-metadata
                #:register-property))

(in-package #:cl-spec/tests/property-test)

(defun make-test-property ()
  "Return a fully populated PROPERTY for use in the tests below."
  (make-instance 'property
                 :name 'transfer-preserves-total-balance
                 :arguments '((state state-spec) (amount positive-money))
                 :targets '(transfer)
                 :kind :invariant
                 :tags '(:money :invariant)
                 :documentation "Transfer keeps the total balance unchanged."
                 :body '((= (total-balance state) (total-balance result)))
                 :source-form '(defproperty transfer-preserves-total-balance)
                 :source-location '(:file "/tmp/bank.lisp")
                 :trials '(:smoke 10 :normal 100)
                 :metadata '(:owner "bank-team")))

(deftest property-slots-round-trip
  (testing "every documented slot is readable"
    (let ((instance (make-test-property)))
      (ok (eq 'transfer-preserves-total-balance (property-name instance)))
      (ok (equal '((state state-spec) (amount positive-money))
                 (property-arguments instance)))
      (ok (equal '(transfer) (property-targets instance)))
      (ok (eq :invariant (property-kind instance)))
      (ok (equal '(:money :invariant) (property-tags instance)))
      (ok (equal "Transfer keeps the total balance unchanged."
                 (property-documentation instance)))
      (ok (equal '((= (total-balance state) (total-balance result)))
                 (property-body instance)))
      (ok (equal '(defproperty transfer-preserves-total-balance)
                 (property-source-form instance)))
      (ok (equal '(:file "/tmp/bank.lisp") (property-source-location instance)))
      (ok (equal '(:smoke 10 :normal 100) (property-trials instance)))
      (ok (equal '(:owner "bank-team") (property-metadata instance))))))

(deftest property-slots-default-to-nil
  (testing "a bare property has NIL everywhere except a required name"
    (let ((instance (make-instance 'property :name 'bare)))
      (ok (eq 'bare (property-name instance)))
      (ok (null (property-arguments instance)))
      (ok (null (property-targets instance)))
      (ok (null (property-kind instance)))
      (ok (null (property-tags instance)))
      (ok (null (property-documentation instance)))
      (ok (null (property-body instance)))
      (ok (null (property-trials instance))))))

(deftest registering-indexes-targets-and-tags
  (testing "REGISTER-PROPERTY derives the index keys from the property itself"
    (let ((*registry* (make-hash-table-registry))
          (instance (make-test-property)))
      (ok (eq instance (register-property instance)))
      (ok (eq instance (find-property 'transfer-preserves-total-balance)))
      (ok (equal '(transfer-preserves-total-balance) (list-properties)))
      (ok (equal '(transfer-preserves-total-balance) (properties-for 'transfer)))
      (ok (equal '(transfer-preserves-total-balance) (properties-with-tag :money))))))

(deftest registering-accepts-an-explicit-registry
  (testing "REGISTER-PROPERTY writes to the registry it is handed"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry))
          (instance (make-test-property)))
      (register-property instance other)
      (ok (null (find-property 'transfer-preserves-total-balance)))
      (ok (eq instance (find-property 'transfer-preserves-total-balance other))))))
```

`tests/property-runner-test.lisp`:

```lisp
;;;; tests/property-runner-test.lisp

(defpackage #:cl-spec/tests/property-runner-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-status
                #:property-result-property
                #:property-result-trials
                #:property-result-seed
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:property-result-elapsed
                #:run-property
                #:run-properties
                #:replay-property))

(in-package #:cl-spec/tests/property-runner-test)

(deftest property-result-slots-round-trip
  (testing "PROPERTY-RESULT carries the documented execution record"
    (let ((result (make-instance 'property-result
                                 :status :failed
                                 :property 'addition-preserves-order
                                 :trials 100
                                 :seed 42
                                 :counterexample '(7 -3)
                                 :shrunk-counterexample '(0 -1)
                                 :condition nil
                                 :elapsed 0.25)))
      (ok (eq :failed (property-result-status result)))
      (ok (eq 'addition-preserves-order (property-result-property result)))
      (ok (eql 100 (property-result-trials result)))
      (ok (eql 42 (property-result-seed result)))
      (ok (equal '(7 -3) (property-result-counterexample result)))
      (ok (equal '(0 -1) (property-result-shrunk-counterexample result)))
      (ok (null (property-result-condition result)))
      (ok (eql 0.25 (property-result-elapsed result))))))

(deftest property-result-defaults
  (testing "a bare result reports :PENDING and no counterexample"
    (let ((result (make-instance 'property-result)))
      (ok (eq :pending (property-result-status result)))
      (ok (null (property-result-property result)))
      (ok (null (property-result-counterexample result)))
      (ok (null (property-result-shrunk-counterexample result))))))

(deftest runner-entry-points-are-stubs
  (testing "the runner signals NOT-IMPLEMENTED until the backend is wired up"
    (ok (signals (run-property 'addition-preserves-order) 'not-implemented))
    (ok (signals (run-properties '(addition-preserves-order)) 'not-implemented))
    (ok (signals (replay-property 'addition-preserves-order 42)
                 'not-implemented))))
```

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/generator-test :silent t)' --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/generator` が見つからない。

- [ ] **Step 3: `src/generator.lisp` を実装**

```lisp
;;;; src/generator.lisp
;;;;
;;;; Generator backend protocol (specification §10, §12).  Neither the IR nor
;;;; the property runner may depend on a concrete generation engine, so the
;;;; engine is installed at load time into *GENERATOR-BACKEND* by a separate
;;;; system (CL-SPEC/CHECK-IT).  Adding an exhaustive, fuzzing or SMT backend
;;;; later means adding methods, not editing this file.

(defpackage #:cl-spec/src/generator
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented
                #:no-generator-backend)
  (:import-from #:cl-spec/src/ir
                #:spec)
  (:export #:*generator-backend*
           #:current-generator-backend
           #:compile-generator
           #:generate-value
           #:run-generated-test
           #:generator-for
           #:sample))

(in-package #:cl-spec/src/generator)

(defvar *generator-backend* nil
  "The generator backend in effect, or NIL when none is installed.

Loading the CL-SPEC/CHECK-IT system installs a CHECK-IT-BACKEND here.  Rebind
it to swap backends for a dynamic extent, for example in tests.")

(defun current-generator-backend ()
  "Return *GENERATOR-BACKEND*, signalling NO-GENERATOR-BACKEND when it is NIL."
  (or *generator-backend*
      (error 'no-generator-backend)))

(defgeneric compile-generator (backend spec &key context options)
  (:documentation "Compile SPEC into a BACKEND-specific generator object.

CONTEXT carries resolution state such as the registry; OPTIONS carries
generation parameters such as size limits.  The returned object is opaque to
everything except BACKEND and GENERATE-VALUE."))

(defgeneric generate-value (backend compiled-generator &key seed)
  (:documentation "Produce one value from COMPILED-GENERATOR using BACKEND.

SEED, when supplied, makes the value reproducible (specification §15)."))

(defgeneric run-generated-test (backend property &key options)
  (:documentation "Run PROPERTY on BACKEND and return a PROPERTY-RESULT.

The backend owns trial generation, failure detection and shrinking; the caller
owns interpretation of the result."))

(defun generator-for (spec-designator &key context options)
  "Return a compiled generator for SPEC-DESIGNATOR using the current backend.

SPEC-DESIGNATOR is either a symbol naming a registered spec or a spec object.

Not implemented yet."
  (declare (ignore spec-designator context options))
  (error 'not-implemented :operator 'generator-for))

(defun sample (spec-designator &key (count 10) seed)
  "Return a list of COUNT values generated from SPEC-DESIGNATOR.

SEED, when supplied, makes the sequence reproducible.  Intended for inspecting
what a spec admits, from the REPL or from an LLM agent.

Not implemented yet."
  (declare (ignore spec-designator count seed))
  (error 'not-implemented :operator 'sample))
```

- [ ] **Step 4: `src/property.lisp` を実装**

```lisp
;;;; src/property.lisp
;;;;
;;;; Property IR (specification §4, §39).  A property is not just a test: it is
;;;; a registered, introspectable statement about a set of target symbols, and
;;;; the registry indexes it so that an agent editing TRANSFER can ask which
;;;; properties must be re-run.

(defpackage #:cl-spec/src/property
  (:use #:cl)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-property)
  (:export #:property
           #:property-name
           #:property-arguments
           #:property-targets
           #:property-kind
           #:property-tags
           #:property-documentation
           #:property-body
           #:property-source-form
           #:property-source-location
           #:property-trials
           #:property-metadata
           #:register-property))

(in-package #:cl-spec/src/property)

(defclass property ()
  ((name :initarg :name
         :initform nil
         :reader property-name
         :documentation "Package-qualified symbol naming this property.")
   (arguments :initarg :arguments
              :initform nil
              :reader property-arguments
              :documentation "List of (VARIABLE SPEC-DESIGNATOR) bindings the
generator fills in.")
   (targets :initarg :targets
            :initform nil
            :reader property-targets
            :documentation "Symbols this property is about, from :ABOUT.
Indexed for reverse lookup.")
   (kind :initarg :kind
         :initform nil
         :reader property-kind
         :documentation "Classification keyword such as :INVARIANT or
:ROUND-TRIP (specification §6).")
   (tags :initarg :tags
         :initform nil
         :reader property-tags
         :documentation "Tag designators, indexed for reverse lookup.")
   (documentation-string :initarg :documentation
                         :initform nil
                         :reader property-documentation
                         :documentation "Human readable description, or NIL.")
   (body :initarg :body
         :initform nil
         :reader property-body
         :documentation "Forms of the property predicate, kept verbatim so that
introspection can show the author's source.")
   (source-form :initarg :source-form
                :initform nil
                :reader property-source-form
                :documentation "The whole DEFPROPERTY form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader property-source-location
                    :documentation "Source location plist, or NIL.")
   (trials :initarg :trials
           :initform nil
           :reader property-trials
           :documentation "Per-profile trial counts, for example
(:SMOKE 10 :NORMAL 100) (specification §33).")
   (metadata :initarg :metadata
             :initform nil
             :reader property-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "A registered, executable statement about program behaviour."))

(defun register-property (property &optional (registry *registry*))
  "Register PROPERTY in REGISTRY under its own name and return PROPERTY.

The target and tag index keys are taken from the property object, which is why
this function lives here rather than in the registry: the registry deliberately
knows nothing about property objects."
  (registry-register-property registry
                              (property-name property)
                              property
                              :targets (property-targets property)
                              :tags (property-tags property)))
```

- [ ] **Step 5: `src/property-runner.lisp` を実装**

```lisp
;;;; src/property-runner.lisp
;;;;
;;;; Property execution and its structured result (specification §13-16).
;;;; Execution is delegated to whichever generator backend is installed, so
;;;; this file never mentions check-it.

(defpackage #:cl-spec/src/property-runner
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/property
                #:property)
  (:export #:property-result
           #:property-result-status
           #:property-result-property
           #:property-result-trials
           #:property-result-seed
           #:property-result-counterexample
           #:property-result-shrunk-counterexample
           #:property-result-condition
           #:property-result-elapsed
           #:run-property
           #:run-properties
           #:replay-property))

(in-package #:cl-spec/src/property-runner)

(defclass property-result ()
  ((status :initarg :status
           :initform :pending
           :reader property-result-status
           :documentation "One of :PASSED, :FAILED, :ERROR, :SKIPPED or
:PENDING.")
   (property :initarg :property
             :initform nil
             :reader property-result-property
             :documentation "Name of the property that was run.")
   (trials :initarg :trials
           :initform nil
           :reader property-result-trials
           :documentation "Number of trials actually executed.")
   (seed :initarg :seed
         :initform nil
         :reader property-result-seed
         :documentation "Random seed the run started from, for replay.")
   (counterexample :initarg :counterexample
                   :initform nil
                   :reader property-result-counterexample
                   :documentation "Arguments of the first failing trial.")
   (shrunk-counterexample :initarg :shrunk-counterexample
                          :initform nil
                          :reader property-result-shrunk-counterexample
                          :documentation "Minimal failing arguments after
shrinking.  This is the value an agent should be shown first.")
   (signalled-condition :initarg :condition
                        :initform nil
                        :reader property-result-condition
                        :documentation "Condition signalled by the property
body, or NIL.")
   (elapsed :initarg :elapsed
            :initform nil
            :reader property-result-elapsed
            :documentation "Wall clock seconds the run took, or NIL."))
  (:documentation "Structured outcome of running one property.

A property run is never reported as a bare boolean: the seed, the trial count
and the shrunk counterexample are what make a failure actionable."))

(declaim (ftype (function ((or symbol property)
                           &key (:profile t) (:seed t) (:options t))
                          property-result)
                run-property))

(defun run-property (property-designator &key profile seed options)
  "Run the property named by PROPERTY-DESIGNATOR and return a PROPERTY-RESULT.

PROFILE selects a trial count from the property's :TRIALS plist and defaults to
:NORMAL.  SEED forces a starting seed.  OPTIONS is passed through to the
generator backend.  Signals NO-GENERATOR-BACKEND when no backend is installed.

Not implemented yet."
  (declare (ignore property-designator profile seed options))
  (error 'not-implemented :operator 'run-property))

(defun run-properties (property-designators &key profile options)
  "Run each property in PROPERTY-DESIGNATORS and return a list of PROPERTY-RESULT.

Every property is run even when an earlier one fails, so that one call reports
the whole picture.

Not implemented yet."
  (declare (ignore property-designators profile options))
  (error 'not-implemented :operator 'run-properties))

(defun replay-property (property-designator seed &key options)
  "Re-run PROPERTY-DESIGNATOR from SEED and return a PROPERTY-RESULT.

Given the same seed and the same property definition the generated sequence is
identical, which is what makes a reported failure reproducible.

Not implemented yet."
  (declare (ignore property-designator seed options))
  (error 'not-implemented :operator 'replay-property))
```

`run-property` の `declaim` が `property` クラスを型として使うので、`(:import-from #:cl-spec/src/property #:property)` は未使用 import にならず、ASDF も `src/property-runner` → `src/property` の依存辺を正しく推論する。

- [ ] **Step 6: `main.lisp` に追加**

`:import-from`:

```lisp
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test
                #:generator-for
                #:sample)
  (:import-from #:cl-spec/src/property
                #:property
                #:property-name
                #:property-arguments
                #:property-targets
                #:property-kind
                #:property-tags
                #:property-documentation
                #:property-body
                #:property-source-form
                #:property-source-location
                #:property-trials
                #:property-metadata
                #:register-property)
  (:import-from #:cl-spec/src/property-runner
                #:property-result
                #:property-result-status
                #:property-result-property
                #:property-result-trials
                #:property-result-seed
                #:property-result-counterexample
                #:property-result-shrunk-counterexample
                #:property-result-condition
                #:property-result-elapsed
                #:run-property
                #:run-properties
                #:replay-property)
```

`:export`（上記シンボルをすべて、コメント `;; Generators` / `;; Properties` / `;; Property results` で区切って追加）。

- [ ] **Step 7: `tests.lisp` に import を 3 行追加**

```lisp
  (:import-from #:cl-spec/tests/generator-test)
  (:import-from #:cl-spec/tests/property-test)
  (:import-from #:cl-spec/tests/property-runner-test)
```

- [ ] **Step 8: テストが通ることを確認**

```bash
rove cl-spec.asd
```

Expected: PASS。

- [ ] **Step 9: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add generator protocol, property IR and property runner"
```

---

## Task 7: function-spec / introspection / dsl

**Files:**
- Create: `src/function-spec.lisp`, `src/introspection.lisp`, `src/dsl.lisp`
- Test: `tests/function-spec-test.lisp`, `tests/introspection-test.lisp`, `tests/dsl-test.lisp`, `tests/main-test.lisp`
- Modify: `main.lisp`, `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/conditions`、`cl-spec/src/registry`、`cl-spec/src/normalize`、`cl-spec/src/property`、`cl-spec/src/utils/source-location`
- Produces:
  `cl-spec/src/function-spec`: クラス `function-spec`（reader `function-spec-name` / `-argument-specs` / `-return-spec` / `-preconditions` / `-postconditions` / `-source-form` / `-source-location` / `-metadata`）、`register-function-spec (function-spec &optional registry)`、スタブ `check-function`
  `cl-spec/src/introspection`: スタブ `describe-spec` / `describe-property` / `spec-data` / `property-data`
  `cl-spec/src/dsl`: マクロ `defspec` / `defspec-function` / `defproperty` / `defgenerator`（展開は成功し、実行時に `not-implemented`）と展開先関数 `expand-function-spec-definition` / `expand-property-definition` / `expand-generator-definition`

- [ ] **Step 1: 失敗するテストを 4 本書く**

`tests/function-spec-test.lisp`:

```lisp
;;;; tests/function-spec-test.lisp

(defpackage #:cl-spec/tests/function-spec-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:make-hash-table-registry
                #:find-function-spec
                #:list-function-specs)
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name
                #:function-spec-argument-specs
                #:function-spec-return-spec
                #:function-spec-preconditions
                #:function-spec-postconditions
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata
                #:register-function-spec
                #:check-function))

(in-package #:cl-spec/tests/function-spec-test)

(deftest function-spec-slots-round-trip
  (testing "every documented slot is readable"
    (let ((instance (make-instance 'function-spec
                                   :name 'transfer
                                   :argument-specs '((from account)
                                                     (to account)
                                                     (amount positive-money))
                                   :return-spec 'transaction
                                   :preconditions '((distinct-accounts-p from to))
                                   :postconditions '((balance-preserved-p))
                                   :source-form '(defspec-function transfer)
                                   :source-location '(:file "/tmp/bank.lisp")
                                   :metadata '(:owner "bank-team"))))
      (ok (eq 'transfer (function-spec-name instance)))
      (ok (equal '((from account) (to account) (amount positive-money))
                 (function-spec-argument-specs instance)))
      (ok (eq 'transaction (function-spec-return-spec instance)))
      (ok (equal '((distinct-accounts-p from to))
                 (function-spec-preconditions instance)))
      (ok (equal '((balance-preserved-p)) (function-spec-postconditions instance)))
      (ok (equal '(defspec-function transfer) (function-spec-source-form instance)))
      (ok (equal '(:file "/tmp/bank.lisp") (function-spec-source-location instance)))
      (ok (equal '(:owner "bank-team") (function-spec-metadata instance))))))

(deftest function-spec-registration
  (testing "REGISTER-FUNCTION-SPEC uses the function spec's own name"
    (let ((*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (ok (eq instance (register-function-spec instance)))
      (ok (eq instance (find-function-spec 'transfer)))
      (ok (equal '(transfer) (list-function-specs)))))
  (testing "an explicit registry argument is honoured"
    (let ((other (make-hash-table-registry))
          (*registry* (make-hash-table-registry))
          (instance (make-instance 'function-spec :name 'transfer)))
      (register-function-spec instance other)
      (ok (null (find-function-spec 'transfer)))
      (ok (eq instance (find-function-spec 'transfer other))))))

(deftest check-function-is-a-stub
  (testing "CHECK-FUNCTION signals NOT-IMPLEMENTED"
    (ok (signals (check-function 'transfer) 'not-implemented))))
```

`tests/introspection-test.lisp`:

```lisp
;;;; tests/introspection-test.lisp

(defpackage #:cl-spec/tests/introspection-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data))

(in-package #:cl-spec/tests/introspection-test)

(deftest introspection-entry-points-exist
  (testing "the four introspection entry points are defined"
    (ok (fboundp 'describe-spec))
    (ok (fboundp 'describe-property))
    (ok (fboundp 'spec-data))
    (ok (fboundp 'property-data))))

(deftest introspection-entry-points-are-stubs
  (testing "each signals NOT-IMPLEMENTED naming itself"
    (ok (signals (spec-data 'positive-integer) 'not-implemented))
    (ok (signals (property-data 'addition-preserves-order) 'not-implemented))
    (ok (signals (describe-spec 'positive-integer) 'not-implemented))
    (ok (signals (describe-property 'addition-preserves-order)
                 'not-implemented))))
```

`tests/dsl-test.lisp`:

```lisp
;;;; tests/dsl-test.lisp

(defpackage #:cl-spec/tests/dsl-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator))

(in-package #:cl-spec/tests/dsl-test)

(deftest dsl-macros-are-macros
  (testing "the four DSL entry points are macros, not functions"
    (ok (macro-function 'defspec))
    (ok (macro-function 'defspec-function))
    (ok (macro-function 'defproperty))
    (ok (macro-function 'defgenerator))))

(deftest dsl-macros-expand-without-error
  (testing "macroexpansion succeeds so that source files still compile"
    (ok (macroexpand-1 '(defspec positive-integer (and integer (range 1 *)))))
    (ok (macroexpand-1 '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction))))
    (ok (macroexpand-1 '(defproperty addition-preserves-order
                         ((x positive-integer) (y positive-integer))
                         (:about +)
                         (> (+ x y) x))))
    (ok (macroexpand-1 '(defgenerator small-integer () (random 100))))))

(deftest dsl-macros-signal-at-runtime
  (testing "evaluating an expansion reaches a stub and signals NOT-IMPLEMENTED"
    (ok (signals (eval '(defspec positive-integer (and integer (range 1 *))))
                 'not-implemented))
    (ok (signals (eval '(defspec-function transfer
                         (:args (amount positive-money))
                         (:returns transaction)))
                 'not-implemented))
    (ok (signals (eval '(defproperty addition-preserves-order
                         ((x positive-integer) (y positive-integer))
                         (:about +)
                         (> (+ x y) x)))
                 'not-implemented))
    (ok (signals (eval '(defgenerator small-integer () (random 100)))
                 'not-implemented))))
```

`tests/main-test.lisp`:

```lisp
;;;; tests/main-test.lisp

(defpackage #:cl-spec/tests/main-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok)
  (:import-from #:cl-spec/main))

(in-package #:cl-spec/tests/main-test)

(defparameter *mvp-api*
  '("DEFSPEC" "FIND-SPEC" "LIST-SPECS" "VALIDP" "VALIDATE" "EXPLAIN"
    "EXPLAIN-DATA"
    "DEFGENERATOR" "GENERATOR-FOR" "SAMPLE"
    "DEFSPEC-FUNCTION" "FIND-FUNCTION-SPEC" "CHECK-FUNCTION"
    "DEFPROPERTY" "FIND-PROPERTY" "LIST-PROPERTIES" "PROPERTIES-FOR"
    "RUN-PROPERTY" "RUN-PROPERTIES" "REPLAY-PROPERTY"
    "DESCRIBE-SPEC" "DESCRIBE-PROPERTY" "SPEC-DATA" "PROPERTY-DATA")
  "The MVP API of specification §51.  Every name must be external in CL-SPEC.")

(deftest cl-spec-nickname-resolves
  (testing "the public package is reachable under the CL-SPEC nickname"
    (ok (eq (find-package "CL-SPEC") (find-package "CL-SPEC/MAIN")))))

(deftest mvp-api-is-external
  (testing "every §51 symbol is external in CL-SPEC"
    (dolist (name *mvp-api*)
      (multiple-value-bind (symbol status) (find-symbol name "CL-SPEC")
        (ok (and symbol (eq :external status)))))))
```

「core system が `check-it` を引かない」ことはテストスイート内では検証できない。`cl-spec/tests` は `cl-spec/check-it` も読み込むため、テストプロセスには常に `CHECK-IT` パッケージが存在する。この不変条件は Step 9 と CI の単体ロードで検証する。

- [ ] **Step 2: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/dsl-test :silent t)' --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/dsl` が見つからない。

- [ ] **Step 3: `src/function-spec.lisp` を実装**

```lisp
;;;; src/function-spec.lisp
;;;;
;;;; Function specs (specification §17-19).  A function spec is attached to an
;;;; existing function by name; the function is never redefined, so an existing
;;;; codebase can adopt cl-spec incrementally.

(defpackage #:cl-spec/src/function-spec
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*
                #:registry-register-function-spec)
  (:export #:function-spec
           #:function-spec-name
           #:function-spec-argument-specs
           #:function-spec-return-spec
           #:function-spec-preconditions
           #:function-spec-postconditions
           #:function-spec-source-form
           #:function-spec-source-location
           #:function-spec-metadata
           #:register-function-spec
           #:check-function))

(in-package #:cl-spec/src/function-spec)

(defclass function-spec ()
  ((name :initarg :name
         :initform nil
         :reader function-spec-name
         :documentation "Package-qualified symbol naming the specified function.")
   (argument-specs :initarg :argument-specs
                   :initform nil
                   :reader function-spec-argument-specs
                   :documentation "List of (PARAMETER SPEC-DESIGNATOR) pairs
in lambda list order, from :ARGS.")
   (return-spec :initarg :return-spec
                :initform nil
                :reader function-spec-return-spec
                :documentation "Spec designator the return value must satisfy,
from :RETURNS.")
   (preconditions :initarg :preconditions
                  :initform nil
                  :reader function-spec-preconditions
                  :documentation "Forms that must hold before the call
(specification §19).")
   (postconditions :initarg :postconditions
                   :initform nil
                   :reader function-spec-postconditions
                   :documentation "Forms that must hold after the call.")
   (source-form :initarg :source-form
                :initform nil
                :reader function-spec-source-form
                :documentation "The whole DEFSPEC-FUNCTION form, kept verbatim.")
   (source-location :initarg :source-location
                    :initform nil
                    :reader function-spec-source-location
                    :documentation "Source location plist, or NIL.")
   (metadata :initarg :metadata
             :initform nil
             :reader function-spec-metadata
             :documentation "Arbitrary plist for callers and future extensions."))
  (:documentation "A contract attached to an existing function by name."))

(defun register-function-spec (function-spec &optional (registry *registry*))
  "Register FUNCTION-SPEC in REGISTRY under its own name and return it."
  (registry-register-function-spec registry
                                   (function-spec-name function-spec)
                                   function-spec))

(defun check-function (function-designator &key trials seed options)
  "Generatively check FUNCTION-DESIGNATOR against its registered function spec.

Arguments are generated from the argument specs, preconditions filter the
generated inputs, and the return value is checked against the return spec.
Returns a PROPERTY-RESULT.

Not implemented yet."
  (declare (ignore function-designator trials seed options))
  (error 'not-implemented :operator 'check-function))
```

- [ ] **Step 4: `src/introspection.lisp` を実装**

```lisp
;;;; src/introspection.lisp
;;;;
;;;; Introspection API (specification §38).  Structured data is the primary
;;;; representation and the DESCRIBE-* functions are projections of it, because
;;;; the intended first-class consumer is a coding agent rather than a human
;;;; reading a REPL transcript.

(defpackage #:cl-spec/src/introspection
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:export #:describe-spec
           #:describe-property
           #:spec-data
           #:property-data))

(in-package #:cl-spec/src/introspection)

(defun spec-data (spec-designator &optional (registry *registry*))
  "Return a plist describing the registered spec named by SPEC-DESIGNATOR.

The plist has the shape

  (:name <symbol> :kind <keyword> :source-form <form>
   :children (<nested plist> ...))

and is what SPEC-DATA's JSON and MCP projections are built from.

Not implemented yet."
  (declare (ignore spec-designator registry))
  (error 'not-implemented :operator 'spec-data))

(defun property-data (property-designator &optional (registry *registry*))
  "Return a plist describing the registered property named by
PROPERTY-DESIGNATOR: its name, targets, kind, argument specs, tags,
documentation, source form, source location and trial configuration.

Not implemented yet."
  (declare (ignore property-designator registry))
  (error 'not-implemented :operator 'property-data))

(defun describe-spec (spec-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (SPEC-DATA SPEC-DESIGNATOR) to STREAM.

Returns NIL.  This is a projection of SPEC-DATA and must not report anything
SPEC-DATA does not already carry.

Not implemented yet."
  (declare (ignore spec-designator stream))
  (error 'not-implemented :operator 'describe-spec))

(defun describe-property (property-designator &optional (stream *standard-output*))
  "Print a human readable rendering of (PROPERTY-DATA PROPERTY-DESIGNATOR) to
STREAM.  Returns NIL.

Not implemented yet."
  (declare (ignore property-designator stream))
  (error 'not-implemented :operator 'describe-property))
```

- [ ] **Step 5: `src/dsl.lisp` を実装**

```lisp
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
                #:not-implemented)
  (:import-from #:cl-spec/src/normalize
                #:normalize-spec-form)
  (:import-from #:cl-spec/src/registry
                #:register-spec)
  (:import-from #:cl-spec/src/property
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

(defun expand-property-definition (name arguments body source-location)
  "Build a PROPERTY from the parts of a DEFPROPERTY form.

ARGUMENTS is the list of (VARIABLE SPEC-DESIGNATOR) bindings; BODY is the
option clauses such as (:ABOUT ...) followed by the predicate forms.

Not implemented yet."
  (declare (ignore name arguments body source-location))
  (error 'not-implemented :operator 'defproperty))

(defmacro defproperty (name arguments &body body)
  "Define a property named NAME over generated ARGUMENTS.

BODY starts with option clauses such as (:ABOUT ...), (:KIND ...) and
(:TAGS ...), followed by the forms of the property predicate.  A NIL result or
a signalled condition counts as a failure.

  (defproperty addition-preserves-order
      ((x positive-integer) (y positive-integer))
    (:about +)
    (:kind :monotonicity)
    (> (+ x y) x))"
  (let ((location (current-source-location)))
    `(register-property
      (expand-property-definition ',name ',arguments ',body ',location))))

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
```

- [ ] **Step 6: `main.lisp` に追加**

`:import-from`:

```lisp
  (:import-from #:cl-spec/src/function-spec
                #:function-spec
                #:function-spec-name
                #:function-spec-argument-specs
                #:function-spec-return-spec
                #:function-spec-preconditions
                #:function-spec-postconditions
                #:function-spec-source-form
                #:function-spec-source-location
                #:function-spec-metadata
                #:register-function-spec
                #:check-function)
  (:import-from #:cl-spec/src/introspection
                #:describe-spec
                #:describe-property
                #:spec-data
                #:property-data)
  (:import-from #:cl-spec/src/dsl
                #:defspec
                #:defspec-function
                #:defproperty
                #:defgenerator)
```

`:export`（上記シンボルをすべて、コメント `;; Function specs` / `;; Introspection` / `;; DSL` で区切って追加）。

- [ ] **Step 7: `tests.lisp` に import を 4 行追加**

```lisp
  (:import-from #:cl-spec/tests/function-spec-test)
  (:import-from #:cl-spec/tests/introspection-test)
  (:import-from #:cl-spec/tests/dsl-test)
  (:import-from #:cl-spec/tests/main-test)
```

- [ ] **Step 8: テストが通ることを確認**

```bash
rove cl-spec.asd
```

Expected: PASS。特に `mvp-api-is-external` が 24 シンボルすべてを external と判定すること。

- [ ] **Step 9: core system が check-it を引かないことを確認**

```bash
ros run --eval '(ql:quickload :cl-spec :silent t)' \
        --eval '(uiop:quit (if (find-package "CHECK-IT") 1 0))'
echo "exit=$?"
```

Expected: `exit=0`。`cl-spec` 単体で `CHECK-IT` パッケージが存在しないこと。

- [ ] **Step 10: 強制コンパイルで警告が出ないことを確認**

```bash
ros run --eval '(ql:quickload :cl-spec :silent t)' \
        --eval '(asdf:compile-system :cl-spec :force :all)' \
        --eval '(uiop:quit 0)'
```

Expected: WARNING / STYLE-WARNING が出力されないこと。

- [ ] **Step 11: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add function specs, introspection and the surface DSL"
```

---

## Task 8: check-it backend（`cl-spec/check-it` system）

**Files:**
- Create: `src/backends/check-it.lisp`
- Test: `tests/backends/check-it-test.lisp`
- Modify: `cl-spec.asd`（`cl-spec/check-it` system を追加）
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/generator`（`*generator-backend*` と 3 つの generic function）、`cl-spec/src/conditions`、外部 `check-it`
- Produces: `cl-spec/src/backends/check-it` が `check-it-backend`（クラス）、`install-check-it-backend ()`、`default-trials ()` を export する。ファイルのロード時に `install-check-it-backend` が呼ばれ、`*generator-backend*` に `check-it-backend` インスタンスが入る。

- [ ] **Step 1: `cl-spec.asd` に system を追加**

`cl-spec` の defsystem の後ろに追記する。

```lisp
(asdf:defsystem "cl-spec/check-it"
  :description "check-it based generator and property execution backend for cl-spec"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec"
               "check-it"
               "cl-spec/src/backends/check-it"))
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/backends/check-it-test.lisp`:

```lisp
;;;; tests/backends/check-it-test.lisp

(defpackage #:cl-spec/tests/backends/check-it-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:current-generator-backend
                #:compile-generator
                #:generate-value
                #:run-generated-test)
  (:import-from #:cl-spec/src/backends/check-it
                #:check-it-backend
                #:install-check-it-backend
                #:default-trials))

(in-package #:cl-spec/tests/backends/check-it-test)

(deftest loading-installs-the-backend
  (testing "loading this system leaves a CHECK-IT-BACKEND in *GENERATOR-BACKEND*"
    (ok (typep *generator-backend* 'check-it-backend))
    (ok (typep (current-generator-backend) 'check-it-backend))))

(deftest install-is-idempotent-and-returns-the-backend
  (testing "INSTALL-CHECK-IT-BACKEND can be called again safely"
    (let ((backend (install-check-it-backend)))
      (ok (typep backend 'check-it-backend))
      (ok (eq backend *generator-backend*)))))

(deftest default-trials-comes-from-check-it
  (testing "the default trial count is taken from CHECK-IT:*NUM-TRIALS*"
    (ok (integerp (default-trials)))
    (ok (plusp (default-trials)))))

(deftest backend-methods-are-stubs
  (testing "the three protocol methods are specialised but not yet written"
    (let ((backend (install-check-it-backend)))
      (ok (signals (compile-generator backend :any-spec) 'not-implemented))
      (ok (signals (generate-value backend :any-generator) 'not-implemented))
      (ok (signals (run-generated-test backend :any-property)
                   'not-implemented)))))
```

- [ ] **Step 3: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/backends/check-it-test :silent t)' \
        --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/backends/check-it` が見つからない。

- [ ] **Step 4: `src/backends/check-it.lisp` を実装**

```lisp
;;;; src/backends/check-it.lisp
;;;;
;;;; check-it generator backend (specification §12, §16).  check-it already
;;;; provides random generation and shrinking, so cl-spec delegates rather than
;;;; reimplementing them.  Nothing outside this file mentions check-it, and the
;;;; core cl-spec system never loads it.

(defpackage #:cl-spec/src/backends/check-it
  (:use #:cl)
  (:import-from #:check-it
                #:*num-trials*)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/generator
                #:*generator-backend*
                #:compile-generator
                #:generate-value
                #:run-generated-test)
  (:export #:check-it-backend
           #:install-check-it-backend
           #:default-trials))

(in-package #:cl-spec/src/backends/check-it)

(defclass check-it-backend ()
  ()
  (:documentation "Generator backend delegating to the check-it library."))

(defun default-trials ()
  "Return check-it's current default number of trials per property run."
  *num-trials*)

(defmethod compile-generator ((backend check-it-backend) spec &key context options)
  "Compile SPEC into a check-it generator.

Not implemented yet."
  (declare (ignore backend spec context options))
  (error 'not-implemented :operator 'compile-generator))

(defmethod generate-value ((backend check-it-backend) compiled-generator &key seed)
  "Draw one value from COMPILED-GENERATOR, optionally seeded.

Not implemented yet."
  (declare (ignore backend compiled-generator seed))
  (error 'not-implemented :operator 'generate-value))

(defmethod run-generated-test ((backend check-it-backend) property &key options)
  "Run PROPERTY through check-it, shrinking any counterexample.

Not implemented yet."
  (declare (ignore backend property options))
  (error 'not-implemented :operator 'run-generated-test))

(defun install-check-it-backend ()
  "Install a CHECK-IT-BACKEND into *GENERATOR-BACKEND* and return it.

Called when this file is loaded, which is what makes loading the
CL-SPEC/CHECK-IT system sufficient to enable generation."
  (setf *generator-backend* (make-instance 'check-it-backend)))

(install-check-it-backend)
```

- [ ] **Step 5: `tests.lisp` に import を追加**

```lisp
  (:import-from #:cl-spec/tests/backends/check-it-test)
```

- [ ] **Step 6: テストが通ることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/backends/check-it-test :silent t)' \
        --eval '(uiop:quit (if (rove:run :cl-spec/tests/backends/check-it-test) 0 1))'
rove cl-spec.asd
```

Expected: 両方 PASS。`tests/generator-test.lisp` の `missing-backend-is-reported` は `*generator-backend*` を NIL に束縛してから検査しているので、backend が導入されても通り続ける。

- [ ] **Step 7: `cl-spec/check-it` が単体でロードできることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/check-it :silent t)' \
        --eval '(uiop:quit (if (typep cl-spec:*generator-backend*
                                      (find-symbol "CHECK-IT-BACKEND"
                                                   "CL-SPEC/SRC/BACKENDS/CHECK-IT"))
                               0 1))'
echo "exit=$?"
```

Expected: `exit=0`。

- [ ] **Step 8: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add check-it generator backend as a separate system"
```

---

## Task 9: runtime instrumentation（`cl-spec/instrument` system）

**Files:**
- Create: `src/instrument.lisp`
- Test: `tests/instrument-test.lisp`
- Modify: `cl-spec.asd`（`cl-spec/instrument` system を追加）
- Modify: `tests.lisp`

**Interfaces:**
- Consumes: `cl-spec/src/conditions`、`cl-spec/src/registry`、`cl-spec/src/validator`
- Produces: `cl-spec/src/instrument` が `*instrumented-functions*`（symbol → 元の関数の hash table）、`instrumented-function-p (name)`、スタブ `instrument-function` / `uninstrument-function` を export する。

- [ ] **Step 1: `cl-spec.asd` に system を追加**

```lisp
(asdf:defsystem "cl-spec/instrument"
  :description "Runtime function instrumentation for cl-spec function specs"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-spec"
               "cl-spec/src/instrument"))
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/instrument-test.lisp`:

```lisp
;;;; tests/instrument-test.lisp

(defpackage #:cl-spec/tests/instrument-test
  (:use #:cl)
  (:import-from #:rove
                #:deftest #:testing #:ok #:signals)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/instrument
                #:*instrumented-functions*
                #:instrumented-function-p
                #:instrument-function
                #:uninstrument-function))

(in-package #:cl-spec/tests/instrument-test)

(deftest instrumentation-table-starts-empty
  (testing "*INSTRUMENTED-FUNCTIONS* is a hash table with nothing in it"
    (ok (hash-table-p *instrumented-functions*))
    (ok (zerop (hash-table-count *instrumented-functions*)))))

(deftest unknown-functions-are-not-instrumented
  (testing "INSTRUMENTED-FUNCTION-P is false for a function nobody touched"
    (ok (null (instrumented-function-p 'transfer)))))

(deftest instrumentation-tracks-the-table
  (testing "INSTRUMENTED-FUNCTION-P reads the table rather than the fdefinition"
    (let ((*instrumented-functions* (make-hash-table :test #'eq)))
      (setf (gethash 'transfer *instrumented-functions*) #'identity)
      (ok (instrumented-function-p 'transfer)))))

(deftest instrumentation-entry-points-are-stubs
  (testing "INSTRUMENT-FUNCTION and UNINSTRUMENT-FUNCTION signal NOT-IMPLEMENTED"
    (ok (signals (instrument-function 'transfer) 'not-implemented))
    (ok (signals (uninstrument-function 'transfer) 'not-implemented))))
```

- [ ] **Step 3: テストが落ちることを確認**

```bash
ros run --eval '(ql:quickload :cl-spec/tests/instrument-test :silent t)' \
        --eval '(uiop:quit 0)'
```

Expected: FAIL。`cl-spec/src/instrument` が見つからない。

- [ ] **Step 4: `src/instrument.lisp` を実装**

```lisp
;;;; src/instrument.lisp
;;;;
;;;; Runtime contract checking (specification §20).  Instrumentation replaces a
;;;; function's definition with a wrapper that validates arguments and return
;;;; value against its registered function spec.  It is a separate system
;;;; because production images should be able to load cl-spec without gaining
;;;; the ability to rewrite fdefinitions.

(defpackage #:cl-spec/src/instrument
  (:use #:cl)
  (:import-from #:cl-spec/src/conditions
                #:not-implemented)
  (:import-from #:cl-spec/src/registry
                #:*registry*)
  (:import-from #:cl-spec/src/validator
                #:validate)
  (:export #:*instrumented-functions*
           #:instrumented-function-p
           #:instrument-function
           #:uninstrument-function))

(in-package #:cl-spec/src/instrument)

(defvar *instrumented-functions* (make-hash-table :test #'eq)
  "Symbol -> the original function object, for every instrumented function.

UNINSTRUMENT-FUNCTION restores from this table, so an entry here is the single
source of truth for whether a function is currently wrapped.")

(defun instrumented-function-p (name)
  "Return true when NAME currently has an instrumentation wrapper installed."
  (nth-value 1 (gethash name *instrumented-functions*)))

(defun instrument-function (name &optional (registry *registry*))
  "Wrap NAME so that each call validates arguments and result against its
registered function spec in REGISTRY.

Signals UNKNOWN-SPEC when no function spec is registered for NAME.  A violation
signals SPEC-VIOLATION from inside the wrapper, so the caller sees the failure
at the call site rather than downstream.

Not implemented yet."
  (declare (ignore name registry))
  (error 'not-implemented :operator 'instrument-function))

(defun uninstrument-function (name)
  "Restore the original definition of NAME and forget its wrapper.

Returns true when a wrapper was removed, NIL when NAME was not instrumented.

Not implemented yet."
  (declare (ignore name))
  (error 'not-implemented :operator 'uninstrument-function))
```

- [ ] **Step 5: `tests.lisp` に import を追加**

```lisp
  (:import-from #:cl-spec/tests/instrument-test)
```

- [ ] **Step 6: テストが通ることを確認**

```bash
rove cl-spec.asd
ros run --eval '(ql:quickload :cl-spec/instrument :silent t)' --eval '(uiop:quit 0)'
```

Expected: 両方成功。

- [ ] **Step 7: lint とコミット**

```bash
mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp main.lisp tests.lisp
git add -A
git commit -m "feat: add runtime instrumentation system"
```

---

## Task 10: CI・lint・エージェント向けドキュメント・開発環境

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/lint.yml`
- Create: `prompts/repl-driven-development.md`, `prompts/common-lisp-expert.md`（cl-mcp からコピー）
- Create: `flake.nix`, `.envrc`
- Create: `CLAUDE.md`, `AGENTS.md`

**Interfaces:**
- Consumes: Task 1-9 で完成したツリー
- Produces: なし（インフラのみ）

- [ ] **Step 1: CI workflow を作成**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Roswell
        env:
          LISP: sbcl-bin/2.5.0
        run: |
          curl -L https://raw.githubusercontent.com/roswell/roswell/master/scripts/install-for-ci.sh | sh
          echo "$HOME/.roswell/bin" >> "$GITHUB_PATH"

      - name: Install dependencies
        run: |
          ros --version
          ros install rove

      - name: Assert the core system does not pull in check-it
        env:
          CL_SOURCE_REGISTRY: ${{ github.workspace }}//:
        run: |
          ros run --eval '(ql:quickload :cl-spec :silent t)' \
                  --eval '(uiop:quit (if (find-package "CHECK-IT") 1 0))'

      - name: Compile with warnings visible
        env:
          CL_SOURCE_REGISTRY: ${{ github.workspace }}//:
        run: |
          ros run --eval '(ql:quickload :cl-spec :silent t)' \
                  --eval '(asdf:compile-system :cl-spec :force :all)' \
                  --eval '(uiop:quit 0)'

      - name: Run tests
        env:
          CL_SOURCE_REGISTRY: ${{ github.workspace }}//:
        run: rove cl-spec.asd
```

- [ ] **Step 2: lint workflow を作成**

`.github/workflows/lint.yml`:

```yaml
name: Lint

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install SBCL
        run: |
          sudo apt-get update
          sudo apt-get install -y sbcl

      - name: Install mallet
        run: |
          git clone https://github.com/fukamachi/mallet.git
          cd mallet && make
          echo "$GITHUB_WORKSPACE/mallet" >> "$GITHUB_PATH"

      - name: Run mallet lint
        run: |
          OUTPUT=$(mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp \
                          tests/*.lisp tests/*/*.lisp 2>&1) || true
          echo "$OUTPUT"
          if ! echo "$OUTPUT" | grep -q "No problems found"; then
            echo "::error::Mallet found problems"
            exit 1
          fi
```

- [ ] **Step 3: prompts を cl-mcp からコピー**

```bash
mkdir -p prompts
cp ~/cl-mcp/prompts/repl-driven-development.md prompts/
cp ~/cl-mcp/prompts/common-lisp-expert.md prompts/
```

両ファイルは cl-mcp のツール利用手順そのものであり、cl-spec の開発でも同じツールを使うため内容の書き換えは不要。

- [ ] **Step 4: `flake.nix` と `.envrc` を作成**

`flake.nix`:

```nix
{
  description = "cl-spec - executable semantic IR and property framework for Common Lisp";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ];
      perSystem = { pkgs, ... }:
        let
          lisp = pkgs.sbcl;
        in {
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              rlwrap
              lisp
            ];

            shellHook = ''
              export CL_SOURCE_REGISTRY="$PWD//:$CL_SOURCE_REGISTRY"
            '';
          };
        };
    };
}
```

`.envrc`:

```
use flake
```

- [ ] **Step 5: `CLAUDE.md` を作成**

```markdown
# CLAUDE.md

## Agent Guidelines

@prompts/repl-driven-development.md
@prompts/common-lisp-expert.md

## Project Overview

cl-spec is an executable semantic IR and property framework for Common Lisp
programs, designed for both humans and LLM coding agents. It provides
machine-readable specifications, runtime contract checking, property-based
testing and structured introspection.

The specification lives in `docs/cl-spec-specification-v0.2-draft.md`; design
documents live in `docs/superpowers/specs/`.

**Current status: skeleton.** The condition hierarchy, the Semantic IR class
hierarchy and the registry are implemented. Normalization, validation,
explanation, generation, property execution, function checking and
instrumentation are stubs that signal `not-implemented`.

## Development With cl-mcp

This project is developed with cl-mcp's tools:

- **Lisp code operations** (search, read, edit, eval): use `clgrep-search`,
  `lisp-read-file`, `lisp-edit-form`, `repl-eval`, `run-tests` per
  `prompts/repl-driven-development.md`
- **Shell commands**: only for `git`, `mallet` and user-requested commands
- cl-spec itself does **not** depend on cl-mcp. Never add it to `:depends-on`

## Systems

| System | Contents | Extra dependency |
|---|---|---|
| `cl-spec` | Semantic IR, registry, validation, explain, introspection, DSL | none |
| `cl-spec/check-it` | generator compilation, property execution, shrinking | `check-it` |
| `cl-spec/instrument` | runtime function instrumentation | none |
| `cl-spec/tests` | test suite | `rove` |

The core system must never load `check-it`. The generator backend is injected
at load time into `cl-spec:*generator-backend*` by `cl-spec/check-it`.

## Package Naming

ASDF `package-inferred-system`: the package name equals the file path.

| File | Package |
|---|---|
| `src/ir.lisp` | `cl-spec/src/ir` |
| `src/backends/check-it.lisp` | `cl-spec/src/backends/check-it` |
| `tests/ir-test.lisp` | `cl-spec/tests/ir-test` |
| `main.lisp` | `cl-spec/main`, nickname `cl-spec` |

Adding a file requires no `.asd` change; dependencies are inferred from
`:import-from`. New test files **must** be added to `tests.lisp`, otherwise
they are never run.

Never reference the `cl-spec` nickname from inside `src/`: ASDF reads it as a
dependency on the root system and the graph becomes circular.

## Testing & Linting

```bash
rove cl-spec.asd                                  # full suite
mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
```

Single suite from the REPL:

```lisp
(rove:run :cl-spec/tests/registry-test)
```

Before opening a PR: `(asdf:compile-system :cl-spec :force :all)` to surface
warnings (`:force t` recompiles nothing here — this is a package-inferred
system, so the work lives in the per-file subsystems that only `:force :all`
reaches), then the full suite, then mallet.

## Code Style

- Google Common Lisp Style Guide
- 2-space indent, <=100 columns
- Blank line between top-level forms
- Lower-case lisp-case: `my-function`, `*special*`, `+constant+`, `something-p`
- Docstrings required on public functions, macros and classes — stubs included
- Each file starts with `;;;; <path>`, then `defpackage`, then `(in-package ...)`
- `(:use #:cl)` only; take everything else through `:import-from`
- Stubs signal `(error 'not-implemented :operator '<name>)` and declare their
  arguments ignored

## Implementation Order

Follow §70 of the specification. Steps 1-3 (Semantic IR, registry protocol,
hash-table registry) are done; the next step is 4, `defspec` normalization.
The first milestone is the vertical slice of §67:

```lisp
(defspec positive-integer (and integer (range 1 *)))
(validp 'positive-integer 10)
(explain-data 'positive-integer -1)
(sample 'positive-integer)
```

## Repository Structure

```
main.lisp         Public API re-export (no logic)
tests.lisp        Aggregate test system and rove runner
src/              Implementation, one responsibility per file
tests/            Rove suites, mirrored naming (*-test.lisp)
docs/             Specification and design documents
prompts/          System prompts for AI agents
```
```

- [ ] **Step 6: `AGENTS.md` を作成**

```markdown
# Repository Guidelines

@prompts/repl-driven-development.md
@prompts/common-lisp-expert.md

## Project Structure & Module Organization

`src/` holds the implementation, one responsibility per file, under ASDF
`package-inferred-system`: the package name equals the file path, so
`src/ir.lisp` defines `cl-spec/src/ir`. Dependencies are inferred from
`:import-from`, so adding a source file needs no `.asd` edit. `main.lisp`
re-exports the public API under the nickname `cl-spec` and contains no logic.
Tests mirror the sources in `tests/` as `*-test.lisp` and **must** be listed in
`tests.lisp` — an unlisted suite never runs.

Three systems sit beside the core: `cl-spec/check-it` (generation and
shrinking), `cl-spec/instrument` (runtime contract wrappers) and
`cl-spec/tests`. The core system must never load `check-it` or cl-mcp.

## Build, Test, and Development Commands

Develop through cl-mcp's REPL tools; run individual suites with `run-tests` so
tests execute inside the agent without shelling out. `rove cl-spec.asd` runs
the full suite in a clean process and is the fallback when the image is stale.

## Coding Style & Naming Conventions

Google Common Lisp Style Guide: 2-space indent, ≤100 columns, blank line
between top-level forms. Each `*.lisp` starts with `;;;; <path>`, then
`defpackage`, then `(in-package ...)`. Use `(:use #:cl)` and nothing else;
import every other symbol explicitly. Lower-case lisp-case, `-p` predicates,
`+constants+`, `*specials*`. Public functions, macros and classes require
docstrings — stubs included. Avoid runtime `eval` and dynamic interning.

## Testing Guidelines

Write Rove tests before implementations. Name suites after the unit under test.
Skeleton stubs are tested by asserting they signal `not-implemented` with the
right operator; replace those assertions with behavioural tests as each module
is implemented. The framework's own property tests (specification §68) arrive
once `run-property` works.

## Commit & Pull Request Guidelines

Commits are imperative and scoped (`module: action`). PRs describe the
capability change, list the commands run (`rove cl-spec.asd`, `mallet ...`,
`(asdf:compile-system :cl-spec :force :all)`) and link the specification
section they implement.

## Security & Configuration Notes

`cl-spec/instrument` rewrites fdefinitions; it is a separate system so that
production images can load cl-spec without that capability. Property bodies and
generators run arbitrary user code — treat a registry populated from untrusted
input as untrusted code (specification §45, §49).
```

- [ ] **Step 7: 全体を検証**

```bash
rove cl-spec.asd
mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp
ros run --eval '(ql:quickload :cl-spec :silent t)' \
        --eval '(uiop:quit (if (find-package "CHECK-IT") 1 0))'
echo "core-clean=$?"
ros run --eval '(ql:quickload :cl-spec/check-it :silent t)' --eval '(uiop:quit 0)'
ros run --eval '(ql:quickload :cl-spec/instrument :silent t)' --eval '(uiop:quit 0)'
```

Expected: 全テスト PASS、mallet が "No problems found"、`core-clean=0`、3 system すべてロード成功。

- [ ] **Step 8: コミット**

```bash
git add -A
git commit -m "chore: add CI, lint, agent guidelines and dev shell"
```

---

## 完了条件（設計文書 §11 の再掲）

1. `(asdf:load-system :cl-spec)` が警告なしで成功し、`check-it` をロードしない
2. `(asdf:load-system :cl-spec/check-it)` と `(asdf:load-system :cl-spec/instrument)` が成功する
3. `(asdf:compile-system :cl-spec :force :all)` が警告を出さない
4. `rove cl-spec.asd` が全テスト green
5. `mallet main.lisp tests.lisp src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp` が "No problems found"
6. 仕様書 §51 の MVP API 全 24 symbol が `cl-spec` パッケージから external として見える（`tests/main-test.lisp` が検証）
