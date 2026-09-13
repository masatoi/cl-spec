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

この表は2026-09-13時点（main `502a6f2`と本改訂）のスナップショットであり、
実行時のcapability APIではない。直近の現状整理と残課題の優先順位は§73.5を参照する。

| 機能 | 状況 | 現在の利用範囲・制限 |
|---|---|---|
| Semantic IR・normalization・hash-table registry | 実装済み | §7〜9、§37。追加registry backendは将来構想 |
| validation・structured explain | 実装済み | `validp`、`validate`、`explain-data`、`explain` |
| Spec・Propertyのデータ取得 | 実装済み | `spec-data`、`property-data`、`function-spec-data` |
| symbolに関連する登録名の取得 | 実装済み | `semantic-data`。本文・signature・methodsの一括取得ではない |
| check-it generator backend | 実装済み | `generator-for`、`sample`。生成可能範囲はvalidationの対応範囲より狭い |
| Property定義・実行 | 実装済み | `defproperty`、`run-property`、`run-properties`。宣言の構造・重複・予算は登録前に検査する（§4） |
| seed・replay・shrinking | 実装済み | 同一実行条件が前提。整数seedの実装対応は現在SBCLのみ |
| Function Spec | 実装済み（最小範囲） | `defspec-function`、`check-function`、`function-spec-data`。必須・optional・key・rest引数、主値または固定個数の多値。全引数を生成する`(:args-generator NAME)`にも対応。§17〜19、§73.1 D1 |
| Custom generator DSL | 実装済み（最小範囲） | `defgenerator`（引数なしのみ）と`defspec`の`(:generator NAME)`節。パラメータ付きgeneratorは未対応、`defgenerator-for`は提供しない。生成値はspecに照らして再検証しない。ANDが畳み込む連言にgenerator指定がある場合、生成器構築時に`generator-unavailable`で拒否する。AND全体へのgenerator指定は可能 |
| 人間向けdescribeプリンター | 未実装 | `describe-spec`、`describe-property`はstub |
| Instrumentation | 実装済み | 独立system、`:input` / `:output` / `:post` |
| cl-mcp adapter | cl-mcp側に実装 | 本リポジトリには無い。`spec-list`・`spec-symbol`・`spec-describe`・`spec-check`。公開名や想定tool名の存在を利用可能の根拠にしない |
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

`:skipped`は「関数を一度も呼んでいない」であって成功ではない。`:pre`が全入力を
棄却した場合と、`:trials`が0の場合の両方でこれになる。実際に検査された件数は
「試行数 − 棄却数」であり、これが0の実行は`:passed`ではなく`:skipped`として
報告されるので、`:passed`かつ0という状態は存在しない。詳細は§17〜19。

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

## 4.1 DEFPROPERTYの確定構文

> **位置付け:** 実装済み。曖昧な宣言を受理して一部を無視する動作を廃止した。

```lisp
(defproperty name ((variable spec-form) ...)
  "任意のdocstring"
  (:about target-symbol ...)
  (:kind :classification)
  (:tags tag ...)
  (:trials (:smoke 10 :normal 100))
  (:shrink t)
  predicate-form ...)
```

- 名前はNIL・keyword以外のsymbol。
- 引数全体と各bindingは有限proper list。bindingは正確に2要素。
  変数は重複のない束縛可能symbolとし、NIL・T等の定数・keyword・非symbol・
  名前が`&`で始まるsymbolを拒否する。引数なしは許可する。
- 先頭のoptionは`:about`・`:kind`・`:tags`・`:trials`・`:shrink`だけ。
  各optionは1回までで、節自体も有限proper listでなければならない。
- `:kind`・`:trials`・`:shrink`は値を正確に1個取る。例えば`(:kind)`は拒否し、
  `(:kind nil)`は受理する。節自体の省略と明示的NILが異なる値になるという意味ではない。
  `:about`はsymbolの列、`:tags`はtag designatorの列を取り、どちらも空でよい。
- `:trials`は重複しないkeyword profileと非負整数予算のplist。空tableも許可する。
  0は明示的な0試行であり、backend defaultへ読み替えない。
- 本文は最低1形式必要。明示的なNILは偽を返す本文であり、空本文とは違う。
  全bodyが文字列1個ならdocstringではなく本文とする。
- 最初の非option形式で本文が始まり、それ以降はoptionに見えても通常のLispコードとして保持する。
  本文開始前の未知keyword節は拒否する。先頭にkeywordを関数位置として使う特殊なコードを
  意図する場合は`progn`等で明示的に本文を開始する。
- `:shrink`の値は登録時に評価する式のまま維持する。変数や式による指定を禁止しない。

違反はmacroexpansion時の`invalid-property-form`となる。
conditionには問題のformと理由を保持する。既存定義と逆引きindexを変更する前に拒否する。
formはoption節に限らず、名前・binding・本文全体の場合もある。
不正DSL形式のcondition reportは循環参照を表示し、表示する長さと深さを制限する。
`defspec`のoptionsと`defspec-function`のclausesも、走査前に有限proper listを要求する。
spec自体の文法は引き続きnormalizerが検査し、不正なspecには`invalid-spec-form`を通知する。

例えば`((x integer ignored))`や重複する`:trials`は、末尾・後続節を無視せず拒否する。
各option値の意味は従来どおりであり、分類keywordの有限な一覧やtagの新しい型制約は導入しない。
tagの逆引きはEQ比較である。文字列等を内容で照合する保証はなく、安定した照合にはsymbolを使う。
tagの型制限や正規化は§73.5のmetadata検証課題に含む。
`:trials`等の設定は必ず本文より前に置く。本文開始後の`(:trials ...)`は予算設定ではなく
関数呼出しであり、通常は未定義関数のエラーになる。この構文境界は変更しない。
この保証は`defproperty`の宣言parserについてであり、公開CLOS APIで直接作った任意の
`property`を包括的に検証する保証ではない（§73.5）。

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
├── FIELD-SPEC
│   └── PLIST-SPEC
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
plist
instance-of

```

`cons-of` はMVPでは実装しない。§52のMVP対応リストにも含まれておらず、§7のIRクラス階層にも
対応ノードが無い。post-MVPとして扱い、`(tuple ...)` または `(list-of ...)` で代替する。

`list-of`と`vector-of`は要素specに続けて`:min-length`・`:max-length`・`:unique`を
keyword引数として受け取る。`:max-length`は`*`で無制限を表し、省略時は無制限、
`:min-length`の省略時は0、`:unique`の省略時はNILである。値は登録前に検査し、
`:min-length`が`:max-length`を超える場合や未知のoptionを拒否する。

`:unique`は要素をEQLで比較する。長さ違反は`:too-short`・`:too-long`、重複は
`:duplicate-element`として説明し、`:too-short`/`:too-long`は`:minimum-length`または
`:maximum-length`と`:actual-length`を、重複は2個目の要素の`:path`と最初の出現位置
`:first-index`を持つ。制約は生成にも反映し、長さは宣言範囲から抽選し、縮小は
`:min-length`を下回らない。`:unique`の生成は有限な要素domainから重複なしで抽選する。
有限な整数`range`は列挙せず直接samplingするため幅の上限はない。`member`、
`boolean`/`null`、`nullable`、およびこれらの`or`は列挙し、その全体は1000要素までに限る。
列挙できない要素、またはカスタムgeneratorが分布を持つ要素には`generator-unavailable`を
通知する。`:max-length`が0のコレクションは要素specをcompileせず空コレクションを生成する。
無制約の`list-of`/`vector-of`のdigestと`spec-data`は変更しない（制約が宣言された
ノードだけが`:min-length`/`:max-length`/`:unique`を持つ）。

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

# 9.2 フィールド付きplist spec

実装済みの記法：

```lisp
(defspec user-record
  (plist
    (:required (:id integer))
    (:optional (:nickname (nullable string)))
    (:closed t)))
```

`:required`・`:optional`・`:closed`はそれぞれ省略可能で、重複は拒否する。
フィールドは`(:keyword spec)`の2要素で、必須・任意をまたいでキーを重複できない。
`:closed`は明示的なbooleanを1つ取る。既定値NILでは未宣言キーを許可し、
Tでは拒否する。不正宣言は`invalid-spec-form`とし、登録前に拒否する。

値は有限のproper listで、keywordと値の組からなる。同一キーの重複、奇数長、
非keywordキー、dotted/circular listを拒否する。値がNILであることと欠落は区別し、
順序は問わない。`(plist)`は構造が正しいkeyword plistすべてを受理する。

`src/field-spec.lisp`に格納形式非依存の`field-definition`
（key・value-spec・required-p）と`field-spec`（fields・closed-p）を置く。
`plist-spec`がkeywordキーとplistの構造を扱う。子IRの列挙は宣言順である。
内部フィールドのkey表現をkeywordに限定せず、将来のalist/hash-tableが独自の
キー比較規則を持てる境界とする。これらのDSLと共通変換APIは未実装。
共通のfinite field list・field-definition要素・boolean closed flagはfield-specで検査し、
plist-specはkeywordと重複キーの制約を加える。初期化・再初期化の変更前に拒否する。

構造検査は子specの述語より前に行う。explainerのエラーkindは構造不正が
`:not-a-plist`、重複が`:duplicate-key`、必須キー欠落が`:missing-key`、
closedなspecの未宣言キーが`:unknown-key`。値の型違反等は既存のkindを使用する。
フィールドの`:path`はキーを含み、例の`:id`なら`(:id)`となる。
欠落時の`:actual NIL`は値NILの違反とはkindで区別する。
追加の`:field-path`は宣言されたフィールドを選択するキー列であり、Function Specの
failure identityに含める。未知キー・重複キーのエラー位置は入力由来の`:path`だけに置き、
そのキー自身を`:field-path`に含めない。これらが宣言フィールド内の入れ子で起きた場合は、
宣言された親キーだけをidentityに残す。通常のlist/vector要素indexもidentityに加えず、
別の宣言フィールドへの移動と、同じ構造違反を保った入力の縮小を区別する。

plistのexpected descriptorは`:kind`・`:closed`・`:fields`を含む。`:fields`の各要素は
`:key`・`:required`・子の`:expected`を持ち、ORの枝やANDのチェック項目でも
フィールド契約を識別できる。構造違反はANDのdescriptor重複除去で省略せず、kindとpathを表示する。
入力構造の検査で作った索引をフィールド照合と未知キー検出にも再利用する。

`spec-data`は`:closed`と`:fields`を返す。`:fields`の各要素は
`(:key KEY :required BOOLEAN :child-index INDEX)`で、`:children`の子IRを指す。
digestはsource-formだけでなく、この関連付け・closed flagと子specを含む。

check-it backendは必須キーを常に生成し、任意キーは各drawで独立に含めるか決める。
未知キーはopenなspecでも生成しない。縮小では任意キーの削除と値の縮小を行い、
必須キーを保持する。定数値・NILも扱う。任意フィールドを含め、全子specの生成器が
必要であり、未対応の子は`generator-unavailable`となる。空plist、必須フィールドが
定数またはcustom generatorのみのplistの縮小capabilityは`:none`。
任意キーの削除が可能なら`:available`とする。これは縮小成功の保証ではない。

フィールド間制約は既存の`and`・`satisfies`で表現する。
制約solverやAND生成の一般化は導入しない。

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

> **位置付け:** 実装済み（最小範囲）。以下の定義構文・関連付けは実装で確定した形である。
> `defgenerator`は空のlambda-listのみを受け付け、関連付けは`defspec`の`(:generator NAME)`節で行う。
> `defgenerator-for`は提供しない（下の二案のうち節を採用した）。生成値はspecに照らして再検証しない --
> specの外を引くgeneratorは、契約が拒む反例として見えるほうが、guardで隠すより正直である。

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
(defgenerator account-generator ()
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

`run-generated-test`の`options`には非負整数の`:trials`を必ず指定する。
戻り値にも実際の生成試行数`:trials`が必須であり、status・観測・件数の整合性を検証する。
詳細なbackend outcome protocolは§14を参照する。

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
各試行は入力と結果を`trial-observation`として記録する。縮小候補についても同じ経路を使い、
NILによる失敗から例外への移動、および異なるcondition型への移動は拒否する。
通常のproperty本体の内部でどの式が偽になったかまでは判別しない。
warning・通常のsignal・期待するconditionまで一律に失敗とする意味ではない。
Function Specの必須error契約`:signals`は§17に従う。restartを含む拡張規則は未対応。

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
`:trials`は構築時の必須引数であり、非負整数を指定する。欠落を0と推測しない。
追加のreaderは次の通りで、Function Specの結果にも共通する。

- `property-result-failure-evidence`：最初に失敗した試行の観測。
- `property-result-shrunk-evidence`：採用された縮小候補の観測。無ければNIL。
- `property-result-shrunk-outcome`：失敗時は`:used`、`:none`、`:different-failure`。
- `property-result-failure-reason`、`property-result-failure-signature`、
  `property-result-explanation`：採用した観測の理由・署名・戻り値specの説明。
- `property-result-rejected`：生成試行のうち前提条件により棄却された件数。
- `property-result-entity-kind`：`:property`または`:function-spec`。

`trial-observation-*`のreaderからarguments、status、reason、signature、explanation、
condition、condition-report、value、arguments-mutated-pを取得できる。argumentsは
呼び出し前の入力、valueはその呼び出しの返り値である。conditionは実際の条件オブジェクトを
保持し、condition-reportは観測時点の表示文字列を保持する。表示処理が失敗しても証拠は失わない。
引数なしの失敗ではcounterexampleがNILでもfailure-evidenceは存在する。
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

## Backend outcome protocol（実装済み）

`run-generated-test`はPROPERTY-RESULTオブジェクトではなく、次のplistを返す。
呼び出し時のoptionsにも`:trials`（非負整数の予算）が必須である。

```lisp
(:status :failed :trials 1 :rejected 0
 :failure <trial-observation>
 :shrunk-failure <trial-observation-or-nil>
 :shrunk-outcome :used)
```

`:status`と実際の生成件数`:trials`は常に必須。件数は予算以下で、`:passed`は予算全体を
消費した場合だけ返す。`:rejected`の省略値は0であり、縮小中の棄却を数えない。
`:failed`・`:error`には元の`:failure`と`:shrunk-outcome`が必須である。
`:used`の場合だけ`:shrunk-failure`を持ち、入力が元と異なり失敗署名が一致することを要求する。
statusとconditionは採用された観測を指す。失敗のない応答にfailureを付けてはならない。
欠落・矛盾した応答は`invalid-backend-result`として拒否する。旧形式のbackendはこのprotocolへ
移行する必要がある。`observe-trial`で評価し、返った観測をそのまま保存するのが基本経路となる。
失敗の観測は同じ`run-generated-test`呼び出し内で、対象propertyを評価して得たものに限る。
別実行からの流用や直接構築した観測は拒否する。この検証はbackendとのprotocol検証であり、
任意のLispコードを実行できるbackendに対するセキュリティ境界ではない。
生成0件、または全件棄却だった実行はrunnerが`:skipped`にする。

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

実行前のcons・配列（文字列を含む）はコピーして証拠として保持する。対象には生成された
オブジェクト自体を渡し、EQなどの同一性に依存する挙動を変更しない。入力の破壊的変更を
検出した場合はarguments-mutated-pを記録し、変更されたgenerator cacheから縮小を続けない。
任意のCLOSオブジェクトや外部状態のcheckpointは提供しない。
コピーと構造比較は明示的な作業リストを使い、長いリストの長さに比例した制御スタックを使わない。
観測の実行元は実行ごとのidentity tokenで検証し、実行中の全観測を保持する表は持たない。

縮小候補はtargetを呼ぶ前に各引数specで検証する。guardが拒否する値や、文字列generatorの
内部表現である文字リストなど、引数domain外の値を反例として採用しない。
縮小中は元の試行の失敗署名と比較し、一致した候補だけを受理する。shrinkerが最後に返す値が
callbackへ渡した値と異なる場合があるため、最終返り値だけを証拠にはしない。
`:used`は実際に評価して受理した候補があることを表す。候補の入力変更やshrinker内部のerrorで
探索を停止しても、それ以前に採用した観測は保持する。`:different-failure`は異なる失敗や
identity不明、縮小時のerrorにより一致を確認できず、採用した縮小がないことを表す。
`:none`は縮小無効・引数なし・入力変更による停止・domain内の候補なしなどで、
観測済みの縮小を採用していないことを表す。
候補の試行と分類は一度の実行で行うが、通常のshrinking自体は対象を複数回呼ぶ。

本書の「最小反例」は、backendが探索して得た縮小済み反例を指す。
大域的な最小性を保証しない。縮小の完了・予算切れ・中断を区別し、元の失敗理由を保持する
要件は§72.4に定める。概念JSONの`minimal_counterexample`もこの意味で読む。

---

# 17. Function Spec

> **位置付け:** 実装済み（最小範囲）。必須・optional引数と主返り値を検査する。
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
| lambda list | 必須引数と`&optional`・`&key`・`&rest`を受け付ける。その他のlambda-list keywordは拒否する。単独で書かれた場合だけでなく、`(&optional integer)`のように引数名の位置に現れた場合も拒否する |
| 引数名 | 束縛可能なsymbolのみ。定数（`t`、`pi`等）と、`:post`が戻り値に使う`RESULT`と同じsymbolは拒否する。述語はこれらの名前を並べたlambdaにコンパイルされるため |
| clauseの形 | 真リストのみ。`(:pre . y)`は`(and . y)`へ展開され、formですらなくなる |
| 多値 | `(:returns (values SPEC...))`で固定個数と各値を検査する。通常の`:returns SPEC`は主返り値のみ（0値ならNIL）。`:post-values (NAME...)`で各値を明示束縛する |
| `(:returns nil)` | 拒否する。型指定子`nil`は要素を持たない型なので、この契約は`nil`を含むあらゆる戻り値を違反として報告する。意図した型は`null`である |
| pre/postの評価順 | `:pre`は呼び出し前、引数のみを見る。`:post`は`:returns`の検査を通過したあと、引数と`result`を見る |
| 全引数generator | `(:args-generator NAME)`で登録済み`defgenerator`を指定可能。引数順のproper listを一回で生成し、個数と各specを検証した後に`:pre`を適用する |
| `result`の束縛 | 契約自身のpackageで`RESULT`が指すsymbolを、`:post`に現れかつ引数名でない場合に束縛する。`:post`に現れる`RESULT`という名前のsymbolがそれと一致しない場合は拒否する。マクロは`:post`の文面が読まれたpackageを見られないので、この解決は代理であり、外した場合に黙って別の契約をコンパイルするより拒否する。`:pre`が戻り値の名前に触れる形式も拒否する（引数名である場合を除く） |
| 実行前の可変値の参照 | pre-stateを参照するDSLは未提供。観測には実行前のcons・配列のコピーを保存するが、任意の状態の復元は行わない |
| signals | `(:signals SPEC)`で、targetから外へ送出されるerrorがSPECを満たすことを要求する。正常復帰は失敗。`:returns`・`:post`とは併用不可 |
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
- `:argument-generator`はgenerator名のsymbolまたは`nil`。`nil`は独立生成を表す。
  generatorの登録は実行時のregistryで解決し、前方定義を許す。
  `function-spec-argument-generator`はその名前を返し、`function-spec-argument-schema`は
  現在の引数specとgenerator名からtuple specを導出する。schemaは保存しないため、
  `reinitialize-instance`後にも古い引数宣言を使い続けない。

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

## 17.1 必須expected-condition契約

`(:signals SPEC)`は一つの非NIL specを取り、targetから外へ送出されるerror conditionを
既存DSLで検査する。例えば`(:signals (and (type spec-violation) (satisfies detailed-error-p)))`。
ユーザー定義condition型は`type`または`instance-of`で明示し、裸のsymbolは登録specへの参照となる。
conditionのslot検査には名前付きの`satisfies`述語を用いる。

- `:pre`が入力を拒否した場合はtargetを呼ばず、従来どおりrejectedとして扱う。
- 期待specを満たすerrorなら試行成功。成功を失敗conditionとして保存しない。
- 正常復帰は`:failed / :missing-condition`。explanationには`:expected`を保存する。
- 不一致のerrorは`:error / :condition-spec`。実際のconditionと`explain-data`を保存する。
- `program-error`・`undefined-function`とそのsubclassは、`:signals`の有無や内容に
  関わらず`:error / :condition`として保持する。明示的にその型を指定しても成功にしない。
  不正な引数個数や存在しない関数の呼び出しを、広い期待specで検証済みにしないためである。
- `:signals`が無い契約でのその他のtarget errorも従来どおり`:error / :condition`。
- warning・非errorのsignalは通常のCLの動作を保ち、この契約を満たさない。
  target内部で処理されて外へ出ないerrorも対象外。
- specの解決・検査はtarget捕捉境界の外で行う。述語のerrorは既存explainerの
  `:predicate-errored`診断となり、不一致として扱う。未定義述語や引数個数の誤りは
  従来どおり伝播し、期待errorとして成功扱いしない。

`:returns`と`:post`（空節も含む）との併用、重複、空の`:signals`、明示NILは
`invalid-function-spec-form`で拒否する。`function-spec`の`:signal-spec`は正規化して保持し、
`function-spec-signal-spec`で読み出す。直接構築・再初期化でもreturn/postとの排他を検査し、
拒否した再初期化は元の状態へ戻す。`:signal-spec nil`は通常の返り値契約を表す。

`function-spec-data`は`:signals`にspec-dataまたはNILを投影する。
宣言digestは期待specと登録された参照先を含む。縮小では、正常復帰による欠落、
condition不一致、従来の返り値違反を別の失敗として扱う。不一致同士でもcondition型と
入力値由来の部分を除いたexplanation形状が一致する場合だけ縮小を採用する。

runtime instrumentationはこの契約に未対応。`instrument-function`は
`unsupported-instrumentation-target`（reason `:expected-condition-contract`）で拒否し、
fdefinitionを変更しない。capabilityのinstrumentationは`:unavailable`となる。
`:input`のみ・空scopeでも同じ制限を適用する。既存wrapperの契約を`:signals`へ変更した場合は
明示的に`uninstrument-function`で解除する。再初期化は捕捉済みの検査を変更せず、
拒否された再インストールも既存wrapperを保持する（§20のlifecycleと同じ）。

statusは正常復帰かerror outcomeかを区別する。契約不一致と契約自身の異常の区別には
`failure-reason`（`:condition-spec`と`:contract-error`）を使う。
欠落時の`:expected`ではAND・OR・NULLABLEも子specのdescriptorを保持する。

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
  ことに注意する。縮小は候補の試行として関数を呼ぶが、分類用の追加呼び出しは行わない。
- `function-check-result-failure-reason`：契約のどちら側が壊れたか。
  `:return-spec`、`:postcondition`、`:condition`、`:contract-error`、または`nil`。
  `:contract-error`はどちらも壊れていない場合で、契約自身の述語やspecが、関数が
  返した値の上で送出したことを意味する。責任はどちら側にもあり得る。
  `undefined-function`と`program-error`だけは伝播させる。存在しない述語、
  未登録のspec名、arityの合わない述語は構造的で、あらゆる入力で送出するため、
  失う反例が無く、報告すべきは壊れたspecそのものである。
  `:precondition`は存在しない。`:pre`が棄却した入力に対して試行の述語は真を
  返すので、棄却された入力が失敗の理由になることはない。
- `function-check-result-explanation`：`:return-spec`失敗時の`explain-data`。
- `function-check-result-shrunk-outcome`：縮小候補がどうなったか（`:used` / `:none` /
  `:different-failure`）。`shrunk-counterexample`がNILである理由を区別するため。
- `function-check-result-budget`：その実行に許された試行数。`trials`は実行が
  止まった位置であって許された数ではないため、両方を記録する。
  `:seed`にresultを渡した再実行は、seedとともにこの予算も引き継ぐ。
- `function-check-result-source-form`：実行時点の契約のsource form。実行は契約を
  同一性で保持するが、resultは名前でしか指していなかった。名前の再登録（reload、
  編集）があると、resultは「Fはpassした」と言い続けるのに、いまFの下にある契約は
  Fが破るものになり得る。

readerの前置は2種類ある。propertyの実行にもあるもの（status、trials、seed、
profile、両方の反例、condition、elapsed）は`property-result-`で読み、契約の実行が
追加するものだけが`function-check-result-`である。`function-check-result-status`は
存在せず、しかもreader errorになるので、それを含むform全体が読めなくなる。

関数を一度も呼ばなかった実行のstatusは`:skipped`であり、`:passed`ではない。
`:pre`が生成入力をすべて棄却した場合と、`:trials`が0の場合の両方が該当する。
関数を一度も呼んでいない実行を成功として報告しない（§73.3のゼロ件成功）。

`failure-reason`は試行のその場で求め、入力・返り値・condition・説明と一緒に観測へ保存する。
targetを再実行する分類処理は無い。戻り値のspec検査も`explain-data`を一度だけ呼び、
`validp`の後で再び説明を作ることによるSATISFIES述語の二重実行を避ける。

targetが送出したerrorは`:condition`、契約の述語側のerrorは`:contract-error`として区別する。
ただし契約側の`undefined-function`・`program-error`は初期試行では伝播する。
縮小時にのみ現れた構造的エラーは候補の拒否として扱い、既存の証拠を失わない。

縮小候補は**元の試行の失敗署名と一致**する場合だけ受理する。property側も同じ仕組みを使う。
Function Specではcondition型に加え、戻り値specの失敗形状、タプル位置、`:post`の形式位置を
比較する。`:return-spec`と`:postcondition`間を同じreturn-value失敗クラスとする既存規則は維持する。
ただし手組みの`function-spec`でpost述語が通常の1値だけを返す場合、失敗した形式は不明である。
この場合は節間の移動も含めてidentityの一致を認めず、元の反例を保持する。
形式別の縮小を可能にする述語は、失敗時に
`(values nil index :cl-spec-post-form-failure)`を返す。`index`は`:postconditions`内の
0始まりの有効な形式位置でなければならず、欠落・範囲外の番号はidentity不明として扱う。
既存の1値述語は引き続き契約の成否判定に使える。保存された形式から述語を再評価・導出はしない。
status・failure-reason・condition・縮小反例は採用した一つの観測から作り、元の観測も残す。
状態を持つtargetについても当時の所見を保持するが、後の再実行が同じ結果になるとは保証しない。

## Function spec

局所contractから自動生成するテスト。

## defproperty

ユーザーが意味的性質を明示するテスト。

両者を併用する。

---

# 19. Preconditionの扱い

> **位置付け:** 一部実装。棄却と件数の報告、function-level argument-set generatorは実装済み。
> 個々の引数から別の引数を参照するdependent DSLや制約solverは未実装。

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

現在は、関数全体にcustom generatorを指定して引数間の制約を生成側へ反映できる。

```lisp
(defgenerator bounded-arguments ()
  (let* ((low (random 10))
         (high (+ low 1 (random 10)))
         (value (+ low (random (1+ (- high low))))))
    (list low high value)))

(defspec-function bounded-value
  (:args (low (range integer 0 20))
         (high (range integer 0 20))
         (value (range integer 0 20)))
  (:args-generator bounded-arguments)
  (:pre (< low high) (<= low value high))
  (:returns integer))
```

`(:args-generator NAME)`を省略した場合は従来の独立生成である。内部では全引数を一つの
tuple schemaとしてcompileする。backendは`property-argument-schema`を使い、
Function Specのadapterは`function-spec-argument-schema`を返す。
`function-spec-data`の`:argument-generator`と`:argument-schema`からこの指定を読める。
schemaは通常のspec-dataで、generator未指定時にも両キーを返す。

generatorは引数なしで一回呼ばれ、引数順のproper listを返す（引数なしの関数では`nil`）。
個数・型・各specの違反、検証中のcons/配列の変更は`invalid-generated-arguments`となる。
そのreaderは`invalid-generated-arguments-generator`、`-value`、`-reason`で、
検証前の生成値を確認できる。targetや`:pre`は呼ばれず、関数の反例として報告しない。
generator自身のerrorは伝播し、有効な値が出るまで再試行する隠れたloopはない。
この検証は全引数generatorの規則であり、§11の単一spec custom generatorの規則とは異なる。

有効な引数でも`:pre`を満たさなければ棄却し、その件数を結果に載せる。
seedは通常の実行と同じrandom stateに適用されるため、generatorがそのstateを使い、
外部状態に依存しなければ入力列を再現できる。`defgenerator`は省略可能な先頭節
`(:shrink (arguments) body...)`をdocstringの後、draw bodyの前に受け付ける。
CLOSでは`:shrinker`に一引数関数またはNILを指定し、`custom-generator-shrinker`で読む。
既存の引数なしdraw bodyは変わらない。sourceがある定義のshrinker更新は、sourceとdraw関数を
同時に更新する。shrinkerの有無とsourceをdigestに反映し、省略した既存定義のdigestは維持する。

shrinkerはコピーされた現在の全引数listを受け、優先順の有限proper listとして候補を返す。
候補は全引数schema、`:pre`、targetの順に調べ、入力変更がなく元の失敗署名に一致する候補だけを
採用する。採用候補から探索を再開する。訪問済み入力を再実行せず、引数ごとの独立縮小を併用しない。
省略時は元の観測を保持して`:shrunk-outcome :none`となる。

custom全引数縮小では`:options '(:shrink-budget N)`で候補予算を指定する（既定100、整数0〜100000）。
生成前に予算を検証する。候補batch全体のproper-list検査も残予算内で行い、超過batchは実行しない。
候補数には重複・schema不適合・pre棄却も含む。生成試行数`:trials`と区別し、
`property-result-shrink-report` / `result-data`の`:shrink-report`へ
`(:candidates N :budget B :termination KEYWORD)`を保存する。
artifact v1には同名の省略可能なmetadataを追加し、旧recordの欠落は`:not-collected`と解釈する。
縮小を観測しない旧backendにも同じ値を用いる。

候補列の不正、shrinker error、検出したcons/配列変更は探索を停止し、元の証拠とそれ以前の採用証拠を
保持する。任意のユーザーコード自体の停止・外部状態復元・大域的最小性は保証しない。
再現には決定的候補順序が必要。nested custom value generatorの縮小は従来のno-opを維持する。

上記3変数の比較テスト（100生成、seed 42）では、独立生成は80棄却・20回の関数検査、
全引数generatorは0棄却・100回の関数検査となった。これはこの生成分布での実測であり、
一般にcustom generatorが`:pre`を満たす保証ではない。

---

# 20. Runtime validation

> **位置付け:** 実装済み。required/optional positional arguments・keywordと主返り値の契約を対象とする。

`validp`はboolean、`validate`は有効な値または構造化`spec-violation`を返す。
関数の呼び出し時検査は独立system `cl-spec/instrument`を明示的にloadして有効化する。
coreのみのloadでは関数定義を書き換えるmoduleもgenerator backendもloadしない。

```lisp
(asdf:load-system :cl-spec/instrument)
(cl-spec/instrument:instrument-function 'transfer
  :registry cl-spec:*registry*
  :scopes '(:input :output :post))
(cl-spec/instrument:instrumented-function-p 'transfer)
(cl-spec/instrument:uninstrument-function 'transfer)
```

公開packageは`cl-spec/src/instrument`、nicknameは`cl-spec/instrument`。
`instrument-function`はNAMEを返し、同じ名前への再適用はラッパーを重ねず検査を更新する。
`(instrument-function name registry)`も利用できる。位置引数・`:registry`ともNILは既定registryを表す。

| scope | 検査内容 | 実行時点 |
|---|---|---|
| `:input` | 引数個数、各引数spec、`:pre` | target実行前 |
| `:output` | 主返り値または固定多値のspecと個数 | targetが正常に返った後 |
| `:post` | 主返り値または明示束縛した各値と引数の事後条件 | output検査の後 |

`:args`はtargetのlambda listのprefixではなく、許容する全引数を定義する。
`(:args (a integer))`なら、targetが`&optional`・`&rest`・`&key`を持っていても
契約が許すのは1引数の呼び出しだけである。追加引数を許す場合はoptional/key/rest宣言を指定する。

既定は全scope。部分集合・空listを指定できる。不明なscope・proper list以外は
`type-error`で拒否し、既存の関数定義を変更しない。無効scopeの検査はコンパイルも実行もしない。
targetは一度だけ実行し、正常時は全multiple valuesをそのまま返す。
通常の返り値契約は主値のみ（0値ならNIL）、明示多値契約は全値と個数を検査する。
target自身のconditionはそのまま伝播する。
pre predicateの`spec-violation`は`check-function`と同じ入力refusalとして扱い、
`:input / :precondition`の`instrumentation-violation`へ変換する。
preのその他のerror、およびpostのerrorはそのconditionを伝播する。
引数・戻り値specのpredicate errorは通常のexplain/validateと同じ規則で扱う。

違反は`instrumentation-violation`（`spec-violation`のsubtype）。
`instrumentation-violation-function`、`-scope`、`-reason`で対象と分類を読み出す。
reasonは`:arity`、`:argument-spec`、`:precondition`、`:return-spec`、`:postcondition`。
既存の`spec-violation-spec/value/path/errors`も利用できる。
`:spec`は実際の引数・戻り値のIR、arityでは引数tuple、pre/postでは合成したpredicate spec。
preの`:value`は引数list、postの`:value`は通常`(primary-value . arguments)`、
`:post-values`では`(returned-values-list . arguments)`とし、
それぞれのpredicate specの入力と一致させる。関数名は専用のfunction readerに保持する。
errorsには`error-datum`を使い、値は`:actual`、kindは`:wrong-length`や`:predicate-failed`など
既存explainerの語彙で表す。scope・reasonはconditionの専用readerで区別する。
pathのprefixは`(:args parameter)`、`(:pre)`、`(:returns)`、`(:post)`。
DSLで識別できるpost形式は`(:post zero-based-index)`となる。
引数・戻り値のerrorsはexplainerの構造化エラーを保持し、分類のために述語を再実行しない。

インストール時の契約の引数名・直接のspec検査・pre/post関数を保持する。
契約を再定義したら再インストールする。名前によるspec参照は既存explainerと同じく、
選択したregistryから呼び出しごとに解決する。postにはtargetによる変更後の引数を渡す
（`check-function`と同じ意味論）。generatorと`:args-generator`は使用しない。

`instrumented-function-p`は現在のfdefinitionと自分のwrapperの同一性を検査し、
staleな内部記録を除去する。外部の再定義を自動検知するportable hookは無いため、
再定義後は状態queryまたは解除を行い、保持している元closureを解放する。
解除はwrapperが現在も有効な場合のみ元関数を復元してTを返す。
未登録・再定義済み・fmakunbound済みならNILを返し、内部記録だけを除去する。
再定義後の再インストールは新しい関数を対象にする。

対象はCOMMON-LISP package以外のsymbolで命名された通常関数に限る。
未知の契約は`unknown-function-spec`、未定義関数は既存の`unbound-target`。
macro・special operator・generic function・COMMON-LISPの関数は
`unsupported-instrumentation-target`で拒否する（`cl-spec-error`と`program-error`のsubtype）。
`unsupported-instrumentation-target-name`と`-reason`で対象と理由を取得できる。
既に保存されたfunction object、lexical function、inline展開済み呼び出しは捕捉できない。
並行実行時のインストール・解除・関数再定義は呼び出し側が直列化する。
productionでのoverheadを避ける場合は有効化しない。

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

> **位置付け:** 一部実装。semantic-dataとcl-mcp側のspec adapterは実装済み。
> 下の長い想定API一覧全体が実装済みという意味ではない。

本フレームワーク自体はMCP implementationへ依存させない。

代わりにpublic introspection APIを提供する。

cl-mcp側は`spec-list`・`spec-symbol`・`spec-describe`・`spec-check`を公開している。
`spec-symbol`がruntime情報とsemantic-dataの関連登録名をjoinし、定義本文と検査は
describe/checkで取得する。cl-mcp PR #154のversioned metadata投影もmainへマージ済み。
coreのschema versionと外部JSON schema versionの境界は§38.1を参照する。

以下の`describe_symbol`や個別操作名は設計上の概念であり、現行tool名を列挙したものではない。

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

> **位置付け:** 設計方針＋一部実装。cl-mcpのspec-symbolがruntime情報と登録名をjoinし、
> spec-describeが定義本文を返す。下の情報すべてを1つの応答に集める保証ではない。

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

> **位置付け:** 実装済み。spec-data・property-data・function-spec-data・semantic-dataと、
> definition/resultの共通メタデータを提供する。外部JSONの変換はadapterが担当する。

全metadataはregistryとSemantic IRから取得可能でなければならない。

避けるべき設計：

```text
macroexpandしなければmetadataが分からない
compiled functionしか残らず意味が読めない
pretty printed stringしか取得できない
```

公開API（登録名またはdefinition objectを受け取る）：

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

## 38.1 Agent-facing schema v1

`schema-info`はLisp plist protocolのversion・必須メタデータ・列挙値・digestの範囲を返す。
`spec-data`、`property-data`、`function-spec-data`の各definition recordと、
`result-data`のresult recordは次のキーを必ず持つ。メタデータは公開APIが返すルートrecordに
集約する。`:children`・引数・戻り値・argument-schema内のspecは`:entity-kind :spec`を持つ
通常のIR投影であり、独立したdigest計算やbackend probeは行わない。

| キー | v1の意味 |
|---|---|
| `:schema-version` | 整数`1`。Lisp protocolのversion |
| `:record-kind` | `:definition`または`:result` |
| `:entity-kind` | `:spec`、`:property`、`:function-spec`。名前のnamespaceを区別 |
| `:definition-digest` | `fnv1a64-v1:`で始まる文字列、または比較不能を表す`NIL` |
| `:definition-digest-complete` | 保存された宣言と登録依存先を全て表現できた場合`T`、他は`NIL` |
| `:definition-digest-covers` | `:declaration-and-registered-dependencies` |
| `:capabilities` | `:generation`、`:shrinking`、`:instrumentation`のplist |

既存の`:kind`を変更せず保持する。`:entity-type`などの別名は追加しない。
consumerは未知のキーを無視し、未知のversionを既知のschemaとして解釈しない。
v1の必須キーで`NIL`は「欠落」の代用ではなく、上表に定義した値である。
versionの無い旧recordは旧protocolとして扱う。新しい省略可能キーの追加はversionを維持し、
既存キーの意味や型を非互換に変更する場合はversionを上げる。

省略可能な追加キー`:digest-omissions`は比較不能の理由、`:digest-exclusions`は意図した対象範囲外を
表す。新しいdefinition recordは両方を持つが、旧v1 recordに存在しない場合は「未収集」と解釈し、
既知の空リストと同一視しない。

### 定義識別

`definition-digest`はdefinition object、または`(definition-digest name :entity-kind kind
:registry registry)`を受け取り、`(values digest complete-p omissions)`を返す。
先頭2値の意味と完全なdigestのbytesは従来どおりである。
同名のspec/property/function-specは独立したnamespaceである。
`definition-metadata`はspec・property・function-spec objectから上表のメタデータを返す。
custom-generatorはdigestの依存先としては扱うが、v1の独立したmetadata recordではない。
非対応objectをmetadataへ渡すと`type-error`、名前のdigestで`:entity-kind`を省略・誤指定しても
`type-error`となる。欠落した登録先は`NIL/NIL`。拡張の記述method内のプログラムエラーは伝播し、
比較不能へ黙って変換しない。

omissionsは`(:kind KIND :path PATH :target SYMBOL-OR-NIL :reason REASON)`のリストである。
kindは`:unresolved-reference`・`:opaque-definition`・`:missing-source`・`:opaque-value`・
`:uninterned-symbol`・`:resource-limit`。同じ対象・kind・reasonは最初の経路で一度記録し、
独立した欠落は走査上限内でまとめて返す。経路は安定した走査番号を使い、参照先は
`(:definitions ID :links KIND NAME)`、childは`(:definitions ID :children INDEX)`、不透明値は
`:declarations`以下の位置index列で示す。上限に達した場合は網羅性を主張せず、上限の理由を残す。

digestは保存されたsource form・正規化IR・説明文・documentation・tags・宣言metadataを基にする。
標準IRの制約を全てslotで表現できる場合は、元source formが無くても完全な記述となる。
参照されたspecと登録された
custom generatorのsource formを推移的に含む。全引数generatorも対象であり、呼び出し側の宣言を
変えずにgeneratorを再定義した場合もdigestが変わる。登録先を解決できない場合、custom-specの
ように標準記述では実装を表せない場合、関数述語だけでsource formの無いproperty/generator等は
`NIL/NIL`を返す。CLOSから与えたsource formは著者の宣言であり、実行closureとの同一性を証明しない。
標準クラスの未知のsubclassも既定では比較不能とする。拡張は`definition-description`を特殊化し、
宣言data・順序付きchild definitions・`(kind . name)`形式のregistry links・完全性の4値を返す。
独自の制約スロットと拡張種別を宣言dataに含め、実行コードを呼ばずに記述する責任を持つ。

対象関数・helper関数の実装、closureの捕捉値、外部状態、source location、backendや実行時optionsは
digestに含めない。`:definition-digest-complete T`はこの限定された範囲の完全性であり、実装が同じ、
契約が正しい、あるいはseedから同じ実行を再現できるという証明ではない。
`:digest-exclusions`は`(:target-implementation :helper-implementations :captured-state
:external-state :source-location :backend)`を返す。この意図した除外はomissionではなく、完全性を
`NIL`に変えない。

v1はpackage-qualified symbol・整数・有理数・浮動小数点数・文字・文字列・cons・配列をタグ付きで
符号化する。cons/配列の共有と循環は参照番号で表す。printer設定やユーザーpretty printerに依存せず、
各character codeを4個のlittle-endian octetとしてFNV-1a 64-bitに入力する。暗号学的hashではない。
不透明なオブジェクト、非interned symbol、移植可能に符号化できないNaN/無限大は比較不能。
definition objectは10,000個まで、符号化は
100,000ノード・1,000,000文字・CAR/配列の入れ子128段まで。長いCDR列は反復処理する。
整数のbit長は65,536まで、配列要素数は100,000まで。上限超過も`NIL/NIL`とし、切り詰めたdigestは返さない。
異なるLisp実装での浮動小数点型・array element type等の一致は保証しない。

### Capabilityと結果

backend拡張用の`backend-capabilities`は`backend spec &key registry`を受け取る。
backend無しは`:generation :unavailable :shrinking :unavailable`、query未実装のbackendは
両方`:unknown`。check-itはgeneratorの構築を試み、成功を`:available`、構築エラーを`:unavailable`
として返す。値を生成せず、custom generator・対象関数・SATISFIES述語を実行しない。
生成成功や契約を満たすdrawの存在を保証するqueryではない。

縮小を無効化したproperty、空tuple、rootがshrinkerを持たないcustom generator（参照経由を含む）、tuple/mappingの
全要素に縮小戦略が無い場合は`:shrinking :none`。listは要素がcustomでも長さを縮小できる。
他の`:available`は縮小戦略の存在だけを意味し、要素ごとの縮小可能性や
必ず有効な縮小候補が得られることを保証しない。`:instrumentation`はcoreのみでは`:unavailable`。
`cl-spec/instrument`をloadすると、対応する通常関数のfunction-specに対して`:available`となる。
spec・property・未定義関数・非対応targetには`:unavailable`を返す。
これは有効化状態ではなく利用可能性であり、現在の有効化状態は`instrumented-function-p`で確認する。
capabilityは現在のbackend・任意module・targetに依存するがdigestには含めない。
捕捉済みmetadataのない手組みresultでは、instrumentationを含む全capabilityを`:unknown`とする。

`run-property`と`check-function`は生成開始前に定義のメタデータを捕捉する。
capability probe用の捨てるgeneratorは構築せず、backendが実行用generatorの構築時に捕捉した
`:capabilities`をoutcomeへ任意で返す。`:generation`と`:shrinking`の有効な列挙値が必須であり、
不正なreportは`invalid-backend-result`となる。未報告のbackendは結果で`:unknown`となる。
`definition-metadata`の`:capabilities`引数はこのprobeを省略するための明示的なreport指定である。
instrumentationは別systemの責務なので、generator backendのreportでは有効化されない。
`property-result-schema-metadata`と`property-result-budget`で保存値を読める。
`result-data`は保存したメタデータと`:name`、`:status`、必須の`:trials`、`:budget`、`:rejected`、
`:seed`、`:profile`、`:elapsed`、`:counterexample`、`:shrunk-counterexample`、`:shrunk-outcome`、
`:failure`、`:shrunk-failure`を返す。failureは捕捉済みの引数・status・reason・signature・explanation・
value・condition-reportを持つ。失敗の無い箇所は`NIL`。condition objectの代わりに捕捉済みreportを返す。
返すcons/配列はsnapshotされる。これはconsumerによる返却dataの変更から保存済み証拠を保護するためで、
任意のオブジェクトをJSON化したり復元可能にしたりするAPIではない。
`:trials`の型は`:record-kind`に従う。propertyのdefinitionではprofile table、resultでは実行件数であり、
互換性を維持するため既存キーを改名しない。Function Specのbudget readerは共通resultのslotを読む。
実行後にregistryを変更しても過去のresultのdigest・omissions・exclusionsは変わらない。
`:options`と`:provenance`も実行前に捕捉する。provenance内の`:collection-states`は各fieldについて
`:known`（収集済み）、`:unknown`（収集を試みたが不明）、`:not-collected`（未収集）を区別する。
未指定のtarget revisionは互換性のため値を`:unknown`とし、collection stateを`:not-collected`とする。
手組みresultに保存メタデータが無ければ
digestは明示的に比較不能となり、budgetは不明なら`NIL`となる。
実行途中に著者が依存定義や外部状態を変更することをfreezeする機能ではない。

cl-mcp adapterは既存のJSON `schema_version`と別に、describe/checkの`core_schema`へこの
メタデータを投影する。新coreでは捕捉済みresultのdigestを優先する。不完全・未対応versionを旧方式で
hashし直して「一致」にしない。versionを持たない旧cl-specのみ従来のadapter digestへfallbackする。
JSONの型表現、可逆なreplay artifact、値の復元は引き続き別protocolの課題である（§73.1 D3/D7）。

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
register-generator
find-generator
list-generators
custom-generator
custom-generator-name
custom-generator-function
custom-generator-documentation
custom-generator-source-form
custom-generator-source-location
spec-generator-name
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
現在の`defspec`は名前とSpec formに加えてoption節を受け付け、§11の`(:generator NAME)`を
実装している。他のoption節は拒否される。

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

## 68.1 実行可能な自己仕様

`cl-spec/specs`を読み込むと、`specs.lisp`の`defspec`・`defspec-function`・
`defproperty`・`defgenerator`が現在のregistryへ登録される。
通常のcore読み込みからは分離し、Rove・check-it・instrumentationには依存しない。
生成検査の実行時だけbackendを別途読み込む。関数の自動instrumentationは行わない。
registryを消去・交換した場合は`cl-spec/specs:register-specifications`で再登録できる。

| 記述対象 | 実行可能な保証 |
|---|---|
| `validp` | 解決可能なspecと値からbooleanを返す |
| `validate` | 正常入力で同一の値を返す。拒否時の条件・errorsの一致はPropertyで検査 |
| `explain-data` | 必須field、valid/errorsの整合性、対象値の同一性 |
| `compile-validator` / `compile-explainer` | spec IRから関数を返す |
| `spec-data` | v1 definition envelope、digestの完全性とomissionの整合性、kind・source-formの保持 |
| `definition-digest` | keyword registryを省略・指定した定義のdigest主値を検査 |
| `find-spec` | optional registryの省略時は現在のregistry、指定時はそのregistryから検索 |
| `trial-observation-outcome` | 未収集、returned全値、signaled条件診断を表すdata |
| `custom-generator-shrinker` | generatorの縮小関数またはNILを返す |
| digest詳細 | 第3戻り値とmetadataのomissionsの一致。意図したexclusionsは完全性を損なわない |
| `semantic-data` | 対象symbolと関連Propertyの保持 |
| 正規化 | IR再正規化の同一性、source-formの保持。不正DSLの有限例には`invalid-spec-form`と非空reasonを要求 |
| 検証の意味論 | compiled validator・validp・explainの一致、AND/OR/NOTの真理条件 |
| `schema-info` / `make-hash-table-registry` | v1 schema metadataの必須keyと、新規registryが空であること |
| `function-spec-data` / `property-data` / `definition-description` | v1 envelopeと宣言projectionの必須key |
| `property-call-arguments-p` / `property-named-arguments` | 生の呼出し形と束縛へのprojection |
| `property-argument-schema` / `function-spec-argument-schema` | 引数schemaがSemantic IRのspecオブジェクトであること |
| `result-data` | v1 result envelopeの必須keyとstatus |
| `make-counterexample-artifact` / `recheck-counterexample` | 失敗resultからartifactを作り、recheck recordを返す |
| `observation-failure-p` / `failure-identities-match-p` | 失敗観測の判定とfailure identityの反射性 |
| registry往復 | `register-*`→`find-*`の同一性、`list-*`の含有、逆引きindexの更新、`clear-registry`の空化 |
| `explain` / `compile-explainer` | 描画とcompiled explainerが`explain-data`と一致 |
| DSL網羅 | MEMBER/VECTOR-OF/PLISTの真理条件、field errorのpath、surface macroの不正宣言拒否 |
| コレクション制約 | LIST-OF/VECTOR-OFの長さ・一意性の真理条件と`:too-short`/`:too-long`/`:duplicate-element` |
| runner再利用 | seedからのreplay一致、artifactのserialize/deserialize往復 |
| instrumentation | status形状、`instrumented-function-p`/`uninstrument-function`、install/uninstall往復と未契約拒否 |

`cl-spec/specs:contract-names`と`property-names`が対象名を返す。
`function-spec-data`・`property-data`・`properties-for`を通して、cl-mcp等からも
人間向け文書の解析なしに参照できる。Propertyには`:cl-spec-self` tagを付ける。
これは本文の設計意図・非機能要件を置き換えるものではなく、検査可能な部分の一次記述である。

生成器は整数・文字列・NIL・T・list・vectorの値と、type・range・AND・OR・NOT・
nullable・list-of・tupleの有限DSL例を生成する。公開契約の入力domainをこの標本集合だけに
狭めるものではない。正規化Property自体の引数domainにはこの有限集合を明記し、不正DSLの
正規化成功まで主張しない。`validate`の正常系は引数集合generatorで構築し、rejectに予算を費やさない。
この自己仕様のcustom generatorにはshrinkerを指定していないため、失敗は元の反例を保持する。
explainとdefinition envelopeの構造は§9.2のplist DSLで記述し、必須キー・値specを
introspectionへ公開する。valid/errorsの関係のみLisp述語に残す。

通常profileは各Property 50試行、smokeは10試行。
`tests/self-specs-test.lisp`は独立registryで再登録・構造化照会・不整合データの拒否を検査し、
27関数契約と22 Propertyをseed 1・42・2026、各50試行で実行する。
任意のinstrumentation自己契約(status、`instrumented-function-p`、`uninstrument-function`と
install/uninstall往復・未契約拒否の2 Property)は別途登録し、専用テストで実行する。
既存の`tests/self-properties-test.lisp`の生成・registry・replay検査も継続する。

keyword optionを指定した呼出し(`:registry`、`:state-policy`)、組み込み`hash-table-registry`、
result/artifactの基本envelope、instrumentationの基本protocolは取り込み済みである。
残る記述範囲は、すべてのkeyword option組合せ、独自のregistry/backend実装、`defspec`自身の不正form、
shrink候補生成の全過程、未実装の`describe-*`である。
不正DSLの有限例は`:signals`によるFunction SpecとmacroexpansionのPropertyで表現する。
`validate`の正常系契約は維持し、拒否とexplain-dataの関係は引き続きPropertyで記述する。
追加APIの仕様を実装する際は、このbundleへ契約またはPropertyを追加し、対象名一覧と検査を更新する。

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
coreの`schema-info`・definition/resultの`:capabilities`と、adapterの`core_schema`投影は
§38.1で確定済み。MCP全操作の可否・実行制限を統一的に列挙するprotocolと、
任意値の可逆な外部表現は引き続きD7の残課題である。

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

| ID | 決定・実装済み | 残る判断・受け入れ条件 | 関連節 |
|---|---|---|---|
| D1 | required/optional/key/rest引数・主返り値/固定多値・pre/post/post-values、必須errorのsignals契約、全引数generator、runtime scope | signalsの非error／選択的outcome・実行前状態・optional/rest返り値は拡張時に決める | §17〜21 |
| D2 | statusとreason、必須trials、budget・棄却数、0件／全件棄却のskip、adapterの検証不足集計 | 実行環境・入力coverageの未知情報、fixture／timeout等の結果との統合 | §14・19・47、LLM-01 |
| D3 | seed/profile replay、宣言digest、観測した元／縮小反例の保持 | 保存入力の直接再検査API、可逆artifact、options・環境・fixture復元条件 | §15・57、LLM-03 |
| D4 | 入力domain/pre検査、failure identity、未知post identity拒否、縮小採否の表示、mutation検知 | 中断・時間／回数予算切れ・完了を分ける結果、任意状態の復元。大域最小性は保証しない | §14・16、LLM-04 |
| D5 | adapterの実行ホストtimeout・worker診断 | coreのtrial／候補ごとのfixture lifecycle、cleanup保証、強制終了との責務境界 | §40・48・60、LLM-04 |
| D6 | SBCLのregistry複合更新lock、参照specの動的解決、wrapperの安全な再設定／解除 | 定義削除・registry世代・in-place編集・cache無効化・並行seed取得 | §8・9.1・20、LLM-05 |
| D7 | Lisp schema v1とMCP JSONの分離、entity-kind、digest・capability投影、表示の省略情報 | 可逆な値表現、opaque/cycle/shared値の復元、MCP操作可否・制限の統一記述 | §26〜28・38.1、LLM-06 |
| D8 | source form・documentation・metadata・宣言digestの保持 | trust／由来の標準保存形式、内容に紐づくreview、遷移権限と変更時の失効 | §44〜45、LLM-02 |

## 73.2 次の実証順

初期のFunction Spec、cl-mcp接続、既知の純粋関数のseed再実行は実証済み。
2026-09-10の実測は以下に履歴として残す。保存入力を直接再検査した実証ではない。

現在は次の順で進める。詳細な受け入れ条件は§73.5に定める。

1. 仕様と現状の不一致を整理し、defpropertyの宣言検査を厳格化する（本改訂で実施）。
2. 保存反例の直接再検査と最小artifact形式を定め、修正前後を同じ入力で検査する。
3. trial・縮小候補ごとのfixture、cleanup、中断結果、worker再利用の責務を固める。
4. registry更新・reload・cache無効化の規則を定め、その上でnamed specの実行コストを測る。
5. これらの実証結果を踏まえてFunction Specの表現力や副作用対象を広げる。

§70は初期architectureの依存順であり、現在の完了状況を意味しない。

### スレッドについて

§48に従い時間上限を実行ホストが持つ以上、検査は呼び出し元とは別のスレッドで走る。
新しいスレッドは動的束縛を継承しないので、`*registry*`と`*generator-backend*`の
rebindはスレッド境界を越えない。ホストはこれを自分で持ち越す必要がある（`progv`、
または各entry pointが取る`:registry`引数）。持ち越さない場合、実行はglobalな
registryで名前を解決する。同じ名前が両方に登録されていれば、別の定義を検査して
その結果を報告し、resultにはそれと分かる情報が無い。

**registryの過去の問題と現状:** 2026-09-10には表の単一操作だけが同期され、
逆引きindexのread-modify-writeで更新が失われた。8スレッドから3000件を登録して
properties-forが1146件しか返さなかった実測は修正前の履歴である。
現在はSBCLで書き手・読み手が同じWITH-REGISTRY-LOCKを取得し、複合更新も保護する。
回帰テストと4000/4000の修正後実測は§73.4 #8に記録した。
他処理系では単一writerを前提とし、汎用の並行更新保証とはしない。

`make-seed`はprocess共有の`*random-state*`から引く。スレッドは`*random-state*`を
共有するので、これは同期されないread-modify-writeであり、衝突率は系の性質では
なく呼び出しの詰まり方で決まる。実測では、8スレッドが密なループで各5000回引くと
40000件中の相異なる値は14277件（重複64%）、一方で各スレッドが1回だけ引いて
joinする形では衝突0だった。判定が誤るわけではないが、並行な掃引では別の実行が
既に試した入力を黙って引き直すことになる。`run-properties`が無条件に謳う
「各実行が自分のseedを引く」は、その分弱い。

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
   `(<= low value high)`を課したためである。当時は生成側にこの関係を反映できなかった。
   現在は§19の`(:args-generator NAME)`で引数集合全体を生成できる。
3. 反例が「境界1点」である場合、一様生成では到達確率が試行数に線形にしか
   効かない。§46のProperty品質と同じ問題が契約側にもある。

## 73.4 繰り越した指摘

以下はFunction Spec初期レビューで挙がった指摘の履歴であり、現在も全件が未解決という
意味ではない。1〜10は下の解決記録を参照し、12は本改訂で解決した。
11・13は§73.5の残課題へ引き継ぐ。本文の修正前の挙動と現行仕様を混同しない。

**報告の正確さ**

1. 契約側で`cl-spec:validate`を使うと、`spec-violation`が`:contract-error`として
   報告される。`validate`の仕事は「値がspecを満たさない」と断定することであり、
   「評価できなかった、責任はどちらとも言えない」の正反対である。`:pre`をこれで
   書くと、30試行passする実行が最初の棄却対象で`:error`になる。
2. 縮小結果の採否をreason keywordの`eq`で判定している。これは粗すぎる。
   条件は種類を問わず`:condition`に、範囲違反は種類を問わず`:return-spec`に
   潰れるので、無関係な縮小がなお採用され、元のconditionやexplanationが
   上書きされる。分類器が既に持っている情報（conditionの型、`explain-data`の
   `:kind`）で比べれば両方とも捕まる。
3. `:returns`を`:post`より先に分類するため、縮小値が同じ契約の別の節にも
   触れると正当な縮小が捨てられる。
4. 縮小結果を抑制したことが呼び出し側から見えない。`shrunk-counterexample`が
   `nil`であることは「縮小は何も小さくできなかった」とも読めるが、引数を持つ
   契約の失敗では常に「縮小結果を捨てた」の意味になる。

**再実行の副作用**

5. 分類の再実行は、実行が終わったあとにtargetを最大2回追加で呼ぶ。§3.2が
   既存コードへの後付けを謳う以上、副作用のあるtargetは想定内であり、
   報告された反例はもはや呼び出し側が置かれている状態を表さない。
   `*random-state*`を読むtargetでは、再実行はseedの先頭から引くため、
   失敗した試行が見たのとは別のdrawで分類される。

**生成の再現性**

6. `sample`と`generate-value`は依然として周囲の`check-it:*size*`を読むため、
   実行が生成する分布と食い違う。`sample`のdocstringは「specが何を認めるかを
   見るため」と言うが、実行が決して引かない分布を見せうる。
7. `check-it:*list-size*`・`*list-size-decay*`・`*num-trials*`は固定していない。
   「生成は(spec, seed, backend)の関数である」はまだ真ではない。

**registry**

8. 上記の逆引きindexの件。

**その他**

9. `run-generated-test`の返すplistがgenericのdocstringに記述されていない。
   0試行を`:skipped`へ写す規則により、`:trials`は事実上backend protocolの
   必須keyになったが、protocolはそれを要求していない。
10. `function-spec-data`の`:kind`は、`spec-data`（IRのkind）や`property-data`
    （著者の分類）とは別の軸の値である。record typeの判別子としては使えない。
11. `shared-initialize :around`のrollbackはslot名の手書きリストを使うため、
    subclassのslotを戻さない。テストがリストとclassの一致を検査していない。
12. `defproperty`は`defspec-function`より緩く、7つの形式で「受理したうえで
    意味の一部を落とす」。厳しさ自体は契約側が正しいが、片方だけが厳しい状態は
    APIとして一貫しない。既存定義を壊す変更になるため、単独で判断する。
13. `:post`の戻り値束縛は、契約自身のpackageという代理で解決している。マクロは
    `:post`の文面が読まれたpackageを見られないので、代理が外れうるケースは
    すべて拒否している（§17）。恒久的な解は明示束縛
    （`(:post (result) ...)`）だが、§17の公開例とcl-mcpのfixtureに波及する。

### 解決記録（2026-09-12以降）

上のうち 1・2・3・4・6・7・8 を実装し、修正前後の挙動を同一の入力で実測して回帰テストを追加した。
その後、verification evidenceの修正で5・9・10とproperty側のfailure identityを実装した。
2026-09-13の本改訂では12のdefproperty宣言検査を厳格化した（§4.1）。
余分なbinding要素と重複optionが受理された修正前の挙動を再現し、拒否と既存定義の保持を
tests/dsl-test.lispで検証する。条項番号は変えない。

| 項 | 直したこと | 修正前 → 修正後（実測） |
|---|---|---|
| 1 | `:pre` を `VALIDATE` で書くと `SPEC-VIOLATION` が `:CONTRACT-ERROR` になっていた。`PRECONDITION-REFUSES-P` がこれを棄却として扱う | 同一契約・同一seed: `:ERROR` / 棄却0 → `:PASSED` / 棄却23 |
| 2 | 縮小結果の採否を reason keyword の `EQ` で判定していた。`FAILURE-SIGNATURE` が condition の型と、`:RETURN-SPEC` では `EXPLAIN-DATA` の `:ERRORS` の形（`:ACTUAL` を除いたもの）を較べる | 無関係な `SIMPLE-TYPE-ERROR` を縮小値として報告 → 実行が見つけた `SIMPLE-ERROR` を保持。`:RETURNS` の別の連言に移った候補も `:DIFFERENT-FAILURE` になる |
| 3 | `:RETURNS` を先に分類するため、同じ契約の別の節に触れる正当な縮小が捨てられていた。`:RETURN-SPEC` と `:POSTCONDITION` を一つのクラスとして較べる | 縮小値が `NIL`（破棄）→ 採用（`:RETURN-SPEC` / `:USED`） |
| 4 | 破棄が呼び出し側から見えなかった。`FUNCTION-CHECK-RESULT-SHRUNK-OUTCOME` を追加（`:USED` / `:NONE` / `:DIFFERENT-FAILURE`） | 引数のない契約と破棄が同じ `NIL` → 区別できる |
| 6 | `SAMPLE` / `GENERATE-VALUE` が周囲の `CHECK-IT:*SIZE*` を読んでいた | 周囲を `*SIZE*` 5000 にすると ±4000 → 既定と同一の列 |
| 7 | `*LIST-SIZE*` / `*LIST-SIZE-DECAY*` / `*BIAS-SENSITIVITY*` / `*RECURSIVE-BIAS-DECAY*` が周囲に依存していた。`WITH-GENERATION-ENVIRONMENT` が `*SIZE*` と共に固定する | `*LIST-SIZE*` 1 の下で縮小候補が空リスト → 既定と同一の引数列 |
| 8 | 逆引きindexが read-modify-write で、並行登録で更新が失われていた。`WITH-REGISTRY-LOCK` が定義表のロックを書き手と読み手の双方で取る | 8スレッド×500（開始バリアあり）で `PROPERTIES-FOR` 1211/4000 → 4000/4000 |

回帰テストは `tests/function-spec-test.lisp`（1・2・3・4）、
`tests/backends/check-it-test.lisp`（6・7）、`tests/registry-test.lisp`（8）にあり、
いずれも修正前のコードで失敗することを確認してある。

**レビューでの追加指摘2件**も直した。ひとつは 2 の最初の実装のバグで、`EXPLAIN-DATA` の
トップレベルから `:kind` と `:path` を読んでいた（トップレベルに `:kind` は無く、`:PATH` は
常に NIL）。そのため `:RETURN-SPEC` の signature が `(:return-value nil nil)` に潰れ、
`:RETURNS` の別の連言へ移った候補を縮小として採用していた。もうひとつは
`hash-table-registry` の `:INITFORM` が `:SYNCHRONIZED` を無条件で渡していたことで、
このキーワードを受け付けない処理系では CL-SPEC 自体がロードできなかった（CLISP で実測:
`SIMPLE-KEYWORD-ERROR`）。`MAKE-REGISTRY-TABLE` が、保証がある処理系でだけそれを要求する。

レビュー2巡目でさらに2件。`FAILURE-SHAPE` が `:ERRORS` しか辿らず、`OR` が枝ごとの失敗を
入れる `:BRANCHES` の中の `:ACTUAL` が署名に残っていた。そのため同じ枝を外す2つの入力が
別の失敗と見なされ、正当な縮小が捨てられていた（`(or (range integer 0 10) string)` に対して
`(- -1 value)`、seed 42 で `:DIFFERENT-FAILURE`、`:BRANCHES` も辿るようにして `:USED`）。
また `:GENERATOR` を `NODE-ATTRIBUTES` の基本メソッドで出していたが、この総称関数のノード別
メソッドは基本メソッドを**置き換える**ため、TYPE / RANGE / MEMBER / PREDICATE / INSTANCE-OF /
REFERENCE の spec では `SPEC-DATA` から消えていた。定義レベルの属性は `SPEC->DATA` が出す。

追加の仕様判断として、ANDの畳み込みで連言のcustom generatorを無視する動作は廃止した。
直接指定・別名参照・入れ子のANDのいずれでも、該当する連言があれば生成器構築時に
`generator-unavailable`を通知する。生成方法を指定する場合はAND全体に`(:generator NAME)`を
付ける。制約が満たされるまで無制限に生成し直す方式は採用しない。

`:post`の複数形式は、先頭から短絡評価し、最初に偽を返した形式の位置を内部の分類に使う。
別形式を破る縮小候補は`:different-failure`として棄却する。公開スロットは追加せず、DSLが
生成する既存の述語からタグ付きの追加値として位置を返す。各形式の評価回数は増やさない。
プログラムから直接渡された通常の1値述語は内部位置を持たず、失敗形式identityは不明となる。
その観測は有効な反例として保持するが、同一性を確定できないため縮小候補としては採用しない。
既知identityの場合だけ、`:return-spec`と`:postcondition`間の移動を同じreturn-value失敗クラスとする
既存の規則を維持する。未知identityは節を横断しても一致させない。

タプルの要素位置は異なる制約を指すため、EXPLAIN-DATAの要素エラーに`:tuple-path`として
保持し、失敗署名でも比較する。入れ子のタプルでは外側から内側への位置のリストとなる。
一方、LIST-OFやVECTOR-OFの要素の添字は値の位置であり、従来どおり`:path`には含むが
失敗署名には含めない。

**Verification evidenceの追加修正**: propertyも偽の戻り値と例外を区別し、例外はcondition型を
比較して縮小候補の採否を決める。§13の「conditionも失敗」と「元と同じ失敗の縮小」は別の判断で
あり、両立する。通常のproperty本体の内部式までは区別せず、同型の例外も同じ分類になる。

分類用のtarget再実行を廃止し、各試行を`trial-observation`に保存する。回帰例では引数なしの
失敗がtarget呼び出し2回→1回、戻り値SATISFIES述語3回→1回となり、返り値の説明も当時の値を指す。
`:trials`欠落のbackend応答は`:skipped`へ推測せず拒否する。結果とbackendのprotocolは§14を参照。

`spec-data`、`property-data`、`function-spec-data`は`:entity-kind`を持ち、それぞれ`:spec`、
`:property`、`:function-spec`でrecordを判別する。既存の`:kind`は互換性のため保持し、IRの種類や
著者の分類として読む。例えば`:kind :function-spec`のpropertyでも`:entity-kind :property`である。
結果オブジェクトは`property-result-entity-kind`で同じ軸を取得する。

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

## 73.5 現在の残課題と受け入れ順（2026-09-13）

以下は未実装・未確定の作業であり、新しい公開APIが利用できるという意味ではない。
純粋関数の反例を修正根拠として扱う用途から順に進める。

### A. 保存反例の直接再検査と最小artifact（D3、優先度高）

現状のreplay-propertyはseedとprofileを使って再生成する。resultには予算とdigestが保存されるが、
replayはそれらを強制復元しない。実測では元の予算2を7へ変更してから同じresultでreplayすると、
7試行でpassしdigestも変わる（現在の§14の制限内）。これは保存入力の修正確認とは別の操作である。

次に決めること：
- 保存した入力を生成器なしで評価するAPIと、入力spec／preの不適合を反例解消と区別する結果。
- property／Function Spec、元／縮小入力、failure identity、seed、profile、数値予算、
  options、宣言digest、target revision、framework/backend/Lisp環境を保持する最小artifact。
- 直接復元できる値の範囲。opaque・循環・共有・表示省略された値とfixture要件の扱い。

受け入れ条件：targetの修正前後を同一保存入力で評価できる。宣言や環境の不一致、
復元不能値は明示し、preview文字列をreaderへ渡して入力復元しない。
既存の再生成replayと直接再検査を、API・結果・文書のすべてで区別する。

### B. Fixture・中断・cleanup（D4/D5、副作用対象を広げる前）

cons/array snapshotとmutation検知は、初期状態の復元ではない。
cl-mcpのホストtimeoutも、coreのtrial／縮小候補の独立性を保証しない。

次に決めること：各trialと各候補のsetup/evaluate/cleanup境界、復元不能な任意オブジェクト、
全体／trial／縮小の予算、完了・中断・予算切れ・cleanup失敗の結果とworker再利用条件。
受け入れ条件：通常終了・失敗・errorでcleanupを実行し、強制終了で保証できない場合は
状態不明を明示する。未復元の状態を次候補の反例の根拠にしない。

### C. Registry世代・reload・cache（D6、継続的REPL運用の保証前）

named specは現在、参照先を呼び出しごとに解決・compileする。同じIR objectへの
reinitialize-instanceも次の呼び出しへ反映するため、objectのEQだけを使うcacheは不正となる。

次に決めること：ファイルから消えた登録定義の削除、更新世代、in-place編集、依存先の無効化、
instrumentationの捕捉契約との関係、並行時のseed取得。
受け入れ条件：再定義・削除・参照先変更後の検査が古いcompiled artifactを使わない。
世代規則を先に確定し、測定に基づいてcacheを追加する。SBCLの既存index lockを
全処理系・任意のREPL操作の整合性保証へ拡大解釈しない。

### D. 型・由来・宣言APIの整合性（D2/D7/D8）

- core Lisp schemaとMCP JSONの可逆値表現を分けて設計する。現行core_schemaはメタデータ投影であり、
  artifactのserializerではない。操作capabilityと実行制限の一覧も別途定める。
- trust/reviewを特定の宣言digestに紐づけ、内容変更で古いreviewを自動継承しない規則を定める。
  任意metadataに保存できることは、権限や状態遷移が強制されることを意味しない。
- defpropertyの厳格化はDSLの宣言parserが対象。直接構築するpropertyのCLOS APIについて、
  初期化・再初期化・登録時の検査責務、metadata値の型制約と互換性を別途確定する。
- Function Specのsubclass追加slotまでrollbackする一般規則（§73.4 #11）は未対応。
  postの明示的な返り値束縛（#13）はDSLとadapter fixtureへ波及するため独立した変更とする。
- condition reportの生成サイズ制限と、大きな値のsnapshotコストを評価する。
  adapterの表示制限だけではcoreでの巨大report構築を防げない。

### E. その後の表現力拡張

optional/key/rest、多値、warning・非errorや正常復帰との選択を許すsignals契約、
generic function instrumentationは、
A〜Cの意味論と結果protocolが固まってから追加する。
引数間参照DSLや制約solverは、実装済みのfunction-level argument-set generatorとは別の拡張である。
`list-of`/`vector-of`の長さ・一意性制約は実装済み（§9、§68.1）。alist/hash-tableの
フィールド仕様とタグ付きunionは、field-specと`definition-constraints`を土台にした次の拡張である。
describe-*は人間向け補助として継続するが、structured dataを利用するLLM検証経路のblockerではない。


### §73.5 implementation addendum: counterexample artifacts (issue #9)

Core exposes `make-counterexample-artifact`, `counterexample-artifact-data`,
`serialize-counterexample-artifact`, `deserialize-counterexample-artifact` and
`recheck-counterexample`. Artifact v1 freezes original and accepted shrunk
observations, selection, captured declaration digest/capability, seed/profile/
budget/options and execution provenance. Provenance `:collection-states` distinguishes
known, unavailable and uncollected fields while retaining legacy scalar values.
The additive `:digest-omissions` and `:digest-exclusions` fields preserve captured
comparison details. Artifact v1 remains unchanged; the data reader represents these
fields as `:not-collected` when an older artifact omitted them.
Recheck is a concrete-input operation without backend loading, generator draws
or shrinking. It requires complete matching declaration identity, admitted input
and `:state-policy :stateless`; it performs at most one target invocation.
Target implementation identity is deliberately separate, so repaired code can be
checked against old evidence. Missing/changed/incomplete definitions, rejected
input/preconditions, unsupported state, same/different failure and success are
separate outcomes. Failure comparison uses the runner's existing failure identity
protocol. Input mutation causes refusal; external application state is outside
this first version's restoration model.

AV1 is a manually parsed, bounded tagged tree, never a Lisp reader form. Only
existing symbols and documented scalar/tree values are supported; aliasing,
cycles and opaque values are rejected rather than silently copied with changed
semantics. The public data reader and serializer return independent copies.
Invalid version, duplicate/unknown record fields, malformed tags and excessive
resources signal `invalid-counterexample-artifact`. See README for value types
and limits. MCP serialization remains the adapter's responsibility.


### Definition invariant implementation addendum (issue #10)

The object model validates Property, Function Spec and custom generator
construction and shared initialization, then validates again before registry
writes. Macro validation is an early diagnostic layer over this boundary.
`validate-definition` and `definition-validation-slots` expose validation and
explicit subclass participation in rollback. Failed updates restore slot values
and boundness; registry storage/indexes are changed only after validation.
Standard class-update initialization is checked too. This is not an arbitrary
object graph transaction: destructive nested edits, unlisted extension slots
and implementation-specific class-change recovery are outside rollback promises.
Registered target/tag index changes remain explicit re-registration operations.
A source-less callable definition remains valid but cannot have a complete
source-based digest. The executable self-spec covers identity preservation of
valid programmatic definition validation.


### Instrumentation freshness implementation addendum (issue #12)

`cl-spec/instrument:instrumentation-status` is a read-only structured query;
`instrumented-function-p` retains its existing boolean/cleanup semantics.
An installation captures registry and contract identity, scopes, its local
unresolved declaration graph, pre/post predicate identities and full dependency
digest. Queries distinguish absent/current/stale/indeterminate and report reasons,
installed/current digests, and dependency status. `:installed-digest-omissions` and
`:digest-exclusions` preserve installation-time details; `:current-digest-omissions`
is freshly collected, including missing-definition or inspection-error diagnostics.
Absent inspection is `:not-collected`, distinct from a known empty omission list.
Named references resolve during
calls, so a dependency-only change is not itself a stale captured check. Opaque
or incomplete declarations cannot establish freshness. Closure state is not
checkpointed. No digest is recomputed in the hot wrapper call path.

`refresh-instrumentation` requires an active installation and defaults to its
stored registry/scopes. Compilation and metadata capture precede replacement;
failure preserves the installed wrapper, and external function redefinitions are
refused rather than overwritten. Target invocation counts and multiple values
remain unchanged. The module is still separate from core; no new dependency on
instrumentation is introduced in `cl-spec` or `cl-spec/specs`.


### PR #22 review corrections

Artifact depth counts nested elements; cdr traversal stays at the current depth.
Node limits bound list length and scheduled traversal work. AV1 remains wire
compatible, with iterative encoding, decoding, writing and parsing. Nonfinite
floats signal the public invalid artifact condition through the codec error type.

Artifact v1 accepts an optional `:metadata-omissions` list of `(:field FIELD
:reason REASON)` records. Unsupported optional metadata gets an unavailable
placeholder; combined metadata budget exhaustion also triggers omission before
retrying evidence encoding. Evidence values, failure identity and declaration
identity are never omitted. Record validation is cycle-safe and factory creation
uses one normal-path wire encoding, without re-decoding that wire to validate it.
Direct recheck uses `property-argument-schema`, including evaluator subclass
specializations; generator annotations do not cause a draw during validation.

Local instrumentation snapshots and full definition digests share the ordered
definition graph walker. Incomplete descriptions cannot establish local equality
or inequality; independently known object/predicate identity changes still can
establish staleness. Existing complete definition digests are unchanged.

Registry index arguments remain independently validated because low-level callers
supply them separately from a property's slots. Invalid index diagnostics preserve
the offending value and describe the finite symbol-list constraint. Runtime version
provenance uses a release version variable, checked against the ASDF system by tests,
without importing ASDF into the property-runner module.


### Call schema / observed outcome implementation addendum (issue #14)

`src/call-schema.lisp`は内部の`call-layout`、`argument-binding`、`bound-call`、
`return-schema`を定義する。実呼出し引数、述語の束縛値、名前付きbinding、suppliednessを分離し、
対象関数のdefault式や述語を実行しない。このIR導入時点では必須位置引数のみを表した。optional対応は後述の#15で追加する。
`function-spec-call-layout`と`function-spec-return-schema`は現在のslotから導出するため、
reinitialize後に古いschemaを参照しない。公開`function-spec-argument-schema`は従来のtupleを返し、
reader、generator指定、宣言digestの既存値を維持する。

`src/call-outcome.lisp`の`invoke-target-once`はtargetを一度だけ呼び、
returnedの全値list、またはsignaledの元のerror instanceを保持する。
`:returns`は従来どおり主値だけを検査し、0値ならNILへ射影する。
`evaluate-trial`の先頭6戻り値は互換とし、省略可能な第7値でtarget outcomeを渡す。
条件判定と戻り値述語の前に、全戻り値のcons/配列をsnapshotする。
PROGRAM-ERROR/UNDEFINED-FUNCTION予約、`:signals`の排他・必須error、既存の失敗署名は変わらない。

`trial-observation-outcome`とresult v1のfailure内`:outcome`は
`(:kind :returned :values LIST)`または
`(:kind :signaled :condition-type TYPE :condition-report STRING-OR-NIL)`を返す。
旧6値拡張の欠落は`:not-collected`。既存`:value`は主値のまま。
artifact v1は実引数と失敗同一性を保持し、targetの返した任意オブジェクトを永続化する要件は加えない。
旧artifactの読込とgeneratorなしの再検証は維持する。

instrumentationは同じbinding/return射影を使うが、targetをcatchして再signalするhelperは使わない。
既存のmultiple-value-callを保ち、callerからtargetのrestartを利用できる。
optional対応は#15、key/restおよび明示的な多値DSLは後続issueで追加する。


### Optional call declarations implementation addendum (issue #15)

`(:args (a SPEC) &optional (b SPEC supplied-p) (c SPEC))`を受け付ける。
optional宣言は2要素または3要素、3番目は省略可能なsuppliedness変数。
必須・optional値・suppliednessを含め全変数名は一意で、定数やlambda-list markerを変数にしない。
`&optional`は一回のみ、必須宣言の後に置く。`&key`/`&rest`等はまだ拒否する。
`defproperty`は従来どおり必須pairのみとし、この構文拡張を暗黙に適用しない。
CLOSの`:argument-specs`も同じmarker/宣言列を受け、spec位置のみを正規化する。

省略された値の契約内束縛はNIL、suppliednessはNIL。明示NILはsuppliedness T。
省略時は値specを評価しない。targetのdefault値を予測・複製せず、default式はtargetで一度だけ評価する。
pre/postはvalueと任意のsuppliednessの順のflat bindingを受け取る。
複数optionalは位置引数なので、後方だけの指定はできない。

必須だけのschemaは既存tupleとdigestを維持する。拡張呼出しには内部`:call-arguments` specを使い、
子spec、required/optional区分、名前、suppliednessをintrospection・digest・explainへ反映する。
`property-call-arguments-p`は述語を再実行せず観測したraw callの形を検査し、
`property-named-arguments`は契約の名前付き束縛へ射影する。artifactには元のraw listを保存する。

生成器はoptional prefixの長さを0〜個数から選び、指定した値だけを生成する。
縮小はoptional suffixの除去、その後の指定値縮小を試みる。schema/pre/失敗同一性/変更検出を通過した
観測だけを採用する。custom引数generatorも同じcall schemaで検査する。
instrumentationはmin/max arityと指定値を検証し、default、多値、targetのconditionを維持する。
自己仕様では`find-spec`のoptional registryを通常生成と省略の両方で検査する。


### Keyword call declarations implementation addendum (issue #16)

`&key ((:external-key variable) SPEC supplied-p)`を受け付ける。suppliednessは省略可能。
暗黙のkeyword名生成は行わず、明示pairを要求してruntime interningを避ける。
変数名と宣言keywordは一意。`:allow-other-keys`はcontrol用に予約する。
`&allow-other-keys`は&key節の最後に一度だけ指定可能。`&rest`は後続で追加する。

raw callのkeyword tailは有限・偶数長で、キーはkeywordでなければならない。
重複keywordはCommon Lisp同様、先頭の値だけを束縛・検証する。後続重複値は無視する。
未知キーは宣言の&allow-other-keys、またはcall中の最初の:allow-other-keysが真なら受け付ける。
controlの重複も先頭優先。省略と明示NILはsuppliednessで区別する。
optionalは位置を貪欲に消費するので、keyword指定には先行optionalの全位置を埋める必要がある。

targetへは元の順序・重複・controlを含むraw listを一度だけ渡す。pre/postは投影した束縛を受ける。
generatorは宣言済みkeyの指定・省略を生成し、shrinkerはpair単位の除去と値の縮小を行う。
省略可能な項目も子generatorが必要。空の&keyだけのcall schemaに縮小戦略があるとは報告しない。
external keyword、名前、suppliedness、global allowanceをintrospection/digestへ含める。
explainの値違反は宣言keyを経路に持つ。未知の入力keyはvalue由来であり、failure identityへ含めない。
自己仕様ではdefinition-digestのkeyword registryを検査する。


### Rest call declarations implementation addendum (issue #17)

`&rest (NAME WHOLE-LIST-SPEC)`は一つのrest宣言を表す。suppliedness変数は指定しない。
required/optionalの後、任意の&key節の前に置く。重複marker、変数名、余分な宣言を拒否する。
restのspecは要素ではなく残りのリスト全体に適用する。空リストも検証対象であり、
rest束縛のpresenceは常に真とする。位置引数を消費したraw listのtailをそのまま束縛し、
要素・tailのidentityを保存する。raw callは常に有限proper listを要求する。

&restと&keyが共存する場合は同じtailを共有し、重複・control pairもrestに含める。
whole-list specと既存keyword検証の両方を満たす必要がある。生成・縮小では組み立てたcallを
再検証し、不適合候補を実行しない。rest単独ではwhole-list specのgeneratorを使い、固定の最大arityを仮定しない。
restとkeyの共存では、注釈なしの正確な(list-of t)だけをkeyword generatorで生成する。
それ以外はrest generatorから最大100候補callを生成し、全引数schemaで交差条件を検査する。
上限まで適合しなければgenerator-unavailableとする。custom generator注釈も検証を迂回せず、
拒否された生成候補でtargetを呼ばない。
explain経路には宣言rest名を用い、introspection/digestは:kind :restとwhole-list specを保持する。
自己仕様のrest-projection-agrees-with-targetはcheck-functionを通じ、CL:LISTの実際の戻り値と
postconditionのrest束縛が一致する法則を生成検査する。


## Fixed multiple-value return contracts implementation addendum (issue #18)

`(:returns (values SPEC...))`は固定個数の返り値を要求する。0個、1個のNIL、
複数個を区別し、不足・余剰をそれぞれ`:missing-values`・`:extra-values`で報告する。
通常の`:returns SPEC`と`:post`のRESULTは従来どおり主値で、0値ならNIL。
VALUESはFunction Specの戻り値宣言だけで認識し、一般データDSLへ追加しない。
内部`return-values-spec`は順序付き子specを持ち、派生return-schemaは`:values` modeとなる。

`(:post-values (NAME...) FORM...)`は固定値数と同数の変数を明示束縛する。
変数は相互に一意かつ束縛可能で、引数・suppliedness変数・RESULT名との衝突を拒否する。
空の変数listは0値契約に対応する。bodyは必要。`:post`・`:signals`と併用不可。
RESULTの暗黙束縛は主値のまま。CLOSの`:post-value-variables`は通常`:primary`、
明示多値では変数listで、対応するcompiled post predicateの第一引数は全値listとなる。
同readerを公開し、再初期化も他のpost slotと整合しなければrollbackする。

返り値を取得するためにtargetを再実行しない。1回の実行で全値を取得し、predicate前に
証拠をsnapshotする。固定多値のfailure identityは`:return-values`、位置は既存の
`:tuple-path`へ保持し、異なる位置・個数違反・post違反への縮小を採用しない。
postの失敗form位置が不明の場合は同一失敗と認めない。

instrumentationはoutput scopeで同じ値射影を検査し、正常時は元の全値を同順・同個数で返す。
post scopeだけを有効にした場合、明示束縛はmultiple-value-bind同様、不足位置をNILとし
余剰値を束縛しない。個数の契約はoutput scopeが担当する。targetのcondition/restartは保持する。

definition/result schema v1へ`:values` nodeと`:post-value-variables`を加算する。
古いprimary-only宣言のdigestは変更しない。artifact v1は新しいfailure identityを認識し、
従来どおり入力と失敗の同一性を保存する。返り値の保存可能性を反例保存の条件にしない。
自己仕様はfind-specの2値、definition-digestの3値とその相互関係を検査する。
