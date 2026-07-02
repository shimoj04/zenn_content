---
title: "【Snowflake】ブール演算を集計・ウィンドウ関数で使用する"
emoji: "📚"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [Snowflake]
published: true
published_at: 2026-07-02 11:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

Snowflakeでの集計際に、「対象が全部TRUEか」「1つでもTRUEがあるか」などを判断する際は [BOOLAND_AGG](https://docs.snowflake.com/ja/sql-reference/functions/booland_agg) や [BOOLOR_AGG](https://docs.snowflake.com/ja/sql-reference/functions/boolor_agg) が便利です。これらは集計関数として使えるだけでなく、OVER句を付ければウィンドウ関数としても使えます。
不定期にしか利用しないので、今回はサンプルデータを使って、両方の使い方を整理しておきます。

## 2. 実施内容
まずはテーブルを作成しサンプルデータを投入します。公式の内容と同じです。

```sql
CREATE OR REPLACE TABLE test_boolean (
  id INTEGER,
  c1 BOOLEAN,
  c2 BOOLEAN,
  c3 BOOLEAN,
  c4 BOOLEAN
)
;

INSERT INTO test_boolean (id, c1, c2, c3, c4) VALUES
  (1, TRUE, TRUE,  TRUE,  FALSE),
  (2, TRUE, FALSE, FALSE, FALSE),
  (3, TRUE, TRUE,  FALSE, FALSE),
  (4, TRUE, FALSE, FALSE, FALSE);

```

[COUNT_IF](https://docs.snowflake.com/ja/sql-reference/functions/count_if) を利用してそれぞれのTRUE/FALSE件数を表にします。
:::details TRUE/FALSEの件数確認SQL
```sql
SELECT
    'TRUEの件数'  AS "TRUE/FALSEの件数",
    COUNT_IF(c1),
    COUNT_IF(c2),
    COUNT_IF(c3),
    COUNT_IF(c4)
FROM test_boolean
UNION ALL
SELECT
    'FALSEの件数' AS "TRUE/FALSEの件数",
    COUNT_IF(NOT c1),
    COUNT_IF(NOT c2),
    COUNT_IF(NOT c3),
    COUNT_IF(NOT c4)
FROM test_boolean;
```
:::

| TRUE/FALSEの件数 | COUNT_IF(C1) | COUNT_IF(C2) | COUNT_IF(C3) | COUNT_IF(C4) |
|---|---|---|---|---|
| TRUEの件数 | 4 | 2 | 1 | 0 |
| FALSEの件数 | 0 | 2 | 3 | 4 |



今回利用する関数は以下の3つです。
これらを集計関数とwindow関数として利用します。

| 関数 | 説明 |
|---|---|
| [BOOLAND_AGG](https://docs.snowflake.com/ja/sql-reference/functions/booland_agg) | グループ内の非NULLブール記録が **すべてTRUE** の場合はTRUEを返す |
| [BOOLOR_AGG](https://docs.snowflake.com/ja/sql-reference/functions/boolor_agg) | グループ内の非NULLブール記録が **1つ以上TRUE** の場合はTRUEを返す |
| [BOOLXOR_AGG](https://docs.snowflake.com/ja/sql-reference/functions/boolxor_agg) | グループ内の非NULLブール記録が **1つのみTRUE** の場合はTRUEを返す |



### 2.1. 集計関数として使用

3つのブール関数を利用して結果を確認します。
```sql
SELECT
    'BOOLAND_AGG' AS func,
    BOOLAND_AGG(c1),
    BOOLAND_AGG(c2),
    BOOLAND_AGG(c3),
    BOOLAND_AGG(c4)
FROM test_boolean
UNION ALL
SELECT
    'BOOLOR_AGG' AS func,
    BOOLOR_AGG(c1),
    BOOLOR_AGG(c2),
    BOOLOR_AGG(c3),
    BOOLOR_AGG(c4)
FROM test_boolean
UNION ALL
SELECT
    'BOOLXOR_AGG' AS func,
    BOOLXOR_AGG(c1),
    BOOLXOR_AGG(c2),
    BOOLXOR_AGG(c3),
    BOOLXOR_AGG(c4)
FROM test_boolean;
```


| FUNC | C1 | C2 | C3 | C4 |
|---|---|---|---|---|
| BOOLAND_AGG | TRUE | FALSE | FALSE | FALSE |
| BOOLOR_AGG | TRUE | TRUE | TRUE | FALSE |
| BOOLXOR_AGG | FALSE | FALSE | TRUE | FALSE |

想定通りですね。BOOLXOR_AGGがちょっとややこしいですが、TRUEが1件のC3の場合のみTRUEとなっていることが確認できます。


### 2.2. ウィンドウ関数として使う
続いて、ウィンドウ関数として使った場合を確認します。
テーブルにIDがマイナスの行を追加します。

```sql
INSERT INTO test_boolean (id, c1, c2, c3, c4) VALUES
  (-4, FALSE, FALSE, FALSE, TRUE),
  (-3, FALSE, TRUE,  TRUE,  TRUE),
  (-2, FALSE, FALSE, TRUE,  TRUE),
  (-1, FALSE, TRUE,  TRUE,  TRUE);
```

`PARTITION BY (id > 0)` で「idが正のグループ(TRUE)」と「idが0以下のグループ(FALSE)」の2つに分けて集計します。

BOOLAND_AGG のみの結果を確認します。
```sql
SELECT
    id,
    BOOLAND_AGG(c1) OVER (PARTITION BY (id > 0)) AS and_c1,
    BOOLAND_AGG(c2) OVER (PARTITION BY (id > 0)) AS and_c2,
    BOOLAND_AGG(c3) OVER (PARTITION BY (id > 0)) AS and_c3,
    BOOLAND_AGG(c4) OVER (PARTITION BY (id > 0)) AS and_c4
FROM test_boolean
ORDER BY id;
```

| id | and_c1 | and_c2 | and_c3 | and_c4 |
|---|---|---|---|---|
| -4 | False | False | False | True |
| -3 | False | False | False | True |
| -2 | False | False | False | True |
| -1 | False | False | False | True |
| 1 | True | False | False | False |
| 2 | True | False | False | False |
| 3 | True | False | False | False |
| 4 | True | False | False | False |

集計関数(パターン1)はグループごとに1行に集約されましたが、ウィンドウ関数では明細行(id)を保ったまま各行に集計結果が付与されています。

:::details BOOLOR_AGG / BOOLXOR_AGG のウィンドウ関数結果

**BOOLOR_AGG**

```sql
SELECT
    id,
    BOOLOR_AGG(c1) OVER (PARTITION BY (id > 0)) AS or_c1,
    BOOLOR_AGG(c2) OVER (PARTITION BY (id > 0)) AS or_c2,
    BOOLOR_AGG(c3) OVER (PARTITION BY (id > 0)) AS or_c3,
    BOOLOR_AGG(c4) OVER (PARTITION BY (id > 0)) AS or_c4
FROM test_boolean
ORDER BY id;
```

| id | or_c1 | or_c2 | or_c3 | or_c4 |
|---|---|---|---|---|
| -4 | False | True | True | True |
| -3 | False | True | True | True |
| -2 | False | True | True | True |
| -1 | False | True | True | True |
| 1 | True | True | True | False |
| 2 | True | True | True | False |
| 3 | True | True | True | False |
| 4 | True | True | True | False |

**BOOLXOR_AGG**

```sql
SELECT
    id,
    BOOLXOR_AGG(c1) OVER (PARTITION BY (id > 0)) AS xor_c1,
    BOOLXOR_AGG(c2) OVER (PARTITION BY (id > 0)) AS xor_c2,
    BOOLXOR_AGG(c3) OVER (PARTITION BY (id > 0)) AS xor_c3,
    BOOLXOR_AGG(c4) OVER (PARTITION BY (id > 0)) AS xor_c4
FROM test_boolean
ORDER BY id;
```

| id | xor_c1 | xor_c2 | xor_c3 | xor_c4 |
|---|---|---|---|---|
| -4 | False | False | False | False |
| -3 | False | False | False | False |
| -2 | False | False | False | False |
| -1 | False | False | False | False |
| 1 | False | False | True | False |
| 2 | False | False | True | False |
| 3 | False | False | True | False |
| 4 | False | False | True | False |
:::

## 3. まとめ
ブール関数は集計時に、稀によく利用するので改めて整理してみました。


## 4. 参考リンク

- [BOOLAND_AGG](https://docs.snowflake.com/ja/sql-reference/functions/booland_agg)
- [BOOLOR_AGG](https://docs.snowflake.com/ja/sql-reference/functions/boolor_agg)
- [BOOLXOR_AGG](https://docs.snowflake.com/ja/sql-reference/functions/boolxor_agg)
- [COUNT_IF](https://docs.snowflake.com/ja/sql-reference/functions/count_if)