---
title: "Snowflakeに外部ステージ/内部ステージを利用してデータを取込む"
emoji: "🐷"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [aws, Snowflake, Snowpipe, s3]
published: true
published_at: 2026-06-27 12:30
---

## 1. はじめに

こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

Snowflakeへのデータ取り込みには、外部ステージと内部ステージを利用する方法があります。
今回はそれぞれ実際に試してみた内容を整理します。

## 2. この記事でやること
今回はそれぞれの方法でデータ取り込みを試します。

| # | ステージ | ストレージ | 方法 |
|---|---|---|---|
| 1 | 外部ステージ | AWS S3 | COPY INTO |
| 2 | 外部ステージ | AWS S3 | Snowpipe |
| 3 | 内部ステージ | ローカル | PUT + COPY INTO |
| 4 | 内部ステージ | ローカル | PUT + REST API |

各種アカウントの接続設定は完了済みとし、テーブルDDL/取込み用データusersを利用します。

:::details テーブルと取込みファイルの内容

テーブルDDL とファイルフォーマット
```sql
-- テーブルDDL
CREATE OR REPLACE TABLE external_users (        -- 外部ステージ + COPY INTO
-- CREATE OR REPLACE TABLE external_pipe_users ( -- 外部ステージ + Snowpipe
-- CREATE OR REPLACE TABLE internal_users (       -- 内部ステージ + COPY INTO
-- CREATE OR REPLACE TABLE internal_rest_users (  -- 内部ステージ + REST API
    user_id   NUMBER,
    name      STRING,
    age       NUMBER,
    email     STRING
);

-- ファイルフォーマット作成（共通）
CREATE OR REPLACE FILE FORMAT csv_file_format
  TYPE = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1
;
```

取込みファイル
```csv
user_id,name,age,email
1,比嘉太郎,28,higa@example.com
2,新垣花子,34,aragaki@example.com
3,宮里一郎,22,miyazato@example.com
```

:::


## 3. 外部ステージを利用したファイルの取込み

### 3.1. COPY INTO
外部ステージを利用する際には、ファイルを配置した AWS環境に関する権限設定も必要なため、S3操作の最小権限を登録したpolicy と role を作成します。


:::details IAM roleの作成（AWS CLI）
```bash
# ポリシーの作成
$ aws --profile my_iam iam create-policy \
  --policy-name snowflake-s3-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource": [
          "arn:aws:s3:::{バケット名}",
          "arn:aws:s3:::{バケット名}/*"
        ]
      }
    ]
  }'

# ロールの作成（Principalは一旦自分のAWSアカウントIDで作成）
$ aws --profile my_iam iam create-role \
  --role-name my_snowflake_role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::{YOUR_AWS_ACCOUNT_ID}:root"
        },
        "Action": "sts:AssumeRole",
        "Condition": {
          "StringEquals": {
            "sts:ExternalId": "DUMMY_EXTERNAL_ID"
          }
        }
      }
    ]
  }'

# ポリシーのARNを確認
$ aws --profile my_iam iam list-policies \
  --query "Policies[?PolicyName=='snowflake-s3-policy'].Arn" \
  --output text

# ロールにポリシーをアタッチ
$ aws --profile my_iam iam attach-role-policy \
  --role-name my_snowflake_role \
  --policy-arn arn:aws:iam::{YOUR_AWS_ACCOUNT_ID}:policy/snowflake-s3-policy

# ロールのARNを確認（SnowflakeのSTORAGE_AWS_ROLE_ARNに使う）
$ aws --profile my_iam iam get-role \
  --role-name my_snowflake_role \
  --query 'Role.Arn' \
  --output text
```
:::

続いて、作成したroleのARNをもとに、Snowflakeにてストレージ統合と外部ステージを作成します。

:::details ストレージ統合・外部ステージ作成（Snowflake）
```sql
-- ストレージ統合の作成
CREATE OR REPLACE STORAGE INTEGRATION s3_storage_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::{YOUR_AWS_ACCOUNT_ID}:role/my_snowflake_role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://{バケット名}/')
;

-- STORAGE_AWS_IAM_USER_ARN と STORAGE_AWS_EXTERNAL_ID を確認
DESC INTEGRATION s3_storage_integration;

-- 外部ステージ作成
CREATE OR REPLACE STAGE s3_external_stage
  URL = 's3://{バケット名}/'
  STORAGE_INTEGRATION = s3_storage_integration
;

-- ※ この時点ではrole側の信頼関係が未更新のためエラーになります
LIST @s3_external_stage;
```
:::

`DESC INTEGRATION`で確認した`STORAGE_AWS_IAM_USER_ARN`と`STORAGE_AWS_EXTERNAL_ID`をもとに、roleの信頼関係を更新します。

:::details roleの信頼関係を更新（AWS CLI）
```bash
$ aws --profile my_iam iam update-assume-role-policy \
  --role-name my_snowflake_role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "{STORAGE_AWS_IAM_USER_ARNの値}"
        },
        "Action": "sts:AssumeRole",
        "Condition": {
          "StringEquals": {
            "sts:ExternalId": "{STORAGE_AWS_EXTERNAL_IDの値}"
          }
        }
      }
    ]
  }'
```
:::

信頼関係の更新後、`LIST @s3_external_stage`でS3バケット内のファイルが参照できるようになりますので、ファイルをアップロードして、データを取込みます。
```bash
# S3へアップロード
$ aws --profile my_iam s3 cp user.csv s3://{バケット名}/user/
upload: ./user.csv to s3://{バケット名}/user/user.csv
```

```sql
-- データ取込み
COPY INTO external_users
FROM @s3_external_stage/user/user.csv
FILE_FORMAT = csv_file_format
;

-- 取込み確認
SELECT * FROM external_users;

... (省略)
```

取込みの確認ができました！

### 3.2. Snowpipe を利用した取込み
次に、SnowpipeとSQSを使ってS3にファイルをアップロードしたタイミングで自動的に取り込む設定をします。
利用時には、S3バケットの対象パスに配置した際に実行するS3イベントに、Snowpipeの SQS ARN を登録することで実行されます。

まずは、Pipeを作成します。
:::details Pipe作成（Snowflake）
```sql
-- Pipe作成
CREATE OR REPLACE PIPE users_pipe
  AUTO_INGEST = TRUE
AS
COPY INTO external_pipe_users
FROM @s3_external_stage/user/snowpipe/
FILE_FORMAT = csv_file_format
;

-- PipeのSQS ARNを確認（S3のイベント通知に設定する）
DESC PIPE users_pipe;
```
:::

`DESC PIPE`で確認した`notification_channel`のSQS ARNをS3のイベント通知に登録します。

:::details S3イベント通知の設定（AWS CLI）
```bash
# DESC PIPEで確認したSQS ARNを変数に入れる
SQS_ARN="arn:aws:sqs:ap-northeast-1:SNOWFLAKE_SQS_ACCOUNT_ID:sf-snowpipe-xxxxxxxxxx"

# S3イベント通知の設定
$ aws --profile my_iam s3api put-bucket-notification-configuration \
  --bucket {バケット名} \
  --notification-configuration '{
    "QueueConfigurations": [
      {
        "QueueArn": "'"${SQS_ARN}"'",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {
                "Name": "prefix",
                "Value": "user/snowpipe/"
              }
            ]
          }
        }
      }
    ]
  }'

# 設定確認
$ aws --profile my_iam s3api get-bucket-notification-configuration \
  --bucket {バケット名}
```
:::

S3イベントに、Snowflake pipe作成時に取得した SQS ARN を登録したので、ファイルをアップロードして確認します。

```bash
$ aws --profile my_iam s3 cp user.csv s3://{バケット名}/user/snowpipe/
upload: ./user.csv to s3://{バケット名}/user/snowpipe/user.csv
```

```sql
-- アップロード後に自動で取り込まれていることを確認
SELECT * FROM external_pipe_users;
... (省略)
```

アップロードしたタイミングでファイルが取込みできることを確認しました。

## 4. 内部ステージからの取り込み（ローカル）
### 4.1. PUT + COPY INTO による取込み
内部ステージを作成し、ローカルのファイルをPUTして取り込みます。

```sql
-- 内部ステージ作成
CREATE OR REPLACE STAGE my_internal_stage;

-- ローカルからファイルをPUT
PUT file://./user.csv @my_internal_stage AUTO_COMPRESS=FALSE;
+-----------+-----------+-------------+-------------+--------------------+--------------------+--------+---------+
| source    | target    | source_size | target_size | source_compression | target_compression | status | message |
|-----------+-----------+-------------+-------------+--------------------+--------------------+--------+---------|
| user.csv  | user.csv  |         136 |         136 | NONE               | NONE               | UPLOADED|        |
+-----------+-----------+-------------+-------------+--------------------+--------------------+--------+---------+

-- データ取込み
COPY INTO internal_users
FROM @my_internal_stage/user.csv
FILE_FORMAT = csv_file_format
;

-- 取込み確認
SELECT * FROM internal_users;
... (省略)
```

手動での取り込みが確認できました！

### 4.2. PUT + REST APIによる取込み
PUTしたタイミングでSnowpipe REST APIを使って取込む設定をします。

```bash
# キーペア生成
$ openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
$ openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

:::details Pipe・ユーザー・権限設定（Snowflake）
```sql
-- Pipe作成
CREATE OR REPLACE PIPE internal_rest_pipe
AS
COPY INTO internal_rest_users
FROM @my_internal_stage
FILE_FORMAT = csv_file_format
;

-- カスタムロール作成
CREATE ROLE snowpipe_role;

-- ユーザー作成
CREATE USER snowpipe_rest_user
  DEFAULT_ROLE = snowpipe_role
  MUST_CHANGE_PASSWORD = FALSE
;

-- ロールの使用権限
GRANT ROLE snowpipe_role TO USER snowpipe_rest_user;

-- 公開鍵を登録
ALTER USER snowpipe_rest_user SET RSA_PUBLIC_KEY='公開鍵の中身';

-- DB・スキーマへのアクセス権限
GRANT USAGE ON DATABASE UDEMY_DB TO ROLE snowpipe_role;
GRANT USAGE ON SCHEMA UDEMY_DB.INTERNAL_STAGES_SCHEMA TO ROLE snowpipe_role;

-- テーブルへのCRUD権限
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA UDEMY_DB.INTERNAL_STAGES_SCHEMA TO ROLE snowpipe_role;

-- ステージへの権限
GRANT READ ON STAGE my_internal_stage TO ROLE snowpipe_role;

-- Pipeへの権限
GRANT OPERATE ON PIPE internal_rest_pipe TO ROLE snowpipe_role;

-- MONITOR権限を付与
GRANT MONITOR ON PIPE UDEMY_DB.INTERNAL_STAGES_SCHEMA.internal_rest_pipe TO ROLE snowpipe_role;

-- 確認
DESC USER snowpipe_rest_user;
```
:::

公式サイトの [Python SDK のサンプルプログラム](https://docs.snowflake.com/ja/user-guide/data-load-snowpipe-rest-load#sample-program-for-the-python-sdk:~:text=Python%20SDK%20%E3%81%AE%E3%82%B5%E3%83%B3%E3%83%97%E3%83%AB%E3%83%97%E3%83%AD%E3%82%B0%E3%83%A9%E3%83%A0) をそのまま利用します。以下変更したポイントのみ記載します。
:::details python SDK サンプルプログラムの変更点
```python
... (省略)
with open("{秘密鍵のディレクトリpath}/rsa_key.p8", 'rb') as pem_in:
  pemlines = pem_in.read()
  private_key_obj = load_pem_private_key(
    pemlines, 
    password=None,  ## 作成したユーザーはパスワードを設定していないため変更
    backend=default_backend())
  

private_key_text = private_key_obj.private_bytes(
  Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()).decode('utf-8')
# Assume the public key has been registered in Snowflake:
# private key in PEM format
    
ingest_manager = SimpleIngestManager(account="{アカウント名}.{リージョン}.aws",
                                     host="{アカウント名}.{リージョン}.aws.snowflakecomputing.com",
                                     user='snowpipe_rest_user',
                                     pipe="{データベース名}.{スキーマ名}.internal_rest_pipe",
                                     private_key=private_key_text)
# List of files, but wrapped into a class
staged_file_list = [StagedFile('user.csv', None)] # 取り込みファイル名を固定で実施
... (省略)
```
:::

事前にuvでプロジェクトを作成し、パッケージをインストールします。
```bash
# プロジェクト作成
$ uv init snowflake-ingest-app
$ cd snowflake-ingest-app

# パッケージインストール
$ uv add snowflake-ingest
```

REST API実行前に`my_internal_stage`にファイルをアップロードします。
```sql
snowsql -q "PUT file://./user.csv @my_internal_stage AUTO_COMPRESS=FALSE;"
```


```bash
# 処理の実行
$ uv run internal_rest.py
{'pipe': '{データベース名}.{スキーマ名}.INTERNAL_REST_PIPE', 'completeResult': True, 'nextBeginMark': None, 'files': [{'path': 'user.csv', 'stageLocation': 'stages/b4639776-b52b-42ec-a25e-8a925f164272/', 'fileSize': 135, 'bytesBilled': 135, 'timeReceived': '2026-06-27T02:36:06.344Z', 'lastInsertTime': '2026-06-27T02:36:43.396Z', 'rowsInserted': 3, 'rowsParsed': 3, 'errorsSeen': 0, 'errorLimit': 1, 'complete': True, 'status': 'LOADED'}], 'statistics': None}
```

```sql
SELECT * FROM internal_rest_users;
... (省略)
```

取込まれることを確認しました

## 5. まとめ
Snowflakeへのデータ取り込みを外部ステージ・内部ステージの2パターンで試しました。
外部ステージはAWS側の権限設定など多いですが、一度作ればSnowpipeなどで自動化できるのは便利そうです。

今回、REST API 実施時は固定のファイル名で実施しましたが、取込み済みファイルは再度取り込まれないため、本番運用時は日付やタイムスタンプなどで管理する必要があります。
ただ、複数回取込まれないというのは重複回避される安心感があって良いですね。

## 6. 参考
- [Snowflake公式：Snowpipe（日本語）](https://docs.snowflake.com/ja/user-guide/data-load-snowpipe-intro)
- [内部ステージ版 Snowpipe Auto-ingest を試してみた（Zenn）](https://zenn.dev/yujmatsu/articles/20251119_sf_snowpipe_test)
- [データのロードの概要](https://docs.snowflake.com/ja/user-guide/data-load-overview#internal-stages)
- [Snowflakeにデータをロード](https://docs.snowflake.com/ja/guides-overview-loading-data)
- [【初心者向け】Snowflake のステージについて整理して実際に試してみる](https://blog.serverworks.co.jp/2025/07/07/155121#%E5%A4%96%E9%83%A8%E3%82%B9%E3%83%86%E3%83%BC%E3%82%B8%E3%82%92%E4%BD%BF%E3%81%A3%E3%81%A6%E3%83%87%E3%83%BC%E3%82%BF%E3%82%92%E3%82%A2%E3%83%83%E3%83%97%E3%83%AD%E3%83%BC%E3%83%89%E3%81%97%E3%81%A6%E3%81%BF%E3%82%8B)
- [Option 1: Load data with the Snowpipe REST API](https://docs.snowflake.com/ja/user-guide/data-load-snowpipe-rest-load#sample-program-for-the-python-sdk)
- [Work with Amazon S3-compatible storage](https://docs.snowflake.com/ja/user-guide/data-load-s3-compatible-storage)
- [SnowflakeのSnowpipe REST APIを利用して内部ステージからデータロードをしてみた](https://dev.classmethod.jp/articles/snowpipe-rest-api-call/)