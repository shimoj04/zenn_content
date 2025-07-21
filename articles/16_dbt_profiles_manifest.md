---
title: "【dbt】プロファイル切替とマニフェスト差分を実装して理解を深める"
emoji: "🌊"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [dbt, postgres, docker]
published: true
published_at: 2025-07-21 21:00
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

今回は、業務で使っている dbt（data build tool）のプロファイル切替や、マニフェストを使った差分管理について理解を深めるため検証した内容を整理しておこうと思います。

検証環境はdockerにて作成しますが、実行環境はMac端末から操作します。

## 2. dbtにおけるプロファイルとマニフェストの役割
dbtで複数の環境（検証/本番）を安全に運用するためには、環境ごとの接続設定や構成状態の把握が大切です。
ここでは、環境ごとに切り替えられる`profiles.yml`と、構成を記録する`manifest.json`の役割について簡単に整理します。

### 2.1. profiles.yml
接続情報（DBホスト、ユーザー、スキーマなど）を定義する設定ファイルです。
`--target`を指定することで、複数環境の切り替えが可能になります。

https://docs.getdbt.com/docs/core/connect-data-platform/profiles.yml

### 2.2. manifest.json
dbt実行後に生成される構成ファイルで、models/seeds/macrosなどの状態が記録されます。  
このファイルを保存しておくことで、`変更された部分のみの差分管理`が可能になります。

https://docs.getdbt.com/reference/artifacts/manifest-json


## 3. 検証環境の構築
それでは、動作確認用dbtとPostgreSQLのdockerコンテナを作成します。
この章と次章を通じて最終的に構築・利用するファイルとディレクトリ構成は以下の通りです。

```bash
.
├── dbt
│   └── my_project
│       ├── saved_state
│       │   ├── dev
│       │   │   └── manifest.json
│       │   └── prod
│       │       └── manifest.json
│       ├── seeds
│       │   ├── sample1
│       │   │   └── sample_seed1.csv
│       │   └── sample2
│       │       └── sample_seed2.csv
│       └── target
│           └──  manifest.json
├── .dbt
│   └── profiles.yml
├── docker-compose.yml
├── Dockerfile
└── .env
```

### 3.1. コンテナの作成
コンテナを構成するファイルは以下3つです。

:::details docker-compose.yml
```yml
version: "3.8"

services:
  postgres:
    image: postgres:15
    container_name: pg_dbt_sandbox
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  dbt:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: dbt_env_sandbox
    command: tail -f /dev/null
    volumes:
      - ${LOCAL_DBT_PATH}:/dbt
    working_dir: /dbt
    depends_on:
      - postgres
    tty: true
    stdin_open: true

volumes:
  pgdata:


```
:::


:::details Dockerfile
```Dockerfile
FROM python:3.11-slim

# システムパッケージとインストール
RUN apt-get update && \
    apt-get install -y jq git build-essential libpq-dev && \
    pip install --upgrade pip && \
    pip install --no-cache-dir dbt-postgres && \
    rm -rf /var/lib/apt/lists/*

```
:::

:::details .env
```bash
POSTGRES_USER={POSTGRES_USER}
POSTGRES_PASSWORD={POSTGRES_PASSWORD}
POSTGRES_DB={POSTGRES_DB_NAME}

LOCAL_DBT_PATH={LOCAL_DBT_PATH}
```
:::

上記ファイルのディレクトリにて以下コマンドを実行し、コンテナ環境を作成します。

```bash
## コンテナをバックグラウンドで起動
$ docker-compose up -d
..{省略}
[+] Running 3/3
 ✔ Network postgres_linux_default  Created  
 ✔ Container pg_dbt_sandbox        Started  
 ✔ Container dbt_env_sandbox       Started   

## コンテナが立ち上がったことを確認
$ docker ps
CONTAINER ID   IMAGE                COMMAND                   CREATED          STATUS          PORTS                    NAMES
8a330296f3a1   postgres_linux-dbt   "tail -f /dev/null"       56 minutes ago   Up 56 minutes                            dbt_env_sandbox
61ba65713888   postgres:15          "docker-entrypoint.s…"   3 hours ago      Up 3 hours      0.0.0.0:5432->5432/tcp   pg_dbt_sandbox

```


### 3.2 dbtプロジェクトの作成と接続確認
それでは先ほど構築した、pg_dbt_sandboxコンテナにて、dbtプロジェクトの作成と初期設定を行います。

まずはコンテナ環境にログインし、dbtのバージョンを確認します。

```bash
## dbt環境コンテナへ入る
$ docker exec -it dbt_env_sandbox bash

## dbtのバージョン確認
$ dbt --version
Core:
  - installed: 1.10.4
  - latest:    1.10.4 - Up to date!

Plugins:
  - postgres: 1.9.0 - Up to date!

```

続いて、初期設定を行います。

:::details 初期設定のログ
```bash
## プロジェクト生成
$ pwd
/dbt
$ dbt init my_project
..{省略}
Your new dbt project "my_project" was created!

For more information on how to configure the profiles.yml file,
please consult the dbt documentation here:

  https://docs.getdbt.com/docs/configure-your-profile

One more thing:

Need help? Don't hesitate to reach out to us via GitHub issues or on Slack:

  https://community.getdbt.com/

Happy modeling!

02:58:19  Setting up your profile.
Which database would you like to use?
[1] postgres

(Don't see the one you want? https://docs.getdbt.com/docs/available-adapters)

Enter a number: 1
host (hostname for the instance): {postgresのサービス名}
port [5432]: 
user (dev username): {POSTGRES_USER}
pass (dev password): {POSTGRES_PASSWORD}
dbname (default database that dbt will build objects in): {POSTGRES_DB}
schema (default schema that dbt will build objects in): public
threads (1 or more) [1]: 1
```
:::


それでは、ポスグレを立てたコンテナとの疎通確認を行うためdbt debugを実行します。

```bash
$ cd my_project
$ dbt debug
..{省略}
03:03:09  Registered adapter: postgres=1.9.0
03:03:09    Connection test: [OK connection ok]
```

疎通確認ができましたので、 `profiles.yml` を使った環境切替や、`manifest.json`による差分管理の検証に入っていきます。

## 4. 実装と検証
ここからは、構築したdbt環境を使用して、以下の2つを実施します。

| ステップ | 内容                                |
| ---- | ------------------------------------- |
| 4.1  | `profiles.yml`を利用したdev/prodスキーマ切替 |
| 4.2  | `manifest.json`を利用した差分ファイルの検知と反映 |

動作確認のため、seeds/直下にサンプルファイルを2つ配置します。

:::details samplesファイル
- dbt/seeds/sample1/sample_seed1.csv
```csv
id,name,age
1,Alice,30
2,Bob,25
3,Charlie,40
```
- dbt/seeds/sample2/sample_seed2.csv
```csv
sample_seed2.csvid,name,age
4,David,22
5,Eve,28
6,Frank,35
7,Grace,29
```
:::

### 4.1 環境ごとに構成を切り替える（プロファイル活用）
今回の挙動確認において検証（dev）は`public`、本番（prod）は`dbt`スキーマを使用するように設定します

#### 4.1.1 profiles.ymlの設定と配置
まずはじめに、環境を分離するため`/.dbt/`直下に`profiles.yml`ファイルを作成します。

```yml
my_project:
  target: dev  # 指定がない場合はdevを利用
  outputs:
    dev:
      host: postgres
      type: postgres
      port: 5432
      dbname: {POSTGRES_DB_NAME}
      user: {POSTGRES_USER}
      pass: {POSTGRES_PASSWORD}
      schema: public
      threads: 1
      
    prod:
      host: postgres
      type: postgres
      port: 5432
      dbname: {POSTGRES_DB_NAME}
      user: {POSTGRES_USER}
      pass: {POSTGRES_PASSWORD}
      schema: dbt 
      threads: 1
```

#### 4.1.2 dbt seed 実行結果
それでは環境毎に登録した`sample_seed1`を取込みます。
`profiles.yml`を読み込むために`--profiles-dir`を、環境を切替るために`--target`を使用します
それでは、dev/prodそれぞの実行結果を確認します。

```bash
## 検証（dev）
$ dbt seed --profiles-dir /dbt/.dbt --target dev
..{省略}
03:39:21  Concurrency: 1 threads (target='dev')
..{省略}
03:39:21  
03:39:21  1 of 2 START seed file public.sample_seed1 .................. [RUN]
03:39:21  1 of 2 OK loaded seed file public.sample_seed1 .............. [INSERT 3 in 0.03s]
..{省略}

## 本番（prod）
$ dbt seed --profiles-dir /dbt/.dbt --target prod
...{省略}
04:04:52  Concurrency: 1 threads (target='prod')
04:04:52  
04:04:52  1 of 2 START seed file dbt.sample_seed1 .................. [RUN]
04:04:52  1 of 2 OK loaded seed file dbt.sample_seed1 .............. [INSERT 3 in 0.03s]
...{省略}
```

検証/本番ともに、指定したスキーマに作成されたことが確認できます。

#### 4.1.3 PostgreSQLへの接続とスキーマ確認
最後に、PostgreSQLのコンテナに入ってテーブルを確認します。

```bash
## PostgreSQLのコンテナに入る
$ docker exec -it pg_dbt_sandbox psql -U {POSTGRES_USER} -d {POSTGRES_DB_NAME} 

## 検証（publicスキーマ）
{POSTGRES_DB_NAME}=# select * from public.sample_seed1;
 id |  name   | age 
----+---------+-----
  1 | Alice   |  30
  2 | Bob     |  25
  3 | Charlie |  40
(3 rows)

## 本番（dbtスキーマ）
{POSTGRES_DB_NAME}=# select * from dbt.sample_seed1;
 id |  name   | age 
----+---------+-----
  1 | Alice   |  30
  2 | Bob     |  25
  3 | Charlie |  40
(3 rows)
```

テーブル構築も確認できましたので、次はmanifestファイルを活用した差分ファイルの更新に移ります。

### 4.2. マニフェストファイルで差分を検知する
ここでは、sample_seed1構築後のmanifestファイルを元にして、検証/本番共にsample_seed2が登録されることを確認します。

#### 4.2.1 manifest.json のコピーと保存
まず、現状のファイルをsaved_state/{dev/prod}/直下にコピーします。

```bash
## 配置先フォルダの作成
$ mkdir saved_state
$ mkdir saved_state/{dev/prod}
## manifestファイルのコピー
$ cp target/manifest.json saved_state/{dev/prod}/manifest.json
```

#### 4.2.2 差分実行の確認
`--state saved_state/{環境}`を指定することで環境毎の更新前manifestを参照し、変更ファイルのみを対象とするため`--select state:modified`を指定して実行します。

```bash
## 変更分のみ取込
$ dbt seed --select state:modified --state saved_state/dev --profiles-dir /dbt/.dbt --target dev
..{省略}
07:26:14  1 of 1 START seed file public.sample_seed2 .................. [RUN]
07:26:14  1 of 1 OK loaded seed file public.sample_seed2 .................. [INSERT 4 in 0.03s]
..{省略}

## manifestの差分調査（sample_seed2が対象となっている行を抜粋）
$ diff -u <(jq . saved_state/dev/manifest.json) <(jq . target/manifest.json)

..{省略}
+    "seed.my_project.sample_seed2": []
..{省略}
```

sample_seed2のみが更新対象となりました！


#### 4.2.3 差分がないことの検証
検証環境のmanifestを最新に更新し、再実行時は更新がないことを確認します。

```bash
## 検証環境のmanifestを最新に更新
$ cp target/manifest.json saved_state/dev/manifest.json

## 再実行
$ dbt seed --select state:modified --state saved_state/dev --profiles-dir /dbt/.dbt --target dev
..{省略}
07:41:12  Nothing to do. Try checking your model configs and model specification args
07:41:12  Completed successfully
07:41:12  Done. PASS=0 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=0 
```

2回目は作成済みのため、更新されないことが確認できました。

#### 4.2.4 本番環境への差分適用確認
最後に本番環境の動作確認です。

```bash
## 本番環境の実行
$ dbt seed --select state:modified --state saved_state/prod --profiles-dir /dbt/.dbt --target prod
..{省略}
07:43:25  1 of 1 START seed file dbt.sample_seed2 .................. [RUN]
07:43:25  1 of 1 OK loaded seed file dbt.sample_seed2 .................. [INSERT 4 in 0.03s]
..{省略}

### 本番環境のmanifestを最新に更新
$ cp target/manifest.json saved_state/prod/manifest.json
```

検証環境は実施しても、本番環境は未反映ですので差分が適用されることが確認できます。

## 5. まとめ
今回は、ローカル環境で`profiles.yml`を使用した環境の切替と、`manifest.json`を活用した差分管理の動作確認を行いました。
実際に試すことでより理解が深まりましたが、本運用時にはmanifestファイルのリモート管理や、DB設定などより詳細な分離も必要かなと感じました。
ただ、シンプルな構成で挙動を確認しておくことで、設計判断もしやすくなると思います。


## 参考リンク
- [About profiles.yml](https://docs.getdbt.com/docs/core/connect-data-platform/profiles.yml)
- [Manifest JSON file](https://docs.getdbt.com/reference/artifacts/manifest-json)
