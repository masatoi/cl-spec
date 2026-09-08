# 欠陥コーパスと事前予想

- 日付: 2026-09-09
- 状態: **測定前**。予想を先に固定するための文書
- 関連: `docs/cl-spec-falsification-conditions.md` の F3・F4

## この文書の目的

`docs/cl-spec-falsification-conditions.md` の F3（property を書く費用がバグの費用を
上回る）と F4（最小反例が欠陥を指さない）は、MCP を待たずに今日測定できる。

測定の標本は、MVP vertical slice を構築する過程で**実際に出た欠陥**である。記録済みで、
修正前後のコミットが git に残っていて、そして重要なことに、**cl-spec の有効性を問う前に
集まった**ので都合よく選ばれていない。

「property で捕まえられたか」を頭の中で答えると、自分に都合よく答えてしまう。修正前の
コミットが残っているので、**実際に checkout して property を書いて走らせる**。思考実験
ではなく測定にする。

**この文書は測定を始める前に書く。** 予想を先に固定しておかないと、結果を見てから
「そう思っていた」と言えてしまうからである。

## 測定手順

各欠陥について:

1. 修正前のコミットを checkout する（ワークツリーを分けて、`main` は触らない）
2. その欠陥を捕まえる property を書く。**cl-spec の DSL だけで書く。**
   通常の rove アサーションで書けてしまうものは「property で捕まった」とは数えない
3. 走らせる。実際に失敗するか
4. かかった手間を記録する（所要時間、property の行数、途中で詰まった点）
5. 修正後のコミットで同じ property を走らせる。pass するか
6. 失敗した場合、**反例だけを見て**修正箇所を特定できるか（F4）

## 判定の定義

- **捕まる**: cl-spec の `defproperty` として書けて、修正前で `:failed` または `:error`、
  修正後で `:passed` になる
- **捕まらない**: property として表現できない、あるいは書けても修正前後で結果が変わらない
- **プロセスが死ぬ**: 修正前でスタックオーバーフロー等によりテストプロセスごと落ちる。
  これは「捕まった」とは別に記録する。property runner が結果を返せないため、
  §14 の構造化結果が得られないからである

---

## 予想（測定前に固定）

### 総括の予想

**6件中3件が捕まる。1件はプロセスが死ぬ。2件は捕まらない。**

捕まらない2件はどちらも「値の性質」ではなく「API 表面の性質」であり、
**そこが cl-spec の適用範囲の境界だと予想する。**

---

### D1. `*size*` クランプ（一般）

**内容**: check-it は数値 generator の上下限を `check-it:*size*`（既定10）で丸める。
`(range integer 20 100)` は 10 を生成し、`validp` が偽になる。

**修正前コミット**: **無い。** これは実装前の調査段階で見つかり、`*required-size*` の
仕組みが最初から計画に入った。測定するには**バグを再導入する**必要がある
（`bounded-generator` の `*required-size*` 更新を外す）。§43 の mutation testing に相当。

**予想: 捕まる。** §68 が自己 property として挙げている「生成値は常に spec を満たす」
そのものである。

```lisp
(defproperty generated-values-satisfy-their-spec ((x wide-range-spec))
  (validp 'wide-range-spec x))
```

**予想する手間**: 15分。既存の `self-generated-values-satisfy-their-spec` の spec を
`(range integer 20 100)` に差し替えるだけ。

**F4 の予想**: 反例は `10` になる。範囲外の値がそのまま出るので、欠陥は明白。

---

### D2. `list-of` / `vector-of` の required-size 遅延

**内容**: 要素 generator をクロージャに遅延させたため、`*required-size*` の束縛が
生きている間に要素の範囲が集計されない。`(list-of (range integer 20 100))` が
10 ばかりのリストを生成する。D1 と同じ症状の、別経路。

**修正前**: `1ed92d6` → **修正**: `8a98027`

**予想: 捕まる。** D1 と同じ property の、要素が複合な版。

**予想する手間**: 10分。D1 を書いた後なら spec を差し替えるだけ。

**F4 の予想**: 反例はリストで、全要素が 10。ただし **shrinking がこれを縮めると
`(10)` になり、単一要素だと「範囲外」がやや見えにくくなる**かもしれない。
D1 より反例の情報量が落ちると予想する。

---

### D3. `and` 畳み込みの参照漏れ

**内容**: `and` の子を平坦な `typecase` で分類したため `reference-spec` が guard に落ち、
`(and integer my-range)` が「無制約な基底 ＋ 全 draw を棄却する guard」にコンパイルされる。
check-it の `guard-generator` は上限なく再帰するのでスタックが溢れる。

**修正前**: `141eac0` → **修正**: `970e1d8`

**予想: プロセスが死ぬ。捕まらない。**

property を書くことはできる（`(defproperty ... ((x (and integer my-range))) ...)`）が、
**引数を生成しようとした時点でスタックオーバーフローする**。property runner が
`property-result` を返せないので、§14 の構造化結果は得られない。

これは cl-spec の適用範囲の外だと予想する。property は「値が性質を満たすか」を問う
仕組みであって、「生成器が停止するか」を問う仕組みではない。

**もし外れるとしたら**: SBCL の `storage-condition` を `call-property` の `handler-case`
が捕まえる場合。ただし現在の実装は `error` しか捕まえておらず、`storage-condition` は
`error` の下ではない。**外れたら、それは runner の condition 分類を見直す根拠になる。**

---

### D4. 反例の浅いコピー

**内容**: `copy-list` はタプルのスパインしか複製しない。複合型の引数では、要素が
sub-generator の `cached-value` と同一オブジェクトであり、`shrink-list-generator` が
それを破壊的に書き換えるので、捕獲済みのはずの反例が壊れる。

**修正前**: `0848089` → **修正**: `7ec81e7`

**予想: 捕まる。ただし property の対象が cl-spec 自身になる。**

```lisp
(defproperty counterexample-survives-shrinking ((x (list-of integer)))
  ;; 失敗する property を走らせ、その結果の反例と縮小反例が
  ;; 独立したオブジェクトであることを確かめる
  ...)
```

つまり **property の中で property を走らせる**形になる。書けるはずだが、
**予想する手間は他より大きい: 45分。** メタな構造になるぶん、書きにくいと予想する。

**F4 の予想**: 反例そのものより、「反例と縮小反例が `eq` である」という事実の方が
情報を持つ。**反例を見ても分からず、property の本体を読んで初めて分かる**タイプだと
予想する。F4 にとって不利な例。

---

### D5. `replay-property` の `:profile` 欠落

**内容**: profile が trial 数を決めるのに `replay-property` が `:profile` を取らない。
400回目で見つかった失敗を100回の予算で再生すると `:passed` が返る。

**修正前**: `bd6c5b5` → **修正**: `b38d432`

**予想: 微妙。おそらく捕まらない。**

「同じ seed と同じ profile なら同じ結果」は property として書ける。しかし欠陥は
**`:profile` という引数が存在しないこと**であり、修正前のコードではその property が
**そもそもコンパイルできない**（`:profile` を渡せない）。

property は「関数の振る舞いの性質」を述べる道具であって、「関数のシグネチャに引数が
あること」を述べる道具ではない。§17 の function spec の領分に近い。

**もし外れるとしたら**: `:trials` を持つ property を profile 既定で走らせて失敗させ、
seed だけで再生して pass することを示す形。これなら修正前でも書ける。
**捕まるとしたらこの形だが、これは「replay が再現しない」ことを示すだけで、
原因が profile だとは言わない。** F4 にとっては不利。

---

### D6. `invalid-property-form` の export 漏れ

**内容**: 公開マクロ `defproperty` が signal する condition が `main.lisp` から
export されておらず、利用者が `handler-case` で名指しできない。

**修正前**: `5283189` → **修正**: `15f2543`

**予想: 捕まらない。断定する。**

これは値の性質ではなく **package の性質**である。cl-spec の spec 言語には
「symbol が external であること」を述べる語彙が無いし、あるべきでもない。

実際、これを捕まえたのは property ではなく `tests/main-test.lisp` の到達性テストで、
しかも当時はハードコードされた名前リストだったため取り逃がし、後に
`do-external-symbols` による構造的検査に置き換えて塞いだ。**適切な道具は property では
なく通常のテストだった**という例。

**これが境界の内側だと判明したら、私の適用範囲の理解が根本的に間違っている。**

---

## 予想のまとめ

| | 欠陥 | 予想 | 予想手間 | F4（反例が欠陥を指すか） |
|---|---|---|---|---|
| D1 | `*size*` クランプ | 捕まる | 15分 | 指す |
| D2 | `list-of` required-size | 捕まる | 10分 | やや弱い |
| D3 | `and` 参照漏れ | プロセスが死ぬ | — | — |
| D4 | 反例の浅いコピー | 捕まる | 45分 | 指さない |
| D5 | `replay` の `:profile` | 捕まらない（微妙） | — | 指さない |
| D6 | `invalid-property-form` export | 捕まらない | — | — |

**捕まる 3 / 死ぬ 1 / 捕まらない 2。**

## 予想している境界

捕まるのは **値の性質**（生成される値が spec を満たすか、オブジェクトが独立か）。

捕まらないのは:

- **API 表面の性質**（symbol が export されているか、関数が引数を取るか）
- **停止性**（生成器が終わるか）

前者は通常のテストの領分、後者は誰の領分でもない。**この2つが cl-spec の適用範囲の
外側だと予想する。**

## 測定後に追記すること

- 実測結果（予想との差分を明示する）
- **予想が外れた箇所とその理由** — ここが一番の収穫になるはず
- F3 の判定: property を書く手間 vs 欠陥を直す手間
- F4 の判定: 反例だけで修正箇所を特定できたか

---

## 測定結果

- 測定日: 2026-09-09
- 状態: **測定済み**。上の予想セクションは記録として一字も変えていない

### 測定条件

各欠陥について `git worktree` を分けて修正前後のコミットを並べ、`main` は触っていない。
ASDF の source registry をワークツリーに固定し（`ql:*local-project-directories*` を空に
して local-projects の cl-spec を引かないようにした上で）、`ql:quickload :cl-spec/check-it`
で読み込んでいる。処理系は roswell 経由の SBCL、check-it は quicklisp の
`check-it-20150709-git`。D3 は予想どおり落ちる可能性があったので、全件を `timeout -s KILL`
つきの別プロセスで走らせた。

D1 は予想セクションが書いているとおり修正前コミットが存在しないので、45dd675 に
`bounded-generator` の `*required-size*` 更新を外して**再導入**した。歴史的な状態ではない。
D3 についても、後述の理由で 45dd675 への再導入を併用した。

### 結果表

| | 欠陥 | 予想 | 実測 | 予想手間 | 実測手間 | F4（反例が欠陥を指すか） |
|---|---|---|---|---|---|---|
| D1 | `*size*` クランプ | 捕まる | **捕まる** `:failed`→`:passed` | 15分 | 約8分 / 6行 | 指す |
| D2 | `list-of` required-size | 捕まる | **捕まる** `:failed`→`:passed` | 10分 | 約3分 / 6行 | 未縮小なら指す、縮小後は弱い |
| D3 | `and` 参照漏れ | プロセスが死ぬ | **プロセスが死ぬ**（＋修正前コミットでは property 自体が書けない） | — | 約20分 / 7行（無駄） | 反例が存在しない |
| D4 | 反例の浅いコピー | 捕まる | **捕まる**（ただし2回目の定式化で） | 45分 | 約25分 / 16行 | 指さない |
| D5 | `replay` の `:profile` | 捕まらない（微妙） | **形によって割れる**。Form A は捕まらない、Form B は `:error`→`:passed` で捕まる | — | 約15分 / 15行 | 反例は指さない。`condition` スロットは指す |
| D6 | `invalid-property-form` export | 捕まらない（断定） | **捕まる** `:failed`→`:passed` | — | 約10分 / 14行 | 指さない（反例はループ添字） |

**予想: 捕まる 3 / 死ぬ 1 / 捕まらない 2。実測: 捕まる 5 / 死ぬ 1 / 捕まらない 0。**

「行」は property 本体（`defspec` と `defproperty`）の行数で、パッケージ定義や結果を印字する
足場は数えていない。「手間」は設計を含む人間側の実時間で、機械時間は D3 を除けば全件で
数秒である。

---

## 予想が外れた箇所

外れたのは2箇所。**どちらも「捕まらない」と言ったものが捕まった**方向であり、しかも
外れ方が同じである。

### 外れ1: D6 は捕まった。「断定する」と書いたのに外れた

予想はこう書いている。

> **予想: 捕まらない。断定する。** これは値の性質ではなく **package の性質**である。
> cl-spec の spec 言語には「symbol が external であること」を述べる語彙が無いし、
> あるべきでもない。

前半は正しい。spec 言語にその語彙は無い。**しかし結論が誤りだった。** property の述語部は
任意の Common Lisp である。だから生成引数を単なるループ添字にして、実行時に
`do-external-symbols` で数えたリストへ `mod` で添字を落とせば、`defproperty` として書けて
しまう。

```lisp
(defproperty d6-every-condition-symbol-is-external-in-cl-spec ((i (range integer 0 1000)))
  (let* ((names (condition-symbol-names))
         (name (nth (mod i (length names)) names)))
    (eq :external (nth-value 1 (find-symbol name "CL-SPEC")))))
```

修正前 5283189 で4回目の試行に `:failed`、修正後 15f2543 で100回 `:passed`。判定の定義
（修正前 `:failed`、修正後 `:passed`）を満たす。**捕まっている。**

**私が取り違えていたのは、「spec 言語で述べられるか」と「property として実行できるか」を
同一視していたこと**である。この2つは別で、後者は前者よりずっと広い。`defproperty` は
「生成された値に対して任意のコードを走らせる」だけの仕組みなので、生成器を列挙器の
代用にすれば、値と関係のない命題でも通ってしまう。

ただし捕まり方は degenerate である。反例は `(I 190)`、縮小反例は `(I 119)` で、**どの
symbol が漏れているかは反例からは一切分からない**。実際に `INVALID-PROPERTY-FORM` を
名指したのは、property ではなく私が診断用に足した `(nth (mod i ...) ...)` の印字である。
generator は乱数を、shrinker は「より小さい添字」を提供しただけで、どちらも欠陥の特定には
寄与していない。そして 15f2543 が実際に採った手（`do-external-symbols` でテストを回す）は
この property より短く、確実で、23個すべてを毎回検査する。

つまり「捕まらない」は外れたが、「**適切な道具は property ではなく通常のテストだった**」と
いう予想の中身は生き残った。外れたのは判定であって、判断ではない。

### 外れ2: D5 は書き方によって捕まる

予想は2つの定式化を挙げて、どちらも決め手にならないと見ていた。実測すると**割れた**。

**Form A（予想が「もし外れるとしたら」と名指した形）: 捕まらない。**
`:trials (:normal 100 :thorough 20000)` の property を `:profile :thorough` で走らせ、
失敗の seed だけで `replay-property` する。

- 修正前 bd6c5b5: `:failed`（反例 `(SEED 7346)`）
- 修正後 b38d432: `:failed`（反例 `(SEED 7346)` — 同一）
- HEAD 45dd675: `:failed`

**修正の前後で結果が変わらない。** 判定の定義で言う「捕まらない」である。理由は明快で、
b38d432 は `replay-property` に `:profile` を**足した**だけであり、呼び出し側が渡さなければ
再生は依然として既定の trial 数で走るからだ。この property は今も真ではない命題を述べて
いる（後述の「未修正の欠陥」）。

**Form B: 捕まる。** 同じことを、再生時に `:profile :thorough` を明示して書く。

- 修正前 bd6c5b5: `:error`、`condition` = `Unknown &KEY argument: :PROFILE`
- 修正後 b38d432: `:passed`

判定の定義を満たす。**しかしこれを「property が捕まえた」と呼ぶのは無理がある。**
捕まえたのはラムダリストの検査であって、property runner ではない。実際、修正前の
ワークツリーではこの property をロードした時点で SBCL が
`STYLE-WARNING: :PROFILE is not a known argument keyword` を出しており、**property を
走らせる前に検出は終わっている**。property は「シグネチャ違反の呼び出しを1個含む
コードブロック」の入れ物として働いただけである。

予想の「property は関数のシグネチャに引数があることを述べる道具ではない」という理屈は
正しい。誤っていたのは、そこから「だから捕まらない」を導いたことである。**述語部が
任意コードである以上、シグネチャ違反は `:error` として結果表に現れる。** D6 と同じ
取り違えである。

### 外れなかったが、想定より強く出た箇所

D3 の予想は「もし外れるとしたら、SBCL の `storage-condition` を `call-property` の
`handler-case` が捕まえる場合」という逃げ道を用意していた。**この逃げ道は閉じている。**

修正前 141eac0 で `(and integer my-range)`（`my-range` = `(range integer 20 100)`）を
`sample` すると、こうなる。

```
fatal error encountered in SBCL pid 3976200 tid 3976200:
Control stack exhausted while pseudo-atomic, fault: 0x7c7e5253ff38
ldb>
```

`handler-case` を `serious-condition` に張っても同じである。これは Lisp のコンディションが
signal される前の、処理系レベルの致命エラーで ldb に落ちている。**runner の condition
分類をどう直しても救えない。** 45dd675 に欠陥を再導入して `run-property` から入っても
まったく同じ落ち方をする（SIGKILL、exit 137）。

加えて、予想が書いていない事実が1つ出た。**D3 の修正前コミット 141eac0 では
`defproperty`・`run-property`・`run-generated-test` がすべて `not-implemented` のスタブ
である。** つまり歴史的な修正前の状態では、この欠陥に property を当てること自体ができない。
欠陥が property 機構より先に存在していたためで、これは「捕まらない」よりさらに手前の話
である。測定は (a) 141eac0 で `sample` を使って欠陥を再現し、(b) 45dd675 に欠陥を再導入して
property を当てる、の2段で行った。

### D4 は予想どおり捕まったが、最初の定式化は空振りした

D4 は「捕まる／45分／反例は指さない」の3つとも当たった。ただし記録しておくべき経過がある。

**最初に書いた property は、修正前後どちらでも `:passed` を返した。**

```lisp
;; 空振りした定式化
(defproperty d4-counterexamples-satisfy-their-argument-spec ((seed (range integer 0 1000000)))
  (let ((inner (run-property 'd4-inner :seed seed)))
    (or (not (eq :failed (property-result-status inner)))
        (validp 'd4-small-list (getf (property-result-counterexample inner) 'xs)))))
```

これは D1・D2・D3 で効いた「生成値は常に spec を満たす」を、反例に対して述べた形であり、
cl-spec の語彙で最も自然な言い方である。**それが空振りした。** 理由は、check-it の
`shrink-int` が generator の `lower-limit` を尊重するので、破壊された反例も
`(range integer 1 100)` の内側（実測では全要素が `1`）に留まるからである。破壊は起きている
——診断すると元の反例と縮小反例は `eq` で、同一オブジェクトだった——のに、**破壊の結果が
spec 違反として現れない**。

捕まえるには、値ではなくオブジェクト同一性を述べるしかなかった。

```lisp
(not (eq (getf (property-result-counterexample inner) 'xs)
         (getf (property-result-shrunk-counterexample inner) 'xs)))
```

これで修正前 `:failed`、修正後 `:passed`。そしてこの定式化に辿り着くには、check-it の
`src/shrink.lisp` を読んで `shrink-list-generator` が `(setf (nth i cached-value) ...)` で
破壊的更新をすること、`shrink-int` が下限を尊重することを知る必要があった。**それは修正
7ec81e7 を書くのに必要だった知識とまったく同じである。**

---

## F3 の判定: property を書く費用 vs 欠陥を直す費用

修正のコストは git に残っている（`src/` と `main.lisp` の変更行、テストは除く）。

| | property | 修正 | 判定 |
|---|---|---|---|
| D1 | 約8分 / 6行 | `bounded-generator` に4行 | property が安い |
| D2 | 約3分 / 6行 | src +31 -10 | property が安い |
| D3 | 約20分 / 7行、結果が得られない | src +43 -13 | 判定不能（property は無駄） |
| D4 | 約25分 / 16行、うち大半が check-it の shrinker を読む時間 | src +32 -3 | **property のほうが高い** |
| D5 | 約15分 / 15行 | src +16 -2 | 同等だが、検出したのはコンパイラ |
| D6 | 約10分 / 14行 | main.lisp +6（実際に塞いだテストは3行） | **property のほうが高い** |

**F3 は部分的に発火する。** 6件中、property が費用対効果で明確に勝ったのは D1 と D2 の
2件だけである。

そして発火の条件がはっきりした。**欠陥が「生成された値が spec を満たさない」形に落ちる
ときだけ、property は安い。** その場合、既存の自己 property の spec を差し替えるだけで
済む——実際 D2 は D1 の `defspec` を1行書き換えただけで3分だった。それ以外の場合、
property を書くには**欠陥の原因をすでに知っている必要がある**。D4 がその典型で、
「反例と縮小反例が `eq` である」と書けるのは、check-it が何を破壊的に書き換えるかを
知っている人間だけである。原因を知ったあとで property を書くのは、修正を書くより高い。

これは §44（LLM による property 生成）の位置づけを分ける。値の性質については、§68 の
テンプレート（「生成値は常に spec を満たす」）の spec を差し替えるだけなので、LLM への
負担は「spec を書くこと」に帰着する。これは自動生成の射程内である。一方メタ property は
原因を知らないと書けないので、**自動生成の対象にならない**。§44 を MVP の前提条件に
格上げするかどうかは、「値の性質だけを対象にするなら不要、メタ property まで求めるなら
そもそも生成できない」という形で答えが割れる。

---

## F4 の判定: 反例だけで修正箇所を特定できたか

自分は答えを知っているので、「これを見せられた人が正しい場所へ導かれるか」で判定した。

| | 反例 | 縮小反例 | 判定 |
|---|---|---|---|
| D1 | `(X 10)` | `(X 10)` | **成立**（条件つき） |
| D2 | `(XS (10 10 … 10))` 18個 | `(XS (10))` | **未縮小なら成立、縮小後は弱い** |
| D3 | — | — | **不成立**（結果が存在しない） |
| D4 | `(SEED 494888)` | `(SEED 0)` | **不成立** |
| D5-B | `(SEED 92166)` | `(SEED 0)` | 反例は**不成立**、`condition` は成立 |
| D6 | `(I 190)` | `(I 119)` | **不成立** |

**D1**: spec が `(range integer 20 100)` で反例が `10` なので、「範囲生成器が下限を守って
いない」までは反例だけで到達する。絞り込み先は `bounded-generator` 1関数である。ただし
**原因（`*size*` によるクランプ）まで届くには「10 が check-it の `*size*` 既定値である」と
いう外部知識が要る。** 反例が指すのは症状の在り処であって、機構ではない。

**D2**: 未縮小反例 `(10 10 10 … 10)`（18個）は強い。全要素が同じ値で、その値が範囲外という
事実は「要素生成器が一律に丸められている」と読める。**縮小反例 `(10)` は明確に弱い。**
予想が「shrinking がこれを縮めると `(10)` になり、単一要素だと範囲外がやや見えにくくなる
かもしれない」と書いたとおりになった。§14 が「縮小反例を agent に最初に見せろ」と定めて
いるのは、**この件については逆効果**である。ここは §14 のスキーマを見直す根拠になる:
縮小反例だけでなく未縮小反例も同格で提示するか、少なくとも「縮小によって失われた構造」を
示す必要がある。

**D4 / D5-B / D6**: 生成引数が seed かループ添字なので、反例はそれぞれ `0`、`0`、`119` で
ある。**これらは何も指さない。** D4 は property 本体を読んで初めて「反例と縮小反例が同一
オブジェクト」という主張が見え、D6 は添字を symbol 名に戻して初めて意味が出る。
予想が D4 について「反例を見ても分からず、property の本体を読んで初めて分かるタイプ」と
書いたのは、D5-B と D6 にもそのまま当てはまる。

**D5-B の例外**: 反例は無力だが、`property-result` の `condition` スロットが
`Unknown &KEY argument: :PROFILE` を持っており、これは欠陥そのものを名指している。
**§14 の構造化結果のうち、反例ではなく `condition` が効いた唯一の例**である。F4 は「最小
反例」についての条件なので判定は不成立だが、構造化結果全体としては成立している。これは
F4 の観測項目を「反例」から「property-result 全体」に広げるべきかという問いを立てる。

**総合すると F4 は 6件中 1.5件でしか成立しない。** ただし成立しなかった4件のうち3件
（D4・D5-B・D6）は生成引数が seed か添字であるメタ／API 表面の property であり、
**F4 が成立しないことと、それが本来 property であるべきでなかったことは、同じ事実の
裏表である。** 値の性質に限れば（D1・D2）F4 は成立している。したがって F4 は発火して
いない——が、発火していないことを確認できたのは2件だけであり、標本は薄い。

---

## 境界の言い直し

予想はこう書いていた。

> 捕まるのは**値の性質**。捕まらないのは **API 表面の性質**と**停止性**。

**停止性は当たり、API 表面は外れた。** そして「捕まる／捕まらない」という切り方そのものが
境界を切る線ではなかったことが分かった。property の述語部は任意の Common Lisp なので、
**書けるものは何でも「捕まる」。** 実際に境界を切るのは、

> **generator と shrinker が仕事をしたかどうか**

である。測定した6件は3階層に分かれる。

**第1層 — 値の性質（D1, D2）。** 生成された値そのものが反例になる。generator は探索を、
shrinker は縮約を実際に担っている。property は安く（数分・6行）、反例は欠陥の在り処を
指す。**cl-spec の本来の射程はここだけである。**

**第2層 — cl-spec 自身についてのメタ property（D4, D5-B）。** 生成引数は seed であり、
反例も seed である。generator は乱数源としてしか働かず、shrinker は「より小さい seed」を
返すだけで、縮約に意味が無い。捕まりはするが、書くのに原因の事前知識が要り（F3 が発火）、
反例は何も指さない（F4 が不成立）。**書けるが、書く価値は薄い。**

**第3層 — API 表面の性質（D6、および D5-B の実際の検出経路）。** 生成引数はループ添字か、
そもそも生成が無関係である。generator は列挙器の代用で、shrinker は無意味というより
誤誘導になる（`(I 119)` は `(I 190)` より「小さい」が、より良い反例ではない）。
**通常のテストのほうが厳密に優れている**——短く、決定的で、全件を毎回検査する。
15f2543 の `do-external-symbols` によるテストが、この property のどの版よりも良い。

**そして停止性（D3）は依然として外側にある。** property runner は結果を返せない。しかも
落ち方が Lisp のコンディションですらないので、§14 の構造化結果は原理的に得られず、runner の
condition 分類をどう直しても救えない。予想が用意していた唯一の反証筋（`storage-condition`
を `handler-case` が拾う）は実測で閉じた。

したがって修正後の境界の言明はこうなる。

> **cl-spec が価値を出すのは、欠陥が「生成された値が spec を満たさない」という形に
> 落ちるときに限られる。** その形に落ちない欠陥も `defproperty` として書けてしまう——
> 述語部が任意コードだからである——が、そのとき generator と shrinker は寄与せず、
> property を書く費用は修正の費用を上回り、反例は欠陥を指さない。
> **「property として書けるか」ではなく「生成と縮小が仕事をするか」が判断基準である。**
> 停止性はこの判断以前に外側で、property 機構そのものが結果を返せない。

この言い直しは §68 の自己 property の書き方に直接効く。今 `tests/self-properties-test.lisp`
にある4つのうち、`self-generated-values-satisfy-their-spec` と
`self-and-matches-its-conjuncts` は第1層だが、`self-registry-lookup-is-stable` は生成した
`x` を `(and x ...)` で捨てているだけの第3層であり、property である必要が無い。

---

## 測定中に見つけた、直していない欠陥

**`property-result` に profile が記録されない。**

`replay-property` は seed 引数に `property-result` をそのまま取れる。docstring はその理由を
「agent が結果から seed を掘り出さなくて済むように」と書いている。ところが `property-result`
には profile のスロットが無い。したがって既定以外の profile で見つけた失敗を

```lisp
(replay-property 'p result)
```

で再生すると、trial 数は既定に戻り、静かに `:passed` が返る。**これは D5 とまったく同じ
故障モードが、呼び出し側に残ったものである。** b38d432 は `replay-property` に引数を足したが、
往復は閉じていない。上の Form A が HEAD (45dd675) でも `:failed` のまま再現する
（反例 `(SEED 26072)`）。

本測定の指示に従い、修正はしていない。

---

## 付録: 使用した property

いずれも `defpackage` と結果を印字する足場は省き、`defspec` / `defproperty` のみを載せる。
実行はワークツリーごとの別プロセスで、`(run-property '<name>)` を直接呼んでいる。

### D1（45dd675 に再導入）

```lisp
(defspec wide-range (range integer 20 100))

(defproperty d1-generated-values-satisfy-their-spec ((x wide-range))
  "Whatever the generator produces, the spec it came from admits."
  (:about cl-spec/src/generator:sample)
  (:kind :invariant)
  (validp 'wide-range x))
```

再導入は `bounded-generator` の先頭2ブロック（`dolist` による各境界の `*required-size*`
更新と、両端有限のときの幅による更新）を削除した。
結果: 修正前 `:failed` trials=1 反例 `(X 10)` / 修正後 `:passed` trials=100。

### D2（1ed92d6 → 8a98027）

```lisp
(defspec d2-wide-list (list-of (range integer 20 100)))

(defproperty d2-generated-values-satisfy-their-spec ((xs d2-wide-list))
  "Whatever the generator produces, the spec it came from admits."
  (:about cl-spec/src/generator:sample)
  (:kind :invariant)
  (validp 'd2-wide-list xs))
```

結果: 修正前 `:failed` trials=1 反例 `(XS (10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10))`
縮小反例 `(XS (10))` / 修正後 `:passed` trials=100。

### D3（141eac0 → 970e1d8、および 45dd675 への再導入）

```lisp
(defspec d3-my-range (range integer 20 100))
(defspec d3-and (and integer d3-my-range))

(defproperty d3-generated-values-satisfy-their-spec ((x d3-and))
  "Whatever the generator produces, the spec it came from admits."
  (:about cl-spec/src/generator:sample)
  (:kind :invariant)
  (validp 'd3-and x))
```

141eac0 ではこの `defproperty` を評価した時点で `not-implemented` になる（`run-property`
も同様）。欠陥そのものは `(sample 'd3-and)` で再現し、SBCL が
`fatal error ... Control stack exhausted while pseudo-atomic` で ldb に落ちる。
`handler-case` を `serious-condition` に張っても同じ。45dd675 で `fold-and-children` の
`reference-spec` 節を削って再導入すると、`run-property` から入っても同じ落ち方をする
（exit 137）。修正後 970e1d8 では `(sample 'd3-and)` が `(70 72 31 38 82)` を返し、
45dd675 では property が `:passed` trials=100。

なお、この欠陥は範囲が `*size*` 既定値の外にあるときだけ発現する。
`(range integer 1 100)` で試すと 141eac0 でも `(4 4 8 10 1)` を返して停止してしまい、
再現しない。「全 draw を棄却する guard」になる範囲を選ぶ必要がある。

### D4（0848089 → 7ec81e7）

空振りした第1版:

```lisp
(defspec d4-small (range integer 1 100))
(defspec d4-small-list (list-of d4-small))

(defproperty d4-inner ((xs d4-small-list))
  (:trials (:normal 25))
  (evenp (length xs)))

(defproperty d4-counterexamples-satisfy-their-argument-spec ((seed (range integer 0 1000000)))
  (:about run-property)
  (:kind :invariant)
  (:trials (:normal 20))
  (let ((inner (run-property 'd4-inner :seed seed)))
    (or (not (eq :failed (property-result-status inner)))
        (and (validp 'd4-small-list (getf (property-result-counterexample inner) 'xs))
             (validp 'd4-small-list (getf (property-result-shrunk-counterexample inner) 'xs))))))
```

結果: 修正前 `:passed` / 修正後 `:passed`。**欠陥を測っていない。**

捕まえた第2版（`d4-small` / `d4-small-list` / `d4-inner` は同じ）:

```lisp
(defproperty d4-counterexample-survives-shrinking ((seed (range integer 0 1000000)))
  "The first failing arguments a run reports are not the same object shrinking
went on to rewrite."
  (:about run-property)
  (:kind :invariant)
  (:trials (:normal 20))
  (let ((inner (run-property 'd4-inner :seed seed)))
    (or (not (eq :failed (property-result-status inner)))
        (not (eq (getf (property-result-counterexample inner) 'xs)
                 (getf (property-result-shrunk-counterexample inner) 'xs))))))
```

結果: 修正前 `:failed` trials=1 反例 `(SEED 494888)` 縮小反例 `(SEED 0)` /
修正後 `:passed` trials=20。

`d4-inner` が長さの偶奇で失敗するのは 7ec81e7 のテストと同じ理由による。要素を1つ抜くと
必ず偶数長になって property が通ってしまうので、check-it は長さ方向の縮小を毎回棄却し、
捕獲済みのリストの要素をその場で書き換える経路に確実に落ちる。

### D5（bd6c5b5 → b38d432）

```lisp
(defspec d5-thousand (range integer 1 1000))

(defproperty d5-inner ((x d5-thousand))
  (:trials (:normal 100 :thorough 20000))
  (/= x 500))

;; Form A -- seed だけで再生する
(defproperty d5-replay-reproduces-a-failure ((seed (range integer 0 100000)))
  (:about replay-property)
  (:kind :round-trip)
  (:trials (:normal 8))
  (let ((first-run (run-property 'd5-inner :profile :thorough :seed seed)))
    (or (not (eq :failed (property-result-status first-run)))
        (eq :failed (property-result-status
                     (replay-property 'd5-inner (property-result-seed first-run)))))))

;; Form B -- 同じ profile を明示して再生する
(defproperty d5-replay-under-the-same-profile-reproduces-a-failure
    ((seed (range integer 0 100000)))
  (:about replay-property)
  (:kind :round-trip)
  (:trials (:normal 8))
  (let ((first-run (run-property 'd5-inner :profile :thorough :seed seed)))
    (or (not (eq :failed (property-result-status first-run)))
        (eq :failed (property-result-status
                     (replay-property 'd5-inner (property-result-seed first-run)
                                      :profile :thorough))))))
```

`d5-inner` は千に一つの値でだけ失敗するので、既定の100回ではたいてい見逃し、
`:thorough` の20000回では必ず見つかる。これが profile の差を観測可能にしている。

結果:

| | bd6c5b5 | b38d432 | 45dd675 |
|---|---|---|---|
| Form A | `:failed` `(SEED 7346)` | `:failed` `(SEED 7346)` | `:failed` `(SEED 26072)` |
| Form B | `:error` `Unknown &KEY argument: :PROFILE` | `:passed` | `:passed` |

### D6（5283189 → 15f2543）

```lisp
(defun condition-symbol-names ()
  "Names of every symbol CL-SPEC/SRC/CONDITIONS exports, in a stable order."
  (let ((names '()))
    (do-external-symbols (symbol (find-package "CL-SPEC/SRC/CONDITIONS"))
      (push (symbol-name symbol) names))
    (sort names #'string<)))

(defproperty d6-every-condition-symbol-is-external-in-cl-spec ((i (range integer 0 1000)))
  "Every symbol CL-SPEC/SRC/CONDITIONS exports is also external in CL-SPEC."
  (:about cl-spec/src/conditions:cl-spec-error)
  (:kind :invariant)
  (let* ((names (condition-symbol-names))
         (name (nth (mod i (length names)) names)))
    (eq :external (nth-value 1 (find-symbol name "CL-SPEC")))))
```

対象は両コミットとも23シンボル。
結果: 修正前 `:failed` trials=4 反例 `(I 190)` 縮小反例 `(I 119)` / 修正後 `:passed`
trials=100。`(mod 119 23)` = 4 が指すのは `"INVALID-PROPERTY-FORM"` だが、**それは反例
からは読めない。**

なお `(member ...)` spec に symbol 名を直書きする版も書ける。しかしそれは 15f2543 が
置き換えたハードコード名リストそのものであり、書き手が漏れに気づいていなければ
`INVALID-PROPERTY-FORM` を列挙しないので、同じ取り逃がしを再現する。
