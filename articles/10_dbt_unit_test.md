---
title: "【dbt】モデル構築からUnit testsまで一気通貫で試してみた"
emoji: "🐡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [dbt, snowflake]
published: true
published_at: 2025-05-17 20:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
dbtのUnit testsを利用して、構築したmodelのロジックテストが実施できます。
本記事ではseedの投入からテスト作成まで実行した内容を整理します。

## 2. 前提条件
- `Unit tests`がリリースされた[dbt-core v1.8.0](https://github.com/dbt-labs/dbt-core/releases/tag/v1.8.0)以上
- dwhはsnowflakeを利用（接続設定は対象外とします）

## 3. 全体像
本記事で実施するステップ内容と作成ファイルを合わせて表にします。

| No | 概要                      | 作成ファイル |
| :-: | :--------------------------- | :------------------------------------ |
| 1 | seedファイルを投入してテーブルを作成 | `seeds/ads_performance_details.csv`<br>`seeds/ads_conversion_metrics.csv` |
| 2 | seedテーブルをsourceとして定義     | `models/schema.yml`                  |
| 3 | model構築のSQLファイルを作成       | `models/ads_performance_summary.sql` |
| 4 | modelに対するUnit testsの実施（成功）    | `models/ads_performance_summary.yml` |
| 5 | modelに対するUnit testsの実施（失敗）    | `models/ads_performance_summary.yml` |
| 6 | ドキュメント生成・確認              | —                                    |

:::details ファイルの配置
```json
dbt_training/
├── dbt_project.yml
├── models
│   ├── ads_performance_summary.sql
│   ├── ads_performance_summary.yml
│   └── schema.yml
└── seeds
    ├── ads_performance_details.csv
    └── ads_conversion_metrics.csv
```
:::


## 4. 実作業
それでは作業毎の内容を実施します。

### 4.1. seedファイルを投入してテーブルを作成
はじめに、取込対象の広告キャンペーンの2つのファイルを作成し`seeds/`直下に配置します。

- 広告キャンペーンの詳細データ（広告費、インプレッション数、クリック数）
    :::details seeds/ads_performance_details.csv
        date,campaign_id,spend,impressions,clicks
        2025-05-01,123,500,10000,100
        2025-05-01,124,300,8000,80
        2025-05-02,123,300,10000,90
        2025-05-02,123,200,5000,50
    :::
- 広告キャンペーンのコンバージョンデータ（コンバージョン数・収益）
    :::details seeds/ads_conversion_metrics.csv
        ```
        date,campaign_id,conversions,revenue
        2025-05-01,123,10,2000
        2025-05-01,124,8,1500
        2025-05-02,123,4,2400
        2025-05-02,123,6,600
        ```
    :::

ファイル配置後に`dbt seed`を実行してデータを取込みます。
データ投入先テーブルも同時に作成されますので便利です。

:::details seed実行ログ
```bash
$ dbt seed
...
01:52:21  1 of 2 START seed file {スキーマ名}.ads_conversion_metrics ........................ [RUN]
01:52:22  1 of 2 OK loaded seed file {スキーマ名}.ads_conversion_metrics .................... [INSERT 4 in 1.20s]
01:52:22  2 of 2 START seed file {スキーマ名}.ads_performance_details ....................... [RUN]
01:52:23  2 of 2 OK loaded seed file {スキーマ名}.ads_performance_details ................... [INSERT 4 in 1.30s]
01:52:23
01:52:23  Finished running 2 seeds in 0 hours 0 minutes and 3.94 seconds (3.94s).
01:52:24
01:52:24  Completed successfully
01:52:24
01:52:24  Done. PASS=2 WARN=0 ERROR=0 SKIP=0 TOTAL=2
```
:::

### 4.2. seedファイルで作成したテーブルをsourceとして定義する
続いてseedで作成したテーブルをmodelから参照するため`schema.yml`ファイルを作成します。

```yml
versions: 2

sources:
  - name: ads
    schema: {スキーマ}
    tables:
      - name: ads_performance_details
        description: "広告キャンペーンの詳細データ（広告費、インプレッション数、クリック数）"
      - name: ads_conversion_metrics
        description: "コンバージョンデータ（コンバージョン数、収益）"
```

### 4.3. model構築のSQLファイルを作成
2つのsourceを元に作成するmodelのテーブル定義を記載します。

| カラム名               | 説明                         |
|-----------------------|-----------------------------|
| `date`                | 配信日                      |
| `campaign_id`         | キャンペーンID             |
| `total_spend`         | 1日あたりの広告費用        |
| `total_impressions`   | 1日あたりのインプレッション数 |
| `total_clicks`        | 1日あたりのクリック数      |
| `total_conversions`   | 1日あたりのコンバージョン数 |
| `total_revenue`       | 1日あたりの収益            |
| `roas`                | 収益 ÷ 広告費用 |
| `performance_rank`    | ROAS = 0 → キャンセル <br> < 5 → 普通 <br> ≥ 5 → 優良 |

2つのテーブルは「`date`, `campaign_id`」を結合キーとして左結合します。
なお、seedで投入したデータには同じ日付・キャンペーンのレコードが存在するため、「日付＋キャンペーン」単位で集約処理も行います。

:::details models/ads_performance_summary.sql（model構築用SQLファイル）
```sql
{{ config(materialized='view') }}

with agg_ads as (
  -- 日付・キャンペーン単位で集約を実施
  select
    date,
    campaign_id,
    sum(coalesce(spend, 0)) as total_spend,
    sum(coalesce(impressions, 0)) as total_impressions,
    sum(coalesce(clicks, 0)) as total_clicks
  from {{ source('ads','ads_performance_details') }}
  group by date, campaign_id
), agg_rev as (
  -- 日付・キャンペーン単位で集約を実施
  select
    date,
    campaign_id,
    sum(coalesce(conversions, 0)) as total_conversions,
    sum(coalesce(revenue, 0))     as total_revenue
  from {{ source('ads','ads_conversion_metrics') }}
  group by date, campaign_id
)

select
  a.date,
  a.campaign_id,
  a.total_spend,
  a.total_impressions,
  a.total_clicks,
  r.total_conversions as total_conversions,
  r.total_revenue as total_revenue,
  case when a.total_spend = 0 then 0 else r.total_revenue / a.total_spend end as roas,
  case when roas = 0 then 'キャンセル'
       when roas < 5 then '普通'
       else '優良' end as performance_rank
from agg_ads a
left join agg_rev r
  using (date, campaign_id)
order by a.date, a.campaign_id
```
:::

`dbt run`実行し、構築したSQLを元にmodelを作成します。

:::details dbt runの実行結果
```bash
$ dbt run
...
01:59:56  1 of 1 START sql view model {スキーマ名}.ads_performance_summary .................. [RUN]
01:59:57  1 of 1 OK created sql view model {スキーマ名}.ads_performance_summary ............. [SUCCESS 1 in 0.50s]
01:59:57
01:59:57  Finished running 1 view model in 0 hours 0 minutes and 1.62 seconds (1.62s).
01:59:57
01:59:57  Completed successfully
01:59:57
01:59:57  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
```
:::

`successfully`と無事に構築ができたことを確認しました！

### 4.4. modelに対するUnit tests（成功）
それでは構築したmodelに対してUnit testsを実施します。
実施のため作成するファイルの登録内容を以下表に記載します。

| 項目    | 内容                             | 設定値                                |
|--------|----------------------------------|-------------------------------------|
| name   | テスト識別名                   | `test_ads_performance_summary`      |
| model  | テスト対象のモデル名             | `ads_performance_summary`            |
| given  | テスト用に投入する入力ソース | `source('ads','ads_performance_details')` <br> `source('ads','ads_conversion_metrics')` |
| expect | 期待される出力結果   | ロジックの出力想定結果を登録                  |

表を元に登録内容を設定したファイルは`models/ads_performance_summary.yml`となります。

```yml
version: 2
models:
  - name: ads_performance_summary
    description: "広告キャンペーンのデータを集約したモデル。"
    columns:
      - name: roas
        description: "広告費用対効果（収益を広告費で割った値）"

unit_tests:
  - name: test_ads_performance_summary
    model: ads_performance_summary
    given:
      - input: source('ads', 'ads_performance_details')
        rows:
          - { date: "2025-05-01", campaign_id: 123, spend: 500,  impressions: 10000, clicks: 100 }
          - { date: "2025-05-01", campaign_id: 124, spend: 300,  impressions:  8000, clicks:  80 }
          - { date: "2025-05-02", campaign_id: 123, spend: 300,  impressions:  10000, clicks:  90 }
          - { date: "2025-05-02", campaign_id: 123, spend: 200,  impressions:  5000, clicks:  50 }
          - { date: "2025-05-03", campaign_id: 200, spend: null,  impressions:  null, clicks:  null }
      - input: source('ads', 'ads_conversion_metrics')
        rows:
          - { date: "2025-05-01", campaign_id: 123, conversions: 10, revenue: 2000 }
          - { date: "2025-05-01", campaign_id: 124, conversions:  8, revenue: 1500 }
          - { date: "2025-05-02", campaign_id: 123, conversions: 4, revenue: 2400 }
          - { date: "2025-05-02", campaign_id: 123, conversions: 6, revenue: 600 }
    expect:
      rows:
        - { date: "2025-05-01", campaign_id: 123, total_spend: 500, total_impressions: 10000, total_clicks: 100, total_conversions: 10, total_revenue: 2000, roas: 4.0, performance_rank: "普通" }
        - { date: "2025-05-01", campaign_id: 124, total_spend: 300, total_impressions: 8000, total_clicks: 80, total_conversions: 8, total_revenue: 1500, roas: 5.0, performance_rank: "優良" }
        - { date: "2025-05-02", campaign_id: 123, total_spend: 500, total_impressions: 15000, total_clicks: 140, total_conversions: 10, total_revenue: 3000, roas: 6.0, performance_rank: "優良" }
        - { date: "2025-05-03", campaign_id: 200, total_spend: 0, total_impressions: 0, total_clicks: 0, total_conversions: NULL, total_revenue: NULL, roas: 0, performance_rank: "キャンセル" }
```

それでは`dbt test`を実行します。
:::details dbt test実行ログ
```bash
$ dbt test
...
02:24:10  1 of 1 START unit_test ads_performance_summary::test_ads_performance_summary ... [RUN]
02:24:11  1 of 1 PASS ads_performance_summary::test_ads_performance_summary .............. [PASS in 1.76s]
02:24:12
02:24:12  Finished running 1 unit test in 0 hours 0 minutes and 3.17 seconds (3.17s).
02:24:12
02:24:12  Completed successfully
02:24:12
02:24:12  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
```
:::

`successfully`になることが確認できました！

### 4.5. modelに対するUnit tests（失敗）
失敗ケースも確認するため、`models/ads_performance_summary.yml`の以下項目を更新し実行します。
- `date: "2025-05-03"`のperformance_rankを「キャンセル -> 優良」に変更

改めて実行するとテストに失敗したことが確認できます。

```bash
$ dbt test
...
02:41:25  1 of 1 START unit_test ads_performance_summary::test_ads_performance_summary ... [RUN]
02:41:26  1 of 1 FAIL 1 ads_performance_summary::test_ads_performance_summary ............ [FAIL 1 in 1.27s]
...
actual differs from expected:

@@ ,...,TOTAL_SPEND,TOTAL_IMPRESSIONS,TOTAL_CLICKS,...,ROAS    ,PERFORMANCE_RANK
...,...,...        ,...              ,...         ,...,...     ,...
   ,...,500        ,15000            ,140         ,...,6.000000,優良
→  ,...,0          ,0                ,0           ,...,0.000000,優良→キャンセル
...
```

先ほど変更した部分が、`優良→キャンセル`になりました。
どこが一致してないか分かり易いですね。

### 4.5. ドキュメント作成
最後にドキュメントを作ります。作成に必要なコードを実行します。

```bash
$ dbt docs generate
..
$ dbt docs serve
...
To access from your browser, navigate to: http://localhost:8080
```

表示されたリンクの、`models/ads_performance_summary`にて作成したmodel情報が表示されることが確認できました！

![](/images/10_dbt_unit_test/1_doc.png)


データリネージには、定義した内容のフローが図として表示されてますので良いですね！
![](/images/10_dbt_unit_test/2_lineage.png)


## 5. まとめ
Unit tests動作確認のためmodel作成からドキュメント確認まで実施しました。
最近dbtを使い出したのですが便利な機能が豊富で便利ですので、今後も活用していきます。
簡易的ですが一気通過で内容をまとめましたので未来の自分含めどなたかの助けになれば幸いです。

## おまけ（Unit testsのinputを登録しない）
Unit tests実行当初は、seedで投入したデータを利用するものと誤認していたためinputを登録せずに実行しておりました。
`'given' is a required property`とエラーがでておりうまくいきませんでしたのでそのコードも記載します。。

:::details models/ads_performance_summary.ymlのgivenの登録なし
```yml
version: 2
models:
  - name: ads_performance_summary
    description: "広告キャンペーンのデータを集約したモデル。"
    columns:
      - name: roas
        description: "広告費用対効果（収益を広告費で割った値）"

unit_tests:
  - name: test_ads_performance_summary
    model: ads_performance_summary
    given:
    expect:
      rows:
        - { date: "2025-05-01", campaign_id: 123, total_spend: 500, total_impressions: 10000, total_clicks: 100, total_conversions: 10, total_revenue: 2000, roas: 4.0, performance_rank: "普通" }
        - { date: "2025-05-01", campaign_id: 124, total_spend: 300, total_impressions: 8000, total_clicks: 80, total_conversions: 8, total_revenue: 1500, roas: 5.0, performance_rank: "優良" }
        - { date: "2025-05-02", campaign_id: 123, total_spend: 500, total_impressions: 15000, total_clicks: 140, total_conversions: 10, total_revenue: 3000, roas: 6.0, performance_rank: "優良" }
        - { date: "2025-05-03", campaign_id: 200, total_spend: 0, total_impressions: 0, total_clicks: 0, total_conversions: NULL, total_revenue: NULL, roas: 0, performance_rank: "キャンセル" }
```
:::

```bash
$ dbt test
02:26:13  Running with dbt=1.9.4
02:26:13  Registered adapter: snowflake=1.9.4
02:26:14  Encountered an error:
Parsing Error
  Invalid unit_tests config given in FilePath(searched_path='models', relative_path='ads_performance_summary.yml', modification_time=1747447746.1647618, project_root='/app/dbt_training') @ unit_tests: {'name': 'test_ads_performance_summary', 'model': 'ads_performance_summary', 'expect': {'rows': [{'date': '2025-05-01', 'campaign_id': 123, 'total_spend': 500, 'total_impressions': 10000, 'total_clicks': 100, 'total_conversions': 10, 'total_revenue': 2000, 'roas': 4.0, 'performance_rank': '普通'}, {'date': '2025-05-01', 'campaign_id': 124, 'total_spend': 300, 'total_impressions': 8000, 'total_clicks': 80, 'total_conversions': 8, 'total_revenue': 1500, 'roas': 5.0, 'performance_rank': '普通'}, {'date': '2025-05-02', 'campaign_id': 123, 'total_spend': 500, 'total_impressions': 15000, 'total_clicks': 140, 'total_conversions': 10, 'total_revenue': 3000, 'roas': 6.0, 'performance_rank': '優良'}]}} - at path []: 'given' is a required property
```

## 参考リンク

- [Unit tests](https://docs.getdbt.com/docs/build/unit-tests)
- [Input for unit tests](https://docs.getdbt.com/reference/resource-properties/unit-test-input)
- [dbtのUnit testsを導入してわかったこと](https://creators.oisixradaichi.co.jp/entry/2024/12/06/172337)
- [dbtのUnit testsをプロダクトに導入してクエリのロジックをテストする](https://developers.cyberagent.co.jp/blog/archives/49438/)
- [[新機能]dbtでSQL上の1つ1つのロジックに対しテストを行える「Unit tests」を試してみた](https://dev.classmethod.jp/articles/dbt-try-unit-tests/)
- [dbtで使用できる主なテスト](https://qiita.com/imaik_/items/f8eee21f9c97fc8045fc)
- [dbtでのtest戦略](https://zenn.dev/linda/articles/cb3d85209d88e5)
- [[dbt] 作成したデータモデルに対してテストを実行する](https://dev.classmethod.jp/articles/dbt-testing/)
- [dbtでのtest戦略](https://zenn.dev/linda/articles/cb3d85209d88e5)
- [dbt 入門](https://zenn.dev/foursue/books/31456a86de5bb4)
- [dbt-unit-testing を使ってモデルのロジックテストを実装する](https://zenn.dev/lexiko/articles/dbt-unit-testing)
- [ROAS](https://www.nttcoms.com/service/b2b_marketing/glossary/roas/)
- [dbt 1.8のUnit Tests 実施とその知見（時間ロックとSQLの分割について）](https://tech.timee.co.jp/entry/2024/06/25/141634)
- [dbtのUnit testsをプロダクトに導入してクエリのロジックをテストする](https://developers.cyberagent.co.jp/blog/archives/49438/)
- [dbt Unit Tests について調べてみました](https://belonginc.dev/members/shuhei/posts/dbt-unit-tests)
