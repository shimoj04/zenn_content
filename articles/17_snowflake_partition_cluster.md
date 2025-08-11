---
title: "【snowflake】マイクロパーティションとクラスタリングを試してみる"
emoji: "💬"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [snowflake]
published: true
published_at: 2025-08-11 23:00
---

## 1. はじめに
こんにちは。（心の内では）健康を目指しつつ、Snowflakeのパフォーマンス設計にも励んでいます。

大規模データを扱うDWHでは必要なデータを効率よく取得するために、マイクロパーティションの構造とクラスタリング設計の考慮が重要です。
今回は、Snowflakeのマイクロパーティションとクラスタリングキー設定がクエリパフォーマンス（データ読取量・処理時間）にどう影響するのか検証してみます。

## 2. 前提
Snowflakeでは、データは自動的に「マイクロパーティション」と呼ばれる小さな単位に分割されてストレージ上に保持されます。
この構造を活かしてクエリパフォーマンスを最適化する方法として、「クラスタリング（CLUSTER BY）」があります。
クラスタリングを設定することで、クエリ実行時に不要なマイクロパーティションをスキャンせずに済むようになり、I/O削減やパフォーマンス向上が期待されます。
今回は、Snowflake上でクラスタリングの有無（有りは「日単位」と「月単位」）による3パターンのテーブルで比較検証し、クラスタリング粒度の違いが実行時の読み取り量や処理時間にどのような影響を与えるのかを確認します。

https://docs.snowflake.com/ja/user-guide/tables-clustering-micropartitions


### 2.1. 検証パターン
以下のサンプルテーブルに対して、クラスタリング設定を3パターンに分けて比較検証します。


```sql
-- サンプルテーブル構成（共通）
CREATE TABLE test_raw_{a/b/c} (
  id BIGINT,
  event_date DATE,
  user_id STRING,
  payload STRING
);
```

| パターン  | テーブル名        | クラスタリングキー             |
| ----- | ------------ | --------------------------------- |
| ① なし  | `test_raw_a` | なし                                |
| ② 日単位 | `test_raw_b` | `event_date`                      |
| ③ 月単位 | `test_raw_c` | `DATE_TRUNC('month', event_date)` |


## 3. 実装確認
本検証では、以下のステップに沿って処理効率を比較します。

1. サンプルデータの作成と投入
2. スキャンデータ量と処理時間の計測
3. クラスタリング情報の確認
4. サンプルデータをソートして再投入した結果の確認

### 3.1. サンプルデータの作成と投入
検証テーブルに対して、1000万件のサンプルデータを生成しパターン①に投入します。
同じ登録内容にするため、パターン②と③にはパターン①のデータを登録します。

:::details サンプルデータの作成と投入するsqlコード
```sql
/*-----------------
パターン①
-----------------*/
-- データの生成（2024年1月1日から365日の間で、1000万件のレコードを作成）
INSERT INTO test_raw_a
SELECT 
  SEQ8() AS id,
  DATEADD(DAY, UNIFORM(0, 365, RANDOM()), DATE '2024-01-01') AS event_date,
  UUID_STRING() AS user_id,
  RPAD('x', 500, 'x') AS payload
FROM TABLE(GENERATOR(ROWCOUNT => 10000000))
;


/*-----------------
パターン②
-----------------*/
-- クラスタリングキー設定
ALTER TABLE test_raw_b CLUSTER BY (event_date);

-- test_raw_a のデータを投入
insert into test_raw_b
select *
from test_raw_a
;

/*-----------------
パターン③
-----------------*/
-- クラスタリングキー設定
ALTER TABLE test_raw_c CLUSTER BY ( date_trunc('month', event_date));

-- test_raw_a のデータを投入
insert into test_raw_c
select *
from test_raw_a
;

```
:::

### 3.2. スキャンデータ量と処理時間の計測
続いて、日付フィルターをかけた`SELECT *`クエリを発行し、[QUERY_HISTORY , QUERY_HISTORY_BY_*](https://docs.snowflake.com/ja/sql-reference/functions/query_history)を使ってスキャンデータ量と処理時間の計測を行い比較します。


```sql
/*-----------------
参照sql
-----------------*/
SELECT *
FROM test_raw_a
-- FROM test_raw_b
-- FROM test_raw_c
WHERE event_date BETWEEN '2024-02-01' AND '2024-02-15'
;

/*-----------------
QUERY_HISTORY_BY_USERによる取得結果
-----------------*/

SELECT 
  query_text, 
  total_elapsed_time/1000 AS "処理時間[s]", 
  bytes_scanned/1024/1024 AS "スキャンデータ量[MB]",
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER())
WHERE  query_text like 'SELECT *%'
ORDER BY start_time DESC
LIMIT 10;
```

`SELECT *`発行後にhistoryを確認して取得した結果を表にします。

| パターン | 処理時間[s] | スキャンデータ量[MB] |
| ---- | ------------: | ---------------: |
| ①    |  1.706 | 752.3 |
| ②    |  1.987 | 261.5 |
| ③    |  1.478 | 176.9 |

クラスタリングを設定することでスキャンデータ量は`①>②>③`のように絞ることができました。
一方、処理時間は`②>①>③`となっております。
②はスキャンデータ量は絞れましたが、処理時間が長くなっているためクラスタリングの情報について確認します。

### 3.3. クラスタリング情報の確認
クラスタリング情報は[SYSTEM$CLUSTERING_INFORMATION](https://docs.snowflake.com/ja/sql-reference/functions/system_clustering_information)を実行し確認します。
確認にあたり取得パラメータと取得結果についてそれぞれ確認します。

#### 3.3.1. 取得パラーメタについて
クラスタリング情報を確認する際のパラメータを表に記載します。

| 項目                             | 説明                                                           |
| -------------------------------- | ------------------------------------------------------------ |
| `cluster_by_keys`                | クラスタリング情報を返すために使用されるテーブルの列                |
| `notes`                          | クラスタリングをより効率的にするための提案を含めることができます |
| `total_partition_count`          | テーブルを構成するマイクロパーティションの総数          |
| `total_constant_partition_count` | 指定された列の値が一定の状態に達したマイクロパーティションの合計数    |
| `average_overlaps`               | テーブル内にある各マイクロパーティションの重複するマイクロパーティションの平均数です。数値が大きい場合は、テーブルが適切にクラスター化されていないことを表示  |
| `average_depth`                  | テーブル内にある各マイクロパーティションの平均重複深度。数値が大きいとテーブルが適切にクラスター化されていない  |
| `partition_depth_histogram`      | テーブル内にある各マイクロパーティションの重複深度の分布を示すヒストグラムです。        |

#### 3.3.2. 取得結果
それではパターン②と③の結果を確認してみます。

```sql
-- パターン②
SELECT SYSTEM$CLUSTERING_INFORMATION('test_raw_b');
-- パターン③
SELECT SYSTEM$CLUSTERING_INFORMATION('test_raw_c');
```

:::details パターン②結果
```json
{
  "cluster_by_keys" : "LINEAR(event_date)",
  "notes" : "Clustering key columns contain high cardinality key EVENT_DATE which might result in expensive re-clustering. Please refer to https://docs.snowflake.net/manuals/user-guide/tables-clustering-keys.html for more information.",
  "total_partition_count" : 14,
  "total_constant_partition_count" : 0,
  "average_overlaps" : 6.5714,
  "average_depth" : 5.0,
  "partition_depth_histogram" : {
    "00000" : 0,
    "00001" : 0,
    "00002" : 0,
    "00003" : 0,
    "00004" : 0,
    "00005" : 14,
    "00006" : 0,
    "00007" : 0,
    "00008" : 0,
    "00009" : 0,
    "00010" : 0,
    "00011" : 0,
    "00012" : 0,
    "00013" : 0,
    "00014" : 0,
    "00015" : 0,
    "00016" : 0
  },
  "clustering_errors" : [ ]
}
```
:::

:::details パターン③結果
```json
{
  "cluster_by_keys" : "LINEAR( date_trunc('month', event_date))",
  "total_partition_count" : 16,
  "total_constant_partition_count" : 3,
  "average_overlaps" : 5.25,
  "average_depth" : 4.25,
  "partition_depth_histogram" : {
    "00000" : 0,
    "00001" : 3,
    "00002" : 0,
    "00003" : 0,
    "00004" : 0,
    "00005" : 13,
    "00006" : 0,
    "00007" : 0,
    "00008" : 0,
    "00009" : 0,
    "00010" : 0,
    "00011" : 0,
    "00012" : 0,
    "00013" : 0,
    "00014" : 0,
    "00015" : 0,
    "00016" : 0
  },
  "clustering_errors" : [ ]
}
```
:::


結果を表にします。

| 項目                             | パターン② | パターン③                   |
| -------------------------------- | --------------- | --------------------------------- |
| `cluster_by_keys`                | `event_date`    | `date_trunc('month', event_date)` |
| `notes`          | Clustering key columns contain high cardinality key..（省略）              | なし                                |
| `total_partition_count`          | 14              | 16                                |
| `total_constant_partition_count` | 0               | 3                                 |
| `average_overlaps`               | 6.5714          | 5.25                              |
| `average_depth`                  | 5.0             | 4.25                              |
| `partition_depth_histogram`      | 00005: 14     | 00001: 3<br>00005: 13            |

まず、パターン②ではカーディナリティの高い項目をキーとしているとnotesが表示されております。また、average_overlaps の値が 6.57 であることから、1つのパーティションに含まれる値が平均で約6.5個の他パーティションと重複してます。

今回使用したサンプルデータは、365日間のランダムな`event_date`を持つ形式で生成しており、データを並べ替えせずに日単位でクラスタリングを行ったため、スキャン対象のデータ量は削減できたものの、日付ごとのデータが細かく分散し、クラスタリングする前より対象データにたどり着くまで時間が増加したと考えられます。

この挙動の検証として、`event_date`でソートした上でクラスタリングした場合の効果も比較してみたいと思います。

### 3.4. サンプルデータをソートして再投入した結果の確認
再度パターン②③に対してソートした状態でデータを投入し、`SELECT *`にかかった時間を取得し表にします。

:::details ソートしたデータを再投入するsqlコード
```sql
/*-----------------
パターン②_ソートして再投入
-----------------*/
delete from test_raw_b;
-- test_raw_a のデータを投入
insert into test_raw_b
select *
from test_raw_a
order by event_date
;

/*-----------------
パターン③
-----------------*/
delete from test_raw_c;
-- test_raw_a のデータを投入
insert into test_raw_c
select *
from test_raw_a
order by event_date
;

```
:::


先ほどよりもスキャン量自体はさらに少なくなっております。
パターン②は処理時間が改善してますがパターン③については遅くなりました。
パターン③はクラスタリングキーが月単位ですが、日単位でデータを並べ替えて挿入したため月単位の粒度での効率的なパーティション分割が難しくなり、対象データを取得するのに時間がかかった可能性があります。


| パターン | 処理時間[s] | スキャンデータ量[MB] |
| ---- | ------------: | ---------------: |
| ①    |  1.706 | 752.3 |
| ②    | ソート前: 1.987<br>ソート後: 1.793 | ソート前: 261.5<br>ソート後: 102.8 |
| ③    | ソート前: 1.478<br>ソート後: 1.754 | ソート前: 176.9<br>ソート後: 92.1 |

また、再度確認したクラスタ情報を表にします。ソートして保持することでより改善されたことが確認できました。

| 項目                             | パターン②（日）      | パターン③（月）                          |
| -------------------------------- | ------------- | --------------------------------- |
| `cluster_by_keys`                | `event_date`  | `date_trunc('month', event_date)` |
| `notes`                          | {先程の結果と同様} | なし                                |
| `total_partition_count`          | 16            | 16                                |
| `total_constant_partition_count` | 0             | 7                                 |
| `average_overlaps`               | 1.0           | 0.75                              |
| `average_depth`                  | 2.0           | 1.5625                            |
| `partition_depth_histogram`      | depth=2: 16   | depth=1: 7<br>depth=2: 9          |



## 4. まとめ
今回の結果から、クラスタリングは「どのようにデータを並べ、キーを設計するか」が重要だなと確認できました。
特にマートテーブルhはBIツールからの参照速度は重要な観点になるため、クラスタリングの効果を最大化する観点は意識すべきだなと実感しました。


## 参考
- [マイクロパーティションとデータクラスタリング](https://docs.snowflake.com/ja/user-guide/tables-clustering-micropartitions#clustering-depth-illustrated)
- [QUERY_HISTORY , QUERY_HISTORY_BY_*](https://docs.snowflake.com/ja/sql-reference/functions/query_history)
- [クラスタリングキーとクラスタ化されたテーブル](https://docs.snowflake.com/ja/user-guide/tables-clustering-keys)
- [SYSTEM$CLUSTERING_INFORMATION](https://docs.snowflake.com/ja/sql-reference/functions/system_clustering_information)
- [超ざっくりマイクロパーティション紹介](https://zenn.dev/dataheroes/articles/972876054c75bc?redirected=1)
- [Snowflakeのクラスタリングキーについて理解を深める](https://zenn.dev/shintaroamaike/articles/570d3165f078f3)
