---
title: "[Snowflake]LATERALを用いて半構造化のデータを展開してみる"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [snowflake, json, lateral]
published: true
published_at: 2025-05-10 17:00
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

Snowflake に登録された半構造化データ（JSON など）は、FLATTENを用いることで複数行に展開できます。
さらに、ネストされた配列を取り扱う際にはLATERALを組み合わせることでデータの取得が可能です。
とても便利なのですが理解がふわっとしてましたので、サンプルデータ作成からLATERALの挙動確認を行い、理解を深めた内容をまとめます。

## 2. 実施内容
挙動確認用テーブルとして、半構造化データを保持するmetricsカラムを含めて作成します。

| カラム名       | データ型   | 説明                           |
| -------------- | ---------- | ------------------------------ |
| id             | INT        | 一意の識別子                   |
| impressions    | INT        | インプレッション数              |
| metrics        | VARIANT    | メトリクス情報を含むJSONデータ |

metricsカラムには`ネストなし`と`ネストあり`の2 パターンを登録し、それぞれの挙動を確認します。

## 3. パターン1: ネストされていない配列の展開
### 3.1. テーブル作成
まずはじめに、ネストされていない配列を格納するテーブルを作成します。

:::details パターン1の調査用テーブル作成
```sql
-- 検証テーブル作成コード（{DB名}.{スキーマ名}は適宜置き換えてください）
CREATE OR REPLACE TEMPORARY TABLE {DB名}.{スキーマ名}.lateral_check_test_table(
    id          INT,
    impressions INT,
    metrics     VARIANT
) AS
SELECT 1 AS id, 2000 AS impressions
     , PARSE_JSON('[{"name":"clicks","value":100},{"name":"ctr","value":0.05},{"name":"conversions","value":12},{"name":"cost","value":150},{"name":"cpc","value":1.50}]') AS metrics
UNION ALL
SELECT 2 AS id, 3500 AS impressions
     , PARSE_JSON('[{"name":"clicks","value":70},{"name":"ctr","value":0.02},{"name":"conversions","value":8},{"name":"cost","value":90},{"name":"cpc","value":1.29}]') AS metrics
UNION ALL
SELECT 3 AS id, 0 AS impressions
     , PARSE_JSON('[]') AS metrics
;

-- 参照用コード
SELECT id, impressions, metrics FROM {DB名}.{スキーマ名}.lateral_check_test_table;
```
:::

作成したテーブルを参照すると以下表のように出力されます。

| id	| impressions	| metrics |
| ----------- | ----------- | ----------- | 
| 1	| 2000	| [ { "group": "performance", "items": [ { "name": "clicks", "value": 100 }, { "name": "ctr", "value": 0.05 } ] }, { "group": "cost", "items": [ { "name": "conversions", "value": 12 }, { "name": "cost", "value": 150 }, { "name": "cpc", "value": 1.5 } ] } ] |
| 2	| 3500	| [ { "group": "performance", "items": [ { "name": "clicks", "value": 70 }, { "name": "ctr", "value": 0.02 } ] }, { "group": "cost", "items": [ { "name": "conversions", "value": 8 }, { "name": "cost", "value": 90 }, { "name": "cpc", "value": 1.29 } ] } ] |
| 3 | 0 | [] |

### 3.2. LATERALによる展開
LATERAL FLATTEN を用いて配列要素を行方向に展開します。
`outer => TRUE`を指定することで、要素が空の配列も行として出力します。
	
```sql
SELECT lctt.id
     , lctt.impressions
     , f.value:name AS metrics_name
     , f.value:value AS metrics_value
FROM {DB}.{SCHEMA}.lateral_check_test_table AS lctt,
LATERAL FLATTEN(input => lctt.metrics, outer => TRUE) AS f;
```

取得結果として、ID(1,2,3)のレコードに含まれるmetrics毎に出力できることを確認しました!
配列が空のID=3を出力対象外にする場合は、`outer`の指定をFALSEにすることで対応可能です。

| id | impressions | metrics_name | metrics_value |
|:----|:----|:----|:----|
|1|2000|clicks|100|
|1|2000|ctr|0.05|
|1|2000|conversions|12|
|1|2000|cost|150|
|1|2000|cpc|1.5|
|2|3500|clicks|70|
|2|3500|ctr|0.02|
|2|3500|conversions|8|
|2|3500|cost|90|
|2|3500|cpc|1.29|
|3|0|||

## 4. パターン2: ネストされた配列の展開
続いて、group配下にitems配列がネストされた以下構成の形式を用意します。

| group          | name          |
| -------------- | ------------- |
| `performance`  | `clicks`      |
| `performance`  | `ctr`         |
| `cost`         | `conversions` |
| `cost`         | `cost`        |
| `cost`         | `cpc`         |

### 4.1. テーブル作成
それでは、検証用のテーブルを作成します。

:::details パターン2の調査用テーブル作成
```sql
-- 検証テーブル作成コード（{DB名}.{スキーマ名}は適宜置き換えてください）
CREATE OR REPLACE TEMPORARY TABLE {DB名}.{スキーマ名}.lateral_check_test_table2(

    id          INT,
    impressions INT,
    metrics     VARIANT
) AS
SELECT 1 AS id, 2000 AS impressions
     , PARSE_JSON('[{"group":"performance","items":[{"name":"clicks","value":100},{"name":"ctr","value":0.05}]},{"group":"cost","items":[{"name":"conversions","value":12},{"name":"cost","value":150},{"name":"cpc","value":1.50}]}]') AS metrics
UNION ALL
SELECT 2 AS id, 3500 AS impressions
     , PARSE_JSON('[{"group":"performance","items":[{"name":"clicks","value":70},{"name":"ctr","value":0.02}]},{"group":"cost","items":[{"name":"conversions","value":8},{"name":"cost","value":90},{"name":"cpc","value":1.29}]}]') AS metrics
UNION ALL
SELECT 3 AS id, 0 AS impressions
     , PARSE_JSON('[]') AS metrics
;

-- 参照用コード
SELECT id, impressions, metrics FROM {DB名}.{スキーマ名}.lateral_check_test_table2;
```
:::

作成したテーブルを参照すると以下のように出力されます。

| id	| impressions	| metrics |
|---- | ---- | ---- | 
| 1 | 2000 | [ { "group": "performance", "items": [ { "name": "clicks", "value": 100 }, { "name": "ctr", "value": 0.05 } ] }, { "group": "cost", "items": [ { "name": "conversions", "value": 12 }, { "name": "cost", "value": 150 }, { "name": "cpc", "value": 1.5 } ] } ] |
| 2 | 3500 | [ { "group": "performance", "items": [ { "name": "clicks", "value": 70 }, { "name": "ctr", "value": 0.02 } ] }, { "group": "cost", "items": [ { "name": "conversions", "value": 8 }, { "name": "cost", "value": 90 }, { "name": "cpc", "value": 1.29 } ] } ] |
| 3 | 0 | [] |


### 4.2. LATERALを重ねた展開
ネスト構造を展開するため、`LATERAL FLATTEN`を2回適用します。

```sql
SELECT
    id,
    impressions,
    grp.value:group::STRING  AS group_name,
    itm.value:name::STRING   AS metrics_name,
    itm.value:value          AS metrics_value
FROM {DB}.{SCHEMA}.lateral_check_test_table2 lctt2,
    LATERAL FLATTEN(input => lctt2.metrics, outer => true)   AS grp,  -- グループを展開
    LATERAL FLATTEN(input => grp.value:items, outer => true) AS itm   -- 各グループ内のnameを展開
;
```

group_name含め、パターン1同様に展開することができました!

|id|impressions|group_name|metrics_name|metrics_value|
|:----|:----|:----|:----|:----|
|1|2000|performance|clicks|100|
|1|2000|performance|ctr|0.05|
|1|2000|cost|conversions|12|
|1|2000|cost|cost|150|
|1|2000|cost|cpc|1.5|
|2|3500|performance|clicks|70|
|2|3500|performance|ctr|0.02|
|2|3500|cost|conversions|8|
|2|3500|cost|cost|90|
|2|3500|cost|cpc|1.29|
|3|0||||

## 5. まとめ
Snowflakeで配列データを取得するLateralの理解を深めるため、テストコード作成と実装確認をしました。
とても強力なツールだなと実感しつつ、利用する際の処理イメージがわきにくかったので未来の自分含め参考になれば幸いです。

## 6. 参考リンク
- [LATERAL](https://docs.snowflake.com/ja/sql-reference/constructs/join-lateral)
- [FLATTEN](https://docs.snowflake.com/ja/sql-reference/functions/flatten)
- [結局 LATERAL とは何者なのか？](https://zenn.dev/indigo13love/articles/450d4d58654b43)
- [チュートリアル](https://docs.snowflake.com/ja/user-guide/tutorials/json-basics-tutorial)

## おまけ（マーケティング用語）

| 略称        | 説明                                                         |
|-------------|--------------------------------------------------------------|
| impressions | 広告がユーザーに表示された回数                                |
| clicks      | 広告がクリックされた総数                                      |
| ctr         | 広告表示回数に対するクリック率（クリック数 ÷ インプレッション数） |
| conversions | 成果（購入、会員登録など）の発生件数                         |
| cost        | 指定期間中に消化した合計広告費用                             |
| cpc         | 1クリックあたりの平均コスト（広告費用 ÷ クリック数）          |
