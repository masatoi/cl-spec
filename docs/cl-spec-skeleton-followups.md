# cl-spec スケルトンからの持ち越し事項

- 日付: 2026-09-08
- 対象: `docs/superpowers/plans/2026-09-08-cl-spec-skeleton.md` の実行中に見つかり、意図的に先送りした事項
- 状態: スケルトンは完成。ここに挙げたものは実装フェーズで決める

スケルトン構築中に、実装より先に決めておくべき設計判断と、既知の技術的負債が出た。作業ログ自体は git 管理外の一時領域にあったため、判断が必要なものだけをここに残す。

## 1. `cons-of` に対応する IR ノードがない（実装前に決める）

**決着**（`docs/superpowers/specs/2026-09-08-cl-spec-mvp-design.md` §2.2）: 選択肢1を採用。
`*spec-primitives*` から `"CONS-OF"` を外し、仕様書 §9 に post-MVP の注記を足した。

`src/normalize.lisp` の `*spec-primitives*` は `"CONS-OF"` を受理ヘッドとして宣言しているが、`src/ir.lisp` に `cons-of-spec` は存在しない。

仕様書の3箇所が食い違っている。

| 箇所 | `cons-of` | `not` |
|---|---|---|
| §9 初期primitive候補 | あり | あり |
| §52 MVPでサポートするSpec | **なし** | **なし** |
| §7 IRクラス階層 | **なし** | あり（`not-spec`） |

現在の `*spec-primitives*` は §9 を写している。`not` は §7 に IR ノードがあるので問題ないが、`cons-of` はどこにも置き場所がない。

`normalize-spec-form` を書く人が `(cons-of a b)` を受け取った時点で必ず詰まる。選択肢は3つ。

1. `*spec-primitives*` から `"CONS-OF"` を外す。§52 の MVP 定義と一致し、全ヘッドが IR ノードを持つ状態になる。仕様書側に「cons-of は post-MVP」と注記する。
2. `cons-of-spec`（car-spec / cdr-spec を持つ）を `src/ir.lisp` に追加し、§7 を更新する。
3. `tuple-spec` の糖衣として定義する。cons は 2 要素リストではないので意味論的には正しくない。

**`normalize-spec-form` の実装に着手する前に決めること。** 実装後に変えるほうが高くつく。

## 2. `*spec-primitives*` は名前で照合する

シンボルではなく名前文字列のリストにしてある。理由は `src/normalize.lisp` の docstring にも書いたが、重要なので再掲する。

利用者は `(defspec foo (and integer (range 1 *)))` を**自分のパッケージで**書く。そこの `range` は `cl-spec/src/normalize` にインターンされた `range` と `eq` ではない。したがって normalizer はヘッドを `symbol-name` で照合しなければならない。`member` を `:test #'eq` で使う実装は、テストでは通っても実利用で壊れる。

## 3. source-location のアクセサが public API に出ていない

**決着**（`docs/superpowers/specs/2026-09-08-cl-spec-mvp-design.md` §2.8）: `spec-data` /
`property-data` は `:source-location` を展開済み plist で返し、`source-location-file` /
`source-location-package` も `main.lisp` から re-export した。

`spec-source-location` / `property-source-location` / `function-spec-source-location` は `main.lisp` から re-export されているが、その戻り値を読むための `source-location-file` / `source-location-package` は re-export されていない。`src/utils/source-location.lisp` の docstring は「戻り値は opaque として扱い、このパッケージのアクセサで読むこと」と書いているので、現状 public API の利用者は内部パッケージに手を伸ばすか、opacity 契約を破って `getf` するしかない。

introspection を実装するときに、アクセサを公開するか、`spec-data` が展開済みの形で返すかを決める。

## 4. `defgenerator` の登録先がない

**未決着**: `defgenerator` がMVPスコープ外のため（`docs/superpowers/specs/2026-09-08-cl-spec-mvp-design.md`
§1.2）、この判断は先送りされたままである。

`src/dsl.lisp` の `expand-generator-definition` の docstring は「ユーザー定義 generator を登録する」と書いているが、`hash-table-registry` は spec / function-spec / property の3索引しか持たない。generator は4つ目のエンティティ種別で、置き場所がない。

後から追加すると、スケルトンで唯一**完全に実装済み**の `src/registry.lisp` — クラス、protocol、`registry-clear` — を変更することになる。`defgenerator` を実装する前に、registry に generator 索引を足すのか、別の仕組みにするのかを決める。

## 5. registry への到達手段が API 全体で不揃い

**部分的に決着**（`docs/superpowers/specs/2026-09-08-cl-spec-mvp-design.md` §2.6）: designator を
受ける公開関数のうち11個だけを `:registry` キーワードへ統一した。対象は `validp` `validate`
`explain-data` `explain` `generator-for` `sample` `run-property` `run-properties`
`replay-property` `spec-data` `property-data`（全て `src/validator.lisp` `src/explain.lisp`
`src/generator.lisp` `src/property-runner.lisp` `src/introspection.lisp` で実測確認済み）。

残りは§2.6が明示的に据え置くと決めた、意図的な不揃いである。

- registry front-end（`find-spec` `list-specs` `find-function-spec` `list-function-specs`
  `find-property` `list-properties` `properties-for` `properties-with-tag` `register-spec`、
  いずれも `src/registry.lisp`）と `register-property`（`src/property.lisp`）
  `register-function-spec`（`src/function-spec.lisp`）`instrument-function`（`src/instrument.lisp`）
  は `&optional (registry *registry*)` の位置引数のまま。§2.6は「互換のため残す」と明言している。
  `register-property` / `register-function-spec` は `main.lisp` から re-export される public API
  でもあり、統一対象11個には最初から含まれていない — `:registry` キーワードで呼べると仮定した
  コードはこの2つに対して型エラーになる。
- `compile-validator` / `compile-explainer` / `compile-generator` は `&key context` のまま。
  §2.6は「context は registry を含む compile 時の環境であり、registry 単体とは別物」として
  意図的に変更対象から外している。
- `describe-spec` / `describe-property`（`&optional (stream *standard-output*)`、registry を
  受ける引数自体が無い）と `check-function`（`&key trials seed options`、同じく registry 引数が
  無い）には到達手段がまだ無い。動的束縛でしか差し替えられない。

したがって元々この項目が指摘していた不揃いは、11関数については解消されたが、それ以外の関数では
今もそのまま残っている。ただしこれはもう「未決定だから揃っていない」のではなく、§2.6が下した
意図的な設計判断（互換性優先、あるいは context と registry を混ぜない）である。

なお `register-spec` は `(name spec &optional registry)` で、兄弟の `register-function-spec` / `register-property` はオブジェクトだけを取って名前を導出する。これは `src/registry.lisp` のヘッダコメントに理由が書いてあるが、export 一覧からは見えない。

## 6. lint（mallet）の負債

スケルトン構築中、mallet はブロッカーにしない方針で進めた。まとめて直すときの対象は以下。

- `src/instrument.lisp` — `cl-spec/src/validator` から `validate` を import しているが呼んでいない（`unused-imported-symbols`）。**削除しないこと。** ASDF に `src/instrument` → `src/validator` の依存辺を認識させるための前方宣言で、ラッパーが `validate` を呼ぶ時点で実体を持つ。良かれと思った cleanup で消すと依存辺が失われ、次のタスクで戻すことになる。理由を書いたコメントを添えるのが望ましい。
- `tests/dsl-test.lisp` — `no-eval` 4件。リポジトリルートの `.mallet.lisp` でパス限定で無効化済み。DSL マクロの展開結果を**実行して** `not-implemented` を検証する唯一の手段であり、`macroexpand-1` だけでは契約の後半を証明できない。この例外を残すかどうかは cleanup 時に再検討する。
- `.github/workflows/lint.yml` は `continue-on-error: true` で advisory。この cleanup が終わったら外す。

タスク15（自己property・ドキュメント同期）時点の `mallet main.lisp tests.lisp src/*.lisp
src/*/*.lisp tests/*.lisp tests/*/*.lisp` 実行結果は13件、すべて既存カテゴリ内。

- `unused-imported-symbols` 11件。上記の `src/instrument.lisp` の1件に加え、`src/explain.lisp`
  ・`src/backends/check-it-generators.lisp` の `collection-spec`、`src/utils/random.lisp` の
  `unsupported-seed`、複数のテストファイルの補助 import。`tests/self-properties-test.lisp` の
  `check-it-backend` と `list-specs` の2件もここに含まれる。`check-it-backend` は本文で参照しない
  ままASDFにgenerator backendをロードさせるための意図的な import（task-15-brief参照）、
  `list-specs` はbriefのdefpackageをそのまま転記したもの。どちらも削除しないこと。
- `needless-let*` 2件（`tests/resolve-test.lisp`、`tests/utils/random-test.lisp`）。
- `no-eval` は `.mallet.lisp` の `:for-paths` で `tests/dsl-test.lisp`・
  `tests/property-runner-test.lisp`・`tests/introspection-test.lisp`・
  `tests/self-properties-test.lisp` に対して無効化済みのため、この実行では報告されない。

## 7. テストの薄い箇所（機能には影響しない）

- `tests/utils/source-location-test.lisp` の `source-location-readers` は「レイアウト非依存」と述べているが、fixture が想定どおりのキー順しか使っていない。`getf` の性質上その主張は真だが、テストは証明していない。
- `src/registry.lisp` の `symbol-sort-key` にある `symbol-package` が NIL の場合のガードは、どのテストも通らない。到達するには uninterned symbol を登録する必要があり、設計上そうする箇所はない。
- `tests/backends/check-it-test.lisp` の `default-trials-comes-from-check-it` は `integerp` と `plusp` しか見ていない。`default-trials` が `check-it:*num-trials*` の load-time スナップショットに変わっても通る。テスト内で `check-it:*num-trials*` を別の値に束縛して戻り値を突き合わせれば、live read の契約を実際に固定できる。

## 完成時点で検証済みの不変条件

以下はスケルトン完成時に実測で確認してある。実装フェーズで壊していないかの基準になる。

- `(asdf:load-system :cl-spec)` は `CHECK-IT` パッケージを一切引き込まない
- cold cache での `(asdf:load-system :cl-spec)` と `(asdf:compile-system :cl-spec :force :all)` がどちらも警告 0
- `cl-spec/check-it` と `cl-spec/instrument` が単体でロードできる
- `rove cl-spec.asd` が 16 test system すべて green
- 仕様書 §51 の MVP API 24 symbol が `cl-spec` パッケージから external かつ到達可能（`tests/main-test.lisp` が検証）
- ディスク上の test ファイル 16 個がすべて `tests.lisp` に列挙されている
