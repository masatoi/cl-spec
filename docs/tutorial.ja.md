# cl-spec 入門チュートリアル

このチュートリアルは、Common Lisp は書けるけれど cl-spec も property-based testing
（PBT）も初めて、という人のための一本道の入門です。REPL に式を打ちながら上から順に
読み進めると、1 時間ほどで一周できます。

題材はショッピングカートの金額計算です。商品の価格と数量という小さな値の仕様から始めて、
明細とカートの構造、小計の性質、関数の契約、エラーの約束、条件ごとの約束へと、
同じカートを章ごとに少しずつ育てていきます。途中でわざと壊した実装も用意し、cl-spec が
バグをどう見つけ、どう報告するかを実際に確かめます。

本文に載せたコードは、実行可能な example
[`examples/tutorial-cart.lisp`](../examples/tutorial-cart.lisp) と同じ定義です。その
`demo-*` 関数が返す決定的な結果（status、失敗理由、エラーの内容など）は、通常のテスト
スイート（`tests/tutorial-cart-example-test.lisp`）で検証しており、変わると
`rove cl-spec.asd` が失敗します。生成された値や反例の具体的な値は、形だけを検証して
います。なお、本文のコード片と example の定義が一致していることは、機械的には検証して
いません。

## 0. はじめに

### cl-spec とは

cl-spec は、値や関数についての「約束」を実行可能なデータとして書くためのライブラリです。
一度書いた約束は、値の検証、違反理由の構造化された説明、約束を満たす値の生成、
property テストや関数契約の検査に、そのまま使い回せます。約束はデータとして registry に
登録されるので、人間だけでなくプログラム（LLM エージェントを含む）からも読めます。

### property-based testing とは

ふつうの単体テストは「入力 `2` と `3` なら結果は `5`」のような具体例を書きます。
property-based testing では、具体例の代わりに「どんな入力でも成り立つはずの性質」を書きます。
テストツールはその性質に対してランダムな入力を何度も作って試し、性質が破れる入力
（反例、counterexample）を探します。反例が見つかると、性質が破れたままになる範囲で入力を
小さく単純にしていきます。これを縮小（shrink）と呼びます。大きなランダム入力のままでは
原因を読み取りにくいので、縮小した反例のほうが手がかりになります。

### 前提と読み込み

- SBCL
- ASDF から cl-spec が見えること（例えば Quicklisp の `local-projects` に置く）
- check-it（Quicklisp から入ります）

REPL で次を評価します。

```lisp
(asdf:load-system :cl-spec/check-it)
```

`cl-spec` 本体は check-it に依存しません。値の生成と property の実行に必要な生成
backend は `cl-spec/check-it` を読み込んだときに組み込まれます。

以降のコードは `cl-user` パッケージで打つことを想定しています。cl-spec の演算子には
`cl-spec:` を付けますが、`range` や `plist` のような spec の中に書く演算子には付けません。
定義した spec や property は、既定の registry（`cl-spec:*registry*`）に登録されます。

### ファイル版の動かし方

本文と同じ定義はファイル版としても用意してあります。読み込んで demo を呼べば、
各章の結果をまとめて確かめられます。

```lisp
(asdf:load-system "cl-spec/examples/tutorial-cart")
(cl-spec/examples/tutorial-cart:demo-find-bug)
```

ファイル版は専用の registry に登録するので、REPL で打った定義とは混ざりません。
REPL で本文を追った後に動かしても、先に動かしても構いません。

> **この章のまとめ**: cl-spec は約束を実行可能なデータとして書くライブラリで、PBT は
> 性質をランダムな入力で試して反例を探し、縮小する手法です。`cl-spec/check-it` を
> 読み込めば準備は完了です。

## 1. 値の仕様を書く

まず、価格と数量の仕様を書きます。価格は 1 円から 10000 円までの整数、数量は 1 から 99 まで
の整数とします。

```lisp
(cl-spec:defspec price (range integer 1 10000))
(cl-spec:defspec quantity (range integer 1 99))
```

`defspec` は名前と spec の組を registry に登録します。`(range integer 1 10000)` は
「1 以上 10000 以下の整数」という spec です。

値が spec を満たすかどうかは `validp` で調べます。

```lisp
(cl-spec:validp 'price 500)
;; => T
(cl-spec:validp 'price 0)
;; => NIL
```

`validp` は真偽しか返しません。なぜ満たさないのかを知りたいときは `explain-data` を使います。

```lisp
(cl-spec:explain-data 'price 0)
;; => (:VALID NIL :SPEC PRICE :VALUE 0 :PATH NIL :ERRORS
;;     ((:KIND :OUT-OF-RANGE :PATH NIL :ACTUAL 0 :EXPECTED (:RANGE :MIN 1 :MAX 10000)
;;       :VIOLATED-BOUND :MINIMUM)))
```

結果は文字列のメッセージではなく plist です。`:errors` には違反が 1 件ずつ plist で並び、
各キーは次の意味を持ちます。

| キー | 意味 |
|---|---|
| `:kind` | 違反の種類。ここでは範囲外（`:out-of-range`） |
| `:path` | 値のどこが違反したか。`NIL` は値そのもの。構造化データでは次章で効いてきます |
| `:actual` | 実際の値 |
| `:expected` | 期待していたもの。ここでは 1〜10000 の範囲 |

この例では、さらに `:violated-bound :minimum`（下限側を破った）も付いています。
データとして返るので、プログラムから違反の種類や場所で分岐できます。

spec は値の検査だけでなく、値の生成にも使えます。

```lisp
(cl-spec:sample 'price :count 5 :seed 42)
;; => (7271 861 5391 5192 5735)   ; 例えば
```

`sample` は spec を満たす値を `:count` 個作ります。`:seed` を指定すると、同じ seed からは
同じ値が出ます。ただし、出てくる値そのものは生成 backend の実装や環境によって異なることが
あります。上の値は一例として読んでください。どの値も `price` を満たすことは変わりません。

なお、`sample` は 2 つ目の値として生成のレポート（試行回数や棄却数などを並べた plist）も
返すので、REPL ではその plist も表示されます。上では省略しました。今は無視して構いません。

> **この章のまとめ**: `defspec` で値の約束を名前付きで登録し、`validp` で検査、
> `explain-data` で違反を構造化データとして読み、`sample` でその約束を満たす値を作れます。

## 2. 構造化データを扱う

次に、カートの明細（line item）とカートそのものの仕様を書きます。明細は
`(:sku "A-1" :price 100 :qty 2)` のような plist とします。

```lisp
(cl-spec:defspec line-item
  (plist (:required (:sku string) (:price price) (:qty quantity))
         (:closed t)))
(cl-spec:defspec cart (list-of line-item :max-length 5))
```

- `plist` は plist の各キーに spec を割り当てます。`:required` に並べたキーは必須です。
- `(:sku string)` の `string` は CL の型です。`(:price price)` の `price` は、前章で登録した
  spec 名です。spec の中では、自分で定義したシンボルは登録済みの spec 名として扱われます。
- `(:closed t)` は「ここに挙げていないキーを許さない」という意味です。
- `list-of` は要素がすべて `line-item` を満たすリストです。`:max-length 5` で長さの上限を
  5 にしています。上限を設けると、生成されるカートが大きくなりすぎず、検査や縮小も速くなります。

正しい明細は通ります。

```lisp
(cl-spec:validp 'line-item '(:sku "A-1" :price 100 :qty 2))
;; => T
```

違反を 3 種類見てみましょう。まず数量が 0 の明細です。

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100 :qty 0))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100 :QTY 0) :PATH NIL
;;     :ERRORS
;;     ((:FIELD-PATH (:QTY) :KIND :OUT-OF-RANGE :PATH (:QTY) :ACTUAL 0 :EXPECTED
;;       (:RANGE :MIN 1 :MAX 99) :VIOLATED-BOUND :MINIMUM)))
```

`:path (:qty)` が、明細のうち `:qty` フィールドが違反したことを指しています。
`:kind` と `:expected` は前章と同じ読み方で、`quantity` の範囲 1〜99 を外れたと分かります。

次に `:qty` が欠けている明細です。

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100) :PATH NIL :ERRORS
;;     ((:FIELD-PATH (:QTY) :KIND :MISSING-KEY :PATH (:QTY) :ACTUAL NIL :EXPECTED
;;       (:SPEC QUANTITY))))
```

今度は `:kind :missing-key` です。`:path (:qty)` は同じく `:qty` を指し、`:expected` は
そこに `quantity` を満たす値が必要だったことを示します。

最後に、仕様にない `:memo` キーを足した明細です。

```lisp
(cl-spec:explain-data 'line-item '(:sku "A-1" :price 100 :qty 2 :memo "gift"))
;; => (:VALID NIL :SPEC LINE-ITEM :VALUE (:SKU "A-1" :PRICE 100 :QTY 2 :MEMO "gift")
;;     :PATH NIL :ERRORS
;;     ((:KIND :UNKNOWN-KEY :PATH (:MEMO) :ACTUAL "gift" :EXPECTED
;;       (:KIND :PLIST :CLOSED T :FIELDS
;;        ((:KEY :SKU :REQUIRED T :EXPECTED (:TYPE STRING))
;;         (:KEY :PRICE :REQUIRED T :EXPECTED (:SPEC PRICE))
;;         (:KEY :QTY :REQUIRED T :EXPECTED (:SPEC QUANTITY)))))))
```

`(:closed t)` にしたので、`:memo` は `:kind :unknown-key` として報告されます。
`:path (:memo)` が余分なキーを指し、`:expected` には許されているフィールドの一覧が入っています。

3 つとも、`:path` を見ればどのフィールドが問題なのかがすぐ分かります。入れ子が深い
データでも、`:path` は値の先頭からのたどり方を示します。最初の 2 つに付いている
`:field-path` は、仕様で宣言したフィールドをたどるキー列です。宣言していない `:memo` の
違反には付かず、`:path` だけが付きます。また、欠落したキーの `:actual NIL` は「値が NIL
だった」のではなく「値がなかった」ことを表し、両者は `:kind` で区別されます。

カートも生成できます。

```lisp
(cl-spec:sample 'cart :count 2 :seed 42)
;; => (((:SKU "4skdcB5UzLJP2t" :PRICE 1529 :QTY 3) (:SKU "u11z" :PRICE 2613 :QTY 2)
;;      (:SKU "6hNrb5VRBdpN84rXmoy" :PRICE 8007 :QTY 9))
;;     NIL)   ; 例えば（2 つ目の戻り値の生成レポートは省略）
```

生成されたカートは、どれも明細 5 件以下で、各明細が `line-item` を満たします。
`list-of` に下限を付けていないので、空のリストも `cart` を満たし、上の例のように空の
カート（`NIL`）が出ることもあります。具体的な値は、前章と同じく環境によって異なることが
あります。

> **この章のまとめ**: `plist` と `list-of` で構造化データの仕様を書けます。違反は
> `:kind` と `:path` で「何が」「どこで」起きたかとして報告され、生成した値は spec を
> 満たします。

## 3. 性質を書く

カートの小計を計算する関数を書きます。

```lisp
(defun cart-subtotal (cart)
  "Return the sum of price times quantity over CART's line items.  Pure."
  (loop for item in cart
        sum (* (getf item :price) (getf item :qty))))
```

この関数が満たすべき性質を 1 つ考えます。2 つのカートをつなげたカートの小計は、
それぞれの小計の和に等しいはずです。具体的なカートを決めずに、この性質をそのまま書きます。

```lisp
(cl-spec:defproperty subtotal-is-additive ((a cart) (b cart))
  (:about cart-subtotal)
  (= (cart-subtotal (append a b))
     (+ (cart-subtotal a) (cart-subtotal b))))
```

- `((a cart) (b cart))` は「`cart` spec から生成した値を `a` と `b` に束縛する」という
  意味です。試行のたびに新しいカートが 2 つ作られます。
- `(:about cart-subtotal)` は、この性質がどの関数についてのものかを記録します。
  後で関数の側から関連する property を引けます。
- 最後の式が性質の本体です。真なら成立、偽なら違反です。

実行してみます。

```lisp
(defparameter *additive* (cl-spec:run-property 'subtotal-is-additive :seed 42))
(cl-spec:property-result-status *additive*)
;; => :PASSED
(cl-spec:property-result-trials *additive*)
;; => 100
```

100 回の試行で、性質が破れる入力は見つかりませんでした。`:seed` を固定しているので、
同じ環境で同じ式を評価すれば同じ入力列で再実行されます。

`:about` で記録した関係は、関数名から引けます。

```lisp
(cl-spec:properties-for 'cart-subtotal)
;; => (SUBTOTAL-IS-ADDITIVE)
```

ここで 1 つ注意があります。`:passed` は「実行した 100 回の試行では違反を観測しなかった」
という意味であって、性質が常に成り立つことの証明ではありません。試行回数や生成される値の
偏りによっては、違反する入力を引かないまま終わることもあります（第 8 章で実際にその例を
見ます）。

> **この章のまとめ**: `defproperty` で「どんな入力でも成り立つ性質」を書き、
> `run-property` でランダムな入力に対して試せます。`:passed` は観測した範囲での結果で、
> 証明ではありません。

## 4. バグを見つける

今度はわざと壊した実装を用意します。先頭の明細を読み飛ばしてしまう小計です。

```lisp
(defun broken-cart-subtotal (cart)
  "A deliberately wrong subtotal: it skips the first line item."
  (loop for item in (rest cart)
        sum (* (getf item :price) (getf item :qty))))
```

前章と同じ性質を、この関数について書きます。

```lisp
(cl-spec:defproperty broken-subtotal-is-additive ((a cart) (b cart))
  (:about broken-cart-subtotal)
  (= (broken-cart-subtotal (append a b))
     (+ (broken-cart-subtotal a) (broken-cart-subtotal b))))
```

実行します。

```lisp
(defparameter *broken* (cl-spec:run-property 'broken-subtotal-is-additive :seed 42))
(cl-spec:property-result-status *broken*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken*)
;; => :PREDICATE-FALSE
```

`:predicate-false` は、性質の本体が偽を返したという意味です。どんな入力で破れたのかは
反例として記録されています。まず、最初に見つかった反例です。

```lisp
(cl-spec:property-result-counterexample *broken*)
;; => (A
;;     ((:SKU "K70jiib" :PRICE 3105 :QTY 48) (:SKU "7C42" :PRICE 3841 :QTY 5)
;;      (:SKU "89M63woD6VjYl" :PRICE 3628 :QTY 84))
;;     B
;;     ((:SKU "Wga8IFI0l5" :PRICE 1496 :QTY 52) (:SKU "Z60xQ5AbZ675t5PI" :PRICE 9340 :QTY 59)
;;      (:SKU "2dCTt" :PRICE 8681 :QTY 33) (:SKU "rky9PYQ" :PRICE 2050 :QTY 1)
;;      (:SKU "4wc2vXqf2yrr2i3" :PRICE 6945 :QTY 14)))   ; 例えば
```

反例は、property の変数名と値を並べた plist です。この大きさのカートでは、何が悪いのかを
目で追うのは大変です。そこで縮小後の反例を見ます。

```lisp
(cl-spec:property-result-shrunk-counterexample *broken*)
;; => (A ((:SKU "89M63woD6VjYl" :PRICE 1 :QTY 1))
;;     B ((:SKU "4wc2vXqf2yrr2i3" :PRICE 1 :QTY 1)))   ; 例えば
```

`a` も `b` も明細 1 件、価格も数量も 1 まで小さくなりました。この入力で性質を手で計算すると、

- 連結したカートは明細 2 件なので、`broken-cart-subtotal` は先頭を飛ばして 1
- `a` も `b` も明細 1 件なので、それぞれ先頭を飛ばして 0、和は 0

となり、1 と 0 が一致しません。明細 1 件のカートの小計が 0 になるのはおかしい、つまり
「先頭の明細が無視されている」ことが読み取れます。

具体的な反例の値は環境によって異なることがありますが、縮小の目的は同じです。なお、
縮小は性質が破れたままの、より小さな入力を探す手続きであり、得られる反例が最小であることは
約束しません。

失敗を再現したいときは、結果オブジェクトをそのまま `:seed` に渡します。

```lisp
(defparameter *replay* (cl-spec:run-property 'broken-subtotal-is-additive :seed *broken*))
(cl-spec:property-result-status *replay*)
;; => :FAILED
(cl-spec:property-result-seed *replay*)
;; => 42
(equal (cl-spec:property-result-counterexample *broken*)
       (cl-spec:property-result-counterexample *replay*))
;; => T
```

結果オブジェクトを渡すと、記録された seed・profile・オプションで再実行されるので、
同じ反例が出ます。修正後に同じ入力で直ったかを確かめるときに便利です。

> **この章のまとめ**: 性質が破れると、反例と縮小後の反例が報告されます。縮小後の反例から
> 原因を読み、結果オブジェクトを `:seed` に渡して同じ失敗を再現できます。

## 5. 関数契約を書く

property は性質を自由な式で書けますが、「この関数はこういう引数を受け取り、こういう値を
返す」という約束は、関数契約として書くほうが素直です。`cart-subtotal` の契約を書きます。

```lisp
(cl-spec:defspec-function cart-subtotal
  (:args (cart cart))
  (:returns (range integer 0 *))
  (:post (>= result (length cart))))
```

- `:args` は引数の名前と spec の組です。ここでは引数 `cart` が `cart` spec を満たします。
  検査のとき、引数はこの spec から生成されます。
- `:returns` は戻り値の spec です。`(range integer 0 *)` は 0 以上の整数（上限なし）です。
- `:post` は事後条件です。`result` は戻り値を指し、引数名（ここでは `cart`）も使えます。
  価格も数量も 1 以上なので、各明細は小計に 1 以上寄与します。したがって小計は明細の件数
  以上になるはずです。それを `(>= result (length cart))` と書いています。

検査します。

```lisp
(defparameter *subtotal-check* (cl-spec:check-function 'cart-subtotal :seed 42))
(cl-spec:property-result-status *subtotal-check*)
;; => :PASSED
```

壊れた実装にも同じ契約を書いて検査します。

```lisp
(cl-spec:defspec-function broken-cart-subtotal
  (:args (cart cart))
  (:returns (range integer 0 *))
  (:post (>= result (length cart))))

(defparameter *broken-subtotal-check*
  (cl-spec:check-function 'broken-cart-subtotal :seed 42))
(cl-spec:property-result-status *broken-subtotal-check*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken-subtotal-check*)
;; => :POSTCONDITION
(cl-spec:property-result-shrunk-counterexample *broken-subtotal-check*)
;; => (CART ((:SKU "Qs6Z64Zb5" :PRICE 1 :QTY 1)))   ; 例えば
```

`:postcondition` は事後条件が破れたことを示します。縮小後の反例は明細 1 件のカートで、
正しい小計は 1 なのに `broken-cart-subtotal` は 0 を返し、`(>= 0 1)` が偽になります。
property と同じく、関数契約の結果も反例・縮小・replay の読み方は共通です。

property と関数契約は、次のように使い分けます。

- 関数契約: 1 つの関数単体の入出力の約束。引数の spec、戻り値の spec、引数と戻り値の関係。
- property: 複数の呼び出しや複数の関数にまたがる法則。第 3 章の性質は `cart-subtotal` を
  3 回呼んで結果を比べるので、1 回の呼び出しの契約としては書けません。

> **この章のまとめ**: `defspec-function` で引数・戻り値・事後条件を契約として書き、
> `check-function` で検査します。関数単体の約束は契約、呼び出しをまたぐ法則は property です。

## 6. エラーを約束する

不正な入力に対して決まったエラーを出すことも、関数の約束の一部です。数量が 1 未満なら
`invalid-quantity` を signal する明細のコンストラクタを書きます。

```lisp
(define-condition invalid-quantity (error)
  ((qty :initarg :qty :reader invalid-quantity-qty))
  (:report (lambda (condition stream)
             (format stream "Quantity ~D is less than 1."
                     (invalid-quantity-qty condition))))
  (:documentation "Signalled by MAKE-LINE-ITEM for a quantity below 1."))

(defun make-line-item (sku price qty)
  "Return a line item plist, or signal INVALID-QUANTITY when QTY is below 1."
  (when (< qty 1)
    (error 'invalid-quantity :qty qty))
  (list :sku sku :price price :qty qty))
```

このエラーの約束を契約として書きます。

```lisp
(cl-spec:defspec-function make-line-item
  (:args (sku string) (price price) (qty (range integer -10 0)))
  (:signals (type invalid-quantity)))
```

- `:signals` は「この関数は、この spec を満たすエラーを出して終わらなければならない」という
  約束です。正常に値を返すと違反になります。
- `qty` の spec を `(range integer -10 0)` にしているのは、この契約が「不正な数量に
  ついての約束」だからです。生成される数量はすべて 1 未満なので、どの試行でもエラーが
  期待されます。正常系と異常系を 1 つの契約にまとめる方法は、次章の `:cases` で扱います。
- `(type invalid-quantity)` の `type` には意味があります。spec の中で、自分で定義した
  （CL の型名ではない）裸のシンボルは登録済みの spec 名として解釈されます。そのため
  `(:signals invalid-quantity)` と書くと「`invalid-quantity` という名前の spec」を探しに
  行き、見つからずに契約側のエラーになります。自作の condition クラスは
  `(type invalid-quantity)` のように `type` で包みます。

検査します。

```lisp
(defparameter *item-check* (cl-spec:check-function 'make-line-item :seed 42))
(cl-spec:property-result-status *item-check*)
;; => :PASSED
```

比較のため、不正な数量を黙って 1 に直してしまう実装を用意します。

```lisp
(defun broken-make-line-item (sku price qty)
  "A deliberately wrong constructor: it silently raises a bad quantity to 1."
  (list :sku sku :price price :qty (max qty 1)))

(cl-spec:defspec-function broken-make-line-item
  (:args (sku string) (price price) (qty (range integer -10 0)))
  (:signals (type invalid-quantity)))

(defparameter *broken-item-check* (cl-spec:check-function 'broken-make-line-item :seed 42))
(cl-spec:property-result-status *broken-item-check*)
;; => :FAILED
(cl-spec:property-result-failure-reason *broken-item-check*)
;; => :MISSING-CONDITION
```

`:missing-condition` は、エラーが期待されていたのに関数が正常に値を返したことを示します。
反例も、これまでと同じように `property-result-shrunk-counterexample` で読めます
（例えば `(SKU "O4skdc" PRICE 1 QTY 0)`。数量 0 を渡しても、エラーにならずに明細が返って
きたということです）。

> **この章のまとめ**: `:signals` で「このエラーを出して終わる」という約束を書けます。
> 自分で定義した condition は `(type ...)` で指し、正常に返ってしまうと
> `:missing-condition` で失敗します。

## 7. 条件ごとに約束を分ける

小計に応じて割引する関数を書きます。小計が 5000 未満なら割引なし、5000 以上なら 10% 引きで、
割引額の端数は切り捨てます。

```lisp
(defun discounted-total (subtotal)
  "Return SUBTOTAL, less 10% rounded down when SUBTOTAL is 5000 or more."
  (if (< subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))
```

この関数の約束は、入力の範囲によって変わります。そこで `:cases` を使い、条件ごとに名前を
付けた約束を書きます。

```lisp
(cl-spec:defspec-function discounted-total
  (:args (subtotal (range integer 0 20000)))
  (:cases
    (:no-discount
      (:when (< subtotal 5000))
      (:returns (range integer 0 *))
      (:post (= result subtotal)))
    (:ten-percent-off
      (:when (>= subtotal 5000))
      (:returns (range integer 0 *))
      (:post (and (< result subtotal)
                  (<= (* 9 subtotal) (* 10 result)))))))
```

- 各 case は名前（`:no-discount`、`:ten-percent-off`）と、条件 `:when` を 1 つ、
  結果の約束 `:returns` または `:signals` を 1 つ持ちます。`:returns` の case には `:post`
  も書けます。
- case の選択は排他的です。入力ごとにすべての `:when` を評価し、ちょうど 1 つが真で
  なければなりません。どれも真でない場合や複数が真の場合は、関数の誤りではなく契約側の
  エラーとして報告され、関数は呼ばれません。
- `:ten-percent-off` の `:post` は、実装の式（`(- subtotal (floor subtotal 10))`）を
  書き写していません。「割引後は元より小さく、元の 9 割以上」という性質として書いています。
  実装を写すと、実装と同じ間違いを契約にも書いてしまうおそれがあるからです。

検査します。

```lisp
(defparameter *discount-check* (cl-spec:check-function 'discounted-total :seed 42))
(cl-spec:property-result-status *discount-check*)
;; => :PASSED
```

`:cases` を持つ契約の結果には、case ごとの集計が付いています。

```lisp
(getf (cl-spec:function-check-result-case-report *discount-check*) :cases)
;; => ((:NAME :NO-DISCOUNT :DOCUMENTATION NIL :CALLED 27 :PASSED 27 :FAILED 0 :ERROR 0)
;;     (:NAME :TEN-PERCENT-OFF :DOCUMENTATION NIL :CALLED 73 :PASSED 73 :FAILED 0 :ERROR 0))
(getf (cl-spec:function-check-result-case-report *discount-check*) :never-called)
;; => NIL
```

`:called` はその case が選ばれて関数が呼ばれた回数です。各 case の回数は生成された値に
よるので、例えば上のように 27 回と 73 回になります（合計は試行回数の 100 です）。
`:never-called` は一度も呼ばれなかった case の一覧で、ここでは空です。

試行回数を 1 回にすると、どうなるでしょうか。

```lisp
(defparameter *one-trial-check*
  (cl-spec:check-function 'discounted-total :trials 1 :seed 42))
(cl-spec:property-result-status *one-trial-check*)
;; => :PASSED
(getf (cl-spec:function-check-result-case-report *one-trial-check*) :never-called)
;; => (:NO-DISCOUNT)   ; 例えば
```

1 回しか試していないので、片方の case しか呼ばれていません（どちらが残るかは引いた値に
よります）。それでも結果は `:passed` です。`:passed` は「呼ばれた case で違反がなかった」
という意味であり、すべての case を試したという意味ではありません。`:cases` を使ったら、
status と一緒に `:never-called` も読む習慣をつけてください。

> **この章のまとめ**: `:cases` で条件ごとに名前の付いた約束を書けます。選択は排他的で、
> 結果には case ごとの集計が付きます。`:passed` でも `:never-called` が空とは限りません。

## 8. 1 回だけ確かめる

割引の境界を間違えた実装を用意します。`<` を `<=` にしてしまったので、小計がちょうど 5000
のときに割引されません。

```lisp
(defun broken-discounted-total (subtotal)
  "A deliberately wrong total: it starts the discount above 5000, not at it."
  (if (<= subtotal 5000)
      subtotal
      (- subtotal (floor subtotal 10))))

(cl-spec:defspec-function broken-discounted-total
  (:args (subtotal (range integer 0 20000)))
  (:cases
    (:no-discount
      (:when (< subtotal 5000))
      (:returns (range integer 0 *))
      (:post (= result subtotal)))
    (:ten-percent-off
      (:when (>= subtotal 5000))
      (:returns (range integer 0 *))
      (:post (and (< result subtotal)
                  (<= (* 9 subtotal) (* 10 result)))))))
```

ランダムに検査してみます。

```lisp
(cl-spec:property-result-status
 (cl-spec:check-function 'broken-discounted-total :seed 42))
;; => :PASSED
```

バグがあるのに `:passed` です。このバグが表に出るのは小計がちょうど 5000 のときだけで、
0〜20000 の範囲から 100 回引いても、5000 ちょうどが出ることはまずありません。第 3 章で
注意したとおり、`:passed` は証明ではありません。

境界値のように、試したい入力が分かっているときは `check-call` を使います。`check-call` は
引数リストを 1 つ受け取り、その入力で契約を 1 回だけ検査します。

```lisp
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(4999)))
;; => :PASSED
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(5000)))
;; => :FAILED
(cl-spec:call-check-result-status
 (cl-spec:check-call 'broken-discounted-total '(5001)))
;; => :PASSED
```

5000 だけが失敗しました。その 1 回の観測を見てみます。

```lisp
(defparameter *at-5000* (cl-spec:check-call 'broken-discounted-total '(5000)))
(cl-spec:trial-observation-case (cl-spec:call-check-result-observation *at-5000*))
;; => :TEN-PERCENT-OFF
(cl-spec:trial-observation-reason (cl-spec:call-check-result-observation *at-5000*))
;; => :POSTCONDITION
```

5000 では `:ten-percent-off` の case が選ばれ、その事後条件（割引後は元より小さい）が
破れています。実装は 5000 をそのまま返したからです。

`check-call` は、引数の生成、縮小、過去の結果からの replay を行いません。与えた引数で、
引数の検査、case の選択、1 回の呼び出し、結果の検査を行うだけです。そのため check-it を
読み込まない `cl-spec` 本体だけでも動きます。境界値や、不具合報告に書かれていた入力を
直接確かめる用途に向いています。

> **この章のまとめ**: ランダム検査は特定の 1 点を見逃すことがあります。試したい入力が
> 分かっているときは `check-call` で、その入力について契約を 1 回だけ確かめます。

## 9. 次に読むもの

ここまでで、値の仕様、構造化データ、property、関数契約、エラー契約、case、1 回だけの検査を
一通り使いました。より詳しい内容は次の文書にあります。guides は英語です。

- [構造化データ walkthrough](guides/structured-data-walkthrough.md):
  alist、hash-table、`object-of`、`tagged-by`、AND の生成など、plist 以外の構造化データ。
- [cases walkthrough](guides/function-spec-cases-walkthrough.md):
  `:cases` の選択規則と、選択エラーや case 別集計の詳細。
- [状態観測 walkthrough](guides/state-observation-walkthrough.md):
  呼び出し前の状態を `:capture` で観測し、呼び出し後を `:state-post` で検査する契約。
- [再現可能な状態付き契約](guides/reproducible-stateful-contracts.md):
  `:fixture` で状態を組み立て直し、状態付き契約を繰り返し検査できるようにする方法。
- [coverage](guides/coverage.md): 合否とは別に、検査で何を試したかを記録する opt-in の仕組み。
- [evidence sufficiency](guides/evidence-sufficiency.md):
  実行結果の status とは別に、得られた証拠が明示した要件を満たすかを評価する仕組み。
- [self-specification](guides/self-specification-guide.md):
  cl-spec 自身の API を cl-spec の契約と法則で記述したバンドル。
- [API リファレンス](api/README.md): 公開されている関数・マクロの一覧。
- [仕様書](cl-spec-specification-v0.2-draft.md): cl-spec の設計と規範的な定義。
- README の [Runtime instrumentation](../README.md#runtime-instrumentation) 節:
  関数契約を実行時の呼び出しに対して検査する方法。
