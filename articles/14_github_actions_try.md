---
title: "Github Actionsを利用してデプロイを自動化してみる"
emoji: "🦔"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [githubactions, Opentofu, さくらのクラウド]
published: true
published_at: 2025-07-06 20:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。

開発においてgitは必要不可欠です。[Github Actions](https://github.co.jp/features/actions)を利用するとイベント（pushやpull request）毎に処理を実行してくれるCI/CDの環境が構築できるのでとても便利です。

今回は以下の2ステップでGithub Actionsの動作確認を行います。

1. GithubActionsのQuickstartを実行
2. Opentofuのplan/applyを実行

## 2. 前提
GithubActinsの実行にあたり、利用可能なリポジトリとOpentofuの環境で構築するリソース対象が存在していることを前提とします。
本記事で動作確認するリポジトリは[shimoj04](https://github.com/shimoj04/my_work_log)です。

また、Opentofuではさくらのクラウドのリソースをデプロイします。
Opentofuの状態管理ファイルは、さくらのクラウドのオブジェクトストレージに保存しますので、設定に関してこちらの記事も合わせて確認いただけたら幸いです。

https://zenn.dev/shimoj_tech/articles/13_sakura_cloud_objectstorage

## 3. GithubActionsのQuickstartを実行
まずはじめに、[Quickstart for GitHub Actions](https://docs.github.com/ja/actions/get-started/quickstart)の実行と出力を確認します。
手順通りに動かすことで、サンプルのworkflowを動かせますので実行後の登録プレースホルダと結果の展開値を表にします。

| プレースホルダ                     | 説明                                   | 展開値                                  |
|------------------------------------|----------------------------------------|-----------------------------------------|
| `${{ github.actor }}`              | ジョブを起動したユーザー名             | `shimoj04`                             |
| `${{ github.event_name }}`         | ワークフローを起動したイベント名       | `push`                                  |
| `${{ runner.os }}`                 | ジョブが動作しているランナーのOS       | `Linux`                                 |
| `${{ github.ref }}`                | チェックアウトされているブランチ参照     | `refs/heads/shimoj04-patch-1`           |
| `${{ github.repository }}`         | リポジトリの`owner/name`              | `shimoj04/my_work_log`                     |
| `${{ github.workspace }}`          | リポジトリがクローンされる作業ディレクトリのパス | `/home/runner/work/my_work_log/my_work_log`     |
| `${{ job.status }}`                | ジョブの最終ステータス                 | `success`                               |

`Lisft files in the repository`項目を確認すると、ディレクトリ直下を参照するようになっているので、ファイルとフォルダを追加してpushします。
```bash
## リポジトリ構成
.
├── README.md
├── sample
│   └── test1.txt
└── test.files
```

push後の結果は、想定通りの構成結果が取得できました。（これは便利）

```bash
Run ls /home/runner/work/my_work_log/my_work_log
  ls /home/runner/work/my_work_log/my_work_log
  shell: /usr/bin/bash -e {0}
README.md
sample
test.files
```

## 4. Opentofuのplan/applyを実行
続いて、workflowとOpentofuを利用したさくらのクラウドのリソースをデプロイしてみます。
実施にあたり以下の内容を試します。

- 4.1. シークレットの登録
- 4.2. workflowとtofuのコード
- 4.3. リソース（ディスク）の作成
- 4.4. リソース（スイッチ）の追加

### 4.1. シークレットの登録
まずはじめに、リソースをデプロイする際に必要なキー値をgitのsercrets（[Using secrets in GitHub Actions](https://docs.github.com/ja/actions/how-tos/security-for-github-actions/security-guides/using-secrets-in-github-actions)）に登録します。対象の項目を表にします。

| No. | シークレット名                           | 説明                                   |
| :-: | :-------------------------------- | :----------------------------------- |
|  1  | `AWS_ACCESS_KEY_ID`               | さくらのクラウド オブジェクトストレージ用のアクセスキー         |
|  2  | `AWS_SECRET_ACCESS_KEY`           | さくらのクラウド オブジェクトストレージ用のシークレットキー       |
|  3  | `OBJECT_STORAGE_NAME`             | オブジェクトストレージのバケット名（ストレージ名）            |
|  4  | `OBJECT_STORAGE_REGION`           | オブジェクトストレージのリージョン |
|  5  | `SAKURACLOUD_ACCESS_TOKEN`        | さくらのクラウド API 利用時のアクセストークン            |
|  6  | `SAKURACLOUD_ACCESS_TOKEN_SECRET` | さくらのクラウド API 利用時のトークンシークレット          |
|  7  | `SAKURACLOUD_API_ENDPOINT`        | さくらのクラウド API のエンドポイント URL            |


### 4.2. workflowとtofuのコード
続いてworkflowとtofuで管理するファイルと役割、トリガーを表にします。


| ファイルとパス                                                     | 役割                                                     | トリガー                     |
| :---------------------------------------------------------- | :-------------------------------------------------------- | :----------------------- |
| [main.tf](https://github.com/shimoj04/my_work_log/blob/main/infra/github_action_tofu/main.tf)                 | Opentofuでリソースを定義するmainファイル                | –                        |
| [opentofu\_plan.yml](https://github.com/shimoj04/my_work_log/blob/main/.github/workflows/opentofu_plan.yml)   | PR作成時に `tofu init`＋`tofu plan` を実行し、差分をチェックするワークフロー      | mainブランチへのPullRequest作成時 |
| [opentofu\_apply.yml](https://github.com/shimoj04/my_work_log/blob/main/.github/workflows/opentofu_apply.yml) | mainブランチpush時に `tofu init`＋`tofu apply` を実行し、リソースを反映するワークフロー | mainブランチへのpush         |



### 4.3. リソース（ディスク）の作成
準備が整いましたのでリソースを作成します。

#### 4.3.1. plan（プルリク作成）
まずは、さくらのクラウドの`ディスク`がデプロイされるコードのブランチを作成しmainブランチにPR（[ディスクを作成するコードのPR #7](https://github.com/shimoj04/my_work_log/pull/7)）を作成します。

PR作成後にPlan用のworkflowが実行されます！
- [shimoj04 is testing OpenTofu Plan CI/CD🚀 #16](https://github.com/shimoj04/my_work_log/actions/runs/16095802903/job/45418486497)

diskが作成されることを確認したログを一部抜粋します。

```bash
  # sakuracloud_disk.disk_from_tofu will be created
  + resource "sakuracloud_disk" "disk_from_tofu" {
      + connector            = "virtio"
      + encryption_algorithm = "none"
      + id                   = (known after apply)
      + name                 = "disk_from_tofu"
      + plan                 = "ssd"
      + server_id            = (known after apply)
      + size                 = 20
      + source_archive_id    = "113701786661"
      + zone                 = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + disk_name = "disk_from_tofu"
```

#### 4.3.2. apply（マージ）
applyはPRのマージ実行にて発火しますので実行します。実行されたworkflowを記載します。

- [shimoj04 is testing OpenTofu Apply CI/CD🚀 #11](https://github.com/shimoj04/my_work_log/actions/runs/16095819306/job/45418521152)

```bash
...（省略）
Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + disk_name = "disk_from_tofu"
sakuracloud_disk.disk_from_tofu: Creating...
sakuracloud_disk.disk_from_tofu: Still creating... [10s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [20s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [30s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [40s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [50s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [1m0s elapsed]
sakuracloud_disk.disk_from_tofu: Still creating... [1m10s elapsed]
sakuracloud_disk.disk_from_tofu: Creation complete after 1m11s [id=113701817814]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

disk_name = "disk_from_tofu"
```

ログより、diskが作成されたことが確認ができました！
また、tfstate（状態管理）ファイルもアップロードされていることが確認できます。

```bash
$ aws --endpoint-url="https://s3.isk01.sakurastorage.jp" --region jp-north-1 --profile sakura_s3 s3 ls s3://{オブジェクト名}/github/test_tofu/
2025-07-06 14:44:15       2460 terraform.tfstate
```

### 4.4. リソース（スイッチ）の追加
#### 4.4.1. plan（プルリク作成）
続いて、`スイッチ`を追加します。
main.tfにスイッチ追加のコードを記載した内容でPR（[スイッチ追加 #8](https://github.com/shimoj04/my_work_log/pull/8)）を作成します。
先ほどと同様にPlanのworkflowが実行されます。

- [shimoj04 is testing OpenTofu Plan CI/CD🚀 #17](https://github.com/shimoj04/my_work_log/actions/runs/16095876142/job/45418633811})


#### 4.4.2. apply（マージ）
追加リソースのみが作成対象になっていることを確認しmergeを実施します。実施後に以下のworkflowが動きます。

- [shimoj04 is testing OpenTofu Apply CI/CD🚀 #12](https://github.com/shimoj04/my_work_log/actions/runs/16095899756)

おや、結果を確認するとエラーとなりました。スイッチの作成上限に達したのが原因のようです。。(後述する再実行によりログは上書きされます)

```bash
Error: creating SakuraCloud Switch is failed: Error in response: &iaas.APIErrorResponse{IsFatal:true, Serial:"b4f7ead9e0c067e71c4fe5ad61268265", Status:"409 Conflict", ErrorCode:"limit_count_in_zone", ErrorMessage:"要求を受け付けできません。ゾーン内リソース数上限により、リソースの割り当てに失敗しました。"}
│ 
│   with sakuracloud_switch.my_switch,
│   on main.tf line 41, in resource "sakuracloud_switch" "my_switch":
│   41: resource "sakuracloud_switch" "my_switch" {
```

利用してないスイッチでしたので、削除実施後に手動にてworkflowを再実行します。

![](/images/14_github_actions_try/2_manual_retray.png)

今度は正常に作成されたことを確認しました！

```bash
OpenTofu will perform the following actions:

  # sakuracloud_switch.my_switch will be created
  + resource "sakuracloud_switch" "my_switch" {
      + description = "Created via OpenTofu"
      + id          = (known after apply)
      + name        = "my-open-tofu-switch"
      + server_ids  = (known after apply)
      + tags        = [
          + "202507",
          + "tofu",
        ]
      + zone        = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
sakuracloud_switch.my_switch: Creating...
sakuracloud_switch.my_switch: Creation complete after 2s [id=113701818056]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

disk_name = "disk_from_tofu"
switch_name = "my-open-tofu-switch"
```


## 5. まとめ
GithubActionsを利用してリソースをデプロイしました。
plan/applyを切り分けたのみですが検証・本番環境への適用など他にも対応の幅が広そうです。
登録に少し手間取りましたが、これからどんどん利用していきたいと思います。

## 6. 参考リンク

- [Quickstart for GitHub Actions](https://docs.github.com/ja/actions/get-started/quickstart)
- [Claude Code GitHub Actionsを使いこなせ！](https://zenn.dev/acntechjp/articles/3f361da473eac8)
- [GitHub Actions を使うなら、気にしたほうがいいこと から1年経って得た知見](https://zenn.dev/smartcamp/articles/6d42e323071e64)
- [GitHub Actionsって何？触ってみて理解しよう！入門・逆引きリファレンス](https://qiita.com/s3i7h/items/b50ceb0008edc3c0312e)
- [GitHub ActionsでHello, World!を出力してみた](https://dev.classmethod.jp/articles/shoma-github-actions-introduction-hello-world-output/)
- [GitHub Actionsを利用したTerraformの自動実行](https://qiita.com/RyutoYoda/items/79400fb2213d90e761ae)
- [TerraformとGithub Actionsで快適デプロイ](https://zenn.dev/x_point_1/articles/bd434c4e0586cc)
- [Using secrets in GitHub Actions](https://docs.github.com/ja/actions/how-tos/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [【Github Actions】AWS環境へのTerraformのCI/CD](https://zenn.dev/yn26/articles/3429b834bb0e42)
- [【GitHub Actions】 OIDC で AWS 認証を行う](https://zenn.dev/yn26/articles/df05547c44b379)
