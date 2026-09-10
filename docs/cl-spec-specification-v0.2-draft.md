# cl-spec 仕様書

**Common Lisp LLM-Oriented Specification & Property Testing Framework**

- 文書バージョン: 0.2-draft
- ステータス: MVP vertical slice実装済み・仕様詳細化中
- LLM向け整理日: 2026-09-09
- 実装状況の根拠: `AGENTS.md`および対応ソースの静的確認。実行環境の対応は別途確認する。
- 本文書はプロジェクトの継続的な設計成果物としてメンテナンスする。

## 改訂履歴

### 0.2-draft

2026-09-09の文書整理：

- §0に読み方、実装状況、実装済みAPIの入口、LLMの判断規則を追加。
- 既存の§1〜§71は参照番号を維持し、機能ごとの位置付けを明示。
- 概念例と現在利用可能なAPIを区別し、開発ループとreplayの説明を補正。
- §72にLLM利用の受け入れ要件、§73に未決定事項と検証方法を集約。
- 本改訂は文書の更新であり、新しいAPIや実行上の保証を実装するものではない。

- Schemata / Malliの内部architecture調査を反映。
- DSL中心からSemantic IR中心のarchitectureへ明確化。
- validator / explainer / generatorをIRから生成するcompiler modelを採用。
- registryをglobal hash-table固定ではなくprotocol化。
- structured explainをprimary representationへ変更。
- Schemataはdependency/forkせず独立実装する方針を明記。
- check-itはbackendとして隔離し、internal APIへの依存を避ける。
- vertical sliceおよび実装順序を更新。

---

# 0. LLM向けの読み方と現在の利用範囲

## 0.1 文書の規約

本書は設計仕様と実装状況を併記する。次のラベルを独立に読む。

| ラベル | 意味 |
|---|---|
| **設計方針** | 採用する責務分離・設計原則。APIの実装済みを意味しない |
| **実装済み** | 整理日時点のソースに実装がある。全環境・全入力での動作保証ではない |
| **一部実装** | 基盤または一部APIのみ存在する。利用範囲は§0.2と当該節で確認する |
| **未実装** | MVPの予定機能。公開symbolがあってもstubの場合がある |
| **将来構想** | MVPの利用可能機能に含めない |
| **要件（現状は未保証）** | 実装・運用が満たすべき条件。現在のrunnerが保証するとは解釈しない |
| **未決定** | 構文・挙動・責務等の設計判断が残る。LLMが推測してAPIを作らない |

本文の「概念」「想定」「候補」「例えば」で示すコード・JSON・クラス定義は、
そのまま実行可能なAPI仕様ではない。節全体が実装済みでも、概念例の全フィールドを
現在の返却値に期待してはならない。正確な呼び出しは対象revisionの公開APIと照合する。

本文の要件と実装が異なる場合、実装の現状と仕様上の要求を別々に報告する。
一方を根拠にもう一方を無断で変更しない。新しい要件の受け入れ条件は§72、
未決定の詳細は§73に記録する。

既存の§番号は、ソース・テスト・他文書からの参照を維持するため変更しない。

## 0.2 実装状況表

この表は2026-09-10時点のスナップショットであり、実行時のcapability APIではない。

| 機能 | 状況 | 現在の利用範囲・制限 |
|---|---|---|
| Semantic IR・normalization・hash-table registry | 実装済み | §7〜9、§37。追加registry backendは将来構想 |
| validation・structured explain | 実装済み | `validp`、`validate`、`explain-data`、`explain` |
| Spec・Propertyのデータ取得 | 実装済み | `spec-data`、`property-data`、`function-spec-data` |
| symbolに関連する登録名の取得 | 実装済み | `semantic-data`。本文・signature・methodsの一括取得ではない |
| check-it generator backend | 実装済み | `generator-for`、`sample`。生成可能範囲はvalidationの対応範囲より狭い |
| Property定義・実行 | 実装済み | `defproperty`、`run-property`、`run-properties` |
| seed・replay・shrinking | 実装済み | 同一実行条件が前提。整数seedの実装対応は現在SBCLのみ |
| Function Spec | 実装済み（最小範囲） | `defspec-function`、`check-function`、`function-spec-data`。必須引数と単一値のみ。§17〜19、§73.1 D1 |
| Custom generator DSL | 未実装 | `defgenerator`はstub。`defgenerator-for`は構想上の名前 |
| 人間向けdescribeプリンター | 未実装 | `describe-spec`、`describe-property`はstub |
| Instrumentation・cl-mcp adapter | 未実装 | 公開名や想定tool名の存在を利用可能の根拠にしない |
| timeout・状態隔離・trust強制 | 要件（現状は未保証） | §40、§45、§48、§60、§72。メタデータだけで強制されない |
| state-machine PBT・mutation・Coalton | 将来構想 | §41、§43、§53〜55 |

現在のstubは `not-implemented` を通知する。LLMはこれを対象関数の契約違反や、
Propertyの反例として扱ってはならない。

## 0.3 目的別の参照先

| 作業 | 読む節 |
|---|---|
| 既存関数を変更する | §0.4、§27〜31、§72 |
| SpecやPropertyを書く | §5〜6、§9〜19、§33、§45〜46、§51〜52 |
| 失敗を調べる | §14〜16、§21〜22、§47〜48、§57 |
| frameworkを実装する | §7〜12、§37〜39、§50、§67〜70、§73 |
| MCPで公開する | §26〜28、§38、§49、§60、§72.6 |
| 将来の機能を検討する | §23〜24、§36、§41〜44、§53〜55、§58 |

## 0.4 LLMによる変更手順

1. 対象revision、Lisp実装、ロード済みsystem、対象packageとsymbolを確認する。
2. Spec・Propertyを定義するsystemをロードする。未ロードと未登録を混同しない。
3. `semantic-data`で登録名を取得し、`spec-data`・`property-data`で必要な本文を読む。
   ソース・signature・呼び出し関係はcl-mcp側から取得する。
4. 関連Propertyと通常テストを選び、変更前の結果を記録する。
   `:about`による直接関連だけでは変更影響を網羅しない。
5. 実装を変更し、ファイルへ保存し、再ロード・コンパイルする。
   REPLだけの定義で完了としない。
6. 通常テスト、関連Property、保存済み反例の再検査を行う。
   完了前にはプロジェクトが要求する範囲のテストを実行する。
7. 失敗、実行エラー、未実行、検証不足を区別し、修正または不足の報告へ進む。
8. 変更内容、検査した契約、実行件数、結果、未検証範囲を報告する。
   Propertyの成功は、生成・検査した範囲についての証拠である。

元の要求が契約変更を含まない限り、失敗を解消するためにSpecを弱めたり、
Propertyを削除したり、入力domainや試行予算を縮小したりしない。
契約変更が必要な場合は、その理由と差分を実装変更と区別して示す。

## 0.5 実装済みAPIの最小利用例

次は既に対象プロジェクトとそのSpec/Property定義をロード済みのREPLで使う呼び出し例。
`target`には既存の対象symbolを渡す。登録内容の作成例は§67を参照する。

```lisp
(asdf:load-system "cl-spec/check-it")

(defun inspect-and-check-target (target)
  "Return registered metadata, property definitions and check results for TARGET."
  (let* ((routing (cl-spec:semantic-data target))
         (names (getf routing :properties-about)))
    (values routing
            (mapcar #'cl-spec:property-data names)
            (cl-spec:run-properties names :profile :normal))))
```

`names`が空なら結果も空であり、「検査成功」ではなく「選択されたPropertyがない」。
この例はAPIの接続を示すだけで、§0.4の変更手順全体を自動化しない。

既存Propertyの個別実行と再生成：

```lisp
;; PROPERTY-NAMEは登録済みPropertyのsymbol。
(let ((result (cl-spec:run-property property-name :profile :normal :seed 18372918)))
  (values (cl-spec:property-result-status result)
          (cl-spec:property-result-trials result)
          (cl-spec:replay-property property-name result)))
```

`run-property`の現在のキーワードは `:profile`、`:seed`、`:options`、`:registry`。
`:timeout`を直接渡すAPIは未実装。replayの制限は§15を参照する。

関数の契約の取得と検査：

```lisp
;; TARGETは(defspec-function target ...)が登録済みのsymbol。
(cl-spec:function-spec-data target)   ; どの入力を受け、どの出力を返すべきか

(let ((result (cl-spec:check-function target :trials 200)))
  (values (cl-spec:property-result-status result)          ; :passed/:failed/:skipped/:error
          (cl-spec:function-check-result-rejected result)   ; :preが棄却した生成入力の件数
          (cl-spec:function-check-result-failure-reason result)
          (cl-spec:property-result-shrunk-counterexample result)))
```

`:skipped`は「`:pre`が全入力を棄却し、関数を一度も呼んでいない」であって
成功ではない。実際に検査された件数は「試行数 − 棄却数」で、`:passed`でも
これが0なら何も検査していない。詳細は§17〜19。

---

## 1. 概要

### 1.1 目的

本プロジェクトは、Common Lispの既存・新規コードベースに対して、

- 機械可読な仕様記述
- 実行時契約検証
- Property-Based Testing
- テストデータ自動生成
- 反例のshrinking
- LLM向けsemantic metadata
- MCP等を通じた外部inspection

を統合的に提供するフレームワークを構築する。

主な利用者として人間だけでなくLLM coding agentを明示的に想定する。

中心となる思想は以下である。

> 実装コードとは別に、そのコードが満たすべき性質を機械可読かつ実行可能な仕様として記述し、LLMが仕様を理解・検証・反例取得に利用できるようにする。

静的型システムをCommon Lispに導入すること自体は目的としない。

代わりに、

- Common Lisp型宣言
- predicate
- CLOS
- function contracts
- property tests
- runtime introspection
- compiler diagnostics

を組み合わせ、「誤ったプログラムを高速に反証できる環境」を構築する。

Property-Based Testingの低レベルバックエンドには `check-it` を利用する。

`check-it` はgenerator DSL、ユーザー定義generator、mapped/chained generator、shrinking等を提供するため、本フレームワークではこれらを再実装せず利用する。`check-it` 自体は汎用テストフレームワークではなく、既存テスト環境にrandomized testingを埋め込む用途を想定している。

---

# 2. プロジェクトの仮称

以下、本設計書では仮に

`cl-spec`

と呼ぶ。

実際の名称は別途決定する。

名前の候補：

- cl-spec
- cl-contract
- cl-properties
- lisp-spec
- semantic-spec
- cl-semantic-contracts

ただし `cl-spec` は既存ライブラリとの名前衝突を事前調査する必要がある。

---

# 3. 設計目標

## 3.1 第一目標：仕様をコードとして記述できる

例えば、

```lisp
(defspec positive-money
  (and integer
       (satisfies plusp)))

```

と記述することで、

`positive-money` が

- integerであり
- 正数である

という意味を機械的に取得できるようにする。

---

## 3.2 関数仕様を独立して記述できる

既存関数を再定義せず、

```lisp
(defspec-function transfer
  (:args
   (from account)
   (to account)
   (amount positive-money))
  (:returns transaction))

```

のように仕様を追加できる。

これは既存Common Lispプロジェクトへの段階的導入を可能にするため重要である。

仕様記述のために `defun` や `defmethod` を専用macroへ置き換えることを必須としない。

---

# 4. Propertyの記述

独立した性質を、

```lisp
(defproperty transfer-preserves-total-balance
    ((state state-spec)
     (from account-spec)
     (to account-spec)
     (amount positive-money))
  (:about transfer)
  (:kind :invariant)

  (= (total-balance state)
     (total-balance
      (transfer state from to amount))))

```

のように記述する。

`defproperty` は単なるテスト定義ではない。

以下の情報を登録する。

- property名
- 対象symbol
- 入力spec
- generator
- predicate本体
- property分類
- documentation
- source location
- tags
- execution configuration

---

# 5. 仕様とPropertyの位置付け

本フレームワークでは次を区別する。

## Spec

値・関数・構造についての局所的契約。

例：

```text
amount is positive
return value is transaction
account state is verified

```

## Property

複数の値、状態、実行前後の関係として表現される意味的性質。

例：

```text
decode(encode(x)) = x

```

```text
normalize(normalize(x)) = normalize(x)

```

```text
total balance before = total balance after

```

```text
failed operation does not modify state

```

---

# 6. Property分類

LLMがpropertyの意味を認識しやすいよう、propertyを分類する。

初期バージョンでは以下を標準化する。

```lisp
:invariant
:roundtrip
:idempotence
:monotonicity
:commutativity
:associativity
:identity
:state-transition
:failure-semantics
:equivalence
:serialization
:ordering
:resource
:custom

```

例：

```lisp
(defproperty normalize-idempotent
    ((x input-spec))
  (:about normalize)
  (:kind :idempotence)

  (equal
   (normalize x)
   (normalize (normalize x))))

```

分類は実行動作に必ずしも影響しない。

主用途は、

- documentation
- introspection
- LLM semantic hints
- filtering

である。

---

# 7. Semantic IR / Specデータモデル

> **位置付け:** 一部実装。Semantic IRは存在する。クラス階層は概念図であり、全候補の実装を意味しない。

`cl-spec` の中核はDSLではなく、正規化された **Semantic IR (Intermediate Representation)** である。

`defspec`、`defspec-function`、`defproperty` 等のmacroはsyntax sugarであり、最終的にはSemantic IR objectを生成・登録する。

Specは内部的にCLOS objectとして表現する。概念例：

```lisp
(defclass spec ()
  ((name
    :initarg :name
    :reader spec-name)

   (description
    :initarg :description
    :reader spec-description)

   (source-form
    :initarg :source-form
    :reader spec-source-form)

   (source-location
    :initarg :source-location
    :reader spec-source-location)

   (metadata
    :initarg :metadata
    :reader spec-metadata)))
```

派生クラスの初期案：

```text
SPEC
├── REFERENCE-SPEC
├── PREDICATE-SPEC
├── TYPE-SPEC
├── AND-SPEC
├── OR-SPEC
├── NOT-SPEC
├── MEMBER-SPEC
├── RANGE-SPEC
├── COLLECTION-SPEC
│   ├── LIST-OF-SPEC
│   ├── VECTOR-OF-SPEC
│   └── TUPLE-SPEC
├── NULLABLE-SPEC
├── INSTANCE-OF-SPEC
└── CUSTOM-SPEC
```

重要な設計原則：

- Semantic IRはvalidation処理そのものではない。
- Semantic IRはvalidator、explainer、generator等へ変換される入力表現である。
- 元のS-expressionを可能な限り保持する。
- machine-readableな正規化表現を提供する。
- DSLを変更してもIRおよびpublic introspection APIを安定させる。

概念的には、

```text
DSL
 ↓
Normalization
 ↓
Semantic IR
 ├─→ Validator Compiler
 ├─→ Explainer Compiler
 ├─→ Generator Backend
 ├─→ Documentation / Serialization
 └─→ LLM Introspection
```

とする。

これはMalliに見られる「schemaを共通IRとしてvalidator・explainer・generator等へ変換する」設計を参考にする。一方、Common LispではCLOS、package-qualified symbol、condition system、MOP等を活かした独自のSemantic IRを定義する。

# 8. Registry architecture

> **位置付け:** 一部実装。protocolとhash-table backendは実装済み。他backendは将来構想。

registryを単一のglobal hash-tableとして固定しない。

初期実装ではhash-table backendを提供するが、public APIはprotocolとして定義する。

概念API：

```lisp
(registry-find-spec registry 'positive-money)
(registry-register-spec registry 'positive-money spec)
(registry-list-specs registry)

(registry-find-property registry 'transfer-preserves-total-balance)
(registry-properties-for registry 'transfer)
```

標準ではdynamic variableを通じてdefault registryを利用する。

```lisp
(find-spec 'positive-money)
(list-specs)
(properties-for 'transfer)
```

初期backend候補：

```text
HASH-TABLE-REGISTRY
COMPOSITE-REGISTRY
READ-ONLY-REGISTRY
```

将来的には、

```text
DYNAMIC-REGISTRY
PERSISTENT-REGISTRY
PROJECT-REGISTRY
```

等を追加可能にする。

registryは少なくとも以下のindexを提供する。

```text
package-qualified symbol → spec
package-qualified symbol → function spec
property name → property definition
target symbol → property list
tag → property list
```

Package-qualified symbolをcanonical identifierとして使用する。

例えば：

```text
MY.APP::TRANSFER
MY.DOMAIN::POSITIVE-MONEY
```

LLM/MCP APIではpackage情報を必ず保持する。

registryをprotocol化する主な理由は以下である。

- test isolation
- ASDF reload時の差し替え
- 一時的なexperimental spec/property
- LLMが生成した候補spec/propertyの隔離
- trusted / experimental registryのcomposition

Malliのregistry abstractionを設計上の参考とするが、実装はCommon Lisp向けに独立して行う。

# 9. Spec composition

Specは組み合わせ可能でなければならない。

例：

```lisp
(defspec positive-integer
  (and integer
       (satisfies plusp)))

```

```lisp
(defspec optional-user
  (or null user))

```

```lisp
(defspec percentage
  (and real
       (range 0 100)))

```

初期primitive候補：

```text
type
satisfies
and
or
not
member
range
list-of
vector-of
cons-of
tuple
nullable
instance-of

```

`cons-of` はMVPでは実装しない。§52のMVP対応リストにも含まれておらず、§7のIRクラス階層にも
対応ノードが無い。post-MVPとして扱い、`(tuple ...)` または `(list-of ...)` で代替する。

可能な限りCommon Lispの型specifierに近い記法を採用する。

ただしCommon Lisp type languageと完全互換にすることは目標としない。

`check-it` もgenerator type specについてCommon Lisp type specと似た構文を採用しているが、同一ではない。

---

# 9.1 Validator / Explainer compiler

> **位置付け:** 一部実装。compiler APIは存在する。最適化・cacheの全要件を保証するものではない。

Semantic IRを実行時に毎回再帰interpretすることだけに依存せず、必要に応じて実行用functionへcompileする。

概念API：

```lisp
(compile-validator spec &key context)
(compile-explainer spec &key context)
```

例えば、

```lisp
(defspec positive-odd-integer
  (and integer
       (range 1 100)
       (satisfies oddp)))
```

から、概念的に、

```lisp
(lambda (value)
  (and (integerp value)
       (<= 1 value 100)
       (oddp value)))
```

に相当するvalidatorを生成できる。

compile方式の目的は以下である。

- validation hot pathのdispatch overhead低減
- spec objectとexecution engineの責務分離
- backend-specific optimization
- cache可能な実行artifact
- 同一IRから複数の実行・表示形式を生成可能にする

MVPでは単純なrecursive interpretationから開始してもよいが、public architectureはcompiler abstractionを前提とする。

---

# 10. Generator生成

> **位置付け:** 一部実装。自動導出はbackendが対応するSpecに限る。

Specから可能な場合はgeneratorを自動導出する。

例：

```lisp
(defspec small-positive-integer
  (range integer 1 100))

```

↓

概念的に：

```lisp
(check-it:generator
  (integer 1 100))

```

## 自動生成可能なspec

初期段階では以下を対象とする。

```text
integer
integer range
character
string
member
or
list
tuple
simple structures

```

---

# 11. Custom generator

> **位置付け:** 未実装。以下の定義構文・関連付けは概念例。

Domain objectについては自動生成できないケースが多い。

例えば、

```lisp
(defclass account ()
  ((balance ...)
   (currency ...)
   (state ...)))

```

だけでは、

```text
balance >= 0
supported currency only
verified account requires KYC

```

などは分からない。

そのため、

```lisp
(defgenerator account-generator
  ...)

```

を提供する。

Specへの関連付け：

```lisp
(defspec account-spec
  (instance-of account)
  (:generator account-generator))

```

または、

```lisp
(defgenerator-for account-spec
  ...)

```

とする。

---

# 12. Generator architecture

> **位置付け:** 一部実装。check-it backendとprotocolは存在する。他backendは将来構想。

Generator backendをSemantic IRから分離する。

Spec自身が`check-it` generatorを直接保持・生成することを必須としない。代わりに、backend-specificなgeneratorへcompileするprotocolを持つ。

概念protocol：

```lisp
(compile-generator backend spec &key context options)
(generate-value backend compiled-generator &key seed)
(run-generated-test backend property &key options)
```

初期backend：

```text
CHECK-IT-BACKEND
```

将来的には、

```text
CUSTOM-EXHAUSTIVE-BACKEND
FUZZER-BACKEND
SMT-BACKEND
```

などを追加可能にする。

上位DSLおよびSemantic IRを `check-it` APIへ直接依存させない。特に `check-it` のinternal symbolを拡張する設計は避ける。

`check-it` は初期の実行backendとして採用し、random generationとshrinkingを委譲する。

Schemataにもschemaから`check-it` generatorを生成する先行例があるが、generator層は`check-it`内部APIへの密結合を含み、cl-specのbackend abstractionとは整合しない。そのためSchemataをgenerator基盤として直接利用しない。

# 13. Property execution

基本フロー：

```text
PROPERTY
   ↓
argument specs
   ↓
generator resolution
   ↓
check-it generator creation
   ↓
generated arguments
   ↓
property body
   ↓
PASS / FAIL / ERROR
   ↓
shrinking
   ↓
minimal counterexample

```

Property本体が、

```text
NIL

```

を返す場合をfailureとする。

想定外のエラーは成功に含めず、真偽値NILによる失敗と区別して記録する。
warning・通常のsignal・期待するconditionまで一律に失敗とする意味ではない。
Function Specの`:signals`、condition分類、restartを含む詳細規則は§73のD1・D4で確定する。

---

# 14. Property Result

> **位置付け:** 一部実装。構造化resultは存在する。概念クラス・JSONは現行schemaではない。

Property実行結果は単なるbooleanではなく構造化する。

```lisp
(defclass property-result ()
  ((status ...)
   (property ...)
   (trials ...)
   (seed ...)
   (profile ...)
   (counterexample ...)
   (shrunk-counterexample ...)
   (condition ...)
   (duration ...)
   (backend ...)))

```

`profile`は実際に選択したprofile名（例：`:normal`）を記録し、`trials`は実行済み試行数を記録する。
profile名だけでは数値の予算は固定されない。Propertyの`:trials`定義とbackend defaultも必要になる。
現在のresultからreplayするとseedとprofileは引き継がれるが、元の予算・options・定義・環境を
完全には復元しない。これらの保存要件は§72.3に定める。

現在の`property-result`はstatus、property、trials、seed、profile、counterexample、
shrunk-counterexample、condition、elapsedを公開readerで提供する。
statusの定義上の候補は`:passed`、`:failed`、`:error`、`:skipped`、`:pending`。
すべての候補を現在のbackendが返すとは限らない。§47のfailure categoryとは別の軸である。

概念的JSON：

```json
{
  "property": "MY.APP::TRANSFER-PRESERVES-TOTAL",
  "status": "failed",
  "kind": "invariant",
  "trials": 347,
  "seed": 18372918,
  "counterexample": {
    "balance": 1,
    "amount": 1
  },
  "minimal_counterexample": {
    "balance": 0,
    "amount": 1
  }
}

```

これはLLM利用に極めて重要である。

---

# 15. Reproducibility

すべてのtest runはseedを記録する。

API：

```lisp
(run-property
 'foo
 :seed 18372918)

```

または、

```lisp
(replay-property
 'foo
 result)

```

を提供する。

LLMが失敗を再現可能であることを必須条件とする。ただしseedだけで任意の環境・状態を再現する
とは保証しない。現在の整数seed対応はSBCLに限定され、未対応実装では`unsupported-seed`となる。

現在の`replay-property`は生成から再実行するAPIである。resultを渡すとseedとprofileを再利用し、
明示したprofileがあればそちらを優先する。optionsは自動保存されないため呼び出し側が再指定する。
同じコード、Spec/Property、generator、profile定義、backend、Lisp実装、初期状態を前提とする。

保存した反例を修正後の実装へ直接入力する「反例の再検査」は、生成列のreplayとは別の操作である。
永続化形式と専用APIは未決定。現時点では具体例テストとして保存して再検査できる。
詳細な再現情報と不一致時の扱いは§72.3を参照する。

---

# 16. Shrinking

shrinkingは `check-it` を利用する。

`check-it` は整数・list・composite generator等について反例の縮小を行う。mapped/chained generatorには制約があり、特に生成値に対する破壊的変更はshrinkingを壊す可能性があるため注意が必要である。

フレームワーク側ではpropertyに、

```lisp
(:shrink t)

```

または、

```lisp
(:shrink nil)

```

を指定可能にする。

生成された値を破壊的変更するpropertyについては、

```text
warning: generated value may have been destructively modified

```

の診断を将来的に検討する。

本書の「最小反例」は、backendが探索して得た縮小済み反例を指す。
大域的な最小性を保証しない。縮小の完了・予算切れ・中断を区別し、元の失敗理由を保持する
要件は§72.4に定める。概念JSONの`minimal_counterexample`もこの意味で読む。

---

# 17. Function Spec

> **位置付け:** 実装済み（最小範囲）。必須引数と単一の戻り値を検査する。
> 対応範囲は§73.1のD1として確定した。

関数仕様は少なくとも、

```text
arguments
return value
relation between args and return
signals

```

を記述できるものとする。

D1（対応範囲）の決定：

| 項目 | MVPの扱い |
|---|---|
| lambda list | 必須引数のみ。`&optional`・`&key`・`&rest`等は拒否する。単独で書かれた場合だけでなく、`(&optional integer)`のように引数名の位置に現れた場合も拒否する |
| 引数名 | 束縛可能なsymbolのみ。定数（`t`、`pi`等）と、`:post`が戻り値に使う`RESULT`と同じsymbolは拒否する。述語はこれらの名前を並べたlambdaにコンパイルされるため |
| clauseの形 | 真リストのみ。`(:pre . y)`は`(and . y)`へ展開され、formですらなくなる |
| 多値 | 対応しない。`(:returns (values ...))`は拒否する。`:returns`は第一返り値を指す |
| `(:returns nil)` | 拒否する。型指定子`nil`は要素を持たない型なので、この契約は`nil`を含むあらゆる戻り値を違反として報告する。意図した型は`null`である |
| pre/postの評価順 | `:pre`は呼び出し前、引数のみを見る。`:post`は`:returns`の検査を通過したあと、引数と`result`を見る |
| `result`の束縛 | `:post`に現れる名前`RESULT`のsymbolを束縛する。異なるpackageの`RESULT`が複数現れる形式、および`:pre`が`RESULT`に触れる形式は拒否する |
| 実行前の可変値の参照 | 対応しない。副作用のない関数を対象とする |
| signals | 対応しない。`(:signals ...)`を含む未知のclauseは拒否する |
| 節の重複 | 拒否する |

対応しない形式は黙って無視せず、`invalid-function-spec-form`を送出して拒否する。
契約の一部だけを受理すると、検査していない主張について検証済みの結果を
報告することになる。この拒否はマクロ展開時に行われ、登録には到達しない。

同じ理由から、`function-spec`オブジェクト自体にも不変条件を課す。クラスと
`register-function-spec`は公開されているため、DSLを経由せずに契約を組み立てられる。

- clauseのformとコンパイル済み述語は、両方あるか両方ないかのいずれかである。
  formだけでは実行できない（§60が実行時`eval`を禁じている以上、formから述語は
  復元できない）ため、checkerは主張を無視したまま`:passed`を報告する。
  述語だけの場合は同じ失敗の裏返しで、述語は実行されるので入力は棄却され
  結果は判定されるのに、`function-spec-data`はその節が無いと報告する。
- 引数の名前は一意である。§14の反例は`{name value}`のplistであり、同じ名前を
  2度束縛したものはplistではない。`getf`は最初の値だけを返し、2つ目は
  復元できないので、失敗に対して報告された反例でその失敗を再現できない。
- 引数と戻り値のspec designatorは拒否せず正規化する。述語と違い
  `normalize-spec-form`で復元でき、正規化済みのspecはそのまま返るので、
  DSLの出力は素通りする。

これらは`shared-initialize`で検査する。`make-instance`だけがslotを埋める
標準の経路ではなく、`reinitialize-instance`と`change-class`も同じslotに届く。
`initialize-instance`だけを覆う検査は、後者が拒否対象の状態をそのまま
書き戻すのを許してしまう。

例：

```lisp
(defspec-function ranged-random
  (:args
   (start integer)
   (end integer))

  (:pre
   (< start end))

  (:returns integer)

  (:post
   (and (>= result start)
        (< result end))))

```

Clojure specの `fdef` がargs、return、args/return間の関係を仕様として扱い、その仕様からgenerative testingを行う設計を参考にする。

---

# 18. 自動generative function test

> **位置付け:** 実装済み。`check-function`が以下を行う。

Function specだけで最低限のproperty testを生成できるようにする。

上記 `ranged-random` なら、

```text
1. args specからstart/endを生成
2. preconditionを満たす入力だけ採用
3. functionを呼ぶ
4. return specを検査
5. postconditionを検査

```

API：

```lisp
(check-function 'ranged-random)

```

これは明示的 `defproperty` とは別物である。

`check-function`の`:trials`は非負整数である。負の値はbackendの試行loopを
一度も回さずに`:passed`を返すため、型として拒否する。

`check-function`は`function-check-result`を返す。これは`property-result`の
subclassであり、status・seed・試行数・反例・縮小反例に加えて次を持つ。

- `function-check-result-rejected`：`:pre`が棄却した生成入力の件数。
  関数に届いた試行の数は「試行数 − 棄却数」である。呼び出し回数ではない
  ことに注意する。縮小と、壊れた側を特定する再実行も関数を呼ぶ。
- `function-check-result-failure-reason`：契約のどちら側が壊れたか。
  `:return-spec`、`:postcondition`、`:condition`、または`nil`。
  `:precondition`は存在しない。`:pre`が棄却した入力に対して試行の述語は真を
  返すので、棄却された入力が失敗の理由になることはない。
- `function-check-result-explanation`：`:return-spec`失敗時の`explain-data`。

`:pre`が生成入力をすべて棄却した実行のstatusは`:skipped`であり、`:passed`では
ない。関数を一度も呼んでいない実行を成功として報告しない（§73.3のゼロ件成功）。

`failure-reason`は報告された反例に対して検査を一度やり直して求める。試行loopの
最後の失敗は、縮小が同じ述語をさらに何度も呼んだあとでは、報告された反例とは
限らないためである。

縮小結果は、それ自体が契約を破ることを確認できた場合にのみ報告する。backendは
縮小中に送出された条件を「まだ失敗している」と数えるが（§13がそう定めている）、
これはpropertyには正しくても、targetに適用すらできない候補をより小さい反例として
通してしまう。実例として`string`引数では、`check-it`がcacheした文字listを述語へ
渡すためtargetが送出し、縮小が失敗領域の外へ出る。報告された最小反例が契約を
満たす値になる。確認できない場合は元の反例へ戻し、どちらも再現しなければ
`failure-reason`は`nil`である。

status・failure-reason・condition・縮小反例は、同じ入力について述べる。
backendのstatusは最初に失敗した試行のものであり、縮小は契約の一方から他方へ
渡ることがある。そのままでは、何も送出しない最小入力の隣に`:error`が並び、
見るべきconditionが無いまま`:failed`と`:condition`が並んだ。

## Function spec

局所contractから自動生成するテスト。

## defproperty

ユーザーが意味的性質を明示するテスト。

両者を併用する。

---

# 19. Preconditionの扱い

> **位置付け:** 一部実装。棄却と件数の報告は実装済み。dependent generatorは未実装。

以下のような入力生成は避けるべきである。

```text
ランダム生成
↓
99.999% reject
↓
1件だけvalid

```

そのため、

```lisp
(:pre ...)

```

だけに依存せず、可能ならgenerator側に制約を反映する。

例えば、

```lisp
(start integer)
(end (integer-greater-than start))

```

のようなdependent generatorを将来的に扱う。

`check-it` はchained generatorを提供しているため、この用途で利用できる。

現在の実装は`:pre`を満たさない生成入力を棄却し、その件数を結果に載せる。
生成側へ制約を反映するdependent generatorは未実装であり、棄却率の高い契約では
実際に検査された件数が試行数より大幅に少なくなる。棄却数は結果から読めるので、
この不足は隠れずに現れる。

---

# 20. Runtime validation

> **位置付け:** 一部実装。値のvalidationは実装済み。関数instrumentationは未実装。

Specを実行時contractにも利用できる。

API：

```lisp
(validp 'positive-money value)

(validate 'positive-money value)

```

差：

```text
VALIDP
→ boolean

VALIDATE
→ value or structured condition

```

関数instrumentation：

```lisp
(instrument 'transfer)

```

すると引数specを呼び出し時に検査する。

```lisp
(uninstrument 'transfer)

```

で解除する。

本番環境ではoverheadを避けるため原則無効。

development / CI / stagingで利用する。

---

# 21. Condition systemとの統合

Common Lisp固有機能としてcondition/restartと統合する。

例えば、

```lisp
(define-condition spec-violation (...)
  ...)

```

情報：

```text
spec
value
path
predicate
expected
actual
source

```

例：

```text
SPEC-VIOLATION

spec:
  POSITIVE-MONEY

value:
  -100

failed:
  PLUSP

path:
  TRANSFER / AMOUNT

```

LLMがstack traceを解析しなくても原因を取得できることを目標とする。

---

# 22. Structured Explain

LLM-oriented frameworkとして、**構造化された説明データをprimary representationとする**。

API：

```lisp
(explain-data 'positive-money -100)
```

概念結果：

```lisp
(:valid nil
 :spec MY.DOMAIN::POSITIVE-MONEY
 :value -100
 :path ()
 :errors
 ((:kind :predicate-failed
   :predicate CL:PLUSP
   :expected (:satisfies CL:PLUSP)
   :actual -100)))
```

JSON等へ変換すると、

```json
{
  "valid": false,
  "spec": "MY.DOMAIN::POSITIVE-MONEY",
  "value": -100,
  "errors": [
    {
      "kind": "predicate-failed",
      "predicate": "CL:PLUSP"
    }
  ]
}
```

人間向けAPI：

```lisp
(explain 'positive-money -100)
```

は`explain-data`のprojectionとして実装する。例えば：

```text
-100 does not satisfy POSITIVE-MONEY

  ✓ INTEGER
  ✗ PLUSP
```

同様に、

```text
condition signal
CLI pretty printer
MCP response
HTML/Markdown documentation
```

も構造化データから派生させる。

Malliのstructured explain / humanize分離を参考にするが、cl-specではLLM consumptionを第一級要件として、path、predicate、expected、actual、child errors、source metadataをより明示的に保持する。

# 23. CLOS integration

> **位置付け:** 一部実装。instance-of以外の専用generic仕様・統合inspectionは将来構想。

CLOSはCommon Lispのsemantic structureとして積極的に利用する。

Spec primitive：

```lisp
(instance-of account)

```

Generic functionについて、

```lisp
(defspec-generic transfer ...)

```

のような専用仕様を将来的に導入可能。

LLM inspectionでは、

```text
generic function
methods
specializers
method qualifiers
applicable methods
related specs
related properties

```

を一括して返せることが望ましい。

---

# 24. Existing type declarationsとの統合

> **位置付け:** 将来構想。既存型宣言との照合規則は未決定。

既存の、

```lisp
(declaim
 (ftype
  (function (account account integer)
            transaction)
  transfer))

```

や、

```lisp
(declare
 (type account from)
 (type integer amount))

```

を可能な範囲で利用する。

ただし初期バージョンでCL compilerの型推論を完全に解析することは行わない。

可能なら、

```text
CL declared type
SPEC declared contract

```

の矛盾を検出する。

例：

```text
FTYPE:
  amount → INTEGER

SPEC:
  amount → STRING

```

ならwarningを出す。

---

# 25. Documentation生成

> **位置付け:** 未実装。以下は人間向け出力の概念例。

Spec/property registryからdocumentationを生成する。

例：

```lisp
(describe-spec 'transfer)

```

↓

```text
TRANSFER

Arguments
  FROM
    ACCOUNT

  TO
    ACCOUNT

  AMOUNT
    POSITIVE-MONEY

Returns
  TRANSACTION

Properties
  TRANSFER-PRESERVES-TOTAL
    invariant

  FAILED-TRANSFER-IS-NOOP
    failure-semantics

```

HTML / Markdown / JSON出力は将来対応する。

---

# 26. LLM向け設計原則

LLM利用では、人間向けpretty printingだけでは不十分。

すべての主要情報について、

```text
human-readable
machine-readable

```

両方のrepresentationを持つ。

原則としてMCP APIからはAST/structured dataを返す。

例えばproperty bodyそのものも、

```lisp
(equal
  (decode (encode x))
  x)

```

を単なるstringとして返すだけでなく、可能ならS-expressionとして保持する。

---

# 27. cl-mcpとの統合

> **位置付け:** 一部実装。semantic-dataは実装済み。MCP tool群は想定API。

本フレームワーク自体はMCP implementationへ依存させない。

代わりにpublic introspection APIを提供する。

cl-mcp側がそれをtoolとして公開する。

§28の `describe_symbol` はcl-spec単独の値を返す関数ではなく、joinである。signature、CL型宣言、
CLOS methods、source locationはcl-mcp側だけが持つ情報であり、cl-specのregistryには存在しない。
したがって `describe_symbol` はcl-mcp側に実装する。

cl-spec側はそのjoinの半分——registryが持っている情報——を1回の呼び出しで返す `semantic-data` を
提供する。現在の返却値は、次の固定キーを持つ登録名のrouting tableである。

```lisp
(:symbol <symbol> :package <string-or-nil>
 :spec <symbol-or-nil> :function-spec <symbol-or-nil>
 :property <symbol-or-nil> :properties-about (<symbol> ...))
```

本文は埋め込まず、登録名から`spec-data`・`property-data`で取得する。
未登録symbolにも同じキー集合を返す。空の結果は未ロード・未登録の可能性があり、契約不要を意味しない。
これにより、cl-mcp側は `find-spec` ・`find-function-spec` ・`find-property` ・
`properties-for` のように個別のindexを列挙しなくてよい。registryのindex構成はcl-specの内部実装
であり、それを別リポジトリに漏らさないための境界がこの関数である。

想定API：

```text
semantic_data

list_specs
describe_spec

list_properties
describe_property

properties_for_symbol

validate_value

sample_spec

run_property
run_properties_for_symbol
run_property_suite

replay_property

check_function

instrument_function
uninstrument_function

```

---

# 28. LLMが関数編集前に取得すべき情報

> **位置付け:** 設計方針。情報の一括取得を行うcl-mcp adapterは未実装。

例えば `TRANSFER` を変更しようとするLLMには、

```text
symbol information

function signature

CL type declarations

function spec

related properties

related generators

CLOS methods

source location

```

を取得させる。

概念的に：

```text
describe_symbol TRANSFER

kind:
  generic-function

spec:
  ...

properties:
  TRANSFER-PRESERVES-TOTAL
  FAILED-TRANSFER-IS-NOOP

methods:
  ...

source:
  transfer.lisp:42

```

---

# 29. LLM coding loop

利用フロー（具体的な判断規則は§0.4と§72）：

```text
task → inspect symbol / load specs
     → read contracts / select tests / record baseline
     → edit / persist / reload / compile
     → ordinary tests + related properties + saved counterexamples
     → assess result AND verification scope
          failure       → counterexample / diagnosis → repair
          error         → identify execution cause → retry or report
          insufficient  → expand checks or report missing evidence
          checks met     → report changes, evidence and remaining limits
```

成功したPropertyだけを根拠に完了としない。ゼロ件、skip、timeout、generator failure、
前提条件の枯渇を成功扱いしない。契約の弱体化による成功も元の要求を満たした証拠にしない。

---

# 30. PropertyをLLMへの仕様として利用する

Propertyはテスト実行時のみロードされる補助コードではなく、

```text
semantic specification

```

として扱う。

LLMが、

```lisp
(defproperty encode-decode-roundtrip
    ((message message-spec))
  (:about encode decode)
  (:kind :roundtrip)

  (equal message
         (decode
          (encode message))))

```

を読めば、

```text
MESSAGE-SPECの入力について、DECODE(ENCODE(message))がmessageに戻ることを要求する

```

と理解できる。

これはdocstringに実行による検査手段を加える。
ただしこのPropertyは`encode(decode(x)) = x`や全入力での逆関数関係まで示さない。
Propertyが表現する関係、入力domain、実際の検査範囲を区別する。

---

# 31. Source relationship

Propertyと対象symbolの関連付けを明示する。

```lisp
(:about encode decode)

```

この情報を逆indexする。

```text
ENCODE
 → ENCODE-DECODE-ROUNDTRIP

DECODE
 → ENCODE-DECODE-ROUNDTRIP

```

コード変更後に直接関連するpropertyを高速実行可能になる。
ただし補助関数の変更、間接呼び出し、generic method、共有状態を介した影響は、
`:about`の逆indexだけでは網羅しない。実行対象の選択根拠と網羅範囲を報告する（§72.5）。

---

# 32. Tags

任意tagを持つ。

例：

```lisp
(:tags
 :domain
 :money
 :critical)

```

利用：

```lisp
(cl-spec:run-properties
 (cl-spec:properties-with-tag :critical))

```

---

# 33. Test profiles

実行コスト別profileを用意する。

```text
:smoke
:normal
:extended
:stress

```

Propertyごとに、

```lisp
(:trials (:smoke 10 :normal 100 :extended 1000 :stress 100000))

```

のように指定可能にする。

CIでは、

```text
PR
 → smoke / normal

nightly
 → extended

manual
 → stress

```

とする。

---

# 34. Ordinary test frameworksとの関係

本フレームワークはFiveAM、Rove等のunit-test frameworkを置き換えない。

役割：

```text
unit test framework
 → concrete example testing

cl-spec
 → executable specification
 → generative/property testing

check-it
 → low-level generation/shrinking engine

```

Property resultを既存frameworkのassertionとしてwrapper提供することは可能。

---

# 35. ASDF integration

推奨構成：

```text
my-project.asd

my-project
my-project/spec
my-project/test
my-project/property-test

```

Production runtimeに `check-it` を要求しない構成を可能にする。

例：

```text
MY-PROJECT/SPEC
 → spec declarations only

MY-PROJECT/PROPERTY-TEST
 → check-it dependency

```

Clojure specも、spec自体はruntimeで利用可能にしつつ、generative testing backendをtest dependencyとして分離する設計を採っている。

---

# 36. Registry persistence

> **位置付け:** 一部実装。image内registryのみ。永続exportは将来構想。

初期バージョンではLisp image内registryのみとする。

将来的には、

```text
JSON
S-expression
SQLite

```

へのexportを検討する。

LLMによるoffline indexingにはJSON/S-expression exportが有用。

---

# 37. Macro design / Normalization

Macroはsyntax sugarとして扱い、runtime coreおよびSemantic IRとは分離する。

例えば、

```lisp
(defspec positive-money
  ...)
```

は概念的に、

```text
source form
  ↓
normalize-spec-form
  ↓
SPEC object (Semantic IR)
  ↓
register-spec
```

となる。

同様に `defproperty`、`defspec-function` もnormalized definition objectを生成してregistryへ登録する。

これにより、

- macro debuggingが容易
- programmatic registration可能
- LLM toolから動的生成可能
- DSLとIRを独立にversioning可能
- source formとnormalized formの両方をinspection可能

となる。

---

# 38. Introspection first

> **位置付け:** 一部実装。spec-data・property-data・semantic-dataは実装済み。

全metadataはregistryとSemantic IRから取得可能でなければならない。

避けるべき設計：

```text
macroexpandしなければmetadataが分からない
compiled functionしか残らず意味が読めない
pretty printed stringしか取得できない
```

望ましい設計（`function-spec-data`は現在の公開APIにはなく、以下はその部分を含む概念例）：

```lisp
(spec-data (find-spec ...))
(property-data (find-property ...))
(function-spec-data (find-function-spec ...))
```

だけでsemantic informationを取得できる。

主要なdefinition objectは元S-expressionとnormalized representationの双方を保持する。

Introspection-firstの原則はconsumer側にも及ぶ。consumerはregistryが `find-spec` ・
`find-function-spec` ・`find-property` ・`properties-for` のように複数のindexへ分かれている
ことを知らなくても、あるsymbolについて何が分かっているかを問い合わせられなければならない。
`semantic-data` (specification §27) がその入口であり、consumerはregistryの内部構造を列挙する
必要がない。

---

# 39. Property definition object

概念クラス：

```lisp
(defclass property-definition ()
  ((name ...)
   (variables ...)
   (specs ...)
   (body ...)
   (function ...)
   (targets ...)
   (kind ...)
   (tags ...)
   (documentation ...)
   (source-location ...)
   (options ...)))

```

`body` は可能なら元S-expressionも保存する。

これはLLMにとって重要である。

compiled functionだけではpropertyの意味を読むことができないため。

---

# 40. Side-effect property

> **位置付け:** 要件（現状は未保証）。以下のsetup/cleanup構文と実行規則は未実装。

副作用を伴うpropertyも許可する。

ただし状態セットアップ/cleanupを明示できるようにする。

例：

```lisp
(defproperty transaction-rollback
    ((scenario transaction-scenario))

  (:setup
   (make-test-database))

  (:cleanup
   (destroy-test-database))

  (:kind :failure-semantics)

  ...)

```

現在のMVPではsetup/cleanup DSLを提供しない。
副作用のあるPropertyを実行する場合は、呼び出し側が各実行の状態初期化と後始末を担う。
状態の独立性を確保できないPropertyに対して、replayやshrinkingの再現性を保証しない。
正式なtrial・縮小候補ごとのlifecycleは§72.4・§73のD5で定める。

---

# 41. Stateful property testing

> **位置付け:** 将来構想。MVP対象外。

将来的にはstate-machine testingを追加する。

概念：

```lisp
(defstate-machine bank-account
  (:state account-model)

  (:command deposit ...)
  (:command withdraw ...)
  (:command freeze ...)

  (:invariant non-negative-balance ...))

```

モデル：

```text
abstract model
   ↓
generated command sequence
   ↓
real implementation
   ↓
compare states

```

これは非常に強力だが、MVPには含めない。

---

# 42. Metamorphic testing

> **位置付け:** 設計方針。Property本体で記述可能。専用kindの追加は将来構想。

正解出力が簡単に分からない処理に対し、

```text
入力を変換すると
出力がどう変わるべきか

```

をpropertyとして書く。

例：

```text
sort(reverse(x)) = sort(x)

```

LLM生成コードやML/数値処理にも適用しやすいため、将来 `:metamorphic` kindを追加してもよい。

---

# 43. Mutation testingとの連携

> **位置付け:** 将来構想。外部mutation engineとの連携。

本フレームワーク自体ではmutation engineを実装しない。

ただしproperty suiteの品質評価として、

```text
mutation score

```

を利用可能にする設計を考慮する。

LLMがpropertyを自動生成した場合、

```text
弱すぎるproperty

```

になる危険がある。

mutation testingはこの検出に有効。

---

# 44. LLMによるProperty生成

> **位置付け:** 将来構想。候補生成の運用要件は§45・§72.2を参照。

将来的な重要機能。

LLMに、

```text
function implementation
type declarations
docstring
unit tests
call sites

```

を提示し、

```text
candidate properties

```

を生成させる。

ただし自動生成propertyを即座にtrusted specificationとして扱ってはならない。

状態：

```text
:experimental
:reviewed
:trusted
:deprecated

```

などをproperty metadataとして持つことを検討する。

---

# 45. Trust model

> **位置付け:** 要件（現状は未保証）。trust metadataの自動付与・昇格制御は未実装。

Property自体も間違う。

したがって、

```text
implementation
vs
specification

```

を単純に「propertyが絶対正しい」と扱わない。

Property metadata：

```lisp
(:status :reviewed)

```

候補：

```text
:experimental
:reviewed
:trusted
:deprecated

```

LLM生成propertyはデフォルト：

```text
:experimental

```

とする。これは目標運用であり、現在の`defproperty` DSLによる自動設定ではない。
`:status` clauseの構文や強制機構は未実装である。

trustはPropertyの由来・レビュー状態であり、正しさの証明でも実行権限でもない。
実装との同時変更、契約の削除・弱体化、承認後の内容変更を追跡する要件は§72.2に定める。

---

# 46. Property quality

以下のようなpropertyは弱い。

```text
result >= 0

```

実装が常に0でも通る。

良いpropertyの例：

```text
roundtrip
conservation
equivalence
idempotence
reference implementation comparison
state invariant

```

ただし分類名だけでPropertyの強さは決まらない。冪等性だけなら定数関数でも満たせる。
roundtripだけでは双方の実装が同じ誤りを共有する場合を排除できない。
独立した具体例・境界値・参照実装・失敗時の性質を組み合わせる。
Framework documentationではproperty設計guideを提供する。

---

# 47. Error taxonomy

> **位置付け:** 設計方針。以下は目標taxonomyであり、現行resultのstatus一覧ではない。

構造化されたfailure categoryを定義する。

```text
:generator-error
:precondition-exhausted
:property-failed
:property-signaled
:spec-violation
:timeout
:backend-error
:internal-error

```

LLMが原因を判別しやすくする。

---

# 48. Timeout

> **位置付け:** 要件（現状は未保証）。以下のtimeoutキーワードは現在利用不可。

LLMによる自律実行を考慮するとtimeoutは必須。

```lisp
(run-property
 'foo
 :timeout 5)

```

timeoutをLLMの自律実行に対する受け入れ要件とするが、coreの当該APIは未実装である。
現在は実行ホスト側で時間上限と必要なワーカー破棄を管理する。
将来のAPIでは生成・trial・shrinking・cleanupを含む全体予算と、trial単位予算を区別する。
中断後に同じimageを再利用してよいかも含め、§73のD5で責務を確定する。

---

# 49. Dangerous operations

Property testでは大量のランダム入力を実行するため、

```text
network
production DB
filesystem destruction
external API

```

へのアクセスを不用意に行わない。

将来的にproperty metadata：

```lisp
(:effects (:database))

```

などを持たせてもよい。

MCP経由での実行ポリシーにも利用できる。

---

# 50. Package / System設計

production runtimeとgenerative testing backendを分離する。

推奨ASDF system構成：

```text
cl-spec
  semantic IR
  registry protocol
  normalization
  validation
  structured explain
  introspection

cl-spec/check-it
  check-it generator compiler
  property execution backend
  shrinking / replay integration

cl-spec/instrument
  runtime function instrumentation

cl-spec/tests
  framework自身のtests
```

packageの内部分割例：

```text
CL-SPEC/IR
CL-SPEC/REGISTRY
CL-SPEC/NORMALIZE
CL-SPEC/VALIDATOR
CL-SPEC/EXPLAIN
CL-SPEC/GENERATOR
CL-SPEC/PROPERTY
CL-SPEC/FUNCTION-SPEC
CL-SPEC/INTROSPECTION
CL-SPEC/CONDITIONS
CL-SPEC/CHECK-IT
```

public package：

```text
CL-SPEC
```

`cl-spec` coreは可能な限り軽量に保ち、`check-it`をproduction dependencyとして強制しない。

# 51. MVP API

> **位置付け:** 目標API一覧。現在利用できる機能は§0.2を参照する。

最初の実用版では以下に絞る。

## Spec

```lisp
defspec
find-spec
list-specs
validp
validate
explain
explain-data

```

## Generators

```lisp
defgenerator
generator-for
sample

```

## Functions

```lisp
defspec-function
find-function-spec
check-function

```

## Properties

```lisp
defproperty
find-property
list-properties
properties-for
run-property
run-properties
replay-property

```

## Introspection

```lisp
describe-spec
describe-property
spec-data
property-data
semantic-data

```

---

# 52. MVPでサポートするSpec

> **位置付け:** normalization・validationの対応範囲。generatorの自動導出範囲とは異なる。

裸の名前はCL型名または登録Spec参照となる。複合CL型は`(type (integer 0 *))`のように
明示する。rangeは`(range lo hi)`または`(range integer lo hi)`・`(range real lo hi)`を用いる。
現在の`defspec`は名前とSpec formの2引数であり、§11の追加option例は未実装。

```text
Common Lisp type
predicate
AND
OR
NOT
MEMBER
numeric range
list-of
vector-of
tuple
nullable
instance-of

```

---

# 53. MVPで対応しないもの

最初から以下は実装しない。

```text
static type checking
dependent types
SMT solving
automatic formal proof
full CLOS protocol specification
state-machine PBT
parallel property testing
distributed testing
automatic mutation testing
Coalton integration
automatic source-code rewriting

```

これらは後続phaseとする。

---

# 54. Implementation phases

> **位置付け:** 実装計画。phase一覧は完了状況を示さない。現状は§0.2を参照する。

## Phase 0: prototype

目的：

`defspec → generator → check-it → defproperty`

が一周することを確認。

実装：

```text
registry
primitive spec
check-it adapter
defproperty
run-property
shrinking result

```

---

## Phase 1: usable MVP

追加：

```text
function specs
automatic function check
structured result
seed replay
source location
tags
property kind
introspection
ASDF test integration

```

この段階で既存Common Lispプロジェクトへ実戦投入可能とする。

---

## Phase 2: LLM integration

現在はこのphaseに挙げる`explain-data`や一部introspectionを先行実装している。
一覧の順番は、全機能がそのphaseで初めて提供されることを意味しない。

追加：

```text
structured JSON-like API
properties-for-symbol
explain-data
cl-mcp adapter
related semantic data
LLM-oriented diagnostics

```

---

## Phase 3: runtime contracts

追加：

```text
instrument
uninstrument
function argument validation
return validation
condition integration

```

---

## Phase 4: advanced PBT

追加候補：

```text
state-machine testing
dependent generators
better shrinking
property coverage
mutation testing integration
parallel trials

```

---

## Phase 5: typed integration

Coaltonとの統合を検討する。

例えば：

```text
Coalton static type
       +
CL-SPEC dynamic specification
       +
property tests
       +
runtime state

```

Coaltonは型情報やcode generationに対するinspection APIを持つため、将来的には同じsemantic interfaceからCoaltonの静的情報も公開できる。

---

# 55. Coalton integration構想

> **位置付け:** 将来構想。MVP対象外。

将来、

```lisp
(import-coalton-type ...)

```

などにより、

```text
Coalton type
→ spec
→ generator

```

を一部自動化できる可能性がある。

ただし、

```text
type inhabitation

```

と、

```text
valid domain value generation

```

は同じではない。

したがって自動generator導出には限界がある。

---

# 56. CI推奨

CIでは最低限、

```text
compile
unit tests
property tests

```

を実行する。

推奨：

```text
Pull Request:
  100 trials/property

main:
  1000 trials/property

nightly:
  10000+ trials/property

```

実際のtrial数はpropertyのコストに応じて調整する。

---

# 57. Failure artifact

> **位置付け:** 要件（現状は未保証）。artifactの自動保存・永続replay形式は未実装。

CI failure時には以下を必ず保存する。

```text
property name
seed
original counterexample
shrunk counterexample
condition
backtrace optionally
source location
framework version
check-it version

```

LLM coding agentがCI failureから直接再現可能にする。

---

# 58. Versioning

> **位置付け:** 将来構想。contractの自動互換性判定は未実装。

Specは実質的にAPI contractである。

Spec変更：

```text
widening
narrowing
semantic change

```

を将来的に比較できると有用。

例：

```text
old:
(integer 0 *)

new:
(integer 1 *)

```

は入力domainのnarrowing。

API compatibility analysisへの応用が可能。

---

# 59. Performance policy

Specを通常のproduction execution pathへ強制的に入れない。

```text
declarations
registry

```

自体は軽量に保つ。

高コストな、

```text
check-it
generative tests
instrumentation

```

はdevelopment dependencyとして利用可能にする。

---

# 60. セキュリティ

LLM/MCPからpropertyを実行する場合、

property bodyは任意Common Lisp codeである。

したがってframework自体でsandboxingができるとは考えない。

MCP側で、

```text
trusted project only
explicit tool permissions
isolated test environment

```

を管理する。

---

# 61. 主要な設計判断

### 決定1

`check-it` はbackendとして使用する。

上位DSLを `check-it` 固有APIへ密結合させない。

### 決定2

SpecとPropertyを分ける。

### 決定3

Propertyと対象symbolの関係を明示する。

### 決定4

metadataはruntime registryへ保存する。

### 決定5

LLM用structured representationを第一級機能とする。

### 決定6

既存Common Lisp関数の書き換えを必須としない。

### 決定7

Propertyはテストコードではなくsemantic specificationとして扱う。

---

# 61.1 先行プロジェクトからの設計判断

## Schemata

Common LispのSchemataは、以下について重要な先行例である。

- CLOSによるschema object hierarchy
- `defschema`からruntime objectへのnormalization
- named schema registry
- Common Lisp typeとの統合
- schema composition
- schemaから`check-it` generatorを生成する試み

一方でcl-specではSchemataを直接dependencyまたはfork元とはしない。理由：

- 主目的がserialization / data validation寄りであり、program semantics中心のcl-specとは軸が異なる。
- core dependencyがcl-specのMVPには過剰である。
- generator実装が未完成であり、`check-it`内部APIへの密結合を含む。
- structured explain、function semantics、property graph、LLM introspectionの要件が大きく異なる。

したがって、CLOS schema設計、CL type integration、DSL normalizationの実例として参考にする。

## Malli

ClojureのMalliはarchitecture referenceとして特に重要である。以下を参考にする。

- schemaをdata / IRとして扱う設計
- registry protocolと複数registry実装
- validator / explainer / generator等をschemaから生成するcompiler型architecture
- structured explainをprimary dataとしhuman readable outputを分離する設計
- function schemaとinstrumentation
- generative function checking

ただしcl-specはMalliのCommon Lisp移植を目的としない。

cl-spec独自の中心は、

```text
Common Lisp program symbol
  + function spec
  + property relationships
  + source/runtime/CLOS metadata
  + compiler diagnostics
  + LLM/MCP introspection
```

から **program semantic graph** を形成する点にある。

## 基本方針

```text
Schemata
  → Common Lisp上のschema implementation patternを参考

Malli
  → Semantic IR / compiler / registry architectureを強く参考

check-it
  → 初期PBT backendとして直接利用

cl-spec
  → 独立実装
```

---

# 62. Clojure specとの差別化

Clojure specから以下を強く参考にする。

```text
spec registry
predicate-based specification
function specification
validation
instrumentation
generator derivation
generative testing
documentation integration

```

Clojure spec自身も、仕様記述の労力をvalidation、error reporting、instrumentation、test-data generation、generative testingへ最大限再利用することを主要目標としている。

本フレームワークではさらに、

```text
LLM introspection
explicit property registry
property-to-symbol relationship
CLOS/MOP integration
condition/restart integration
MCP exposure

```

を重視する。

---

# 63. Haskell型システムとの関係

本フレームワークはHaskell型システムを再現しない。

Haskell：

```text
invalid program
→ type checker rejects before execution

```

本フレームワーク：

```text
executable specification
→ generated execution
→ counterexample

```

したがって保証の性質は異なる。

しかしLLM coding agentにとっては、

```text
generate
→ execute
→ minimal counterexample
→ repair

```

というfeedback loopを構築できる。

---

# 64. Common Lispであることの強み

Common Lispでは以下を同一imageから取得できる。

```text
source definitions
runtime objects
CLOS classes
generic functions
methods
method combinations
compiler diagnostics
conditions
restarts
specifications
properties

```

これをcl-mcp等からLLMへ公開すると、

```text
Common Lisp image
=
semantic oracle

```

として利用できる。

---

# 65. 最終的なシステム像

```text
                     Source code
                         │
           ┌─────────────┼──────────────┐
           │             │              │
      CL declarations   Specs       Properties
           │             │              │
           │             ▼              ▼
           │        Spec Registry   Property Registry
           │             │              │
           │             └──────┬───────┘
           │                    │
           │             Generator Layer
           │                    │
           │              check-it backend
           │                    │
           │            Property execution
           │                    │
           └──────────────┬─────┘
                          │
                    Structured results
                          │
                         MCP
                          │
                         LLM
                          │
                    source modification
                          │
                          └────────→ repeat

```

---

# 66. 成功条件

本フレームワークの成功は、DSLの美しさではなく以下で評価する。

## 人間に対して

- 仕様がコードから読み取れる
- propertyを書く負担が過度でない
- failureが理解しやすい
- 既存プロジェクトへ段階導入できる

## LLMに対して

- 対象symbolの契約を問い合わせ可能
- 関連propertyを自動発見可能
- propertyを個別実行可能
- minimal counterexampleを取得可能
- seedから再現可能
- 修正後に関連propertyだけ再実行可能

## 工学的に

- production runtimeへの依存を最小化できる
- check-itを交換可能
- property/spec registryを外部からinspection可能
- Common Lispの通常の開発スタイルを破壊しない

---

# 67. 最初に実装すべきvertical slice

最初の実装ではProperty runnerだけを急がず、Semantic IRの価値が一周することを確認する。

```lisp
(defspec positive-integer
  (and integer
       (range 1 *)))
```

これに対して、

```lisp
(find-spec 'positive-integer)
(spec-data 'positive-integer)
(validp 'positive-integer 10)
(explain-data 'positive-integer -1)
(sample 'positive-integer)
```

が動作する。

`spec-data` の概念結果：

```lisp
(:name CL-USER::POSITIVE-INTEGER
 :kind :and
 :source-form (AND INTEGER (RANGE 1 *))
 :children
 ((:kind :type :type INTEGER)
  (:kind :range :min 1 :max :unbounded)))
```

上の例は説明のため省略している。実際の`spec-data`は全ノードで同じキー集合
（`:name` `:kind` ノード固有キー `:source-form` `:source-location`）を返し、
`:children` は子を持つノードにのみ付く。値によってキーが出没しないほうが、
JSON/MCP投影の消費側を壊しにくい。

次に、

```lisp
(defproperty addition-preserves-order
    ((x positive-integer)
     (y positive-integer))
  (:about +)
  (:kind :monotonicity)

  (> (+ x y) x))
```

を追加し、

```lisp
(properties-for '+)
(run-property 'addition-preserves-order)
```

までを通す。

内部フロー：

```text
DEFSPEC
→ normalize
→ Semantic IR
→ registry
→ validator / explainer / generator compilation

DEFPROPERTY
→ Property IR
→ registry / reverse index
→ check-it backend
→ structured property result
```

このvertical sliceが完成してからfunction specs、instrumentation、MCP integrationへ進む。

---

# 68. 初期テスト方針

framework自体にもproperty testingを使う。

特に、

```text
generator outputs always satisfy spec

successful validation implies VALIDP

replay(seed) reproduces generated sequence

registry lookup is stable

spec composition obeys boolean semantics

```

などをpropertyとして記述する。

自身が提供する仕組みを自身の品質保証に使う。

---

# 69. 最初に検討すべき技術的論点

> **位置付け:** 未決定事項の入口。実装済みの判断も含む歴史的リスト。残課題は§73で管理する。

実装開始時には以下を優先的に決定する。

1. Semantic IRのcanonical representation
2. Spec DSLの正確なsyntaxとnormalization rule
3. `*` 等のCL type syntaxとの互換性
4. Predicate specとCL type specの統合方法
5. registry protocolとdefault registryのdynamic binding
6. validator / explainer compiler API
7. structured explain/error schema
8. generator backend protocol
9. check-it generatorへの変換層
10. source location取得方法
11. package reload / ASDF reload時のregistry更新
12. 重複spec/property定義の扱い
13. property bodyおよびsource form保持方法
14. random seedの管理
15. check-it shrinking resultの取得方法
16. destructive test valueへの対応
17. recursive/reference specのgenerator strategy
18. compiler artifactのcache invalidation

---

# 70. 推奨する実装開始順

> **位置付け:** 実装計画。初期の依存順を示す。次の実証順は§73.2を参照する。

今回の先行実装調査を踏まえ、実装順を以下へ更新する。

```text
1. Semantic IR
2. Registry protocol
3. Hash-table registry
4. DEFSPEC normalization
5. Validator compiler
6. Structured explainer
7. VALIDP / VALIDATE / EXPLAIN / SPEC-DATA
8. Generator backend protocol
9. check-it adapter
10. Property IR
11. Property registry / reverse index
12. DEFPROPERTY
13. Property runner
14. Structured property result
15. seed / replay / shrink integration
16. Function Spec IR
17. Function checker
18. Introspection API
19. Runtime instrumentation
20. cl-mcp adapter
```

この順序の重要な点は、generatorやPBTに入る前に、

```text
DSL → Semantic IR → registry → validation → structured explain
```

というsemantic infrastructureを完成させることである。

---

# 71. プロジェクトの核心

本プロジェクトの本質はProperty-Based Testing libraryをもう一つ作ることではない。

`check-it` が既に担っている、

```text
random generation
shrinking
```

を再実装する必要はない。

また、Schemataのようなserialization schema libraryを再実装すること自体も目的ではない。

本当に構築したいのは、Common Lisp program semanticsを表現する **executable Semantic IR** と、その周辺runtimeである。

```text
Common Lisp code
      +
machine-readable Semantic IR
      +
executable properties
      +
semantic registry / graph
      +
validator / explainer / generator compilers
      +
LLM introspection
```

その結果、LLMは、

```text
「このコードは何をするか」
```

だけではなく、

```text
「どの入力を受け入れるか」
「どの出力を返すべきか」
「どの関係・不変条件を壊してはいけないか」
「どのpropertyを変更後に再実行すべきか」
「失敗した最小反例は何か」
```

を直接問い合わせ、実行によって確認できる。

これは静的型システムの代替ではない。

Common Lispの動的性、CLOS、REPL、condition system、runtime introspectionを維持しながら、LLMが安全にコードを変更するためのsemantic feedbackを大幅に強化するための仕組みである。

アーキテクチャ上の短い定義として、cl-specを次のように捉える。

> **cl-spec is an executable semantic IR and property framework for Common Lisp programs, designed for both humans and LLM coding agents.**

---

# 72. LLM利用の受け入れ要件

> **位置付け:** 要件（現状は未保証）。以下は自律開発に利用するための受け入れ条件であり、
> 現在のresultに同名のslotやJSON keyが存在するという意味ではない。
> 具体的なAPI/schemaとcore・backend・adapter間の責務は§73で確定する。

## 72.1 検証結果と検証範囲（LLM-01）

結果は「性質が反証されたか」と「要求した検査を実施できたか」を区別する。

報告に必要な情報：

- 選択したProperty名、選択根拠、対象revision、契約の識別情報。
- 要求した試行予算、実際に評価した件数、生成・前提条件による棄却件数。
- 成功・失敗・実行エラー・skip・中断と、その理由。
- 未ロード・未登録・未選択・未対応による未検証範囲。
- 生成domainや重要な境界値の検査状況。計測していないcoverageは不明とする。

**受け入れ条件:** Propertyがゼロ件、実行件数がゼロ、前提条件の枯渇、
timeout、generator/backend errorのケースが、成功した検証として報告されない。
成功した試行数から、未計測の入力網羅率や正しさの確率を導出しない。

現在のrunnerに情報がない場合は、呼び出し側の実行記録を併記するか不明と報告する。
不足した値をLLMが推測で埋めない。

## 72.2 契約の由来と変更（LLM-02）

Spec/Propertyについて、由来となる要求・文書・具体例、作成者または生成元、
レビュー状態、内容のversionまたはdigestを追跡可能にする。

`:experimental`、`:reviewed`、`:trusted`、`:deprecated`を共通の状態語彙とし、
レビューは特定の内容に対して記録する。内容変更後に以前のレビューを自動継承しない。
状態遷移の権限と記録形式は未決定であり、現在のregistryが強制するものではない。

**受け入れ条件:** 実装修正と同時にPropertyを削除、前提条件を追加、入力domainを縮小、
期待値を変更、または試行予算を削減した場合、契約・検査条件の変更として差分に現れる。
候補Propertyの成功だけで既存のtrusted契約を置き換えない。

契約変更自体がユーザー要求である場合は、その要求に基づく変更として扱う。
この要件は正当な仕様変更を禁止するものではない。

## 72.3 再生成と反例の再検査（LLM-03）

再現には二つの目的がある。

| 操作 | 固定するもの | 確認すること |
|---|---|---|
| 生成列のreplay | seed、定義、環境、生成設定、初期状態 | 同じ条件で失敗を再生成できるか |
| 保存反例の再検査 | 入力と必要なfixture | 修正後の実装でその失敗が解消したか |

再現artifactには、Property名、元の入力と縮小済み入力、失敗段階・理由、
seed、profile名と解決済み数値予算、生成・縮小options、framework/backend/Lispのversion、
ソースrevision、Spec/Property/generatorの識別情報、fixtureの復元条件を保存する。
未コミット・REPLのみの変更がある場合は、revisionだけで定義を特定できないことを示す。

**受け入れ条件:** 定義・環境・予算の不一致を検出または呼び出し側の責任範囲として明示し、
条件を変更した再実行を「元の実行を厳密に再現した」と報告しない。
読めるプレビューしか保存できない値は、直接replay可能な入力として扱わない。

外部I/Oや時刻などseedで制御しない要素はfixtureで固定するか、再現保証の対象外として記録する。

## 72.4 状態・縮小・時間上限（LLM-04）

各trialと各縮小候補の評価は、独立に復元できる初期状態から開始する。
破壊的に変更される生成値は実行前の入力を保持し、適切なcopyまたは再構築手段を用いる。
任意のCLOSオブジェクトに汎用の安全なdeep copyがあるとは仮定しない。

縮小中も入力Specとpreconditionを満たすこと、および元の失敗との対応を確認する。
別の例外が出ただけの候補を、元の論理的失敗の縮小結果として置き換えない。
失敗の同一性を判定する詳細規則は§73のD4で決定する。

**受け入れ条件:** 通常終了・失敗・エラーでcleanupが実行され、縮小の完了・予算切れ・
中断が区別される。強制終了でcleanupを保証できない場合はその事実を記録し、
状態が不明なワーカーを後続検証に再利用しない。

時間予算は生成・評価・縮小・cleanupを含む全体とtrial単位を区別する。
具体的な強制終了機構は実行ホストの責務を含めて定める。
framework内のmetadataはsandboxや外部アクセス制御の代わりにはならない。

## 72.5 変更影響とimageの整合性（LLM-05）

`properties-for`が返すのは`:about`に直接登録された関連である。
依存関係を辿って選択する場合は、その取得元と限界を併記する。
呼び出し関係、generic method、共有状態を含む完全な変更影響解析はMVPで保証しない。

実行した定義が保存済みソースと一致するよう、再ロード・コンパイルを行う。
registryの重複登録、削除された定義、参照先の変更、compiled artifactのcacheについて、
更新・無効化規則を明示する。現在の個別実装を越える一括保証は§73のD6で確定する。

**受け入れ条件:** 直接関連の部分実行を「全回帰テスト」と報告しない。
REPLの一時定義で成功しても、保存・再ロード後の検証を完了するまで修正完了としない。
imageの状態が不明な場合は、クリーンなプロセスで必要な検証を行う。

## 72.6 機械可読境界（LLM-06）

Lisp内部のIR/plistと外部JSON schemaを区別し、外部表現にschema versionを持たせる。
MCP公開時には利用可能な操作・未対応機能・実行制限を取得できるようにする。
capabilityの具体的なAPI名と返却形式は未決定。

外部表現では、少なくとも次の区別を保持する。

- symbolのpackageと名前、未登録と情報未取得。
- false、null、空list、値なし、および多値の個数。
  Lispの`NIL`の用途はフィールドの型で定め、任意値だけから意味を推測しない。
- 整数・有理数等の値の正確さと、表示用文字列。
- 再構築可能な値、CLOS等の不透明オブジェクト、循環・共有参照。
- 完全な本文と、長さ・深さの制限による省略。

symbolの表示文字列を任意のreader入力として評価しない。既存symbolの解決と
未解決の診断を用い、tool入力の解釈のために任意code実行や動的internを要求しない。
表示用previewを保存反例の復元形式と混同しない。

**受け入れ条件:** packageの異なる同名symbolを区別できる。省略を完全なデータと誤認しない。
非対応schemaや復元不能な入力に明示的な診断を返す。
無制限のProperty本体や巨大な値を毎回返さず、概要から必要な詳細を取得できる。

# 73. 未決定事項と次の検証

## 73.1 設計判断の一覧

以下の項目はAPIを推測で補うための候補一覧ではなく、実装前に決める判断事項である。
解決時には当該節・実装状況表・対応する受け入れテストを併せて更新する。

| ID | 決めること | 関連節 | 決定・検証が必要な時点 |
|---|---|---|---|
| D1 | Function Specのlambda list、多値、pre/post、signals、実行前状態、未対応構文 | §17〜19、§21 | 決定済み（§17の表）。対応範囲を広げるときに再検討 |
| D2 | status/categoryの対応、棄却・試行数の定義、予算、検証不足の集計 | §14、§19、§47、LLM-01 | 自律実行結果の公開前 |
| D3 | replay artifact schema、定義識別、復元不能値、options保存、直接反例再検査API | §15、§57、LLM-03 | CI artifact連携前 |
| D4 | 縮小時の失敗同一性、入力妥当性、完了状態 | §16、LLM-04 | 縮小結果を修正根拠にする機能の拡張前 |
| D5 | fixture lifecycle、timeout、強制終了、cleanup、ワーカー再利用の責務 | §40、§48、§60、LLM-04 | 副作用を伴う自律実行前 |
| D6 | reload時の定義削除、参照更新、registry世代とcache invalidation | §8、§9.1、§69、LLM-05 | 継続的REPL連携の保証前 |
| D7 | JSONの型表現、schema version、capability、情報省略の規則 | §26〜28、LLM-06 | cl-mcp adapter公開前 |
| D8 | trustの保存形式、由来、内容変更時の扱い、状態遷移の権限 | §44〜45、LLM-02 | LLM生成Propertyの採用自動化前 |

## 73.2 次の実証順

既存のvertical sliceを基礎に、次の順でLLMの開発作業に接続する。

1. 純粋な小関数を対象にFunction Specの最小対応範囲を確定し、checkerを実装する。
2. 既存の`semantic-data`・`property-data`・runnerを最小限のcl-mcp adapterへ接続する。
   初回は副作用のない対象を選び、実行ホストで時間上限を設ける。
3. 既知の不具合について、契約取得・反例取得・修正・保存反例の再検査を一周させる。
4. 実行結果の不足、再現条件、取得情報量を測り、LLM-01〜06の未達項目を明示する。
5. その結果に基づき、副作用のある対象や高度なPBTへの拡張を判断する。

§70は初期architectureの依存順であり、この実証順は現在の実装から利用価値を確認する順である。

### 1〜3の実測（2026-09-10）

Function checkerとcl-mcp adapterを接続し、既知の欠陥で一周させた。対象は
`(floor (* count (- value low)) (- high low))`、閉区間の右端で`count`を返す
off-by-one。

- `:about`で選ばれる2つのPropertyは両方passした。単調性も左端も、この欠陥では
  壊れない。契約の`(:post (< result count))`だけが壊れる。
  Property中心の運用では見つからない欠陥が存在する、という具体例である。
- 契約の初回実行（100 trials、backend default）はpassした。棄却83件、実際の
  呼び出しは17回。棄却数を報告しなければ「100試行が通った」と読める実行が、
  実際には17回しか関数を呼んでいない。§19の懸念は理論上のものではない。
- 試行数を2000に上げて18試行目で反例。縮小結果は
  `VALUE=-1 LOW=-2 HIGH=-1 COUNT=1`、壊れた側は`:postcondition`。
- 修正後、同じseedとdigestで再実行してpass、`reproduction: faithful`。
  Propertyも引き続きpass。

判明した不足：

1. 契約には`:trials` tableがないため、profileでは試行数を上げられない。
   adapter側に明示的な試行数の引数が要る。cl-spec本体では`check-function`の
   `:trials`で足りる。
2. 棄却率が80%を超えるのは、独立に生成した3つの整数に`(< low high)`と
   `(<= low value high)`を課したためである。§19のdependent generatorが
   未実装である限り、この形の契約は試行数で殴るしかない。
3. 反例が「境界1点」である場合、一様生成では到達確率が試行数に線形にしか
   効かない。§46のProperty品質と同じ問題が契約側にもある。

## 73.3 LLM向け有用性の評価

同じ修正課題について、通常のソース・テスト・REPLを使う条件と、
それらにcl-specを追加する条件を比較する。モデル、ツール、時間・試行予算、
初期コードを揃え、複数課題・複数実行でばらつきを記録する。

測定対象：

- 独立した受け入れテストで確認した修正成功率と回帰の発生。
- 修正時間、tool呼び出し数、LLMへ渡す情報量。
- 失敗の再現率、保存反例による修正確認の可否。
- 契約の不当な弱体化、ゼロ件成功、検証不足の見落とし。
- 人間がSpec・generator・Propertyを用意し、保守する負担。

評価用の受け入れ条件は、修正を行うLLMが都合よく変更できない形で管理する。
単一の成功例や生成したPropertyの成功率だけで、開発全体の改善を主張しない。
数値目標は初期実証のbaseline取得後に決める。
