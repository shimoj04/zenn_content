---
title: "Airflowをクラウドに構築してDAGを動かすまで"
emoji: "🙆"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [Airflow, python, さくらのクラウド]
published: true
published_at: 2025-07-21 12:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

最近、業務でAirflowを触る機会があり「便利そうだな」と実感しました。
Airflowは、ワークフローをコードで記述し、スケジュール実行できるツールで、データエンジニア界隈では広く使われています。

今回はそのAirflowの挙動をより深く理解するため、クラウドサーバー（Rocky Linux）に導入し、DAGの作成と実行までを一通り試してみます。

## 2. AirflowとDAGについて
Airflowは、DAG（Directed Acyclic Graph）という形でワークフローをコード化し、定期実行・管理できるジョブ管理ツールです。
DAGでは、複数のタスクを依存関係付きで定義できるため、バッチ処理やETLなどの自動化にもよく使われています。
この後の章では、Airflowを構築した環境でDAGファイルを作成し、ジョブを登録・実行してみます。


## 3. Airflow実行環境の準備
それでは、Airflowを動かすための環境を構築していきます。
今回はRocky Linux上にPythonの仮想環境を用意し、Airflow本体をインストールしたうえで、Web UIやSchedulerの起動確認までを行います。

| ステップ | 内容                     |
| ---- | ---------------------- |
| 3.1  | Python・仮想環境のセットアップ     |
| 3.2  | Airflowのインストール         |
| 3.3  | 初期化とユーザー作成             |
| 3.4  | Web UI・Schedulerの起動と確認 |

クラウドサーバー（Rocky Linux）は、こちらの記事で構築したものを利用します。
https://zenn.dev/shimoj_tech/articles/12_sakura_cloud_tofu

> ※ 動作確認のためデータベースにSQLiteを使用しますが本番環境では非推奨です

### 3.1. Python・仮想環境のセットアップ
まずはじめに、airflowを導入するためのPython環境と、仮想環境（venv）を作成します。

```bash
## パッケージの更新と必要な依存のインストール
$ sudo dnf update -y
$ sudo dnf install -y gcc gcc-c++ git curl wget libffi-devel python3-devel python3-pip

## Pythonバージョンの確認
$ python3 --version
Python 3.9.21

## 仮想環境の作成と有効化
$ python3 -m venv airflow_venv
$ source airflow_venv/bin/activate

```

### 3.2. Airflowの導入
それでは次に、Airflow本体をインストールします。今回はバージョン`2.9.1`を使用します。

```bash
## バージョン指定
(airflow_venv) $ export AIRFLOW_VERSION=2.9.1
(airflow_venv) $ export PYTHON_VERSION="$(python --version | awk '{print $2}' | cut -d. -f1-2)"
(airflow_venv) $ export CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
### 登録内容の確認
(airflow_venv) $ echo $CONSTRAINT_URL
https://raw.githubusercontent.com/apache/airflow/constraints-2.9.1/constraints-3.9.txt

## pipアップデートとAirflowのインストール
(airflow_venv) $ python -m pip install --upgrade pip
(airflow_venv) $ pip install "apache-airflow==${AIRFLOW_VERSION}" --constraint "${CONSTRAINT_URL}"

### インストール確認
(airflow_venv) $ airflow version
2.9.1
```

### 3.3 初期化とユーザー作成
続いて、Airflowを初期化し管理用ユーザーを作成します。
{メールアドレス}と{パスワード}は置き換えて登録してください。

```bash
## 環境変数の設定（任意のディレクトリに変更可能）
$ export AIRFLOW_HOME=~/airflow

## DBの初期化（SQLiteを利用）
$ airflow db init

## ユーザーの作成
$ airflow users create \
--username admin \
--firstname Admin \
--lastname User \
--role Admin \
--email {メールアドレス} \
--password {パスワード}
```

### 3.4 Web UI・Schedulerの起動と確認
それでは最後に、Airflowの`Web UI`と`Scheduler`を起動します。
なお、デフォルトで登録されているサンプルファイルを除外する設定も合わせて実施します。

```bash
## サンプルDAGを無効化（airflow.cfgを編集）
    ### load_examples = False　に変更
(airflow_venv) $ vi ~/airflow/airflow.cfg 

# airflowを起動
(airflow_venv) $ airflow scheduler &
(airflow_venv) $ airflow webserver -p 8080 &
```

上記コマンド後に、ブラウザからhttp://<サーバーのIP>:8080 にアクセスすると、添付図のようにAirflowのWeb UIが表示されます！

![](/images/15_airflow_infra_and_dags/1_login_page.png)

## 4. DAGの登録と実行
Airflowの実行環境が構築できました。
Airflowでは、各ジョブ（タスク）をDAG（Directed Acyclic Graph）という単位で定義します。
ここでは2つのDAGファイルを作成し、それぞれ単体実行したあと、最後にそれらをまとめて自動実行するDAGも作成します。

### 4.1 DAGファイルの作成
DAGファイルは`~/airflow/dags/`に配置することで、Airflowに自動的に認識されます。
今回は、単純な文字出力と実行時刻を出力する2つのDAGファイルを作成します。

:::details hello_dag.py
```python
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

with DAG(
    dag_id='hello_airflow',
    start_date=datetime(2023, 1, 1),
    schedule_interval='@daily',
    catchup=False
) as dag:
    hello_task = BashOperator(
        task_id='say_hello',
        bash_command='echo "Hello, Airflow!"'
    )
```
:::

:::details bash_write_time_file.py
```python
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime
import pendulum

dag = DAG(
    dag_id="bash_output_file_dag",
    start_date=pendulum.datetime(2025, 7, 31, tz="UTC"),
    schedule="@once",
    catchup=False
)

bash_command = """
mkdir -p /home/ssh_user/get_test_files

EXEC_TIME=$(date -u "+%Y%m%d%H%M%S")
JST_TIME=$(TZ=Asia/Tokyo date "+%Y-%m-%d %H:%M:%S")

echo "UTC: $EXEC_TIME" > /home/ssh_user/get_test_files/$EXEC_TIME.txt
echo "JST: $JST_TIME" >> /home/ssh_user/get_test_files/$EXEC_TIME.txt
"""

write_file_task = BashOperator(
    task_id="write_datetime_file",
    bash_command=bash_command,
    dag=dag
)
```
:::

ファイル作成後に以下コマンドにて登録されているDAGを確認することができます。

```bash
(airflow_venv) $ airflow dags list

dag_id               | fileloc                                             | owners  | is_paused
=====================+=====================================================+=========+==========
bash_output_file_dag | ~/airflow/dags/bash_write_time_file.py | airflow | True     
hello_airflow        | ~/airflow/dags/hello_dag.py            | airflow | True     

```

### 4.2 DAGの個別実行
それでは登録されたDAGファイルを個別に実行します。
DAGはWebUIからも実行可能ですが、挙動を確認するためCLIでテスト実行を確認します。

まずは、単純な文字出力の確認から行います。
```bash
### テスト実行
(airflow_venv) $ airflow tasks test hello_airflow say_hello
..(省略)
[{実行時刻}] {subprocess.py:75} INFO - Running command: ['/usr/bin/bash', '-c', 'echo "Hello, Airflow DAGs!"']
[{実行時刻}] {subprocess.py:86} INFO - Output:
[{実行時刻}] {subprocess.py:93} INFO - Hello, Airflow DAGs!
..(省略)
```
出力が確認できました！


続いて、実行時刻を出力の確認を行います。
```bash
## ファイル保存先のディレクトリ作成
(airflow_venv) $ mkdir get_test_files

### テスト実行
(airflow_venv) $ airflow dags trigger bash_output_file_dag
..(省略)
[{実行時刻}] {subprocess.py:75} INFO - Running command: ['/usr/bin/bash', '-c', '\nmkdir -p /home/ssh_user/get_test_files\n\nEXEC_TIME=$(date -u "+%Y%m%d%H%M%S")\nJST_TIME=$(TZ=Asia/Tokyo date "+%Y-%m-%d %H:%M:%S")\n\necho "UTC: $EXEC_TIME" > /home/ssh_user/get_test_files/$EXEC_TIME.txt\necho "JST: $JST_TIME" >> /home/ssh_user/get_test_files/$EXEC_TIME.txt']
[{実行時刻}] {subprocess.py:86} INFO - Output:
[{実行時刻}] {subprocess.py:97} INFO - Command exited with return code 0
..(省略)

### ファイルの出力確認
(airflow_venv) $ ls -la get_test_files/
..(省略)
-rw-r--r-- 1 ssh_user ssh_user   45 Jun 29 13:58 20250629045848.txt
```
実行タイミングでファイルが出力されていることが確認できました。


### 4.3. DAGをまとめてトリガーするDAGの作成
最後に2つのDAGををまとめて自動実行するDAGを作成し実行してみます。

作成するコードは以下です。

:::details trigger_wrapper.py
```python
from airflow import DAG
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from datetime import datetime
import pendulum

with DAG(
    dag_id="trigger_hello_and_time",
    start_date=pendulum.datetime(2025, 7, 31, tz="UTC"),
    schedule="@once",
    catchup=False
) as dag:

    trigger_hello = TriggerDagRunOperator(
        task_id="trigger_hello_airflow",
        trigger_dag_id="hello_airflow"
    )

    trigger_time = TriggerDagRunOperator(
        task_id="trigger_bash_output_file",
        trigger_dag_id="bash_output_file_dag"
    )

    trigger_hello >> trigger_time

```
:::

今度はWebUIからDAGを確認します。
まず依存関係を定義した`trigger_hello_and_time`が登録されていることが確認できました。

![](/images/15_airflow_infra_and_dags/2_1_web_ui_dag.png)

続いて、このDAGに入り右側にある「▶︎」をクリックすることで、ジョブが実行されます。

![](/images/15_airflow_infra_and_dags/2_2_web_ui_dag.png)

左側の緑の縦棒が実行回数で、その下に実行順番「trigger_hello_airflow -> trigger_bash_output_file」が記載されております。

## 5. まとめ
AirflowとDAG構成の理解を深めるため、環境構築からDAGの実行までを一通り試してみました。
PythonからBashを扱えたり、ジョブの依存関係をコードで明確に定義できたりと、Airflowがさまざまな場面で活用されている背景がわかった気がしました。

DAGファイル作成や依存関係登録など、未来の自分含めどなたかの参考になれば幸いです。


## 参考リンク

- [Airflow環境構築パターン&構築手順メモ　～その1～](https://qiita.com/yuuman/items/a449bbe36710ad837df7)
- [Installation from PyPI](https://airflow.apache.org/docs/apache-airflow/stable/installation/installing-from-pypi.html#installation-and-upgrade-of-airflow-core)
- [Dags](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html)
- [Apache Airflow で DAG ファイルを登録する](https://zenn.dev/ymasaoka/articles/register-dag-with-apache-airflow)
