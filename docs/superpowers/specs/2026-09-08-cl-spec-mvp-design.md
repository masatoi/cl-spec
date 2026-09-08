# cl-spec MVP 設計

- 日付: 2026-09-08
- 対象: `docs/cl-spec-specification-v0.2-draft.md` §67 vertical slice（§70 の実装順 4〜15）
- 前提: スケルトン（§70 の 1〜3: Semantic IR、registry protocol、hash-table registry）は完成済み
- 状態: 承認済み。実装計画はこの文書から起こす

## 0. この文書の位置付け

仕様書は MVP を3層で定義している。§67 の vertical slice、§51 の MVP API 24 シンボル、§54 の Phase 1
である。本設計が対象とするのは **§67 vertical slice** であり、これは §70 の実装順 4〜15 に対応する。

vertical slice を単位に選ぶ理由は仕様書自身が述べている。「このvertical sliceが完成してから
function specs、instrumentation、MCP integrationへ進む」（§67）。依存が一直線に並び、途中で
設計を戻す必要がない。

---

## 1. スコープ

### 1.1 実装する

| §70 | 項目 | 主なファイル |
|---|---|---|
| 4 | `defspec` normalization | `src/normalize.lisp`, `src/dsl.lisp` |
| 5 | Validator compiler | `src/validator.lisp` |
| 6 | Structured explainer | `src/explain.lisp` |
| 7 | `validp` / `validate` / `explain` / `explain-data` / `spec-data` | 上記 ＋ `src/introspection.lisp` |
| 8 | Generator backend protocol | `src/generator.lisp` |
| 9 | check-it adapter | `src/backends/check-it.lisp` |
| 10 | Property IR | `src/property.lisp` |
| 11 | Property registry / 逆索引 | 実装済み（`src/registry.lisp`） |
| 12 | `defproperty` | `src/dsl.lisp` |
| 13 | Property runner | `src/property-runner.lisp` |
| 14 | 構造化 property result | `src/property-runner.lisp` |
| 15 | seed / replay / shrink | `src/utils/random.lisp`（新規）, `src/backends/check-it.lisp` |

§51 の MVP API のうち `property-data` だけを追加で実装する。`property-result` を JSON へ投影する際に
必要であり、Property IR が出来ていれば実装量が小さいためである。

完成時に動作するもの：

```lisp
(defspec positive-integer (and integer (range 1 *)))

(find-spec 'positive-integer)
(spec-data 'positive-integer)
(validp 'positive-integer 10)          ; => T
(validate 'positive-integer -1)        ; => SPEC-VIOLATION を signal
(explain-data 'positive-integer -1)
(explain 'positive-integer -1)
(sample 'positive-integer)

(defproperty addition-preserves-order ((x positive-integer) (y positive-integer))
  (:about +)
  (:kind :monotonicity)
  (> (+ x y) x))

(properties-for '+)
(run-property 'addition-preserves-order)
(replay-property 'addition-preserves-order 18372918)
```

### 1.2 実装しない（stub のまま）

`defspec-function`、`check-function`、`defgenerator`、`describe-spec`、`describe-property`、
`instrument-function` / `uninstrument-function`、cl-mcp adapter。

`defgenerator` をスコープ外にすることで、持ち越し事項 #4（`defgenerator` の登録先が registry に無い）を
**触らずに済む**。registry に4つ目の索引を足すかどうかの判断を、実際に必要になる時まで先送りできる。
`src/registry.lisp` はスケルトンで唯一完全に実装済みのファイルであり、根拠なく変更しない。

`describe-spec` / `describe-property` は人間向け pretty printer であり §70 の step 18 に属する。
`explain` の人間向け投影はここで作るので、後から流用できる。

---

## 2. Spec 層

### 2.1 `normalize-spec-form` の判定規則

```lisp
(normalize-spec-form form &key name source-location) ; => spec オブジェクト
```

FORM の形による分岐：

1. **既に `spec` オブジェクト** — そのまま返す。プログラム的な合成と、LLM ツールからの動的登録のため。
2. **シンボル** — 下記の規則で `type-spec` か `reference-spec` に振り分ける。
3. **cons** — `symbol-name` でヘッドを照合し、対応する IR ノードへ。
4. **それ以外の atom**（数値、文字列など） — `invalid-spec-form` を signal。値の集合は `member` で書く。

#### シンボル単体の判定

`(and integer (range 1 *))` の `integer` は型、`(or null user)` の `user` は他 spec への参照である。
両者を registry の内容で区別すると、定義順によって同じ FORM の意味が変わる。よって registry を参照しない
規則を採る。

> シンボル S が **`COMMON-LISP` パッケージにあり、かつ型指定子として使える**なら `type-spec`。
> それ以外はすべて `reference-spec`。

型指定子として使えるかは `(typep nil S)` が error を signal するかで判定する。パッケージ条件を併せて
課すのは、ユーザーのパッケージに `user` という**クラス**があると `(typep nil 'user)` が error を出さず、
normalization の意味が CLOS 環境に依存してしまうためである。

ユーザー定義型・クラスは `(type foo)` / `(instance-of foo)` と明示させる。

#### 受理するヘッド

```
(type <cl型指定子>)          (satisfies <述語シンボル>)
(and s...)                   (or s...)              (not s)
(member v...)                (range [基底型] lo hi)
(list-of s)                  (vector-of s)          (tuple s...)
(nullable s)                 (instance-of <クラス名>)
```

- ヘッドは `symbol-name` で照合する（持ち越し #2）。利用者は自分のパッケージで DSL を書くため、
  そこの `range` は `cl-spec/src/normalize` にインターンされた `range` と `eq` ではない。
  `member` を `:test #'eq` で使う実装はテストで通っても実利用で壊れる。
- `range` は 2 引数形 `(range 1 *)` と 3 引数形 `(range integer 1 100)` の両方を受ける。
  3 引数でかつ第1引数がシンボルなら基底型、2 引数なら基底型 NIL（意味論上は `real`）。
  §52 が「numeric range」と定めているとおり **range は数値のみ**を扱う。基底型が `integer` /
  `real` 以外の range は `invalid-spec-form`。文字の範囲は MVP では扱わず、`(type character)` を使う。
- `*` は `symbol-name` が `"*"` のシンボルとして照合し、`:unbounded` に写す。
- `(member v...)` の値は正規化しない。リテラル値である。
- `(and)` は常に真、`(or)` は常に偽。CL の `and` / `or` に合わせる。
- `(not s)` は子をちょうど1つ取る。個数違いは `invalid-spec-form`。

`name` / `source-location` / `source-form` は**最上位の spec にのみ**付ける。子は自分の部分 form を
`source-form` に持つが `name` は NIL である。

### 2.2 `cons-of` は落とす（持ち越し #1 の決着）

`*spec-primitives*` から `"CONS-OF"` を削除する。§52 の MVP 定義と一致し、宣言された全ヘッドが対応する
IR ノードを持つ状態になる。`(cons-of a b)` には「post-MVP」と名指しした `invalid-spec-form` を返す。
仕様書 §9 の primitive 候補一覧に「cons-of は post-MVP」の注記を足す。

`src/ir.lisp` は**変更しない**。MVP に必要な IR ノードはすべて揃っている。

### 2.3 explainer を正とする

IR ノード種別ごとに書くのは **explainer クロージャだけ**である。

```lisp
(compile-explainer spec &key context)  ; => (lambda (value path) -> errors-list)
(compile-validator spec &key context)  ; => (lambda (value) (null (funcall explainer value nil)))
```

`validp` と `explain-data` の判定が食い違わないことが構成上保証される。§68 が
"successful validation implies VALIDP" を property として挙げているのは、両者が独立実装だと乖離しうる
からであり、一本化すればその乖離が原理的に起きない。

成功時 explainer は空リストを返すだけで consing しないので、`validp` の成功パスは最初から軽い。
§59 が「spec を production execution path へ強制的に入れない」と定めているため、失敗パスの consing は
MVP の制約にならない。

#### `and` は最初の失敗で短絡する

`(and integer (satisfies plusp))` に `"foo"` を渡した場合、短絡しなければ `plusp` が `TYPE-ERROR` を
出す。また §22 の人間向け出力例

```text
-100 does not satisfy POSITIVE-MONEY

  ✓ INTEGER
  ✗ PLUSP
```

は、値 -100 に対する短絡の結果とちょうど一致する（integer は通り、plusp で止まる）。安全性と仕様書の
出力例の両方が短絡を支持する。

`and` ノードのエラーデータは、子ごとの検査状態を持つ。

```lisp
(:kind :conjunct-failed
 :path ()
 :actual "foo"
 :conjuncts ((:expected (:type INTEGER)      :status :satisfied)
             (:expected (:satisfies PLUSP)   :status :failed)
             (:expected (:range :min 1 :max 100) :status :unchecked))
 :errors (<失敗した子のエラー群>))
```

`explain` のチェックリスト表示はこの `:conjuncts` から作る。短絡したことがデータに現れるので、
「未検査」と「合格」を人間にも LLM にも区別して示せる。

`:expected` に入る小さな plist を各ノードの **expected descriptor** と呼ぶ。`(:type INTEGER)`、
`(:satisfies PLUSP)`、`(:range :min 1 :max 100)`、`(:member 1 2 3)` のような形で、ノード種別ごとに
1つ定義する。

#### `or` は全枝を評価する

いずれかが成功すれば valid。全滅時に単一のエラーを返す。

```lisp
(:kind :no-branch-matched
 :path () :actual v
 :branches ((:expected ... :errors (...)) ...))
```

#### 述語呼び出しは保護する

`predicate-spec` の explainer は述語呼び出しを `handler-case` で包み、signal された condition を
エラーデータへ変換する。

```lisp
(:kind :predicate-errored
 :predicate PLUSP :expected (:satisfies PLUSP) :actual "foo"
 :condition-type CL:TYPE-ERROR :condition-report "...")
```

`(satisfies plusp)` を `and` の外で単体使用した時に `validp` が例外を投げるのは呼び手の期待に反する。

#### エラー種別の一覧

| `:kind` | 発生元 |
|---|---|
| `:type-failed` | `type-spec` |
| `:predicate-failed` | `predicate-spec`（述語が NIL を返した） |
| `:predicate-errored` | `predicate-spec`（述語が signal した） |
| `:not-member` | `member-spec` |
| `:out-of-range` | `range-spec`（`:violated-bound :minimum` / `:maximum` を持つ） |
| `:conjunct-failed` | `and-spec` |
| `:no-branch-matched` | `or-spec` |
| `:negation-failed` | `not-spec` |
| `:not-a-list` / `:not-a-vector` | `list-of-spec` / `vector-of-spec` |
| `:not-a-sequence` / `:wrong-length` | `tuple-spec`（tuple はリストとベクタの両方を受ける） |
| `:not-an-instance` | `instance-of-spec` |

要素単位の失敗は子の explainer の結果をそのまま伝播し、`:path` に位置（リストなら添字）を積む。

### 2.4 `reference-spec` は呼び出し時に解決する

`reference-spec` のクロージャは registry オブジェクトだけを捕捉し、**名前の解決は呼び出しごとに**行う。

これで3つが同時に片付く。

- 前方参照（未定義の spec を参照する spec を先に定義できる）
- 再定義への追随（キャッシュされた古い定義を掴み続けない）
- 再帰 spec のコンパイル時無限再帰の回避

呼び出し時に未登録なら `unknown-spec` を signal する。値のエラーではなくプログラムのエラーなので、
エラーデータではなく condition である。

### 2.5 コンパイル結果はキャッシュしない

§9.1 は「cache可能な実行artifact」を目標に挙げるが、MVP では入れない。

- property 実行では generator は trial ループの**外**で1回コンパイルされる
- `sample` も1回
- §59 が spec を production hot path に置かないと定めている

将来 memo 化できるよう、コンパイル呼び出しは各層1つの内部関数に集約しておく（公開 API の
`generator-for` とは別の、非 export の関数）。`spec` クラスへのキャッシュスロット追加は行わない（`src/ir.lisp` を純粋な IR に保つ）。

### 2.6 registry 引数を揃える（持ち越し #5 の決着）

designator を受ける公開関数すべてに `&key (registry *registry*)` を追加する。

対象: `validp` `validate` `explain-data` `explain` `generator-for` `sample`
`run-property` `run-properties` `replay-property` `spec-data` `property-data`

`spec-data` / `property-data` の位置引数 registry は `:registry` に寄せる。これで
「`describe-spec` の第2引数は stream なのに `spec-data` の第2引数は registry」という不揃いが消える。

`explain` は現在 `(spec-designator value &optional (stream *standard-output*))` だが、
`(spec-designator value &key (stream *standard-output*) (registry *registry*))` に変える。
`&optional` と `&key` の混在を避けるためで、MVP 実装前の唯一の変更機会である。

`compile-validator` / `compile-explainer` / `compile-generator` の `:context` はそのまま。context は
registry を含む compile 時の環境であり、registry 単体とは別物である。

registry front-end（`find-spec` 等）の位置引数 `&optional (registry *registry*)` は互換のため残す。

§51 が挙げるシンボル名は変わらない。

### 2.7 `spec-data` の形（§67）

```lisp
(:name CL-USER::POSITIVE-INTEGER
 :kind :and
 :source-form (AND INTEGER (RANGE 1 *))
 :source-location (:file "/path/to/foo.lisp" :package "CL-USER")
 :children ((:kind :type  :type INTEGER)
            (:kind :range :min 1 :max :unbounded)))
```

`:kind` は `spec-kind` の戻り値であり、公開 introspection の discriminator である（`src/ir.lisp` の
docstring が既に約束している）。キー名は IR のスロット reader 名とは独立に決める。`spec-data` が
安定した投影であり、内部スロット名の変更から利用者を守る層だからである。

**スキーマは一様にする。** 全ノードが `:name` `:kind` `:source-form` `:source-location` と
ノード固有キーを持ち、子がある時だけ `:children` が付く。§67 の例は子から `:name` と
`:source-form` を省いているが、これは概念例の省略とみなす。キーが値によって出没する schema は
消費側（特に JSON 投影）を壊しやすい。仕様書 §67 の例に注記を足す。

### 2.8 source-location（持ち越し #3 の決着）

- `spec-data` / `property-data` は `:source-location` を**展開済み plist**で返す。opaque なオブジェクトが
  public API に漏れない。
- 併せて `source-location-file` / `source-location-package` を `main.lisp` から re-export する。
  `spec-source-location` の戻り値を、内部パッケージに手を伸ばさずに読めるようにするため。

---

## 3. Generator 層

### 3.1 境界

core（`src/generator.lisp`）は check-it を一切参照しない。`cl-spec` システムが `check-it` を
ロードしないことは CI が検証している（`.github/workflows/ci.yml`）。既存のプロトコル generic を使う。

```lisp
(compile-generator   backend spec     &key context options)  ; => backend固有オブジェクト（opaque）
(generate-value      backend compiled &key seed)
(run-generated-test  backend property &key options)
```

trial ループは **backend 側**に置く。`generate` / `cached-value` / `shrink` はすべて check-it 固有の
API であり、core に持ち込むと境界が壊れる。core は seed の決定と結果の組み立てだけを担う。

### 3.2 IR → check-it generator の対応

`check-it:generator` はマクロだが、展開先の generator クラス（`int-generator`、`or-generator`、
`tuple-generator`、`list-generator`、`guard-generator`、`mapped-generator` 等）は export されている。
実行時に `make-instance` で直接組み立てられるので **`eval` は不要**である（Google スタイルガイドの
runtime `eval` 禁止に触れない）。

| IR ノード | check-it での構成 |
|---|---|
| `type-spec` | curated table を引く。`integer`→`int-generator`、`real`/`float`→`real-generator`、`character`→`char-generator`、`string`→`string-generator`、`null`→定数 NIL、`boolean`→`or-generator` of `t`/`nil`。表に無い型は `generator-unavailable` |
| `range-spec` | 基底型に応じ int-generator / real-generator の `:lower-limit` `:upper-limit`。`:unbounded` は check-it の `'*` へ |
| `member-spec` | `or-generator`、`:sub-generators` に値を直接。check-it に `(defmethod generate (generator) generator)` があり非 generator は定数として扱われる |
| `or-spec` | `or-generator` |
| `and-spec` | 制約畳み込み（3.3） |
| `list-of-spec` | `list-generator :generator-function (lambda () <子generator>)` |
| `vector-of-spec` | `mapped-generator`（`:mapping` で list→vector） |
| `tuple-spec` | `tuple-generator` |
| `nullable-spec` | `or-generator`（定数 NIL ＋ 内側） |
| `not-spec` / 単体の `predicate-spec` / `instance-of-spec` | `generator-unavailable` を signal |
| `reference-spec` | registry 経由で解決してコンパイル。コンパイル中の名前集合を持って循環を検出し、循環時は `generator-unavailable`（再帰 generator は §11 の post-MVP） |

`reference-spec` の generator は explainer と違い**コンパイル時に**解決する。generator は trial ループの
外で1回だけ組み立てられ、その後は同じオブジェクトを使い続けるためである。

### 3.3 `and` は guard ではなく制約畳み込み

check-it の `guard-generator` は棄却時に `(generate generator)` を**上限なしで再帰**する。

```lisp
(defmethod generate ((generator guard-generator))
  (let ((try (generate (sub-generator generator))))
    (if (funcall (guard generator) try)
        try
        (generate generator))))
```

満たせない guard はスタックオーバーフローになる。`(and integer (range 1 *))` を「無制約 int-generator ＋
全体 guard」にすると約50%が棄却され、深い再帰を踏む。

よって次の順で構成する。

1. `and` の子から type 制約と range 制約を集め、**1つの基底 generator に畳み込む**。
   `(and integer (range 1 100))` → `int-generator :lower-limit 1 :upper-limit 100`。棄却ゼロ。
   複数の range があれば区間の交わりを取る。交わりが空なら `generator-unavailable`。

   **子の分類は再帰的に行う。** `reference-spec` は registry で解決してから分類し、
   入れ子の `and-spec` は平坦に展開する。ここを IR の葉2クラスへの `typecase` で済ませると、
   `(defspec my-range (and integer (range 1000000 1000010)))` を参照する `(and integer my-range)` が
   「基底は無制約 int-generator、guard は my-range を要求」という形にコンパイルされ、
   全draw が棄却されて `guard-generator` の無制限再帰でスタックが溢れる — 畳み込みが防ぐために
   存在している、まさにその失敗モードを再現してしまう。再帰は `*reference-trail*` で保護する。
2. 畳み込めなかった子（`satisfies`、`not` など）が残った時**だけ** `guard-generator` で包む。
   guard は and-spec 全体の validator。
3. 基底 generator が決まらない `and`（`(and (satisfies foo) (satisfies bar))` など）は
   `generator-unavailable`。

§67 の `(and integer (range 1 *))` はケース1に落ち、棄却ループが起きない。

`shrink` の `guard-generator` メソッドは guard を尊重する実装（guard 違反の縮小値を反例として採らない）で
あることは実装で確認済みなので、ケース2でも縮小結果は健全である。

### 3.4 check-it 側の制約（実装時に必ず踏まえる）

実装を読んで確認した事実である。実装者が同じ調査を繰り返さないために記録する。

1. **`check-it:check-it` は使えない。** `check-it%` の戻り値は T / NIL のみで、反例と縮小結果は
   `*check-it-output*` へ**印字されるだけ**である。§14 の構造化結果は取り出せない。
   `generate` / `cached-value` / `shrink` を直接使って trial ループを自前で書く。
   生成と縮小のアルゴリズム自体は check-it のものを使うので §71（「check-it を再実装しない」）に反しない。

2. **`shrink tuple-generator` は `cached-value` を破壊的に書き換える。**
   `(setf (nth i cached-value) shrunk-elem)` を行うため、縮小前の反例は失われる。
   **shrink を呼ぶ前に反例をコピーしておくこと。** check-it 自身も印字用に事前 stringify して回避している。

3. **`shrink mapped-generator` は縮小しない。** 内側で計算した `shrunk-elem` を `setf` せずに捨てており、
   実質 no-op である。したがって `vector-of` の反例は縮小されない。MVP の既知の限界として記録し、
   独自 shrink の実装は post-MVP に回す。

4. **`check-it:*size*` が数値の上下限を握り潰す。** `int-generator-function` /
   `real-generator-function` は与えられた limit を `(min (abs limit) *size*)` で丸める。
   `*size*` の既定は 10 なので、`(range integer 20 100)` は **10** を、
   `(range integer -100 -50)` は **-10** を生成する。どちらも要求した範囲の外側であり、
   §68 の「生成値は常に元の spec を満たす」が壊れる。
   対策: generator のコンパイル時に有限境界の絶対値の最大を集め、
   `compile-generator` が (generator, required-size) の組を返す。`sample` と
   `run-generated-test` が `generate` の周りで `check-it:*size*` をその値まで引き上げる。
   引き上げは束縛なので他の生成に漏れない。

5. **`real-generator-function` の finite/finite 分岐にバグがある。** 下限の計算が
   `(abs low)` ではなく `(abs high)` を読む。

   ```lisp
   (let ((new-high (* (min (abs high) *size*) (signum high)))
         (new-low  (* (min (abs high) *size*) (signum low))))   ; ← (abs low) であるべき
     (+ (random (float (- new-high new-low))) new-low))
   ```

   下限と上限が 0 をまたがない限り区間が幅0に潰れ、`(random 0.0)` が TYPE-ERROR を出す。
   `(range 1 100)` は 3.4-4 の対策で `*size*` を 100 に上げるため、まさにこれを踏む。
   対策: 有限×有限の実数範囲は下限を 0 へ平行移動してから生成し、`mapped-generator` で
   戻す。下限が 0 なら `(signum 0)` が 0 になり正しい式と一致するので、バグの影響がない。
   片側が `*` の分岐にはこのバグは無いのでそのまま通す。`shrink` は実数を縮小しない
   （下記6）ので、`mapped-generator` を挟んでも失うものは無い。

   **平行移動した分、`*required-size*` は区間幅も見なければならない。** 3.4-4 の
   `max(|min|, |max|)` だけでは、0 をまたぐ範囲で足りない。`(range real -10 10)` は
   required-size 10 のまま内側 generator に `[0, 20]` を渡すことになり、check-it が
   `[0, 10]` にクランプして写像後は `[-10, 0]` — 宣言した範囲の上半分が到達不能になる。
   値は妥当なままなので validity のテストでは捕まらない。有限×有限では
   `(ceiling (abs (- maximum minimum)))` も併せて折り込む。

   下限と上限が等しい退化した範囲は generator を作らず、その唯一の値を定数として返す。
   check-it は非 generator を定数として扱うので、これで `(random 0.0)` を回避できる。

6. **`shrink` は実数を縮小しない。** `(defmethod shrink ((value real) test))` が
   「can't shrink over non-discrete search space」として値をそのまま返す。
   実数を引数に取る property の反例は縮小されない。

7. `check-it:*num-trials*` は `check-it%` 専用であり、自前ループでは自分で回数を持つ。
   ただし既定値の出所としては `default-trials`（`check-it:*num-trials*` を live read する）を使い続ける。

### 3.5 `sample` / `generator-for`

```lisp
(sample spec-designator &key (count 10) seed (registry *registry*))
(generator-for spec-designator &key context options (registry *registry*))
```

`sample` は seed 指定時に再現する。`generator-for` の戻り値は backend 固有オブジェクトであり opaque と
して扱う。

---

## 4. Property 層

### 4.1 `defproperty` 構文

```lisp
(defproperty addition-preserves-order ((x positive-integer) (y positive-integer))
  "x と y が正なら x + y は x より大きい"
  (:about +)
  (:kind :monotonicity)
  (> (+ x y) x))
```

パース規則: 引数リストの後、先頭の文字列を1つだけ docstring として取り、続いて car が既知キーワードの
cons を option 節として消費する。該当しない form が現れたらそこから body。

既知キーワード: `:about`（targets）、`:kind`、`:tags`、`:trials`、`:shrink`（§16）。
`property` クラスに `shrink` スロットは無いので、`:shrink` は `metadata` に
`(:shrink <boolean>)` として格納する（既定 T）。専用スロットの追加は、他の実行オプションが
増えた時にまとめて行う。
**未知のキーワードで始まる cons は body の先頭として扱う。** option 節の集合を閉じておかないと、
将来キーワードを追加した時に既存 property の body が黙って option として食われる。この規則は
`defproperty` の docstring に明記する。

`:trials` の値は **plist**（`(:smoke 10 :normal 100)`）とする。§33 は
`(:trials (:smoke 10) (:normal 100))` という入れ子リスト記法で書いているが、`src/property.lisp` の
`trials` スロットの docstring が既に plist と定めており、そちらに合わせる。仕様書 §33 の記法を
plist に更新する。

引数の spec form は load 時に `normalize-spec-form` で正規化する。

### 4.2 Property IR の変更

`src/property.lisp` に2点。

- **`function` スロットを追加**（§39 が挙げている）。`(lambda (x y) body...)` をコンパイルして保持し、
  reader は `property-function`。`body` は S 式のまま維持する — §39 が「compiled function だけでは
  property の意味を読むことができない」と明記しているため、両方持つ。
- **`arguments` は正規化済み IR を保持する。** 現在の docstring は "(VARIABLE SPEC-DESIGNATOR)" と
  書いているので修正する。シンボル指定は `reference-spec` になり呼び出し時解決なので、前方参照は効く。

`property-result` に `:backend` スロット（§14 が挙げている）は**追加しない**。backend は現状1つで、
export を増やす根拠がない。post-MVP に回す。

### 4.3 seed（`src/utils/random.lisp` 新規）

```lisp
(seed->random-state seed)  ; #+sbcl sb-ext:seed-random-state / #-sbcl unsupported-seed を signal
(make-seed)                ; 新しい整数 seed を返す
```

整数 seed を公開契約とする（§14 / §15 の例が整数であり、JSON / MCP にそのまま乗る）。
整数から `random-state` を作る手段は ANSI に無いので、実装依存の分岐をこの1ファイルに封じ込める。
CI は SBCL のみを対象としており、他実装の対応は `#+` を足すだけで済む形にしておく。

core が `*random-state*` を束縛し、backend は seed を知らない。

### 4.4 実行フロー

**core `run-property`**:

1. property を解決する（無ければ `unknown-property`）
2. seed を決める（未指定なら `make-seed`）
3. trials を決める（§33。`(property-trials p)` の plist を profile で引き、無ければ backend の既定値。
   既定 profile は `:normal`）。core は check-it を参照できないので、`src/generator.lisp` に
   `backend-default-trials (backend)` という generic を1つ足し、backend 側が答える
4. 各引数 spec を generator にコンパイルし、`tuple-generator` に束ねる
5. `*random-state*` を seed から束縛して `run-generated-test` を**1回**呼ぶ
   （trial ループも shrink も内側なので、束縛1つで実行全体を覆える）
6. 戻ってきた plist に seed / property / elapsed を足して `property-result` を作る

**backend `run-generated-test`**:

- trials 回: `generate` → `cached-value` → `(apply fn values)` を `handler-case` で包んで実行
- 本体が NIL を返した → `:failed`、condition を signal した → `:error`
  （§13 はどちらも failure とするが、LLM が原因を知る必要があるので **`property-result` では区別する**）。
  状態名は `src/property-runner.lisp` の `status` スロットの docstring が既に列挙している
  `:PASSED` / `:FAILED` / `:ERROR` / `:SKIPPED` / `:PENDING` に従う
- 失敗時: 反例を**コピーしてから** `check-it:shrink` を tuple-generator に対して呼ぶ（3.4-2）。
  shrink のテスト関数は `(lambda (args) (apply fn args))` を「error は失敗」として包んだもの
- 戻り値 plist: `(:status … :trials n :counterexample <値のリスト> :shrunk-counterexample <同> :condition c)`

**反例は値のリストとして返し、引数名との対応付けは core が行う。** backend は引数名を知らなくてよく、
§14 の `{"balance": 1, "amount": 1}` という形は core が組み立てる。

`elapsed` は `get-internal-real-time` の差分。

### 4.5 `replay-property`

skeleton のシグネチャは `(property-designator seed &key options)`、§15 の例は
`(replay-property 'foo result)` である。第2引数に**整数 seed と `property-result` の両方**を受ける。
`property-result` が来たらその seed を使う。

---

## 5. Condition

`src/conditions.lisp` に3つ追加する。いずれも `cl-spec-error` の下。

| condition | スロット | 用途 |
|---|---|---|
| `invalid-spec-form` | `form`, `reason` | normalization の失敗。未知ヘッド、引数個数違い、post-MVP のヘッド |
| `generator-unavailable` | `spec`, `reason` | IR から generator を導出できない |
| `unsupported-seed` | `implementation` | 整数 seed → random-state の手段が無い実装 |

---

## 6. ファイルの増減

**新規**

- `src/resolve.lisp` — designator（シンボル or オブジェクト）→ spec / property の解決と、
  compile context からの registry 取り出し。explain / validator / generator / introspection /
  property-runner がすべて必要とする共通の責務なので、`src/registry.lisp` を触らずにここへ置く。
  未登録の判定は `registry-find-spec` / `registry-find-property` の**第2返り値**で行う。
  registry は docstring で `(values entry found-p)` を約束しており、第1値だけを見ると
  「NIL として登録された名前」と「未登録」が区別できない
- `src/backends/check-it-generators.lisp` — IR → check-it generator の写像。backend プロトコルの
  結線と trial ループ（`src/backends/check-it.lisp`）とは別の責務なので分ける。
  `package-inferred-system` なので `.asd` の変更は不要
- `src/utils/random.lisp` — seed shim
- `tests/resolve-test.lisp`
- `tests/utils/random-test.lisp`
- `tests/self-properties-test.lisp` — §68 の自己 property

**変更**

`src/conditions.lisp`, `src/normalize.lisp`, `src/validator.lisp`, `src/explain.lisp`,
`src/generator.lisp`, `src/property.lisp`, `src/property-runner.lisp`, `src/introspection.lisp`,
`src/dsl.lisp`, `src/backends/check-it.lisp`, `main.lisp`, `tests.lisp`, および対応するテスト。

**変更しない**

`src/ir.lisp`（MVP に必要なノードは揃っている）、`src/registry.lisp`（generator 索引の判断を先送りできる
ため）、`src/function-spec.lisp`、`src/instrument.lisp`。

> `tests.lisp` への追加を忘れると新しいテストファイルは**一度も走らない**。新規テストファイルごとに
> 必ず追加する。

---

## 7. テスト方針

各層の rove ユニットテストに加え、§68 が求める自己 property を
`tests/self-properties-test.lisp` に置く。フレームワークが提供する仕組みを自身の品質保証に使う。

- 生成値は常に元の spec を満たす（`sample` の全要素が `validp`）
- `explain-data` の `:valid` と `validp` が一致する
- 同じ seed の replay が同じ反例を再現する
- `(and a b)` の validp が「a かつ b」と一致する（spec composition の boolean 意味論）
- registry lookup が安定である

自己 property は property runner が動いて初めて書けるので、実装順としては最後に置く。それまでは
通常の rove アサーションで各層を固める。

---

## 8. スケルトンから引き継ぐ不変条件

`docs/cl-spec-skeleton-followups.md` が実測で確認した以下は、実装後も維持されねばならない。

- `(asdf:load-system :cl-spec)` は `CHECK-IT` パッケージを一切引き込まない
- cold cache での `(asdf:load-system :cl-spec)` と `(asdf:compile-system :cl-spec :force :all)` が
  どちらも警告 0
- `cl-spec/check-it` と `cl-spec/instrument` が単体でロードできる
- §51 の MVP API 24 シンボルが `cl-spec` パッケージから external かつ到達可能
- ディスク上のテストファイルがすべて `tests.lisp` に列挙されている

---

## 9. 持ち越し事項の処理

`docs/cl-spec-skeleton-followups.md` の各項目について。

| # | 項目 | 本設計での扱い |
|---|---|---|
| 1 | `cons-of` に IR ノードが無い | **決着**: `*spec-primitives*` から削除。§52 に一致（2.2） |
| 2 | `*spec-primitives*` は名前で照合 | **踏襲**: 2.1 に規則として明記 |
| 3 | source-location のアクセサ非公開 | **決着**: `spec-data` は展開済み、アクセサも re-export（2.8） |
| 4 | `defgenerator` の登録先が無い | **先送り**: `defgenerator` をスコープ外にして判断を回避（1.2） |
| 5 | registry 到達手段の不揃い | **決着**: `:registry` キーワードに統一（2.6） |
| 6 | mallet の負債 | **据え置き**: lint は advisory のまま。一括 cleanup は別タスク |
| 7 | テストの薄い箇所 | **据え置き**: 機能に影響しない。触る機会に直す |

---

## 10. MVP の既知の限界（doc に明記する）

- `vector-of` の反例は縮小されない（check-it の `shrink mapped-generator` が no-op、3.4-3）
- 実数を引数に取る property の反例は縮小されない（check-it の `shrink real` が恒等、3.4-6）
- 有限×有限の実数範囲は check-it のバグ（3.4-5）を避けるため平行移動して生成する
- 再帰 spec は generator を持てない（`generator-unavailable`）。validation と explain は動く
- `not` / 単体の `satisfies` / `instance-of` は generator を持てない
- `and` の generator は制約畳み込みのヒューリスティックに依存する。畳み込めない組み合わせは
  `generator-unavailable`
- 畳み込めなかった述語を包む guard は、依然として check-it の無制限再帰の上に載っている。
  満たす値が存在しない、あるいは極端に稀な述語（`(and integer (satisfies never-true))` など）は
  スタックを溢れさせる。retry 上限を持つ guard は post-MVP
- 整数 seed による replay は SBCL のみ。他実装では `unsupported-seed`
- コンパイル結果はキャッシュしない。`validp` を巨大なループで回す用途は想定しない（§59）
