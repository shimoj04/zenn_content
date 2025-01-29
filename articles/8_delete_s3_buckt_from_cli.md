---
title: "CLIコマンドを実行してS3バケットを削除する"
emoji: "✨"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["s3", "aws"]
published: true
published_at: 2025-01-30 09:00
---

## はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
不要になったS3バケットを削除する際は、バケット内のバージョニング 含めたオブジェクトをすべて削除する必要があります。

一連の流れをCLIコマンドで実装しましたので内容を整理します。

## 1. 処理フロー
S3バケットを削除するにあたり以下フローにて処理を行います。

1. バケット内のオブジェクトを全て削除
2. バージョニングが有効なオブジェクトを検索
3. バージョン管理されたオブジェクトが存在する場合のみ削除を実行
4. S3バケットを削除

処理内容をshファイルとして整理したコードは以下となります。

:::details S3バケットを削除するコード
```sh
#!/bin/bash

# バケット名とプロファイルを引数として受け取る
BUCKET_NAME=$1
PROFILE=$2

# エラーハンドリングの設定
set -e  # エラー時に実行を停止
trap 'echo "エラーが発生しました。処理を中断します。"; exit 1' ERR

# 引数チェック
if [ -z "$BUCKET_NAME" ] || [ -z "$PROFILE" ]; then
    echo "使用方法: $0 <バケット名> <プロファイル名>"
    exit 1
fi

# バケットの存在確認
if ! aws s3 ls "s3://${BUCKET_NAME}" --profile "${PROFILE}" >/dev/null 2>&1; then
    echo "バケット ${BUCKET_NAME} が存在しません。"
    exit 1
fi

echo "バケット ${BUCKET_NAME} の削除を開始します..."

# 1. バケット内のオブジェクトを全て削除
echo "バケット内のオブジェクトを削除中..."
aws s3 rm "s3://${BUCKET_NAME}" --recursive --profile "${PROFILE}"

# 2. バージョニングが有効なオブジェクトを検索
echo "バージョン管理されたオブジェクトを削除中..."
VERSIONS=$(aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --profile "${PROFILE}" \
    --output=json \
    --query='{Objects: [].{Key:Key,VersionId:VersionId}}')

# 3. バージョン管理されたオブジェクトが存在する場合のみ削除を実行
if [ "$(echo $VERSIONS | jq '.Objects | length')" -gt 0 ]; then
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --profile "${PROFILE}" \
        --delete "$VERSIONS"
fi

# 4. S3バケットを削除
echo "バケットを削除中..."
aws s3 rb "s3://${BUCKET_NAME}" --profile "${PROFILE}"

echo "バケット ${BUCKET_NAME} の削除が完了しました。"
```
:::

## 2. 実行
コードをファイルとして保存して、S3バケット名とprofile名を引数として渡して実行します。

```sh
$ bash {コードのファイル名}.sh {削除対象のS3バケット名} {プロファイル名}

バケット {削除対象のS3バケット名} の削除を開始します...
バケット内のオブジェクトを削除中...
delete: s3://{削除対象のS3バケット名}/{オブジェクト}/ {対象オブジェクト名}
...
(対象オブジェクト数分レコードが出力)
...
バージョン管理されたオブジェクトを削除中...
バケットを削除中...
remove_bucket: {削除対象のS3バケット名} 
バケット {削除対象のS3バケット名} の削除が完了しました。
```

## 3. まとめ
S3のコンソール画面にオブジェクトを全て削除する（空にする）項目もありますが個人的に、GUI操作はヒューマンエラーが怖いのでコードとして整理してみました。
手動削除ではなくコードで削除をしたいという同じ思いを持っている方の助けになれば幸いです。
