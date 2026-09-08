# cl-spec スケルトン設計

- 日付: 2026-09-08
- 対象: `cl-spec` プロジェクトの初期骨格（ASDF system 構成・ファイル構成・パッケージ分割・スタブ規約）
- 上位文書: `docs/cl-spec-specification-v0.2-draft.md`（以下「仕様書」。節番号はこれを指す）

## 1. 目的とスコープ

`cl-spec` は仕様書 §71 の定義どおり *executable semantic IR and property framework for Common Lisp programs* である。本設計文書は、その実装を開始できる状態まで**リポジトリの骨格を作る**ことだけを対象とする。

### やること

- `cl-spec.asd` を `package-inferred-system` 化し、仕様書 §50 の 4 system 分割を実現する
- 仕様書 §70 の実装順に対応する src モジュールを 1 ファイル 1 責務で配置する
- 宣言的な骨格（condition 階層・Semantic IR の CLOS 階層・registry protocol と hash-table backend・公開 API の export 一覧）を実装する
- 変換ロジック（normalize / validator / explain / generator / property runner / function spec / instrument）をスタブとして配置する
- 各モジュールに対応する rove テストファイルを置き、スケルトン状態で CI が green になるようにする
- リポジトリ雑務（git 初期化・README 統一・CI/lint workflow・prompts・flake.nix・LICENCE）を整える

### やらないこと

- 仕様書 §53 の非 MVP 項目（static type checking, dependent types, SMT, state-machine PBT ほか）
- MCP adapter（仕様書 §27）。cl-mcp は**開発ツールとしてのみ前提**とし、`cl-spec` のコードは cl-mcp に依存しない
- Semantic IR の変換ロジックそのものの実装。これはスケルトン完成後に §70 の順で進める

## 2. 前提

| 項目 | 決定 |
|---|---|
| ASDF | `:class :package-inferred-system`（cl-mcp と同じ） |
| パッケージ命名 | ファイルパスと一致。`src/ir.lisp` → `cl-spec/src/ir` |
| cl-mcp | 開発ツールとしての前提のみ。`:depends-on` には入れない |
| PBT backend | `check-it`（Quicklisp 収録済み。`CHECK-IT` パッケージが `generator` / `generate` / `shrink` / `def-generator` / `*num-trials*` を export することを確認済み） |
| ユニットテスト | rove |
| ライセンス / 作者 | MIT / Satoshi Imai |
| バージョン | 0.1.0 |

仕様書 §50 は内部パッケージ名を `CL-SPEC/IR` のように例示しているが、`package-inferred-system` はパッケージ名とファイルパスの一致を要求するため、これを literal に採るとソースが全てリポジトリルート直下に並ぶ。分割単位（IR / REGISTRY / NORMALIZE / VALIDATOR / EXPLAIN / GENERATOR / PROPERTY / FUNCTION-SPEC / INTROSPECTION / CONDITIONS / CHECK-IT）は §50 に従い、名前空間は `cl-spec/src/<path>` とする。

## 3. ASDF system 構成

仕様書 §50 / §35 の要求は「production runtime に `check-it` を強制しない」ことである。これを 4 system で満たす。

```lisp
;;;; cl-spec.asd

(asdf:defsystem "cl-spec"
  :class :package-inferred-system
  :description "Executable semantic IR and property framework for Common Lisp programs"
  :author "Satoshi Imai"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("alexandria"
               "cl-spec/main")
  :in-order-to ((test-op (test-op "cl-spec/tests"))))

(asdf:defsystem "cl-spec/check-it"
  :description "check-it based generator and property execution backend for cl-spec"
  :depends-on ("cl-spec"
               "check-it"
               "cl-spec/src/backends/check-it"))

(asdf:defsystem "cl-spec/instrument"
  :description "Runtime function instrumentation for cl-spec function specs"
  :depends-on ("cl-spec"
               "cl-spec/src/instrument"))
```

- `cl-spec/main`（`main.lisp`）と `cl-spec/tests`（`tests.lisp`）はルートのアグリゲートファイルから推論させる。cl-mcp と同一のパターン。
- `cl-spec/check-it` と `cl-spec/instrument` は .asd で明示定義する。推論に任せるとルート直下に `check-it.lisp` / `instrument.lisp` を置くことになり、実装本体を置く `src/backends/check-it.lisp` / `src/instrument.lisp` と名前が二重化するため。明示定義した system 名は package-inferred-system の推論より優先される。
- 結果として `(asdf:load-system :cl-spec)` は `check-it` を一切ロードしない。

## 4. ファイル構成

```
cl-spec.asd
main.lisp                       ; cl-spec/main  (nickname: cl-spec) 公開 API 集約
tests.lisp                      ; cl-spec/tests rove ランナー
src/
  conditions.lisp               ; cl-spec/src/conditions
  ir.lisp                       ; cl-spec/src/ir
  normalize.lisp                ; cl-spec/src/normalize
  registry.lisp                 ; cl-spec/src/registry
  validator.lisp                ; cl-spec/src/validator
  explain.lisp                  ; cl-spec/src/explain
  generator.lisp                ; cl-spec/src/generator
  property.lisp                 ; cl-spec/src/property
  property-runner.lisp          ; cl-spec/src/property-runner
  function-spec.lisp            ; cl-spec/src/function-spec
  introspection.lisp            ; cl-spec/src/introspection
  dsl.lisp                      ; cl-spec/src/dsl
  instrument.lisp               ; cl-spec/src/instrument
  backends/
    check-it.lisp               ; cl-spec/src/backends/check-it
  utils/
    source-location.lisp        ; cl-spec/src/utils/source-location
tests/
  conditions-test.lisp          ; cl-spec/tests/conditions-test
  ir-test.lisp
  normalize-test.lisp
  registry-test.lisp
  validator-test.lisp
  explain-test.lisp
  generator-test.lisp
  property-test.lisp
  property-runner-test.lisp
  function-spec-test.lisp
  introspection-test.lisp
  dsl-test.lisp
  main-test.lisp
  utils/source-location-test.lisp
  backends/check-it-test.lisp
docs/
  cl-spec-specification-v0.2-draft.md
  superpowers/specs/2026-09-08-cl-spec-skeleton-design.md
prompts/
  repl-driven-development.md
  common-lisp-expert.md
.github/workflows/ci.yml
.github/workflows/lint.yml
CLAUDE.md  AGENTS.md  README.md  LICENCE  .gitignore  flake.nix  .envrc
```

`src/instrument.lisp` と `src/backends/check-it.lisp` は core system の依存グラフに入らない。`main.lisp` がこれらを import しないことでその不変条件を保つ。

## 5. モジュールの責務と依存関係

package-inferred-system では `defpackage` の `:use` / `:import-from` から依存が推論されるため、依存関係はそのままファイル間の依存グラフになる。循環は存在しない。

| モジュール | 責務 | 依存 | 仕様書 |
|---|---|---|---|
| `src/conditions` | `cl-spec-error` を根とする condition 階層、`spec-violation`、`not-implemented` | なし | §21, §47 |
| `src/utils/source-location` | 定義フォームの source location 取得 | なし | §31, §69-10 |
| `src/ir` | Semantic IR の CLOS 階層と reader、`spec-kind` 等の generic function | conditions, utils/source-location | §7 |
| `src/normalize` | DSL フォーム → Semantic IR の正規化 | ir, conditions | §9, §37 |
| `src/registry` | registry protocol の generic function 群と `hash-table-registry`、`*registry*` | ir, conditions | §8 |
| `src/validator` | `compile-validator`、`validp`、`validate` | ir, conditions | §9.1, §20 |
| `src/explain` | `compile-explainer`、`explain-data`（構造化）、`explain`（人間向け projection） | ir, validator, conditions | §22 |
| `src/generator` | generator backend protocol、`*generator-backend*`、`generator-for`、`sample` | ir, conditions | §10, §12 |
| `src/property` | Property IR、registry への登録と逆引き | ir, registry, conditions, utils/source-location | §4, §39 |
| `src/property-runner` | `run-property` / `run-properties` / `replay-property`、`property-result`、seed・shrink 統合 | property, generator, registry, conditions | §13-16 |
| `src/function-spec` | Function Spec IR、`check-function` | ir, registry, generator, conditions | §17, §18, §19 |
| `src/introspection` | `describe-spec` / `describe-property` / `spec-data` / `property-data` | ir, registry, property, function-spec, explain | §38 |
| `src/dsl` | `defspec` / `defspec-function` / `defproperty` / `defgenerator` | normalize, registry, ir, property, function-spec, generator, utils/source-location | §37 |
| `src/instrument` | `instrument-function` / `uninstrument-function` | function-spec, validator, registry, conditions | §20 |
| `src/backends/check-it` | check-it への generator compile と property 実行の委譲 | generator, ir, property, conditions, `check-it` | §12, §16 |

### backend 差し替えの仕組み

`src/property-runner` は実行時に generator backend を必要とするが、`check-it` に依存してはならない。これを `src/generator` が持つ動的変数で解決する。

```lisp
;; src/generator.lisp
(defvar *generator-backend* nil
  "Current generator backend. Set by CL-SPEC/CHECK-IT at load time.")

(defgeneric compile-generator (backend spec &key context options))
(defgeneric generate-value (backend compiled-generator &key seed))
(defgeneric run-generated-test (backend property &key options))
```

`cl-spec/check-it` をロードすると `src/backends/check-it.lisp` が `check-it-backend` インスタンスを `*generator-backend*` に設定する。backend 未設定のまま `run-property` を呼んだ場合は `no-generator-backend` を signal し、`cl-spec/check-it` をロードするよう報告する。これにより仕様書 §12 の「上位 DSL および Semantic IR を check-it API へ直接依存させない」を構造的に保証する。

## 6. スタブの粒度

全ファイルを一律 `error` にはしない。**宣言的な骨格は実装し、変換ロジックはスタブにする。**

### 実装するもの

- `src/conditions.lisp` の condition 階層一式（`define-condition` は宣言であり、以降すべてのモジュールが参照する）
- `src/ir.lisp` の SPEC クラス階層（仕様書 §7）:
  `spec` を基底に `reference-spec` / `predicate-spec` / `type-spec` / `and-spec` / `or-spec` / `not-spec` / `member-spec` / `range-spec` / `collection-spec`（→ `list-of-spec` / `vector-of-spec` / `tuple-spec`）/ `nullable-spec` / `instance-of-spec` / `custom-spec`。
  基底スロットは `name` / `description` / `source-form` / `source-location` / `metadata`。
- `src/registry.lisp` の protocol generic function 群と `hash-table-registry` の実装、および `*registry*`。索引は仕様書 §8 のとおり spec / function-spec / property / target symbol → property list / tag → property list。
- 各パッケージの `:export` 一覧（仕様書 §51 の MVP API 全 symbol を含む）
- `main.lisp` の公開 API 集約

理由: IR クラス階層と registry は「ロジック」ではなく「型」であり、これが確定しないと他のどのモジュールも書き始められない。仕様書 §70 の実装順 1〜3 に相当する。

### スタブにするもの

上記以外の関数・メソッド・マクロ。本体は次の形とする。

```lisp
;; src/conditions.lisp
(define-condition not-implemented (cl-spec-error)
  ((operator :initarg :operator :reader not-implemented-operator))
  (:report (lambda (condition stream)
             (format stream "~S is not implemented yet."
                     (not-implemented-operator condition)))))
```

```lisp
;; 使用例（src/normalize.lisp）
(defun normalize-spec-form (form &key name source-location)
  "Normalize a DSL spec FORM into a Semantic IR object. Not implemented yet."
  (declare (ignore form name source-location))
  (error 'not-implemented :operator 'normalize-spec-form))
```

スタブであっても docstring と引数リストは確定させる。これが実装時の契約になる。

`src/dsl.lisp` のマクロは、マクロ展開自体は成功させ、展開結果の実行時に `not-implemented` を signal する形にする（`defspec` を書いたファイルがコンパイルエラーにならないようにするため）。

## 7. 公開 API（`main.lisp`）

仕様書 §51 の MVP API をそのまま export 対象とする。

```
Spec         defspec find-spec list-specs validp validate explain explain-data
Generators   defgenerator generator-for sample
Functions    defspec-function find-function-spec check-function
Properties   defproperty find-property list-properties properties-for
             run-property run-properties replay-property
Introspection describe-spec describe-property spec-data property-data
```

加えて骨格上必要な以下を export する。

```
Registry     *registry* make-hash-table-registry
             registry-find-spec registry-register-spec registry-list-specs
             registry-find-function-spec registry-register-function-spec
             registry-find-property registry-register-property
             registry-properties-for registry-properties-with-tag
Conditions   cl-spec-error spec-violation not-implemented no-generator-backend
IR           spec spec-name spec-description spec-source-form
             spec-source-location spec-metadata spec-kind spec-children
Generator    *generator-backend* compile-generator generate-value run-generated-test
```

パッケージ `cl-spec/main` に nickname `cl-spec` を付ける（cl-mcp の `cl-mcp/main` → `cl-mcp` と同じ）。内部モジュールからは nickname を参照しない。参照すると ASDF が root system `cl-spec` への依存と解釈し、循環するため。

仕様書の表記揺れ: §51 は `sample`、§67 の vertical slice は `sample-spec` と書かれている。API 章である §51 を正とし `sample` を採用する。仕様書側は次回改訂時に §67 を合わせる。

## 8. テスト方針

- `tests/<module>-test.lisp` → パッケージ `cl-spec/tests/<module>-test`。cl-mcp と同じミラー命名。
- `tests.lisp` が全テストパッケージを `:import-from` し、`asdf:perform :after ((op test-op) ...)` で `rove:run` する（cl-mcp の `tests.lisp` と同一機構）。
- スケルトン段階の各テストは「そのモジュールの公開シンボルが存在し、関数は `fboundp`、クラスは `find-class` で引ける」ことを検証する**スモークテスト**とする。スタブでも green になり、CI が初日から意味を持つ。
- 実装済みの `src/ir` と `src/registry` については実テストを書く。具体的には、hash-table-registry への spec 登録と検索、target symbol からの property 逆引き、tag 索引、未登録シンボルの検索が `nil` を返すこと。
- 仕様書 §68 が求める「framework 自身への property testing」は、`run-property` が動くようになってから `tests/` に追加する。スケルトン段階では対象外。

## 9. リポジトリ雑務

| 項目 | 内容 |
|---|---|
| git | `git init` 済み。スケルトンを初回コミットする |
| README | `README.org` / `README.markdown`（cl-project 生成物）を削除し `README.md` に統一 |
| LICENCE | MIT、著作権者 Satoshi Imai |
| `.gitignore` | cl-mcp のものをベースに fasl 各種・`*~`・`.#*`・`.serena/`・`.cache/`・`.direnv/`・`.mcp.json` を無視。`docs/` は無視しない |
| `.github/workflows/ci.yml` | Roswell + SBCL で `rove cl-spec.asd`。cl-spec は GitHub 未公開のため、cl-mcp の `ros install <org>/<repo>` ではなく `CL_SOURCE_REGISTRY` にチェックアウトを通す |
| `.github/workflows/lint.yml` | mallet で `src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp` を lint。cl-mcp と同じく "No problems found" を要求 |
| `prompts/` | cl-mcp の `repl-driven-development.md` / `common-lisp-expert.md` を cl-spec 向けに調整して移植 |
| `CLAUDE.md` / `AGENTS.md` | cl-mcp 流。cl-mcp のツール（`repl-eval` / `run-tests` / `clgrep-search` 等）で開発する前提、package-inferred-system の命名規約、Google Common Lisp Style Guide、mallet lint を記載 |
| `flake.nix` / `.envrc` | cl-mcp から移植。`lisp = pkgs.sbcl`、`CL_SOURCE_REGISTRY` を通す shellHook |
| 既存ファイル | `src/main.lisp` と `tests/main.lisp`（cl-project 生成物）は本構成に置き換えるため削除 |

## 10. コードスタイル

cl-mcp の `CLAUDE.md` / `AGENTS.md` に合わせる。

- Google Common Lisp Style Guide
- インデント 2 スペース、100 桁以内
- トップレベルフォーム間に空行
- 小文字 lisp-case。`*special*` / `+constant+` / `something-p`
- 各ファイルは `;;;; <path>` コメント → `defpackage` → `(in-package ...)` の順
- `defpackage` は `(:use #:cl)` を先頭に置き、他パッケージは `:import-from` で個別に取り込む
- 公開関数・クラスには docstring を付ける。スタブも例外としない

## 11. 完了条件

1. `(asdf:load-system :cl-spec)` が警告なしで成功し、`check-it` をロードしない
2. `(asdf:load-system :cl-spec/check-it)` と `(asdf:load-system :cl-spec/instrument)` が成功する
3. `(asdf:compile-system :cl-spec :force :all)` が警告を出さない
4. `rove cl-spec.asd` が全テスト green
5. `mallet src/*.lisp src/*/*.lisp tests/*.lisp tests/*/*.lisp` が "No problems found"
6. 仕様書 §51 の MVP API 全 symbol が `cl-spec` パッケージから external として見える

## 12. スケルトン完成後の進め方

仕様書 §70 の実装順に従う。スケルトンは 1〜3（Semantic IR / Registry protocol / Hash-table registry）を実装済みの状態で完成するため、次のステップは 4（`defspec` normalization）から始まる。仕様書 §67 の vertical slice、すなわち

```lisp
(defspec positive-integer (and integer (range 1 *)))
(validp 'positive-integer 10)
(explain-data 'positive-integer -1)
(sample 'positive-integer)
```

が通ることを最初のマイルストーンとする。
