# 再構築可能な Stateful Function Contract 設計案

日付: 2026-09-26
状態: レビュー用ドラフト。以下の新構文・API・結果フィールドは未実装。
対象: 仕様 §17.3、§17.4、§73.5 B。実装計画ではなく意味論と境界の提案。

## 1. 目的と前提

状態を変更する関数について、各試行を明示された開始状態から実行し、
同じ失敗の縮小・再生成replay・保存反例の直接再検査を可能にする。
LLMが修正前後を比較する根拠を、変更済みのREPL内オブジェクトから切り離す。

既存の :capture / :state-post の評価順序、case選択、期待error、多値、
失敗identityを再利用する。状態の観測と再構築は別の能力として扱う。
coreにcheck-itやcl-mcpへの依存を追加しない。

初版はメモリ内の専有状態を毎回新規作成する :fresh 方式を前提とする。
これは今回の設計上の仮定であり、ユーザーが外部DBを必須と指定したものではない。
DB fixtureとworker監督は後続段階とし、対応していない保証をcapabilityに表示しない。

## 2. 方式の比較と選択

| 方式 | 長所 | 問題・判断 |
|---|---|---|
| recipeから新規作成 | 保存・縮小する値が単純。既存generator/codecを利用できる | アプリ作者が構築手順を書く。初版に採用 |
| 同じ実オブジェクトのsnapshot/restore | 既存インスタンスを直接検査できる | alias、CLOS、外部資源、部分復元の意味論が大きい。初版対象外 |
| プロセス単位の隔離 | メモリ破損やハング後の隔離に有効 | 外部DBの復元は別途必要。cl-mcp等の監督側が必要。後続 |

汎用deep-copy、任意オブジェクトcodec、state-machine PBT、
並行操作列、業務呼び出しのrollbackは導入しない。

## 3. 中心となる三つの値

1. recipe: 初期状態と操作入力を表す再構築データ。
2. call arguments: setupが作り、実際の関数へ渡すraw引数リスト。
3. fixture context: setupからcleanupへ資源情報を渡す、試行専用の一時領域。

生成・縮小・保存するのはrecipe。実引数とcontextは永続化しない。
recipeは既存AV1 codecで往復可能なbounded treeに限定する。
alias、cycle、opaque値を黙ってコピーして意味を変えない。
この制限はartifact生成時だけでなく、fixture実行入力の受理時に検査する。
生成器もrecipeの構築のみを行い、実オブジェクトや外部資源を確保しない。

同じrecipeから意味的に同じ初期状態を作ることはfixture作者の契約である。
frameworkはsetupを毎回呼ぶが、任意のアプリ状態の等価性を証明しない。
時刻、乱数、外部応答が意味に影響するならrecipeへ含めるか専有の依存へ注入する。
ambientな乱数seedを揃えることだけを状態再構築とは呼ばない。

## 4. 宣言API案

新しいregistry entityを増やさず、Function Specにinlineの :fixture を一つ持たせる。
共有したい実装は通常のLisp関数として呼ぶ。

```lisp
;; 新構文の提案。make-account等はアプリ側の関数。
(cl-spec:defspec-function withdraw!
  (:args (account (satisfies account-p))
         (amount (range integer 1 1000)))
  (:fixture
    (:isolation :fresh)
    (:version 1)
    (:recipe (recipe (tuple (range integer 0 1000)
                            (range integer 1 1000))))
    (:setup (context)
      (destructuring-bind (balance amount) recipe
        (let ((account (make-account :balance balance)))
          (setf (gethash :account context) account)
          (list account amount))))
    (:cleanup (context)
      (clrhash context)))
  (:capture (before (account-balance account)))
  (:cases
    (:enough
      (:when (<= amount before))
      (:returns (satisfies listp))
      (:state-post (= (account-balance account) (- before amount))))
    (:insufficient
      (:when (> amount before))
      (:signals (type insufficient-funds))
      (:state-post (= (account-balance account) before)))))
```

- :isolation は初版では :fresh のみ。:version は正整数の作者管理revision。
- :recipe は一つの (NAME SPEC)。NAMEはsetup/cleanup内だけに束縛する。
- :setup / :cleanup はそれぞれ一つ、context変数一つと非空bodyを持つ。
- contextはframeworkが試行ごとに作る空のEQ hash-table。永続化・公開投影しない。
- setupの主値はraw引数の有限proper list。余分な戻り値は使用しない。
- cleanupの戻り値は使用しない。通常終了を「作者のcleanup契約が完了した」と記録する。
- cleanupはsetupが途中で失敗したcontextも受け付ける。NIL値と未登録を区別する。
- recipeはtarget引数、capture、case guard、postへ暗黙に束縛しない。
- :args は実関数の呼出しschemaのまま。optional/key/restを引き続き利用できる。
- :fixture と従来の :args-generator の同時指定は定義時に拒否する。
  recipeのcustom generatorはrecipe specの既存generator注釈で指定する。
- fixtureはトップレベルのみ。caseごとのfixtureやfixtureの入れ子は初版非対応。
- :capture / :state-post がなくてもfixtureは宣言できる。戻り値の失敗にも独立試行は必要。

:fresh は、新規の可変状態を試行が専有し、次の試行や共有globalへ漏らさない契約。
既存の共有オブジェクト、DB、ファイル、socket、thread、外部通知を操作するfixtureは
この能力の対象外。自動検出したという保証はしない。
contextを空にすること自体がrollbackなのではなく、専有メモリを到達不能にできる構成が前提。

## 5. 試行の意味論

```text
recipe schema / codec検査
  → recipeの証拠と作業用コピーを分離
  → 空contextを作成
  → unwind-protect開始
      setupを一度呼ぶ
      setupの実引数をcall schemaで検査
      既存evaluate経路
        binding → pre → capture → case → target → outcome → state-post
      説明・outcome・capture証拠を固定
    cleanupを一度呼ぶ
  → recipeの非変更とcleanup完了を確認
  → lifecycleと契約観測を合成
```

setup開始後は、成功、pre拒否、capture/guard失敗、target error、
state-post失敗、説明の構築エラーでもcleanupを試みる。
setup自体がerrorになった場合も空または部分構築済みcontextでcleanupを呼ぶ。
recipe検査以前の拒否はsetup/cleanup/targetすべて0回。

cleanupはstate-postの後。状態検査前にcleanupして変更を隠してはならない。
実引数schema違反は :fixture-arguments-error。targetを呼ばずrunを停止する。
pre拒否は従来どおり :rejected。cleanup完了後に次の通常試行へ進める。
setup失敗は生成棄却へ変換しない。

通常のcondition処理は既存evaluatorの規則を維持する。
従来伝播するPROGRAM-ERROR等をfixture機能が期待errorへ変更しない。
cleanupはunwind-protectで走るが、外向きthrow等の任意の非局所脱出を
無理にproperty-resultへ変換しない。戻らない呼出しに成功resultは存在しない。
cleanup自身の通常errorは捕捉して記録し、既存の契約証拠を上書きしない。
外向きの制御移動を起こすcleanupはfixture契約外とする。

作業用recipeをsetup等が変更したら :fixture-recipe-mutation で停止。
targetへ可変のrecipe部分を渡す場合はsetupが別コピーを作る。
実引数の変更は許可するので、それだけで縮小停止にしない。
既存の「実引数が変化したら縮小停止」はfixtureなしの経路では維持する。

## 6. 評価器とrunnerの構造

既存function-check-propertyを実引数用の内側adapterとして維持する。
新しいfixture-check-propertyは、recipeを一引数として持つ外側adapterとする。

外側の property-argument-schema は (tuple RECIPE-SPEC)。
backendが扱う内部引数は (list recipe)。
property-named-argumentsはrecipeの宣言名で投影する。
内側の function-spec-argument-schema は従来どおり実引数を表す。

observe-trialは通常propertyとfixture adapterをdispatchできるgenericへ変更し、
従来の通常methodは既存のsnapshot/classificationを維持する。
fixture methodは共通lifecycleを実行し、内側の観測を得てから、
recipe・lifecycle・凍結済みcall証拠を持つ外側観測を返す。
evaluate-trialの既存先頭6戻り値や、実引数に対する判定順序は変更しない。

新規内部関数 observe-fixture-trial を通常run、縮小、直接再検査で共有する。
backendが独自にsetup/cleanupを呼ぶ実装は認めない。
共通lifecycle moduleはFunction Specをimportせず、実引数validatorと評価callbackを受け取る。
fixture-check-propertyの定義・specialized methodはfunction-spec側に置き、
そこから共通lifecycleを呼ぶ。ASDF package inferenceの循環依存を避ける。
run開始時にfixture関数と宣言metadataを捕捉し、途中のregistry再定義で混在させない。
これは並行REPL変更全般のtransactionやclosure内状態の固定を保証しない。

## 7. 結果モデルと失敗の優先順位

契約観測と実行環境の健全性を別々に記録する。
:freshは能力宣言であって、世界全体の安全性を検査した結果ではない。

fixture result / observationには :input-kind :fixture-recipe を明記する。
既存 :arguments とcounterexample accessorはrunner入力であるrecipeを表し、
実引数の診断は別の :call-evidence へ投影する。
fixtureの結果投影はschema-version 2とし、v1 consumerによる実引数との誤読を防ぐ。
fixtureなしのresult/call-check-dataはv1を維持する。

追加するlifecycleレコード:
- :setup / :evaluation / :cleanup: :not-started、:completed、:error、:interrupted。
- :state: :not-acquired、:released、:unknown。
- :errors: phase、reason、condition-type、bounded reportの順序付き一覧。
- :target-called: T / NIL / :unknown。conditionの型から推定しない。
- :completion: :completed / :aborted / :interrupted。

通常cleanup完了なら :released。cleanup失敗・中断なら :unknown。
「元の口座を復元した」とは表示しない。
setup未実行なら :not-acquired。実行途中の状態不明をこの値で隠さない。

| 状況 | 公開結果 | 継続 |
|---|---|---|
| outcome/state-post成立、cleanup成功 | :passed | 次の試行可 |
| pre拒否、cleanup成功 | :rejected（runでは棄却数へ） | 次の試行可 |
| target契約違反、cleanup成功 | :failed、既存identity | 縮小可 |
| setup / 実引数構築の失敗 | :error、fixture phase | 停止 |
| recipe変更 | :error、fixture phase | 停止 |
| cleanup失敗 | :error、:fixture-cleanup-error、state unknown | 停止 |
| 契約違反とcleanup失敗の両方 | runは:error、内側の違反証拠も保持 | 停止 |

runの実行errorと、原反例・採用済み縮小反例を別slotに持つ。
縮小中のcleanup失敗でもrun全体を:errorとし、直前の原反例を消さない。
property-result-status / failure-reason / failure-phaseはrun errorを優先し、
:failureと:shrunk-failureには取得済みの契約観測を残す。
これに合わせてgeneratorのbackend結果検証も更新し、phaseを自由なmetadataで迂回しない。
errorだけでtargetが未実行なら、counterexampleを捏造しない。

case-reportは通常試行だけを数える。fixture開始数とtarget呼出数を混同しない。
targetを呼んだ後のcleanup失敗でも当該caseの:calledは1回。
その通常試行は最終:errorとして1回計数し、先行するstate違反は内側証拠に残す。
setup失敗はどのcaseの:calledも増やさない。fixture error数を別に持つ。
縮小候補はcase-reportへ混ぜず、shrink-reportに記録する。

call-evidenceは既存capture-valueのavailability規則に合わせる。
opaque実引数・戻り値をlive referenceのまま「凍結済み」と公開しない。
実引数の完全保存は要求せず、再実行の根拠にはrecipeを使う。

## 8. Shrinking

recipe用の既存generator/shrinkerを使う。custom/通常の両縮小経路に適用する。
各候補についてrecipe検査→setup→実引数検査→共通評価→cleanupを完結させる。
recipe nodeのcustom shrinkerを、tuple内部の既存縮小が自動的に扱うとは仮定しない。
check-it側に一引数のwrapperを設け、recipe生成値を (list recipe) へ、
recipe縮小候補を各一要素リストへ変換してwhole-argument縮小経路へ接続する。
custom shrinkerの候補数上限・入力非変更検査はwrapperの前後で維持する。

採用条件は、入力が適合し、targetが呼ばれ、cleanupが完了し、
recipeが変更されず、原反例と同じfailure identityを持つこと。
case名とstate-post式indexは既存identityをそのまま使う。
recipeの値、資源identity、実行IDをfailure identityへ混ぜない。

pre拒否・別caseの別失敗は採用しない。
capture/guard error、setup error、cleanup errorを小さな反例として採用しない。
原観測がtargetに到達していない場合は従来どおり縮小しない。
state-post phaseが存在するというだけで一律に禁止する分岐は改める。

候補予算には不適合・棄却候補も含め、既存bounded探索と循環候補の制限を維持する。
予算切れであっても、開始済み候補のcleanupは省略しない。
cl-specは最小性を保証せず、探索予算内で得られた同一失敗の小さい例を報告する。
cleanup失敗後に別候補へ進んではならない。

capabilityは fixture存在だけで :shrinking available としない。
実際のrecipe縮小戦略、backendのlifecycle対応、宣言上の可否を合わせて判断する。

## 9. Replayと直接再検査を分ける

### 再生成replay

check-functionに過去resultを渡す既存操作は、seedからrunを再生成する意味を維持する。
保存された一反例だけを試す操作へ読み替えない。
fixture経路では完全な一致する宣言digest、fixture version、
保存された生成設定と予算が必要。欠ける場合はsetup前に拒否する。
過去resultを渡しつつ異なる設定を指定する場合は再現操作として拒否し、
異なる実験は整数seedによる新runとして明示する。

同じrecipe列でも未管理の時計・外部乱数等まで一致するとは主張しない。
backend/Lisp環境が異なる場合の生成列の保証は既存seed機構の範囲を超えない。

### 直接recipe検査

新API案:
(check-fixture function-designator recipe &key registry)

生成・縮小を行わず、共通lifecycleを一度実行するcore API。
fixtureがない契約は拒否する。戻り値は専用fixture-check-resultとし、
fixture-check-dataでschema v2の一試行結果を取得する。
この結果からもv2 artifactを作れるようfactoryを拡張する。
seed/profileは :not-collected とし、架空の生成runを付けない。

既存check-callはcaller所有の実引数をそのまま検査し、fixtureを実行しない。
fixture宣言がある契約でも同じであり、resultに :execution-mode :direct-call を明記する。
この結果をfixtureで実行された証拠としてartifact化・再実行してはならない。
check-callがcaller所有の口座を破棄するような意味変更をしない。

## 10. Artifact v2

stateless artifact v1の意味とwire互換を維持し、fixture用はartifact-version 2とする。
データschemaのv2であり、reader-freeのAV1 wire codecを作り直す意味ではない。

v2は以下を必須とする:
- function-specの名前と完全な宣言digest、そのomissions/exclusions。
- fixture versionと :input-kind :fixture-recipe。
- 原反例と任意の採用済み縮小反例のrecipe、failure identity。
- 該当観測のlifecycle成功記録、宣言済み状態観測のbounded診断。
- selection、取得できたseed/profile/予算/options/provenance。
- target revisionはfixture identityから分離して記録する。

setup closure、context、CLOS実インスタンス、実行コードは格納しない。
codecは未知symbolをinternせず、reader evalもしない。
artifactを読むだけではsetupやtargetを実行しない。

保存できるのはtargetに到達した失敗で、対象観測とrunのlifecycleが正常終了したもの。
cleanup失敗・中断を含むrunは、以前のcleanな反例が残っていても初版では保存を拒否する。
診断用result-dataは残す。保存可否は現在のregistryでなく捕捉済み証拠から決める。
不完全digestもv2作成時に拒否する。未実行の契約側errorを反例として保存しない。

recheck-counterexampleに :state-policy :fixture を追加する。
既定の :unconfirmed とv1の :stateless は維持する。
:fixtureは登録済みfixtureを実行する方針であり、「statefulだから許可」の全解除ではない。

直接再検査の順序:
1. bounded decodeとv2 record検証。
2. 登録済み契約・fixture・宣言digest/versionの完全一致を確認。
3. recipe検査。ここまでsetup/targetは0回。
4. generatorなしで共通lifecycleを一度だけ実行。
5. :same-failure / :different-failure / :passed / :precondition-rejected を区別。
6. fixture障害は :fixture-error、state unknownを明示し、:passedへ変換しない。

target実装の変更は許す。fixtureやcontract変更で同一開始条件を失ったものは比較拒否する。
source digestは呼び出す任意helperの実装まで固定しない。
fixture作者は構築意味論の変更時に :version を更新する。
この規約への依存をdigest-exclusionsと文書に明記する。
自動的な関数依存閉包hashやfixture移行機構は初版には追加しない。

## 11. 中断とworkerの責務

coreは通常のLisp unwindingでcleanupを試みる。
無限ループ、kill、処理系crashから自分自身でresultを返すとは保証しない。
portableな強制timeout APIをこの変更だけで新設しない。

後続の監督protocol:
- 親側がrun/trial IDと :started を、workerへ実行依頼する前に記録する。
- workerはcleanup後のterminal recordを返す。
- kill/crash/通信断でterminal recordを得られなければ親側が
  :completion :interrupted / :state :unknown / :target-called :unknown を報告する。
- 遅延した古いworkerの応答はrun/trial IDで区別する。
- 不明状態を成功、未実行、正常な予算切れへ置換しない。

この監督実装はcl-mcp側に置く。coreにworker管理を持ち込まない。
coreが返したcleanup errorについても、adapterは自動で同じ検査を再試行しない。
同一runの続行を止め、監督側が隔離・廃棄方針を適用する。
通常error後のworker再利用と、外部資源が復旧したかは別問題である。

後続DB対応には、専有namespace/transaction、部分setupの回収、
接続断時の状態照会、冪等な回収、外部への非transactional副作用の範囲が必要。
単純に :fresh の許可値へ :database を追加して保証を拡張しない。

## 12. 定義整合性と互換性

fixture objectはFunction Specが所有する構造化slotとし、任意metadataに隠さない。
recipe schema、binding名、version、isolation、hook formsとcompiled functionsの
整合をmacroとobject validationの両方で検査する。
reinitialize失敗時はdefinition-validationの参加slotをrollbackする。
introspectionはhookを呼ばず、closure/contextを公開しない。

definition-descriptionの子にfixtureとrecipe specを追加し、
登録済みspec/generator依存を既存graph walkerへ接続する。
fixture未使用の定義はdigest bytes、schema v1、既存の禁止理由を維持する。
:capture / :state-postのみの契約は引き続きrestoration unavailable。
通常defpropertyへのfixture DSLは初版対象外。

fixture付き契約はruntime instrumentationを拒否する。
input-only scopeでもfixtureを無視した部分wrapperを黙って作らない。
既存のcase/expected-error/state制約についても拒否を維持する。

古いbackendがfixtureを通常の引数として処理しないよう、
backend capabilityにtrial lifecycleの対応版を追加する。
fixture実行は対応backendのみ、非対応は生成やsetupより前に拒否。
check-fixture / artifact recheckはbackendをロードしない。

## 13. 主な実装接続点

| ファイル | 責務 |
|---|---|
| 新規 src/fixture.lisp | fixture定義、validation、recipe/contextの規約 |
| 新規 src/fixture-execution.lisp | callbackを受ける共通lifecycle、一試行結果 |
| src/dsl.lisp | :fixture宣言のparserと展開 |
| src/function-spec.lisp | fixture slot、内外adapter、check-functionの選択、check-fixture |
| src/execution.lisp | observe-trial dispatch、lifecycle/call証拠 |
| src/backends/check-it.lisp | recipe縮小、phase判定、障害時の即停止 |
| src/generator.lisp | backend能力と結果整合性の検証 |
| src/property-runner.lisp | run errorと契約証拠の分離、v2投影、replay確認 |
| src/schema.lisp | fixture依存digestとcapability/introspection |
| src/counterexample.lisp | v2 factory/検証/直接再検査 |
| src/utils/artifact-values.lisp | 既存codecの再利用。値の対応範囲を拡大しない |
| main.lisp | 新規公開APIのre-exportのみ |
| specs.lisp / self-spec-fixtures.lisp | lifecycleと再検査の実行可能な自己仕様 |
| tests.lisp | 新規suiteを明示登録 |

fixture-executionはfixture定義と汎用executionに依存し、function-specには依存しない。
function-specがfixture-executionを利用する。artifactからbackend実装への依存を作らない。

## 14. 受け入れ試験

Roveで以下を実装前に固定する。個別suiteはcl-mcp run-tests、全体は既存suiteで検証する。

1. 同じrecipeを二度検査すると別EQの口座が同じ初期残高でtargetへ届く。
2. 出金成功、残高不足error、更新忘れ、error前の部分更新を既存identityで分類する。
3. pre拒否/capture/guard/outcome/state-post各経路でsetup1、cleanup1、target0または1。
4. setup途中のerrorでもcleanup1。部分contextを渡し、次trialは開始しない。
5. target違反とcleanup errorが同時でも両方の証拠が残り、runは:error。
6. state-postはcleanup前、公開証拠はcleanupによる変更後も過去値を保つ。
7. 縮小候補ごとに新しい口座。同じcaseと式indexの失敗だけ採用する。
8. 通常/custom shrinker双方でsetup/cleanupを迂回しない。
9. 縮小中のcleanup errorで次候補を実行せず、直前の反例を保持する。
10. recipeの共有/cycle/opaque値、codec予算超過はsetup前に拒否。
11. recipe破壊は停止。新規実引数の許可された変更では縮小を止めない。
12. 保存反例の再検査はcoreのみで動き、generator/seed drawは0、target最大1。
13. fixture version/digest不一致、不完全宣言はsetup前に拒否。
14. artifact読込・introspection・capability照会はsetup/cleanup/targetを呼ばない。
15. v1 artifactとfixtureなしのdigest/resultを既存fixtureで回帰検証する。
16. check-callがfixtureを実行せず、callerの実引数をそのまま使用する。
17. programmatic construction、reinitialize拒否、registry writeの整合性を検査する。
18. 非対応backendは生成前に拒否。fixture instrumentationはfdefinition変更前に拒否。
19. 0試行・全pre拒否は成功検査と表示しない。case-reportは縮小候補を数えない。
20. 外向きthrowでもcleanupを実行し、成功resultを返さない。
21. 後続adapter試験でworker killとterminal record欠落をstate unknownとして報告する。

## 15. 導入順

A. coreのrecipe/lifecycleとcheck-fixture、失敗記録、定義整合性。
B. check-functionとcheck-itの通常試行・縮小、能力判定。
C. artifact v2と直接再検査、fixture replay、自己仕様・例・ガイド。
D. cl-mcpの中断監督と結果投影。
E. 外部状態の専有・復旧protocol。

A〜Cでメモリ内stateful検査の一連の利用が成立する。
D完了前はworker killの構造化報告を提供済みと宣伝しない。
E完了前はDB rollbackや本番業務状態の復元を保証しない。
各段階の実装計画は本設計のレビュー後に作成する。
