# 実行結果と検証証拠の充足判定を分離する設計案

日付: 2026-09-26
状態: レビュー用ドラフト。ここに示す新API・フィールドは未実装。
対象: cl-spec core。MCP adapterの変更、実装計画、実装作業は含まない。

## 1. 目的

LLM・人間・MCP consumerが、:passedを「変更しても安全」「全条件を確認済み」と
読み替えず、実行で分かったことと未確認・未計測の範囲を判断できるようにする。

既存の:statusの意味を変えない。充足判定は、明示された検証条件に対する判定であり、
プログラムの正しさ、統計的信頼度、マージ可否を保証しない。

今回の仮定: 初版では通常試行数と宣言済みnamed casesを対象とする。
optional field、数値境界、tagged union、組合せ、並行性の網羅性は追加計測が必要な後続機能。
それらが検証済みであるとは表示しない。

## 2. 現状の根拠

- src/property-runner.lispのresult-dataは、実行時metadata、status、trials、budget、
  rejected、generation-report、shrink-report、case-report等を投影する。
- src/function-spec.lispのcase-run-reportは宣言case、called/passed/failed/error、
  never-calledを持つ。報告に参加しないbackendは:NOT-COLLECTEDを返す。
- run-generated-testの結果検証は、:passedが要求試行予算を消費したことを検査する。
  ただしpre拒否もtrialsに入るので、予算消費は有効な契約検査回数ではない。
- trials - rejectedは、setup/capture/guard等の失敗がある結果について
  target呼出回数や契約検査完了回数と一致するとは限らない。
- generation-reportのattemptsはbounded filterの生成元呼出回数であり、
  targetの試行回数ではない。
- fixtureのrun-errorは縮小中にも発生する。通常試行の違反証拠と別に保持される。
- 過去resultの投影は現在のregistryを参照しない。この原則を維持する。

## 3. 方式の比較

| 方式 | 長所 | 問題 |
|---|---|---|
| 実行事実と明示policyを分離 | 判断基準が見え、同じrunを違う方針で評価できる | 新しい小さなpolicy APIが必要 |
| coreが一律にpartial/completeを決める | 呼出側が簡単 | 何をもって十分とするかが隠れる |
| MCP/LLMだけで判定 | coreの変更が少ない | consumerごとに解釈が揺れ、直接利用にも使えない |

第一案を採用する。coreは事実の要約とpolicy評価を担当し、
MCPはその結果を変換する。policyは初版では有限の宣言データに限定する。

## 4. 三層の境界

1. execution result: 既存の:statusと失敗証拠。
2. evidence summary: そのrunで取得した事実、既知の欠落、未計測項目。
3. evidence assessment: 明示policyの要求を満たしたか。

新しい包括的な:verifiedや:fully-verifiedは作らない。
元提案の:verification :partialは、初版では意味を限定した:assessmentに置き換える。

判定値:

| 値 | 意味 |
|---|---|
| :satisfied | 指定した全要求について、取得済み証拠が基準を満たす |
| :insufficient | 少なくとも一つの要求が、既知の事実として未達 |
| :unknown | 既知の未達はないが、要求判定に必要な計測が欠けている |
| :not-assessed | policyが指定されていない |

既知未達と未計測が同時にあれば全体は:insufficientとし、両方を明細に残す。
:satisfiedは必ずpolicyとscopeを伴う。gapが空というだけでは:satisfiedにしない。
要求ごとのchecksでは、上記の判定に加えて:not-applicableを使用する。

:failedと:satisfiedは共存できる。要求した検査を実施して違反を発見した場合である。
:errorと:satisfiedも、通常試行の要求を満たした後に縮小cleanupが失敗した場合にあり得る。
呼出側が「成功かつ指定基準を満たす」を求めるなら、
:status :passed AND :assessment :satisfiedを明示的に評価する。

## 5. API案

新しい公開API:

(evidence-summary result)
(assess-evidence result policy)

両方とも副作用のない投影・評価であり、target、generator、predicate、fixture hook、
registry lookupを実行しない。返すデータはsnapshotとしてコピーする。
対応resultはproperty-result/function-check-result、call-check-result、fixture-check-result。

例:

(assess-evidence
 result
 '(:policy-version 1
   :requirements
   ((:kind :min-checked-trials :count 100)
    (:kind :all-declared-cases :min-checked 1))))

policyを省略する別構文は作らない。判定しない用途はevidence-summaryを使う。
初版ではdefproperty/defspec-functionのDSLにpolicyを追加せず、
run-property/check-functionの試行予算や停止条件も変更しない。

result-data、call-check-data、fixture-check-dataには:evidenceを追加する。
ここにはpolicy未指定のsummaryだけを載せ、既定の充足基準を暗黙に適用しない。
明示assessmentは別の自己完結recordとして返す。

## 6. summaryとassessmentのデータ例

以下は100回の契約検査は完了したが、:overflowが一度も検査されなかった例。

(:schema-version 1
 :record-kind :evidence-assessment
 :execution-status :passed
 :assessment :insufficient
 :scope :single-run
 :subject (:name withdraw
           :definition-digest "..."
           :definition-digest-complete t
           :target-revision :unknown)
 :policy (:policy-version 1
          :requirements
          ((:kind :min-checked-trials :count 100)
           (:kind :all-declared-cases :min-checked 1)))
 :checks
 ((:requirement (:kind :min-checked-trials :count 100)
   :status :satisfied :observed 100)
  (:requirement (:kind :all-declared-cases :min-checked 1)
   :status :insufficient))
 :gaps
 ((:kind :case-checks-below-minimum
   :case :overflow :required 1 :observed 0
   :source (:case-report :cases :overflow)))
 :unknowns nil)

subjectは利用可能な識別情報を持つが、definition-digestはtarget実装のidentityではない。
target-revisionが不明なら明示する。このrecordだけで別commitへの承認を移し替えない。

summaryには以下を持たせる。

- :schema-version 1 / :record-kind :evidence-summary / :assessment :not-assessed。
- :execution-status、:scope (:single-runまたは:single-call)、subject。
- :dimensions: 計測対象ごとのavailability、unit、facts、source。
- :gaps: 計測できた既知の欠落。例えば:case-never-called、:no-checked-trials。
- :unknowns: 対象として宣言されているが、必要な報告が欠けた次元。
- :limitations: 初版が扱わない網羅性・再現性上の範囲を説明するデータ。

summaryのgapは「観測した欠落」であり、policy違反と同義ではない。
assessmentのgaps/unknownsは指定policyに関係するものだけを列挙する。
policyで要求していないoptional field網羅性を、常にunknownの原因にしない。

:availabilityは:collected / :not-collected / :not-applicable。
計測済みの0と未計測を分離し、後者に:observed 0を入れない。

## 7. 初版のpolicy語彙

### :min-checked-trials

(:kind :min-checked-trials :count N)

Nは1以上の整数。単位は通常試行のうち契約判定が:passedまたは:failedで完了した回数。
:rejected、:error、fixture lifecycle失敗は含まない。
期待されたerrorが:signals契約に適合し、全体が:passedなら1回と数える。
:failedは違反を判定できた試行であり、成功回数を意味しない。
「判定完了」は最初の違反で短絡した場合も含み、全post/state-post式を実行したという意味ではない。
縮小候補、生成filterのattempts、別run、artifact recheckは加算しない。

### :all-declared-cases

(:kind :all-declared-cases :min-checked N)

実行開始時点で宣言されていた各caseに、最低N回の完了した契約判定を要求する。
既存case-reportのpassed + failedを使い、calledだけでは充足としない。
setup/capture/guard errorやcleanup errorだけでcaseを検証したと数えない。

宣言caseがないことを実行時snapshotで確認できれば:not-applicableとして要求を除外する。
宣言の有無自体が不明なら:unknown。全要求が:not-applicableとなるpolicyは
:satisfiedとせず:not-assessed / :no-applicable-requirementsを返す。

未実行caseが論理的に到達不能であるとは推論しない。除外が必要なら契約や
検証方針を明示的に見直す。初版に自動case除外・到達可能性判定は追加しない。

### :requested-trials-completed

(:kind :requested-trials-completed)

生成runの実行済み通常試行数が、保存された要求予算に達したかを評価する。
予算は有効検査数ではない。これ単独では0予算や全pre拒否を除外できないため、
:min-checked-trialsと組み合わせる。

direct checkでは:not-applicable。予算が保存されていなければ:unknown。

### policyの検証

有限・循環なしのkeyword plistでversion 1を必須とする。
requirementsは空でない有限リスト。重複kind、重複key、未知key/kind、
不正な閾値はinvalid-evidence-policyとして拒否する。
未対応のoptional-field要求を勝手に無視しない。
実装済み要求に必要な計測がない場合だけ、通常の:unknown判定を返す。

## 8. 計測と保存

checked-trialsをtrials - rejectedから一般的に推測しない。
run終了時に、通常試行だけの新しい:trial-reportを結果オブジェクトに保存する。

(:report-version 1
 :collection :complete
 :unit :normal-trials
 :counts (:passed 80 :failed 0 :rejected 20 :error 0)
 :checked 80)

- countingはbackendが通常試行をnote-trial-outcomeへ渡す地点で一度だけ行う。
- observe-trial自体には全件countingを置かない。縮小も同じ経路を通るため。
- runner所有のcontextで数え、registryや定義objectにはrunのcountを残さない。
- fixtureではcleanupを含む最終のouter observationを数える。
- shrink中のrun-errorは通常試行を追加しない。既存のrun-errorに残す。
- 対応backendはtrial-report v1への参加を明示し、begin/endの完了を報告する。
  completeは「全試行を計測した」という意味で、実行成功や予算消費とは別。
- coreはreport count合計=outcome.trials、rejected一致、checked=passed+failed、
  非負整数、通常試行のrun provenance、計測開始/終了の対応を検証する。
  同じ通常試行observationの二重報告も拒否し、countの水増しを防ぐ。
  報告プロトコル違反はinvalid-backend-resultであり、計測不能に丸めない。
- 参加しないbackendは既存実行を継続できるが:trial-report :not-collectedとする。
  そのbackendが返したstatusだけでchecked回数を捏造しない。

case-reportは既存の通常試行counterを再利用する。新しいtrial-reportとの整合性を検査し、
宣言case集合をrun開始時に保存する。source-formを再解析して宣言caseを推定しない。

direct checkは既存の一回のobservationからtrial-report相当の事実を構成できる。
ただしscopeは:single-call、生成予算は:not-applicableとする。
宣言case集合はcheck-call/check-fixtureの開始時にsnapshotする。
そのため、単一callから全caseを検証済みと誤って扱わない。

旧resultや手動構築resultでreportが欠けたとき、回数を0としない。
既存case-report等に明示的な証拠があればその次元だけ利用し、それ以外は:not-collected。
別runの集約は初版対象外。replayや同一seedの結果を足して独立試行数を増やさない。

## 9. 取り込む情報と混ぜない情報

| 情報 | 初版での扱い |
|---|---|
| 完了した通常試行、case別判定回数 | policyの充足判定 |
| 未実行case、計測されないcase | gapとunknownを分離 |
| pre拒否数・比率 | 事実として表示。高いだけで一律に不足としない |
| generation-budget-exhausted | 実行の中断事実。要求未達はcountやbudgetから判定 |
| shrink予算切れ・shrinkerなし | 反例の縮小範囲の制限。成功runのcoverage不足にしない |
| fixture cleanup failure | 既存:error/run-error/state unknownを明示。outer errorはcheckedに含めない |
| generation/shrinking capability | 利用可能な機能。実行した証拠として数えない |
| incomplete digest・target revision不明 | 識別・再現性の制限。case coverage不足と混ぜない |
| optional fieldの有無・数値境界 | 初版のcoverage scope外。後続の明示計測が必要 |

将来はcoverage dimensionsを拡張できるが、初版に任意callbackやpolicy pluginは入れない。
unknown次元の列挙は、保存済み宣言や要求で識別できる対象に限る。

## 10. 互換性と依存関係

実行status、停止条件、seed、shrinking、artifact identityは変更しない。
外側の既存schema v1/v2を維持し、追加の:evidenceには独立したversion 1を持たせる。
schema-infoにevidence schema、assessment値、policy versionを公開する。
既存のunknown-keyを無視する規約とprojection/self-contractテストで互換性を確認する。

counterexample artifact v1/v2にpolicyやsummaryを新たに必須保存しない。
artifactの直接recheckを元の生成run全体のcoverage証拠として扱わない。
summaryを使うMCP adapterはcl-mcp側の別変更とする。

想定する責務:

- src/evidence.lisp: schema、policy validation、純粋な集約判定とgeneric投影protocol。
  resultクラスやrunnerをimportせず、循環依存を避ける。
- src/execution.lisp / src/generator.lisp: 通常試行report contextとbackend報告検証。
- src/property-runner.lisp: reportの保存、property-resultの投影method、result-data。
- src/function-spec.lisp: 宣言case snapshot、direct result method、fixture/case統合。
- src/backends/check-it.lisp: trial-report参加の明示と通常試行の計測完了。
- src/schema.lisp / main.lisp: schema discoveryとpublic APIの再export。

result-dataを生成してから再度同じresult-dataを呼ぶような再帰は避ける。
summaryは専用のsaved-facts genericから構成し、投影関数間の循環を作らない。

## 11. 主な受け入れ条件

1. :passedかつ未検査caseあり → statusは不変、all-declared-cases要求は:insufficient。
2. 全caseが最低回数を満たす → その要求だけについて:satisfied。
3. calledだけ増え、契約errorとなったcase → checked回数は増えない。
4. 0試行・全pre拒否 → checked=0、min-checked要求は:insufficient。
5. 計測非対応backend → checkedは:not-collected、対応要求は:unknown。
6. 未達と未計測の共存 → :insufficientと両明細を返す。
7. policyなし → :not-assessed。gapsが空でも:satisfiedにしない。
8. 不適用要求だけ → :not-assessed。不存在と未計測を混同しない。
9. expected signals適合 → checkedを1回計数する。
10. fixture setup/cleanup error → checkedを増やさない。
11. shrink回数・filter attemptsが増えても通常試行coverageは増えない。
12. :failed/:errorとassessmentの独立性を検証する。充足が実行失敗を隠さない。
13. summary/assessmentの呼出でtarget、predicate、generator、hookを呼ばない。
14. registry再定義後も過去resultのfacts、宣言case、判定は不変。
15. 同じresult/policyは同じelapsed非依存の判定・安定順序のgap列を返す。
16. 未対応policy、重複key、循環データを明示拒否する。
17. 返却plistの変更で元resultや次のsummaryを変えない。
18. core単独でdirect summary/assessmentが使え、check-itをloadしない。
19. 既存のstateless/stateful結果、replay、artifact、instrumentationの全テストを維持する。

gapの順序はpolicyの要求順、caseは保存された宣言順とする。
検証範囲外の未計測を、測定済み0や「問題なし」に変換しないことを重点的にテストする。

## 12. 開発の分割案

第一段階: 純粋なsummary/policy評価、通常試行report、既存case-report統合、
direct APIへの対応、schema discovery、self contracts、ガイド。

第二段階: optional field有無、境界値、tagged branch等のcoverage宣言と実測。
第三段階: 異なるrunの集約。定義・target revision・policy identityと重複排除を別設計する。

今回の設計は第一段階まで。合格基準を満たすまで自動で試行を追加する探索、
CIを失敗させる既定policy、マージの自動許可は含めない。
