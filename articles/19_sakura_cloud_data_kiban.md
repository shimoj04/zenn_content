---
title: "dbt×DuckDB×Supersetで作るデータ分析基盤"
emoji: "🔖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [dbt, duckdb, superset, さくらのクラウド]
published: true
published_at: 2025-12-03 12:00
---

この記事は [さくらインターネット Advent Calendar 2025](https://qiita.com/advent-calendar/2025/sakura) 3日目の記事です。

こんにちは。（心の内では）健康を目指して日々精進している shimoj です。
普段は データエンジニア として、データの収集や加工などを担当しています。

「学びはアウトプットを伴ってこそ」と自分に言い聞かせてますが、久々の投稿です。
今回は さくらのクラウドを使って、軽量なデータ分析基盤を構築してみた内容をまとめます。

## 1. 今回やること（全体像）
構築するのは、次の流れで動く ミニマムな分析基盤 です。

```さくらのオブジェクトストレージ → DuckDB → dbt → Superset```

内容は以下となります。
1. サンプルデータを作成し、オブジェクトストレージに配置
2. DuckDBでオブジェクトストレージのファイルを読取る
3. dbt で共通化（名寄せ・整形）
4. Superset で可視化

データ分析としては「収集 → 蓄積 → 加工 → 分析 → 可視化」 / スケジュール管理 / 通知 ..etc など必要事項がたくさんありますが、`蓄積後の整形〜可視化` にフォーカスした構成をやってみます。

## 2. 事前準備
始める前に 利用するOSS と さくらのクラウドの構成 について記載します。

### 2.1. 利用するOSS
今回の主役となる OSS を表にします。

| 種別     | OSS          | 役割                                 |
| ------ | ------------ | ---------------------------------- |
| データベース | [**DuckDB**](https://duckdb.org/)   | オブジェクトストレージ上の CSV を直接読み込み、分析クエリを実行 |
| モデリング  | [**dbt**](https://www.getdbt.com/)      | SQL モデル化とカラム統一、ファクト/ディメンション生成      |
| 可視化    | [**Superset**](https://superset.apache.org/) | DuckDB 上のデータからダッシュボード作成            |

### 2.2. 利用するさくらのクラウド
利用するは次の 3つです。

- [サーバー](https://cloud.sakura.ad.jp/products/server/): DuckDB / dbt を同梱
- [サーバー](https://cloud.sakura.ad.jp/products/server/): Superset 
シンプルモードで構築したサーバーの例です。
![](/images/19_sakura_cloud_data_kiban/1_make_sakura_server.png)

- [オブジェクトストレージ](https://cloud.sakura.ad.jp/products/object-storage/): raw データ（CSV）の置き場（APIキーを取得）
![](/images/19_sakura_cloud_data_kiban/2_object_api.png)


## 3. データ構成と課題
### 3.1. サンプルのデータ構成
今回はサンプルとして、次の 3種類のデータを扱います。
なお2つの売上システムは [generate_sales_sample.py](https://github.com/shimoj04/zenn_content/blob/main/sandbox/stacks/01_data_analysis_sakura_cloud/1_make_sample_file/generate_sales_sample.py) にて実行して生成します。顧客は[customer.csv](https://github.com/shimoj04/zenn_content/blob/main/sandbox/stacks/01_data_analysis_sakura_cloud/1_make_sample_file/customer.csv) サンプル用ファイルを使用します。

1. システム1の売上（sales_sys1）

| カラム名               | 型         | 説明      |
| ------------------ | --------- | ------- |
| sales_mgmt_no      | VARCHAR   | 売上管理番号  |
| order_datetime     | TIMESTAMP | 注文日時    |
| customer_id        | VARCHAR   | 顧客ID    |
| product_id         | VARCHAR   | 商品ID    |
| `amount`             | INTEGER   | 税抜金額    |
| `amount_include_tax` | INTEGER   | 税込金額    |
| `order_status`       | VARCHAR   | 注文ステータス |
| payment_method     | VARCHAR   | 支払方法    |
| store_code         | VARCHAR   | 店舗コード   |

2. システム2の売上（sales_sys2）

| カラム名                 | 型         | 説明        |
| -------------------- | --------- | --------- |
| sales_mgmt_no        | VARCHAR   | 売上管理番号    |
| billing_datetime     | TIMESTAMP | 請求日時      |
| customer_id          | VARCHAR   | 顧客ID      |
| product_id           | VARCHAR   | 商品ID      |
| `price`                | INTEGER   | 税抜金額      |
| `tax_price`            | INTEGER   | 税額        |
| `billing_status`       | VARCHAR   | 請求ステータス   |
| subscription_plan_id | VARCHAR   | サブスクプランID |
| billing_cycle        | VARCHAR   | 課金周期      |

3. 顧客情報（customer）

| カラム名          | 型       | 説明              |
| ------------- | ------- | --------------- |
| customer_id   | VARCHAR | 顧客ID            |
| customer_name | VARCHAR | 氏名              |
| age_group     | VARCHAR | 年代              |
| gender        | VARCHAR | 性別              |
| region        | VARCHAR | 地域              |
| customer_type | VARCHAR | 顧客種別（個人 / 法人など） |


### 3.2. 課題点
今回のケースでは、税抜金額や注文ステータスの表記揺れがあります。
料金の合計を求める際に、税抜と税込金額 を集計するなど意図しない誤集計が発生する可能性があります。
そこで dbt を使って項目の共通化を実施します。

## 4. 実施内容

### 4.1. 環境構築
まずは作成したサーバの環境構築を行います。

#### 4.1.1. dbtとDuckDBの構築
ローカル端末からSSH接続し、DuckDB / dbt を構築します。

:::details DuckDBとdbtの構築
```bash
# ローカル端末からSSH接続
$ ssh -i  ~/.{秘密鍵配置パス} ubuntu@{サーバーのグローバルIP}

$ pwd
/home/ubuntu

# duckdbの取得
$ wget https://github.com/duckdb/duckdb/releases/download/v1.1.2/duckdb_cli-linux-amd64.zip
$ unzip duckdb_cli-linux-amd64.zip
$ chmod +x duckdb
$ sudo mv duckdb /usr/local/bin/

## DuckDBのバージョン確認
$ duckdb --version
<jemalloc>: Out-of-range conf value: narenas:0
v1.1.2 f680b7d08f
```

続いてdbtを導入します。
```bash
# venv環境作成
$ python -m venv venv

# 有効化
$ source venv/bin/activate

# dbt-duckdb のインストール
(venv)$ pip install --upgrade pip
(venv)$ pip install dbt-duckdb
# プロジェクトの開始
(venv)$ dbt init sakura_analytics
```
:::


#### 4.1.2. superset構築
SupersetはDockerコンテナをたてるため、導入から開始します。

:::details Dockerの導入
```bash
# ローカル端末からSSH接続
$ ssh -i  ~/.{秘密鍵配置パス} ubuntu@{サーバーのグローバルIP}

# docker導入
$ sudo apt update
$ sudo apt install -y ca-certificates curl gnupg
$ sudo install -m 0755 -d /etc/apt/keyrings
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$ sudo chmod a+r /etc/apt/keyrings/docker.gpg

$ echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
$ sudo apt update
$ sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

$ docker --version
Docker version 29.1.1, build 0aedba5
```

dockerのバージョンが出たら、[3_superset](https://github.com/shimoj04/zenn_content/tree/main/sandbox/stacks/01_data_analysis_sakura_cloud/3_superset) の2つのファイルを配置して、dockerコンテナを起動します。

```bach
$ docker compose build
$ docker compose up -d
```
:::


### 4.2 Duckdbからオブジェクトストレージのファイルを読み取る
構築後に、DuckDb / dbt を導入したサーバに接続しduckdbにログインします。

```bash
# -- warehouse.duckdb に構築したデータが登録される
  # duckdbに入ると 先頭が D となる
$ duckdb warehouse.duckdb 
D
```

続いてオブジェクトストレージに配置したサンプルファイルを取込みます。

:::details サンプルファイルを取込むSQL
```sql
CREATE TABLE raw_sales_sys1 AS
  SELECT *
  FROM read_csv(
    's3://{バケット名}/raw/sales_sys1/2025/*/*.csv',
    columns = {
      'sales_mgmt_no': 'VARCHAR',
      'order_datetime': 'TIMESTAMP',
      'customer_id': 'VARCHAR',
      'product_id': 'VARCHAR',
      'amount': 'BIGINT',
      'amount_include_tax': 'BIGINT',
      'order_status': 'VARCHAR',
      'payment_method': 'VARCHAR',
      'store_code': 'VARCHAR'
    },
    header = TRUE,
    delim = ',',
    SKIP = 1,
    auto_detect = FALSE
  );

CREATE TABLE raw_sales_sys2 AS
  SELECT *
  FROM read_csv(
    's3://{バケット名}/raw/sales_sys2/2025/*/*.csv',
    columns = {
      'sales_mgmt_no': 'VARCHAR',
      'billing_datetime': 'TIMESTAMP',
      'customer_id': 'VARCHAR',
      'product_id': 'VARCHAR',
      'price': 'BIGINT',
      'tax_price': 'BIGINT',
      'billing_status': 'VARCHAR',
      'subscription_plan_id': 'VARCHAR',
      'billing_cycle': 'VARCHAR'
    },
    header = TRUE,
    delim = ',',
    SKIP = 1,
    auto_detect = FALSE
  );

CREATE TABLE raw_customer AS
  SELECT *
  FROM read_csv(
    's3://{バケット名}/raw/customer/customer.csv',
    columns = {
      'customer_id': 'VARCHAR',
      'customer_name': 'VARCHAR',
      'age_group': 'VARCHAR',
      'gender': 'VARCHAR',
      'region': 'VARCHAR',
      'customer_type': 'VARCHAR'
    },
    header = TRUE,
    delim = ',',
    SKIP = 1,
    auto_detect = FALSE
  );
```
:::


### 4.3. dbt による整形
DBT プロジェクトを構成します。コードの詳細は[models](https://github.com/shimoj04/zenn_content/tree/main/sandbox/stacks/01_data_analysis_sakura_cloud/2_dbt/models)を参照ください。


```bash
# 構成
models
  ├── staging
  │   ├── sources.yml
  │   ├── stg_sales1.sql
  │   └── stg_sales2.sql
  └── dwh
      ├── fct_sales.sql
      └── dim_customer.sql
```

各スキーマの役割を記載します。
- staging：売上システム1/2 の命名を統一
- dwh：売上を統合したファクト /  顧客のディメンションを作成

models直下のファイルを配置後に`dbt run` にて作成します。
```bash
$ dbt run
...
00:14:52  Completed successfully
00:14:52
00:14:52  Done. PASS=9 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=9
00:14:52  [WARNING][DeprecationsSummary]: Deprecated functionality
```

ここで共通化したテーブルを作成しました。

さて、共通化したデータは、duckdb/dbtサーバーの`warehouse.duckdb`です。

~~（手間ですが）~~ ローカル端末経由で supersetのサーバへファイルを転送します。

```bash
# warehouse.duckdbをローカルに取得
scp -i ~/.ssh/{秘密鍵} ubuntu@{サーバーIP}:/home/ubuntu/warehouse.duckdb .

# warehouse.duckdb をsupersetサーバに転送
scp -i ~/.ssh/{秘密鍵} warehouse.duckdb ubuntu@{サーバーIP}:/home/ubuntu/duckdb_file/ 
```

### 4.4. superset による可視化
それでは、supersetで作成した最終的なダッシュボード図と取得項目を記載します。

- 11_total_amount: 税抜金額の合計
- 12_mgmt_no_counts: 契契約の合計
- 13_customer_counts: 契約のある顧客数の合計
- 14_chart_saleym_amount: 売上金額の月次推移
- 15_product_sales_amount: 売上金額の月次推移（商品毎に区分

![](/images/19_sakura_cloud_data_kiban/3_dashboard.png)

グラフができるとなんだかやった感があるなと感じます。
ランダムに作成したサンプルデータ、不定期に月次推移が上下するのは面白いですね。
上がったり下がったりあるのは面白いですね。

以下 superset での設定項目を記載します。

:::details supersetの登録内容
1. まずはじめにログインします。（ユーザー/ パスワード: admin/admin）
- https://{sueprsetサーバーのIPアドレス}:8088

2. 続いて、データベースの接続設定を行います。（接続設定）
- Supported databases: Other
- SQLAlchemy URI: duckdb:////duckdb/warehouse.duckdb

3. Datasetsの作成（売上と顧客を結合し、キャンセルを省いた結果を取得）

```sql
select sales.*
     , customer.age_group, customer.gender, customer.region, customer.customer_type
from warehouse.dbt_dwh.fct_sales sales
left join warehouse.dbt_dwh.dim_customer customer
on sales.customer_id = customer.customer_id
where 1 = 1 and order_status != 'canceled' and sales.sale_ym >= '2025-01-01';
```
:::

## ５. まとめ
今回は、さくらのクラウドを使って 軽量なデータ分析基盤を自作してみました。
業務や今回の構築を通して、共通化というのは「データ分析基盤の中で一番地味だけど重要なところ」ではないかと個人的に実感しております。
作りながら、コード管理や自動化などを考えたり楽し維持感を過ごしたので今後も、少しずつ改良しながらより良い基盤を作れたらなと感じております。

さくらインターネットのアドベントカレンダーは始まったばかりです！
明日以降もお楽しみにお待ちください！
