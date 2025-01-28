---
title: "IAMポリシーのViewOnlyとReadOnlyアクセスの権限を比較してみた"
emoji: "😊"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["IAM"]
published: true # trueを指定する
published_at: 2025-01-29 09:00 # 未来の日時を指定する
---

## はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimoJです。
普段はAWS上に構築したデータ分析基盤に関するお仕事をしております。

AWS環境が運用フェーズに入ったタイミングの権限管理について検討しておりました。
調査してみるとAWSが提供する管理ポリシーとして[ReadOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ReadOnlyAccess.html)、[ViewOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ViewOnlyAccess.html)がありました。
どちらのポリシーでもS3バケット内のファイル名まで確認できます。
一方、ReadOnlyAccessのみs3:get権限が付与されておりファイル取得まで可能でした。

運用上、すべてのS3バケットからファイル取得ができるのは良くないので、ViewOnlyAccessを付与して必要なバケットのみに限定してファイルが取得できる方針にて進めることにしました。

方針は決定しましたが2つのポリシー差分が気になり調査したところ以下記事にて、比較を行う手順がまとめられてましたので確認してきます。

- [IAM Policy ViewOnlyAccessとReadOnlyAccessの違い](https://dev.classmethod.jp/articles/iam-policy-readonly-vs-viewonly/)


## 1. 前提
確認時はMac端末にて実行しております。
また、CLIのセットアップは完了していることを前提とします。


## 2. バージョン確認
まず、ReadOnlyAccessとViewOnlyAccessの現在のバージョンを確認します。

```sh
# ViewOnlyAccessの最新バージョン
$ aws --profile {プロファイル名} iam get-policy --policy-arn arn:aws:iam::aws:policy/job-function/ViewOnlyAccess --query Policy.DefaultVersionId --output text
v23

# ReadOnlyAccessの最新バージョン
$ aws --profile {プロファイル名} iam get-policy --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --query Policy.DefaultVersionId --output text
v124
```

結果を比較すると、ReadOnlyAccessの方が更新されていることがわかります。


## 3. ファイル取得
では、バージョンを指定してファイルをローカルに取得します。

```sh
# ViewOnlyAccessの最新バージョンを取得
$ aws --profile {プロファイル名} iam get-policy-version --policy-arn arn:aws:iam::aws:policy/job-function/ViewOnlyAccess --version-id v23 --query PolicyVersion.Document.Statement > target_files/view_text_output.txt

# ReadOnlyAccessの最新バージョンを取得
$ aws --profile {プロファイル名} iam get-policy-version --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --version-id v124 --query PolicyVersion.Document.Statement > target_files/read_text_output.txt
```

## 4. リソースごとの権限比較
それでは取得した2つのファイルにおける「S3」のリソースを比較します。
｜の左側がViewOnlyAccess、右側がReadOnlyAccessとなります。

```sh
## S3
$ diff -y -W 80 <(cat target_files/view_text_output.txt | grep s3:) <(cat target_files/read_text_output.txt | grep s3:)  
            "s3:ListAllMyBuckets",    |             "s3:DescribeJob",
            "s3:ListBucket",	      |             "s3:Get*",
            "s3:ListMultiRegionAccess" |             "s3:List*",

```
結果より、ReadOnlyAccessにはGet*がついてるためS3バケットからファイルが取得できることが確認できました。

同様にいくつかのリソースで権限の比較を確認してみます。

```sh
## IAM
$ diff -y -W 80 <(cat target_files/view_text_output.txt | grep iam:) <(cat target_files/read_text_output.txt | grep iam:)
            "iam:GetAccountSummary",  |             "iam:Generate*",
            "iam:GetLoginProfile",    |             "iam:Get*",
            "iam:List*",		            "iam:List*",
				      >             "iam:Simulate*",

# redshift
$ diff -y -W 80 <(cat target_files/view_text_output.txt | grep redshift:) <(cat target_files/read_text_output.txt | grep redshift:)
            "redshift:DescribeCluster |             "redshift:Describe*",
            "redshift:DescribeEvents" |             "redshift:GetReservedNode
            "redshift:ViewQueriesInCo |             "redshift:ListRecommendat
				      >             "redshift:View*",

# ecs（権限が同じのため差分の出力はない）
$ diff -y -W 80 <(cat target_files/view_text_output.txt | grep ecs:) <(cat target_files/read_text_output.txt | grep ecs:)

# waf
$ diff -y -W 80 <(cat target_files/view_text_output.txt | grep waf:) <(cat target_files/read_text_output.txt | grep waf:)
				      >             "waf:Get*",
            "waf:List*",		            "waf:List*",
```

ecsは同じ権限が付与されているため出力はありませんでしたが、他のリソースでは差分の確認ができました。


## 5. ViewOnlyAccessポリシーを付与して特定S3バケットを操作する
最後に、ViewOnlyAccessを付与したあと、特定のS3バケットのみファイルが取得するコードを作成します。

{バケット名}/{Allowパス}配下フォルダ配下を取得するためのIAMポリシーは以下となります。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::cm-shimoji-sandbox/test/*"
                "arn:aws:s3:::{バケット名}/{Allowパス}/*"
            ],
            "Effect": "Allow"
        }
    ]
}
```

取得を許可したフォルダ配下とそれ以外のパスからファイルを取得した際の結果を記載します。
```sh
## Allowパス配下のファイル取得
$ aws --profile {プロファイル名} s3 cp s3://{バケット名}/{Allowパス}/ファイル.text ./
download: s3://{バケット名}/{Allowパス}/a.text to ./a.text      

## NotAllowパス配下のファイル取得
$ aws --profile {プロファイル名} s3 cp s3://{バケット名}/{NotAllowパス}/ファイル.text ./
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

## 6. まとめ
AWS管理ポリシーの[ReadOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ReadOnlyAccess.html)と[ViewOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ViewOnlyAccess.html)を比較しました。
今回はViewOnlyAccessを付与して必要な権限を追加する方針にしましたが、必要な権限毎に指定する内容が変わりそうなだと実感しました。

## 7. 参考リンク
- [AWS Identity and Access Management でのポリシーとアクセス許可](https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/access_policies.html)
- [ReadOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ReadOnlyAccess.html)
- [ViewOnlyAccess](https://docs.aws.amazon.com/ja_jp/aws-managed-policy/latest/reference/ViewOnlyAccess.html)
- [IAM Policy ViewOnlyAccessとReadOnlyAccessの違い](https://dev.classmethod.jp/articles/iam-policy-readonly-vs-viewonly/)
