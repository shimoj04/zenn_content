---
title: "【さくらのクラウド】オブジェクトストレージのS3互換APIを使ってみる"
emoji: "📚"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [さくらのクラウド, オブジェクトストレージ, Opentofu]
published: true
published_at: 2025-06-28 20:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
さくらのクラウドにはオブジェクトストレージのサービスがあり、Amazon S3互換APIが利用できると公式サイトに記載されております。
https://manual.sakura.ad.jp/cloud/objectstorage/api.html

筆者はAWSのAmazon S3を利用することが多かったこともあり興味がありましたので、さくらのオブジェクトストレージを利用して以下2つを実施します。

1. オブジェクトストレージの作成とS3互換API操作
2. OpenTofuのtfstate保存先として使ってみる

## 2. 前提
実行環境を記載します。
※ aws cliのセットアップやさくらのクラウドのアカウント作成手順、OpenTofuの構築は本記事では割愛します。

- OS: macOS
- aws cli: 2.27.44
- OpenTofu: v1.9.1

## 3. オブジェクトストレージの作成とS3互換API操作
オブジェクトストレージの作成からCLI実行までを実行します。
この章で実施する内容は以下となります。

1. バケットの作成
2. アクセスキーの登録
3. CLIによる動作確認
4. バージョン依存によるCLIの失敗

### 3.1. バケットの作成
公式サイトの手順に沿って、「サイト」の作成と「バケット」の作成を実施します。
https://manual.sakura.ad.jp/cloud/objectstorage/about.html

サイト作成時に発行されるAPIは後ほど登録するため、控えておきます。
直近、「アクセストークンシークレット」表示仕様の変更があり、これまでのように再確認ができなくなってますので控え忘れにご注意を。。

https://cloud.sakura.ad.jp/news/2025/06/19/access-token-secret/


### 3.2. アクセスキーの登録
取得したアクセスキー/シークレットアクセスキーを`~/.aws/credentials`にsakura_s3として登録します。

```sh
## sakura_s3を追加後の表示
$ cat ~/.aws/credentials
[default]
..（省略）

[sakura_s3]
aws_access_key_id = {アクセスキー}
aws_secret_access_key = {シークレットアクセスキー}

```

### 3.3. コマンドを実行
続いて、さくらのオブジェクトストレージにcliコマンドを実行する際のパラメータを表にします。

| パラメータ               | 説明                                                | 設定値                                        |
|-------------------------|-----------------------------------------------------|---------------------------------------------|
| `--endpoint-url`        | さくらのクラウドオブジェクトストレージのS3互換APIエンドポイントURLを指定      | `https://s3.isk01.sakurastorage.jp`         |
| `--region`              | SigV4署名に使用するリージョンを指定             | `jp-north-1`         |
| `--profile`             | 認証情報／設定を読み込む AWS CLI プロファイル名を指定 | `sakura_s3`          |
| `s3`                    | 操作対象のサービスを指定（S3互換オブジェクトストレージ） | `s3`       |


上記を元に、バケットの一覧を取得します。
```sh
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --region jp-north-1 --profile sakura_s3 s3 ls
2025-06-27 21:35:52 {作成したバケット名}
```

aws cliの要領でバケット名が取得できました！

### 3.4. バージョン依存によるCLIの失敗
次に、ファイルのアップロードを試してみます。

```sh
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --profile sakura_s3 --region jp-north-1 s3 cp test.file s3://{作成したバケット名}/
upload failed: ./test.file to s3://{作成したバケット名}/test.file An error occurred (422) when calling the PutObject operation: Unprocessable Content
```

おや、失敗しました。どうやら、バージョン起因による不具合なようです。

[【2025年4月17日追記】オブジェクトストレージ AWS CLI および AWS SDK ご利用できないバージョンのご案内](https://cloud.sakura.ad.jp/news/2025/02/04/objectstorage_defectversion/?_gl=1%2A6gwoir%2A_gcl_aw%2AR0NMLjE3NTA5ODAwMjcuRUFJYUlRb2JDaE1Jc295UjNaeVFqZ01WY0ZvUEFoMzNEeVhlRUFBWUFTQUFFZ0xWNHZEX0J3RQ..%2A_gcl_au%2ANjkyOTU0NTc5LjE3NDY1Nzk5OTI.)


記事によると、`AWS CLI v2 2.23.0`以降は影響を受けるため、バージョンを下げて再トライします。

```sh
$ curl "https://awscli.amazonaws.com/AWSCLIV2-2.0.30.pkg" -o "AWSCLIV2.pkg"
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 20.7M  100 20.7M    0     0  4952k      0  0:00:04  0:00:04 --:--:-- 4952k
AWSCLIV2.pkg
$ sudo installer -pkg AWSCLIV2.pkg -target /
Password:
installer: Package name is AWS Command Line Interface
installer: Installing at base path /
installer: The install was successful.

$ aws --version
aws-cli/2.0.30 Python/3.7.4 Darwin/24.5.0 botocore/2.0.0dev34
```

再実行します。

```sh
## ローカルからバケットにファイルをアップロード
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --profile sakura_s3 --region jp-north-1 s3 cp test.file s3://{作成したバケット名}/
upload: ./test.file to s3://{作成したバケット名}/test.file  

## バケットからローカルにファイルをダウンロード
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --profile sakura_s3 --region jp-north-1 s3 cp s3://{作成したバケット名}/test.file test_download.file
download: s3://{作成したバケット名}/test.file to ./test_download.file

## ローカルの取得確認
$ ls 
test_download.file	test.file
```

ファイルのアップロードもダウンロードも無事に出来ました！

## 4. OpenTofuのtfstate保存先として使ってみる
OpenTofuはTerraform互換のIaCツールで、`tfstate`（状態ファイル）を外部ストレージに保存することができます。
リソース作成時の`tfstate`ファイルを保存先としてさくらのクラウドのオブジェクトストレージを指定して試します。
この章で実施する内容は以下となります。

1. backend設定と構築コード
2. リソースの作成
3. `tfstate`ファイルの確認

### 4.1. backend設定と構築コード
まず、S3互換環境に対応するためのbackendパラメータを表にします。

| オプション                      | 説明                                                                                       | 設定値  |
|-------------------------------|-------------------------------------------------------------------------------------------|--------|
| `skip_credentials_validation` | 非AWS環境（STS 未対応）で STS API 呼び出しによる認証情報検証をスキップします。                     | `true` |
| `skip_region_validation`      | 提供されたリージョン名の妥当性検証をスキップします。カスタムリージョン使用時に有効です。             | `true` |
| `force_path_style`            | パススタイル URL（`https://<HOST>/<BUCKET>/...`）を強制し、バケット名ホスト方式を回避します。        | `true` |
| `skip_requesting_account_id`  | AWS アカウント ID 取得（IAM／STS／メタデータ）呼び出しをスキップし、非AWS 環境との互換性を確保します。 | `true` |
| `skip_s3_checksum`            | オブジェクトアップロード時に MD5 チェックサムヘッダーを送信せず、互換性のない S3 API との問題を回避します。| `true` |

今回は`tfstate`ファイルのアップロード確認が目的のため、単体のdiskのみ作成します。
backendパラメータ表をもとにコードを作成します。

:::details main.tf
```hcl
############################################################
# 0. backend（state 保存先）
############################################################
terraform {
  backend "s3" {
    bucket                      = "{バケット名}"
    key                         = "disk/disk_from_tofu.tfstate"
    endpoint                    = "https://s3.isk01.sakurastorage.jp"
    region                      = "jp-north-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    force_path_style            = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
  required_providers {
    sakuracloud = {
      source  = "sacloud/sakuracloud"
      version = "2.27.0"
    }
  }
}

provider "sakuracloud" {
  zone = "is1a"
}

############################################################
# 2. diskのリソース作成
############################################################
data "sakuracloud_archive" "rockylinux" {
  os_type = "rockylinux"
}

resource "sakuracloud_disk" "disk_from_tofu_test" {
  name              = "disk_from_tofu"
  plan              = "ssd"
  connector         = "virtio"
  size              = 20
  source_archive_id = data.sakuracloud_archive.rockylinux.id
}

############################################################
# 3. 出力
############################################################

output "disk_id" {
  value = sakuracloud_disk.disk_from_tofu_test.id
  description = "作成したディスクの ID（UUID）"
}

```
:::

### 4.2. リソースの作成
作成したコードを元にリソースを作成します。


```bash
## さくらのクラウドのアクセスキーをexportする
export SAKURACLOUD_ACCESS_TOKEN=**********
export SAKURACLOUD_ACCESS_TOKEN_SECRET=**********

## さくらのクラウドのオブジェクトストレージ用アクセスキーをexportする
export AWS_ACCESS_KEY_ID=**********
export AWS_SECRET_ACCESS_KEY=**********

## init処理を実施
$ tofu init -migrate-state
..(省略)

## plan（DryRun）を実施
$ tofu plan
..(省略)

## applyを実行してリソース作成
$ tofu apply
..(省略)
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

disk_id = "作成したdiskのidを出力"
```

Outpusとして`disk_id`を指定しているため、applyでリソースが作成され出力されていることを確認しました。

### 4.3. tfstateファイルの確認
リソースが作成されたので、tfstateファイルを確認します。

```bash
# オブジェクトストレージのファイルを確認
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --region jp-north-1 --profile sakura_s3 s3 ls s3://{バケット名}/disk/
2025-06-28 11:59:54       2460 disk_from_tofu.tfstate
```

オブジェクトストレージに`tfstate`が出力されています！


## 5. まとめ
S3互換APIを利用した動作確認を実施しました。
`endpoint-url`はこれまで意識したことがなかったのですが、S3コマンドを利用できるのはとても便利ですね。

## 6. 参考リンク

- [AWS API リクエストの Signature Version 4 署名をトラブルシューティングする](https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/reference_sigv-troubleshooting.html)
- [オブジェクトストレージ サービス基本情報(AWS CLIでの利用例)](https://manual.sakura.ad.jp/cloud/objectstorage/about.html#objectstrage-about-aws-cli)
- [過去にリリースされた AWS CLI バージョン 2 をインストールする](https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/getting-started-version.html)
- [【2025年4月17日追記】オブジェクトストレージ AWS CLI および AWS SDK ご利用できないバージョンのご案内](https://cloud.sakura.ad.jp/news/2025/02/04/objectstorage_defectversion/?_gl=1%2A6gwoir%2A_gcl_aw%2AR0NMLjE3NTA5ODAwMjcuRUFJYUlRb2JDaE1Jc295UjNaeVFqZ01WY0ZvUEFoMzNEeVhlRUFBWUFTQUFFZ0xWNHZEX0J3RQ..%2A_gcl_au%2ANjkyOTU0NTc5LjE3NDY1Nzk5OTI.)
- [Terraformを使用してインフラストラクチャの自動化](https://zenn.dev/nislab/articles/localstack-practice-02)
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)