---
title: "S3バケットにあるzipファイルを解凍して配置する"
emoji: "💭"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["S3", "boto3", "python"]
published: true # trueを指定する
published_at: 2024-09-13 15:00 # 未来の日時を指定する
---

# はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
普段はデータ分析基盤周りに関する業務を担当しております。

業務上、S3バケットに連携されたファイルを加工して配置する処理をしたりします。
今回は連携されたZipファイルを解凍し、ファイル配置までをまとめます。

# 全体像
処理としては配置されたZipファイルに対してローカル端末から「解凍/転送処理」を実行します。



プログラム処理日をオブジェクトキーに含めた形式にするため、取得元/転送先の配置先は以下表になります。

| 項目 | オブジェクトキー |
| --- | --- |
| zip配置先 | zip_test/source/{yyyy}/{mm}/{dd}/直下 |
| 解凍後ファイル配置先 | zip_test/target/{yyyy}/{mm}/{dd}/直下 |

なお、AWS権限設定関連は割愛し、Zip解凍後のファイルが配置されているところまでを確認します。

# 事前準備
まず、準備としzipファイルを作成しS3にアップロードします。


```sh
# 1. テストファイルを作成
$ echo "これはファイル1の内容です。" > file1.txt
$ echo "これはファイル2の内容です。" > file2.txt

# 2. 作成したファイルの確認
$ ls -l file1.txt file2.txt
-rw-r--r--  1 ***.***  staff  41  9  9 10:53 file1.txt
-rw-r--r--  2 ***.***  staff  41  9  9 10:53 file2.txt

# 3. zipファイルを作成
$ zip files.zip file1.txt file2.txt
  adding: file1.txt (stored 0%)
  adding: file2.txt (stored 0%)

# 4. zipファイルの中身確認
$ zipinfo files.zip 
Archive:  files.zip
Zip file size: 396 bytes, number of entries: 2
-rw-r--r--  3.0 unx       41 tx stor 24-Sep-09 10:53 file1.txt
-rw-r--r--  3.0 unx       41 tx stor 24-Sep-09 10:53 file2.txt

# 5. s3フォルダに転送
$ aws --profile **** s3 cp files.zip s3://{バケット名}/zip_test/source/2024/09/09/
Enter MFA code for arn:aws:iam::{AWSアカウント番号}:mfa/****: 
upload: ./files.zip to s3://{バケット名}/zip_test/source/2024/09/09/files.zip

```

# 実装
では実際に実装したコードを記載します。処理フローは以下となります。
1. プログラム実行時間取得と変数の指定
2. 一時ディレクトリの作成
3. 一時ディレクトリにzipファイルをダウンロード
4. 解凍したファイルをS3にアップロード
5. 一時ディレクトリの削除


```python
from boto3.session import Session 
import zipfile
import os
from datetime import datetime, timedelta, timezone
import tempfile
import shutil

# ローカル実行時のAWS環境の対応
profile_nm = プロファイル名
session = Session(profile_name = profile_nm)
S3_CLIENT = session.client("s3")

# プログラム実施日の取得
now_jst = datetime.now(timezone(timedelta(hours=9)))  ## JST（日本標準時）はUTC+9時間
formatted_date = now_jst.strftime('%Y/%m/%d')  # ## yyyy/mm/dd 形式で取得
print(f"formatted_date: {formatted_date}")

# zip配置先の変数
SOURCE_BUCKET = zipファイルを配置したバケット名
source_sub_prefix = "zip_test/source/" + formatted_date + "/"
source_zip_file_name = "files.zip"
SOURCE_ZIP_KEY = source_sub_prefix + source_zip_file_name
print(f"SOURCE_ZIP_KEY: {SOURCE_ZIP_KEY}")

# csv保存先の変数
TARGET_BUCKET = 解凍後ファイルを配置するバケット名
TARGET_PREFIX = "zip_test/target/" + formatted_date + "/"
print(f"TARGET_PREFIX: {TARGET_PREFIX}")
# 取得ファイル名の配列
FILES_TO_EXTRACT = ['file1.txt', 'file2.txt']


def main():
    temp_dir = tempfile.mkdtemp()  # 一時ディレクトリを手動で作成
    try:
        local_zip_path = os.path.join(temp_dir, 'temp.zip')  # 一時ファイルパスを作成
        
        # S3からZIPファイルをダウンロード
        S3_CLIENT.download_file(
            SOURCE_BUCKET, 
            SOURCE_ZIP_KEY, 
            local_zip_path
        )
        print(f"Downloaded {SOURCE_ZIP_KEY} to {local_zip_path}")
        
        # ZIPファイルを解凍
        with zipfile.ZipFile(local_zip_path, 'r') as zip_ref:
            zip_ref.extractall(temp_dir)
            print(f"Extracted ZIP file to {temp_dir}")
        
        # 解凍したファイルをS3にアップロード
        for root, dirs, files in os.walk(temp_dir):
            files.remove("temp.zip")  # 固定のzip名は除去する

            for file_name in FILES_TO_EXTRACT:
                file_path = os.path.join(root, file_name)
                s3_key = os.path.join(TARGET_PREFIX, file_name)

                # S3にアップロード
                with open(file_path, 'rb') as f:
                    S3_CLIENT.put_object(
                        Bucket=TARGET_BUCKET, 
                        Key=s3_key, 
                        Body=f
                    )
                print(f"Uploaded {file_name} to s3://{TARGET_BUCKET}/{s3_key}")
    finally:
        # 一時ディレクトリを削除
        shutil.rmtree(temp_dir)
        print(f"Temporary directory {temp_dir} deleted.")


if __name__ == '__main__':
    main()

```

# 動作確認と結果
pythonコードを実行と、配置先S3バケットのファイル確認用コードを記載します。


```sh
# 1. pythonファイルの実行と出力表示
$ python s3_zip_file_動作確認.py
formatted_date: 2024/09/09
SOURCE_ZIP_KEY: zip_test/source/2024/09/09/files.zip
TARGET_PREFIX: zip_test/target/2024/09/09/
Downloaded zip_test/source/2024/09/09/files.zip to /var/folders/t_/3mt5lqq917b_fpqpbvnz08xw0000gp/T/tmplstimx2i/temp.zip
Extracted ZIP file to /var/folders/t_/3mt5lqq917b_fpqpbvnz08xw0000gp/T/tmplstimx2i
Uploaded file1.txt to s3://{S3バケット名}/zip_test/target/2024/09/09/file1.txt
Uploaded file2.txt to s3://{S3バケット名}/zip_test/target/2024/09/09/file2.txt
Temporary directory /var/folders/t_/3mt5lqq917b_fpqpbvnz08xw0000gp/T/tmplstimx2i deleted.

# 2. ファイルの配置確認
$ aws --profile プロファイル名 s3 ls s3://{S3バケット名}/zip_test/target/2024/09/09/
2024-09-09 hh:mm:ss         41 file1.txt
2024-09-09 hh:mm:ss         41 file2.txt
```

解凍後のファイルが指定したオブジェクト配下に存在することを確認しました。


# まとめ
解凍と転送に関する処理を実装しました。
コード自体は簡易的なものですが、配置先の日付パスなど個人的に忘れやすいので今後思いだす際に活用できたらなと思います。

# 参考URL

[スイッチロールしたIAM RoleをPython Boto3で使いたい](https://dev.classmethod.jp/articles/use_iam_role_for_boto3/)
