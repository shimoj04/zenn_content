---
title: "RedshiftでUNLOADを実行しS3にテーブルデータを出力する"
emoji: "🌊"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Redshift"]
published: true
published_at: 2025-01-31 09:00 # 未来の日時を指定する
---

# はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
普段はDWHであるRedshfitをメインにデータ分析基盤周りの業務に携わっております。
業務としてはファイル取込みからデータマートの作成までが多いですが、作成したデータマートをS3に出力することもあります。
出力時は[UNLOAD](https://docs.aws.amazon.com/ja_jp/redshift/latest/dg/r_UNLOAD.html)を利用しますのでパラーメータ指定別の出力内容について確認したいと思います。

## 前提
Redshiftクラスターが存在しており、UNLOADする必要な権限が付与されているものとします。

## 利用テーブルの作成
まずUNLOADする対象のテーブルを作成するため、プロシージャとして作成するコードを記載します。

:::details 動作確認テーブル作成のプロシージャコード
```sql

--------------------------
-- テスト用のスキーマを作成
--------------------------
create schema test;

--------------------------
-- テーブル再構築用のプロシージャコード
--------------------------
CREATE OR REPLACE PROCEDURE test.generate_test_data(num_records INT)
AS $$
DECLARE
  i INT;
BEGIN
  -- 作成対象のテーブルが存在してたら削除
	DROP TABLE IF EXISTS test.test_data;
  -- テストデータを格納するテーブルを作成
  CREATE TABLE IF NOT EXISTS test.test_data (
    id INT IDENTITY(1,1),
    name VARCHAR(50),
    email VARCHAR(100),
    age INT,
    created_at TIMESTAMP
  );

  -- 指定された件数のデータを生成
  FOR i IN 1..num_records LOOP
    INSERT INTO test.test_data (name, email, age, created_at)
    VALUES (
      'User' || i,
      'user' || i || '@example.com',
      20 + (i % 60),  -- 20歳から79歳までのランダムな年齢
      CURRENT_TIMESTAMP - (random() * INTERVAL '100 days')  -- 過去100日以内のランダムな日付
    );
  END LOOP;

  -- 生成されたデータ数を確認
  RAISE INFO 'Generated % records', num_records;
END;
$$ LANGUAGE plpgsql;
;

```
:::

作成したプロシージャを以下のように実行します。

```sql
--------------------------
-- 「2000」を引数にプロシージャを実行
--------------------------
call test.generate_test_data(2000);
```

## UNLOADの動作確認
作成したテーブルから以下表の4パターンとしてデータをS3に出力します。

| No | フォーマット | ヘッダー | パラレル | パーティション | 圧縮 | S3サブパス | パーティション |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pattern1 | csv | OFF | ON | 含めない | ー | pattern1 | 含めない |
| pattern2 | csv | ON | ON | 含む | GZIP | pattern2 | 含む |
| pattern3 | json | ー（サポート外） | ON | 含む | GZIP | pattern3 | 含む |
| pattern4 | PARQUET | ー（サポート外） | OFF | 含めない | ー（サポート外） | pattern4 | 含めない |

取得する際に実行するコードは以下となります。

:::details 4パターンのUNLOADコマンド
```sql
--------------------------
-- pattern1
--------------------------
UNLOAD ('select *, to_char(created_at, ''YYYYMM'') as yyyymm from test.test_data')
TO 's3://{S3bucket名}/unlopad_test/dev/pattern1/'
iam_role 'arn:aws:iam::1234567890:role/{ロール名}'
FORMAT CSV
-- HEADER
-- GZIP
PARALLEL ON -- デフォルトはONだが名義的に指定
-- partition by (yyyymm)
EXTENSION 'csv'
;

--------------------------
-- pattern2
--------------------------
UNLOAD ('select *, to_char(created_at, ''YYYYMM'') as yyyymm from test.test_data')
TO 's3://{S3bucket名}/unlopad_test/dev/pattern2/'
iam_role 'arn:aws:iam::1234567890:role/{ロール名}'
FORMAT CSV
HEADER
GZIP
PARALLEL ON
partition by (yyyymm) INCLUDE
EXTENSION 'csv'
;

--------------------------
-- pattern3
--------------------------
UNLOAD ('select *, to_char(created_at, ''YYYYMM'') as yyyymm from test.test_data')
TO 's3://{S3bucket名}/unlopad_test/dev/pattern3/'
iam_role 'arn:aws:iam::1234567890:role/{ロール名}'
FORMAT JSON
-- HEADER  -- サポート外
GZIP
PARALLEL ON
partition by (yyyymm)
EXTENSION 'json'
;

--------------------------
-- pattern4
--------------------------
UNLOAD ('select *, to_char(created_at, ''YYYYMM'') as yyyymm from test.test_data')
TO 's3://{S3bucket名}/unlopad_test/dev/pattern4/'
iam_role 'arn:aws:iam::1234567890:role/{ロール名}'
FORMAT PARQUET
-- HEADER
-- GZIP
PARALLEL OFF
-- partition by (yyyymm)
EXTENSION 'parquet'
;

```
:::

S3に出力したオブジェクトパスをCLIコマンドを利用して確認します。
```sh
# UNLOAD出力先のパス
$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/
                           PRE pattern1/
                           PRE pattern2/
                           PRE pattern3/
                           PRE pattern4/
2025-01-30 14:06:22          0 


# パターン1
$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern1/
2025-01-30 14:17:21     140450 0000_part_00.csv
2025-01-30 14:17:21          0 0001_part_00.csv


# パターン2
$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern2/
                           PRE yyyymm=202410/
                           PRE yyyymm=202411/
                           PRE yyyymm=202412/
                           PRE yyyymm=202501/

$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern2/yyyymm=202410/
2025-01-30 14:18:24       5000 0000_part_00.csv


# パターン3
$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern3/              
                           PRE yyyymm=202410/
                           PRE yyyymm=202411/
                           PRE yyyymm=202412/
                           PRE yyyymm=202501/

$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern3/yyyymm=202410/
2025-01-30 14:19:20       5259 0000_part_00.json


# パターン4
$ aws --profile csa-demo s3 ls s3://{S3bucket名}/unlopad_test/dev/pattern4/              
2025-01-30 14:19:50      57611 000.parquet

```

## まとめ
Redshiftに構築したテーブルのデータを出力しました。
出力フォーマットやパーティションを含めるなどの設定項目はありますが、作成したマートをファイル出力する際はとても便利だなと思いました。
この記事がどなたかの助けになれば幸いです。

## 参考リンク
- [UNLOAD の例](https://docs.aws.amazon.com/ja_jp/redshift/latest/dg/r_UNLOAD_command_examples.html)

