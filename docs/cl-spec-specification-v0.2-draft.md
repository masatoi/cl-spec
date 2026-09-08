# cl-spec 仕様書

**Common Lisp LLM-Oriented Specification & Property Testing Framework**

- 文書バージョン: 0.2-draft
- ステータス: 設計・プロトタイプ前
- 本文書はプロジェクトの継続的な設計成果物としてメンテナンスする。

## 改訂履歴

### 0.2-draft

- Schemata / Malliの内部architecture調査を反映。
- DSL中心からSemantic IR中心のarchitectureへ明確化。
- validator / explainer / generatorをIRから生成するcompiler modelを採用。
- registryをglobal hash-table固定ではなくprotocol化。
- structured explainをprimary representationへ変更。
- Schemataはdependency/forkせず独立実装する方針を明記。
- check-itはbackendとして隔離し、internal APIへの依存を避ける。
- vertical sliceおよび実装順序を更新。

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

可能な限りCommon Lispの型specifierに近い記法を採用する。

ただしCommon Lisp type languageと完全互換にすることは目標としない。

`check-it` もgenerator type specについてCommon Lisp type specと似た構文を採用しているが、同一ではない。

---

# 9.1 Validator / Explainer compiler

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

conditionが発生した場合もfailureとして扱う。

---

# 14. Property Result

Property実行結果は単なるbooleanではなく構造化する。

```lisp
(defclass property-result ()
  ((status ...)
   (property ...)
   (trials ...)
   (seed ...)
   (counterexample ...)
   (shrunk-counterexample ...)
   (condition ...)
   (duration ...)
   (backend ...)))

```

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

LLMが失敗を再現可能であることを必須条件とする。

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

---

# 17. Function Spec

関数仕様は少なくとも、

```text
arguments
return value
relation between args and return
signals

```

を記述できるものとする。

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

## Function spec

局所contractから自動生成するテスト。

## defproperty

ユーザーが意味的性質を明示するテスト。

両者を併用する。

---

# 19. Preconditionの扱い

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

---

# 20. Runtime validation

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

本フレームワーク自体はMCP implementationへ依存させない。

代わりにpublic introspection APIを提供する。

cl-mcp側がそれをtoolとして公開する。

想定API：

```text
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

理想的な利用フロー：

```text
LLM receives task
        ↓
inspect symbol
        ↓
read specs/properties
        ↓
edit code
        ↓
compile
        ↓
run ordinary tests
        ↓
run related properties
        ↓
failure?
   ┌────┴─────┐
  yes         no
   ↓           ↓
minimal     complete
counterexample
   ↓
LLM repair

```

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
ENCODEとDECODEはinverse relationshipを持つ

```

と理解できる。

これはdocstringより強い。

なぜならpropertyは実行可能である。

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

コード変更後に関連propertyだけを高速実行可能になる。

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
(run-properties
 :tag :critical)

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
(:trials
 (:smoke 10)
 (:normal 100)
 (:extended 1000)
 (:stress 100000))

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

全metadataはregistryとSemantic IRから取得可能でなければならない。

避けるべき設計：

```text
macroexpandしなければmetadataが分からない
compiled functionしか残らず意味が読めない
pretty printed stringしか取得できない
```

望ましい設計：

```lisp
(spec-data (find-spec ...))
(property-data (find-property ...))
(function-spec-data (find-function-spec ...))
```

だけでsemantic informationを取得できる。

主要なdefinition objectは元S-expressionとnormalized representationの双方を保持する。

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

初期MVPではsetup/cleanupを省略してもよい。

---

# 41. Stateful property testing

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
:proposed
:reviewed
:trusted
:deprecated

```

などをproperty metadataとして持つことを検討する。

---

# 45. Trust model

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

とする。

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

Framework documentationではproperty設計guideを提供する。

---

# 47. Error taxonomy

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

LLMによる自律実行を考慮するとtimeoutは必須。

```lisp
(run-property
 'foo
 :timeout 5)

```

Property全体、またはtrial単位timeoutを将来的に実装する。

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

cl-spec/test
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

```

---

# 52. MVPでサポートするSpec

```text
Common Lisp type
predicate
AND
OR
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
(sample-spec 'positive-integer)
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

