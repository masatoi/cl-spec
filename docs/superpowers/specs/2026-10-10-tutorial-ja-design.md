# 日本語入門チュートリアルの設計

日付: 2026-10-10
状態: 実装済み（ブランチ docs/tutorial-ja）。
基準: main 2538477（PR #39 マージ後）

## 1. 目的

`docs/` には機能別の guides（すべて英語）と自動生成の API リファレンスがあるが、
cl-spec を初めて使う人が最初に読む一本道の文書がない。README は機能の網羅であり、
学習順には並んでいない。

本設計は、日本語の入門チュートリアルを一本追加する。英語版は後続作業とし、
本設計の範囲外とする。

### 読者

Common Lisp は書けるが、cl-spec も property-based testing（PBT）も初めての人。
LLM エージェント向けの使い方（cl-mcp の `spec-check` など）は扱わない。

### 成功条件

- 読者が本文を上から順に REPL で実行し、記載どおりの結果を得られる。
- 本文に載せた結果が API 変更で古くなったとき、`rove cl-spec.asd` が失敗する。
- 読了後、読者が機能別 guides に進むための語彙と道筋を持っている。

## 2. 範囲

扱う: `defspec`、`validp`、`explain-data`、`sample`、plist spec、`list-of`、
`defproperty`、`run-property`、seed、shrink、replay、`defspec-function`
（`:args`、`:returns`、`:post`）、`check-function`、`:signals`、`:cases`、
`check-call`。

扱わない（「次に読むもの」で guides へ案内するだけ）: runtime instrumentation、
`:capture` / `:state-post`、`:fixture`、coverage、evidence sufficiency、
counterexample artifact、alist / hash-table / `object-of` / `tagged-by`、
custom generator、self-specification bundle。

## 3. ファイル

| ファイル | 内容 |
|---|---|
| `docs/tutorial.ja.md` | 本文（日本語）。入口なので guides ではなく `docs/` 直下。英語版は将来 `docs/tutorial.md`。 |
| `examples/tutorial-cart.lisp` | 本文のコードの実体。inferred subsystem `cl-spec/examples/tutorial-cart`。 |
| `tests/tutorial-cart-example-test.lisp` | 各 `demo-*` を実行し本文の結果を検証する。`tests.lisp` に登録する。 |
| `README.md` | Documentation 節にチュートリアルへのリンクを追加する。 |
| `CLAUDE.md` | Systems 表に example 行を追加する。 |

`cl-spec.asd` は変更しない。example の `defpackage` にある bare
`(:import-from #:cl-spec/src/backends/check-it)` が check-it backend への依存を
宣言する（既存 example と同じ）。

## 4. 題材

ショッピングカートの金額計算を全章で育てる。既存 example の銀行口座（withdraw）や
時間区間（batch）と重ならない。

- `price`: 正の整数（円）。
- `quantity`: 1 以上の上限付き整数。
- `line-item`: plist `(:sku string :price price :qty quantity)`、`:closed t`。
- `cart`: `line-item` のリスト（長さに上限を設け、生成と縮小を速く保つ）。
- `cart-subtotal`: Σ price × qty。
- `broken-cart-subtotal`: 縮小後の反例が明細 1 件程度になる、読んで原因が分かるバグを
  含む版（例: 先頭明細を落とす）。具体的なバグは実装計画で決める。
- `make-line-item`: 数量が 1 未満なら condition `invalid-quantity` を signal する。
- `discounted-total`: 小計 5000 未満は割引なし、5000 以上は 10% 引き（端数の扱いは
  実装計画で固定する）。

## 5. 章立て

0. **はじめに**: cl-spec とは何か、PBT を一段落で。前提（SBCL、ASDF、check-it）と
   読み込み方。example ファイル版は専用 registry に登録している旨の注記。
1. **値の仕様**: `defspec` で `price`、`quantity`。`validp`、`explain-data` の
   `:errors`（`:kind`、`:path`、`:expected`）の読み方、seed つき `sample`。
2. **構造化データ**: `line-item` の plist spec と `cart`。欠落 key、未知 key、
   値の誤りに対する `explain-data` と `:path (:qty)`。
3. **性質を書く**: 「連結したカートの小計は各小計の和」を `defproperty` で書き、
   `run-property` で `:passed`。`:passed` は観測した試行で違反がなかったという意味で
   あり証明ではない、と一言触れる。
4. **バグを見つける**: `broken-cart-subtotal` の同じ性質が失敗する。counterexample、
   shrunk counterexample、結果を `:seed` に渡す replay を順に読む。縮小は最小を
   約束しないことに触れる。
5. **関数契約**: `defspec-function`（`:args`、`:returns`、`:post`）と
   `check-function`。正しい実装は通り、壊れた実装は反例を返す。property との
   使い分け（関数単体の入出力の約束 vs 複数の操作にまたがる法則）。
6. **エラー契約**: 不正な数量に対する `make-line-item` を `:signals` で書く。
   正常に返ると `:failed / :missing-condition` になることを示す。
7. **条件ごとの契約**: `discounted-total` を `:cases` で書く。
   `function-check-result-case-report` の各 case の `:called` と `:never-called` を
   読み、`:passed` が全 case の実行を意味しないことを確認する。
8. **1 回だけの確認**: `check-call` で境界値 4999 と 5000 を確かめる。
   生成器を使わないので check-it なしでも動くことに触れる。
9. **次に読むもの**: 各 guide、API リファレンス、仕様書への案内。

## 6. 実行可能性の担保

既存 walkthrough（structured-data、function-spec-cases、state-observation）と
同じ方式をとる。

- `examples/tutorial-cart.lisp` はロード時に関数と condition を定義するだけで、
  spec の登録、値の生成、demo の実行はしない。呼び出し側の `*registry*` を変えない。
- `make-example-registry` と `register-example!` が専用 registry に全定義を登録する。
  `register-example!` 内のフォームは本文で読者が打つフォームと同じにする。
- 章ごとに `demo-*` 関数を置き、本文に載せる結果を plist で返す。
- 本文は読者が REPL（`cl-user`）に打つ形（`cl-spec:defspec ...`）で示す。
  ファイル版との関係は第 0 章で一度だけ説明する。
- seed は固定する。status、failure reason、case report の件数など決定的な値は
  テストで完全一致を検証する。check-it の実装に依存して揺れうる値（生成値や反例の
  具体値）は本文で「例えば」と示し、テストでは形（明細の件数、型、spec への適合）
  を検証する。
- 制約: 本文のコード片と example ファイルの一致は機械的に検証しない
  （既存 walkthrough と同じ）。

## 7. 言語と体裁

- 本文は日本語。識別子、API 名、REPL の出力は原文のまま。
- example とテストのコード、コメント、docstring は英語（リポジトリの流儀）。
- Google Common Lisp Style Guide、100 桁以内、ファイル先頭は `;;;; <path>`。

## 8. 検証

- `rove cl-spec.asd` の全件が通る。新しいテストが実際に走っていることを確認する。
- 新しい Lisp プロセスで `(asdf:compile-system :cl-spec :force :all)` と
  `(asdf:compile-system "cl-spec/examples/tutorial-cart" :force :all)` を実行し、
  警告がないことを確認する（example は root system の依存ではないため、前者だけでは
  コンパイルされない）。
- mallet は参考扱い（現状 PR をブロックしない）。
- 本文のコード片を新しいイメージで上から実行し、記載どおりの結果になることを
  一度手で確かめる。
