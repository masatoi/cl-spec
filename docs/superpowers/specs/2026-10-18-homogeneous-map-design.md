# 同種マップ spec（`hash-table-of` / `alist-of`）の設計

日付: 2026-10-18
状態: レビュー用設計。ここに示す DSL・IR・エラー kind は未実装。
基準: main 36b629c
関連: [keyed field 設計](2026-09-15-keyed-field-representations-design.md)、
[AND 生成設計](2026-09-15-and-generation-composability-design-revised.md)

## 1. 目的と合意済みの範囲

「すべてのキーが K を満たし、すべての値が V を満たす」任意キーのマップを
spec として書けるようにする。現状の `hash-table` / `alist` / `plist` は宣言した
キーしか扱えず、`(and hash-table (satisfies ...))` で検証はできても説明・生成が
できない。JSON 風のデコード結果、カウント表、ID 索引などがこの形を取る。

合意済みの決定：

- 対象表現は hash-table と alist。plist はキーが keyword に限られるため対象外。
- 純粋な同種マップのみ。宣言フィールドとの混在（TypeScript の index signature、
  JSON Schema の additionalProperties）は扱わない。
- エントリ数制約 `:min-count` / `:max-count` を最初の版に含める。
- 既存の `field-spec` / `collection-spec` から独立した IR ファミリーとして実装する。

## 2. DSL と正規化

```lisp
(defspec word-counts
  (hash-table-of string (range integer 0 *) :test equal :min-count 1))

(defspec headers
  (alist-of string (list-of string) :test equal :max-count 64))
```

`(hash-table-of K V &rest options)` と `(alist-of K V &rest options)` を追加する。
K と V は通常の spec 形式で、名前参照と入れ子を許す。head は他の primitive と
同じく symbol 名で照合する。

options は `list-of` と同じ keyword/value の組である。

| option | 値 | 省略時 |
|---|---|---|
| `:test` | `eq`・`eql`・`equal`・`equalp`（keyword でも通常の symbol でもよい） | `eql` |
| `:min-count` | 非負整数 | 0 |
| `:max-count` | 非負整数または `*` | 無制限 |

`:test` の既定値は既存の `hash-table` / `alist` に揃える。test の解釈は
`cl-spec/src/field-spec` の `key-test-designator` を使う。

次は登録前に `invalid-spec-form` として拒否する：K または V の欠落、奇数個の
options、未知の option、option の重複、不正な値、`:min-count` が `:max-count` を
超える宣言。

## 3. Semantic IR

新ファイル `src/map-spec.lisp`（package `cl-spec/src/map-spec`）に置く。

```text
spec
└─ map-of-spec            ; 抽象。key-spec / value-spec / key-test / min-count / max-count
   ├─ hash-table-of-spec  ; spec-kind :hash-table-of
   └─ alist-of-spec       ; spec-kind :alist-of
```

- `key-test` は正規の keyword（`:eq` 等）、`max-count` は整数または `:unbounded`。
- `spec-children` は `(key-spec value-spec)` の順。
- `validate-definition` は key-test の正規性、count 制約、子が spec object である
  ことを検査する。DSL を経ない直接構築と再登録もこれで同じ制約を受ける。
  `definition-validation-slots` に新スロットを加える。

他の責務は `tagged-by` の前例に従って既存ファイルに置く：検証・説明は
`explain.lisp`、`node-attributes` は `introspection.lisp`、`definition-constraints`
は `schema.lisp`、生成器は `backends/check-it-generators.lisp`。

## 4. 検証と説明

### 4.1 検査順

構造検査を子 spec より先に行う。

1. 構造。既存の helper と kind をそのまま使い、構造不正なら 1 件だけ返して止める。
   - `hash-table-of`：`hash-table-structure-error` による `:not-a-hash-table`、
     `:wrong-key-test`（`:actual-test` 付き）。
   - `alist-of`：`alist-structure-error` による `:not-an-alist`、`:bad-association`、
     `:duplicate-key`（`:path` は 2 個目の出現位置）。
2. エントリ数。新 kind `:too-few-entries`（`:minimum-count`）と `:too-many-entries`
   （`:maximum-count`）で、どちらも `:actual-count` を持つ。list の
   `:too-short` / `:too-long`（length）とは option 名に合わせて分ける。
3. エントリごとに K でキー、V で値を検査する。同一エントリでキーと値の両方が
   違反すれば両方を報告する（キーの違反が先）。

### 4.2 path と `:entry-path`

- キー違反・値違反とも `:path` は `(KEY . 親 path)` で、値の中の位置を指す。
  値由来なので failure identity には入らない。
- キー違反か値違反かは新しい `:entry-path` で表す。`:tuple-path` と同じく、
  マップの階層ごとに `:key` または `:value` を先頭へ積む。
  例：`(hash-table-of string (hash-table-of symbol integer))` の内側の値違反は
  `:entry-path (:value :value)`。
- `:entry-path` は spec 由来であり identity に入る。これにより K と V が同じ spec
  （例：`string` → `string`）でもキー違反と値違反を区別できる。
- マップのキーは `:field-path` に入れない。宣言されたフィールドではなくデータであり、
  list の index と同じ扱いである。

### 4.3 failure identity

`*failure-shape-keys*` に `:entry-path`、`:minimum-count`、`:maximum-count` を加える。
`:actual-count` は値由来なので加えない。既存の
`every-explained-error-key-is-classified` が分類漏れを検出する。

### 4.4 報告順

- `alist-of` は list の順に報告する。
- `hash-table-of` はキー違反をすべて報告し、次に値違反をすべて報告する。各群の中は
  `maphash` の順である。既存の `:unknown-key` と同じく、利用者の `print-object` が
  通知・停止しうるため、キーを印字して並べ替えることはしない。

identity は shape を並べた list なので、異なる shape で違反するエントリが複数あると、
元の table と縮小候補とで順序が入れ替わりうる。その場合、候補は「別の失敗」として
捨てられる。これは縮小の機会を逃す方向の誤りで、別の失敗を縮小結果として出すことは
ない。SBCL は削除のない table を挿入順に回し、縮小候補も元の順で作るため、
実際にはまれである。

### 4.5 expected 記述

```lisp
(:kind :hash-table-of :test :equal :key <K の記述> :value <V の記述>
 [:min-count n] [:max-count m])
```

`alist-of` も同じ形で `:kind :alist-of`。count は既定値でないときだけ含める。

### 4.6 付随する改善

`alist-structure-error` の重複キー検査は `member` による O(n²) である。4 つの
test はすべて `make-hash-table` の `:test` に使えるため、意味を変えずに
hash table による線形検査へ置き換える。既存の `alist` spec も恩恵を受ける。

## 5. 生成と縮小

### 5.1 生成可否

K と V の両方の生成器が必要である。どちらかが作れなければ `generator-unavailable`
とし、理由でキー側か値側かを示す。`:max-count` が 0 なら子をコンパイルせず空の
マップを返す。

### 5.2 エントリ数

`bounded-collection-generator` と同じ式を使う。上限を
`min(max-count, max(*size*, min-count))` とし、`[min-count, 上限]` から一様に引く。
`*required-size*` を `min-count` まで引き上げる。

### 5.3 キー

キーは宣言した `:test` で互いに区別できなければならない。

1. K が有限 domain を持つ場合（`enumerable-values` または `finite-integer-range`
   が答える場合）は、`:unique` と同じく domain から重複なしで抽選する。
   `enumerable-values` は EQL で重複を除いているため、宣言した `:test` で再度
   重複を除く（`equalp` なら `"a"` と `"A"` は 1 つになる）。
   - 除いた後の domain が `min-count` 未満なら、コンパイル時に
     `generator-unavailable` とする。domain は正確に列挙されているので、これは
     作れないと断定できる場合に限られる。
   - エントリ数は domain の大きさで切り詰める。
2. それ以外の場合は K の生成器から引き、既出のキーと `:test` で衝突したら引き直す。
   引き直しは generation request の共有予算を使う。衝突を
   `record-generation-rejection` で記録し、次の候補を `reserve-generation-candidate`
   で確保する。
   - 1 つの枠で 8 回続けて衝突し、その時点で `min-count` を満たしていれば、
     少ないエントリ数のまま確定する。エラーにはしない。
   - `min-count` に届く前に予算が尽きれば、既存の `generation-budget-exhausted`
     になる。これは満たす値が存在しないという主張ではない。
   - キー衝突は生成レポートの attempts / rejections に現れる。仕様書 §12・§14 の
     予算の記述を「マップのキー重複除去も予算を消費する」と更新する。

### 5.4 値と表現

エントリごとに新しい V 生成器を作り、値ごとの縮小に使う。

`hash-table-of` は宣言した test の新しい table を毎回作り、キーを抽選順に入れる。
`alist-of` は `(KEY . VALUE)` を抽選順に並べた新しい list である。対象関数が値を
書き換えても次の試行に影響しない。

### 5.5 縮小

次の順に試す。候補を採用するのは、性質の callback が「spec を満たし、まだ失敗する」
と報告した場合だけである。

1. エントリ削除。エントリ数が `min-count` を超える間、1 件ずつ削除を試す。
2. 値の縮小。各値の生成器を縮小し、V を満たさない値は採用しない。
3. キーの縮小。K の生成器から引いたキーに限る（有限 domain から抽選したキーは
   `:unique` と同じく対象外）。K を満たさない候補と、他のキーと `:test` で衝突する
   候補は採用しない。

`generator-shrink-strategy-p` に分岐を加える。実効上限が `min-count` を超えて
エントリを削除できるか、キーまたは値の子が縮小手段を持てば `:available`、
どちらもなければ `:none` とする。

### 5.6 AND との合成

数値の畳み込みには参加しない。通常に構築可能な連言として扱い、既存の規則のまま
生成元に選ばれうる。

## 6. Introspection と schema

- `node-attributes`：`:test`、既定値でないときの `:min-count` / `:max-count`、
  `:key-child-index 0` と `:value-child-index 1`。
- `definition-constraints`：同じ内容を digest に入れる。既存ノードの digest と
  `spec-data` は変わらない。
- `definition-description-complete-p` の whitelist に `map-of-spec`、
  `hash-table-of-spec`、`alist-of-spec` を加える。漏れると新ノードを含む spec の
  digest が不完全扱いになる。
- `main.lisp` に新しい export は無い。

## 7. 他機能との関係

- 反例 artifact：`alist-of` の値は、キーと値が codec で扱える型なら保存できる。
  `hash-table-of` の値は codec が hash table を扱わないため、既存の `hash-table`
  spec と同じ理由で保存を拒否する。
- coverage：マップ用の次元は追加しない。coverage schema はこれらのノードを次元を
  持たないノードとして通過させ、テストでそれを固定する。
- instrumentation と Function Spec：引数・返り値の spec として使えること以外に
  変更は無い。

## 8. テスト

新しいテストファイルは `tests.lisp` に登録する。

- `tests/map-spec-test.lisp`：正規化の受理・拒否、直接構築の定義検査、digest と
  `spec-data`。
- `explain-test`：構造・エントリ数・キー・値の各違反と path、入れ子での
  `:entry-path` の積み方、K と V が同じ spec での identity の区別。
- `failure-shape` の分類テスト。
- generator テスト：有限 domain からの重複なし抽選（`equalp` での再重複除去を含む）、
  `string` キーの衝突時の引き直し、`min-count` を満たせない場合の
  `generator-unavailable`（有限 domain、コンパイル時）と
  `generation-budget-exhausted`（引き直し）、縮小 3 段階、キー衝突・spec 違反の
  候補を採用しないこと、縮小 capability の報告。
- 性質テスト：生成値がすべて `validp` を満たすこと（両表現、各 `:test`）。
- coverage schema が新ノードを次元なしで通過させること。

## 9. ドキュメント

- 仕様書：§9 の primitive 一覧に追加し、新節「§9.6 同種マップ」（§9.5 はタグ付き union）を書く。§12・§14 の
  予算の記述を更新する。
- `CLAUDE.md` の Current status に追記する。

## 10. Non-goals

- 宣言フィールドとの混在（index signature）。必要なら `and` で書ける。
- `plist-of`。
- `:unique` の比較を EQL 以外にすること。
- マップ用の coverage 次元。
- `hash-table-of` の値の反例 artifact 保存。
- キーを印字して並べ替えることによる報告順の決定。
