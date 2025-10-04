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

# バケット内のオブジェクトを削除
echo "バケット内のオブジェクトを削除中..."
aws s3 rm "s3://${BUCKET_NAME}" --recursive --profile "${PROFILE}"

# バージョニングが有効な場合のバージョン削除
echo "バージョン管理されたオブジェクトを削除中..."
VERSIONS=$(aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --profile "${PROFILE}" \
    --output=json \
    --query='{Objects: [].{Key:Key,VersionId:VersionId}}')

# バージョン管理されたオブジェクトが存在する場合のみ削除を実行
if [ "$(echo $VERSIONS | jq '.Objects | length')" -gt 0 ]; then
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --profile "${PROFILE}" \
        --delete "$VERSIONS"
fi

# バケット自体を削除
echo "バケットを削除中..."
aws s3 rb "s3://${BUCKET_NAME}" --profile "${PROFILE}"

echo "バケット ${BUCKET_NAME} の削除が完了しました。"
