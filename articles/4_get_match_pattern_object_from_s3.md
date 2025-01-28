---
title: "s3バケットからlistした結果に対して正規表現を適用し特定オブジェクト名を取得する"
emoji: "😽"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["s3", "python"]
published: true # trueを指定する
published_at: 2024-09-15 09:00 # 未来の日時を指定する
---

## はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
普段はデータ分析基盤周りに関する業務を担当しております。

データ分析基盤では、S3バケットに連携されたファイルを加工しDWH（Redshfitなど）に取込みまでを主に担当しております。
今回は、S3バケットに連携されたファイル名の接頭辞がランダムな数値が付与されたパターンにおける、特定パターンのファイル名取得についてまとめます。

## 1. 前提
取得ファイル名は以下のように日付などで特定できる項目も存在しているものとします。

- {ランダムな数値4桁}_{yyyymmdd（プログラム実行年日）}_file.txt
	- 2024年9月1日に送信した場合: 0933_20240901_file_001.txt

実行条件としてローカル端末のPC（Mac）から、python（3.9.4）を実行し確認します。

## 2. 事前準備
準備として確認するファイルを生成しS3バケットに転送します。
まず、はじめにライブラリと変数を登録します。

```python
from boto3.session import Session 
import re
import os
import tempfile

# role切替用
session = Session(profile_name = プロファイル名)
s3_client = session.client("s3")
# 対象バケットを指定
BUCKET_NAME = S3バケット名
SUB_PREFIX = "s3_list_text/source"
```

続いて、4つのファイルを作成してS3バケットに転送します。

```python
file_data_list = [
    {"directory": SUB_PREFIX, "filename": "0933_20240901_file_001.txt", "content": "これはファイル1-1の内容です。"},
    {"directory": SUB_PREFIX, "filename": "3949_20240902_file_001.txt", "content": "これはファイル2-1の内容です。"},
    {"directory": SUB_PREFIX, "filename": "7186_20240902_file_001.txt", "content": "これはファイル2-2の内容です。"},
    {"directory": SUB_PREFIX, "filename": "5986_20240902_file_002.txt", "content": "これはファイル3-1の内容です。"}
]
"""テスト用のファイルを作成してS3に転送"""
temp_dir = tempfile.mkdtemp()
results = []

for data in file_data_list:
    filename = data['filename']
    content = data['content']
    s3_key = f"{data['directory']}/{filename}"
    temp_file_path = os.path.join(temp_dir, filename)

    with open(temp_file_path, 'w', encoding='utf-8') as file:
        file.write(content)

    s3_client.upload_file(temp_file_path, BUCKET_NAME, s3_key)
    print(f"Uploaded: s3://S3バケット名/{s3_key}")
    results.append({"filename": filename, "status": "success", "s3_key": s3_key})
    os.remove(temp_file_path)
```

転送時のprint文となります。
```sh
print文の出力結果
Uploaded: s3://S3バケット名/s3_list_text/source/0933_20240901_file_001.txt
Uploaded: s3://S3バケット名/s3_list_text/source/3949_20240902_file_001.txt
Uploaded: s3://S3バケット名/s3_list_text/source/7186_20240902_file_001.txt
Uploaded: s3://S3バケット名/s3_list_text/source/5986_20240902_file_002.txt
```

## 3. 実装
ではアップロードしたファイルに対して以下の処理を試していきます。

1. listしたオブジェクト名を確認（全件）
2. 正規表現を利用して指定した接頭辞に一致するファイル名のみ取得
3. 正規表現を利用して指定した「年月日」に一致するファイル名のみ取得
4. 正規表現で特定箇所の値を取得して一致するファイル名のみ取得


### 3.1. listしたオブジェクト名を確認（全件）
`list_objects_v2`を利用してS3バケットのSUB_PREFIX配下のオブジェクト名を全て取得します。まずは実行する関数を作成します。

```python
def fetch_s3_objects():
    """S3バケットの指定配下のオブジェクト名を全て取得する"""
    continuation_token = None
    fetch_file_names = []
    while True:
        if continuation_token:
            response = s3_client.list_objects_v2(
                Bucket=BUCKET_NAME, 
                Prefix=SUB_PREFIX, 
                ContinuationToken=continuation_token
            )
        else:
            response = s3_client.list_objects_v2(
                Bucket=BUCKET_NAME, 
                Prefix=SUB_PREFIX
            )

        if 'Contents' in response:
            for obj in response['Contents']:
                file_name = obj['Key']
                only_file_name = os.path.basename(obj['Key'])  # ファイル名だけを取得
                print(only_file_name)
                fetch_file_names.append(only_file_name)

        if response.get('IsTruncated'):  # 次のページがある場合
            continuation_token = response.get('NextContinuationToken')
        else:
            break
    return fetch_file_names
```

関数を実行した結果、アップロードしたファイル名が全て取得できました。

```sh
fetch_file_names = fetch_s3_objects()
fetch_file_names
['0933_20240901_file_001.txt',
 '3949_20240902_file_001.txt',
 '5986_20240902_file_002.txt',
 '7186_20240902_file_001.txt']
```

### 3.2. 正規表現を利用して指定した接頭辞に一致するファイル名のみ取得
それでは、listしたファイル名（fetch_file_names）に、正規表現（`re.match`）を利用して接頭辞が「3」から始まるファイル名のみを取得します。

```python
# 実行コマンド
[file for file in fetch_file_names if re.match(r'^3', file)]
# 出力結果
['3949_20240902_file_001.txt']
```
4つのファイルから接頭辞が3のファイルのみ出力されました。


### 3.3. 正規表現を利用して指定した「年月日」に一致するファイル名のみ取得
今度は、ファイル名に含まれる「yyyymmdd」項目に一致するファイル名のみ取得してみます。
こちらも正規表現を利用して、「20240901」がファイル名に含まれる結果を確認します。

```python
target_date = "20240901"
pattern = rf'\d+_{target_date}_.*\.txt$'
[file for file in file_names if re.match(pattern, file)]
# 結果
['0933_20240901_file_001.txt']
```

該当する1ファイルのみ確認できました。
同様に「20240902」に該当するファイル名の取得を確認します。
```python
target_date = "20240902"
pattern = rf'\d+_{target_date}_.*\.txt$'
[file for file in file_names if re.match(pattern, file)]
# 結果
['3949_20240902_file_001.txt',
 '5986_20240902_file_002.txt',
 '7186_20240902_file_001.txt']
```

こちらも該当の3ファイルが取得できました。

### 3.4. 正規表現で特定箇所の値を取得して一致するファイル名のみ取得
先ほどは、変数を入力し該当するファイル名を取得しましたが、指定した位置の値を取得（`re.search`）して比較する方法も試してみます。

```python
target_date = "20240901"
pattern2 = rf"\d{{4}}_(\d{{8}})_.*\.txt$"

# 20240901の結果確認
for file in fetch_file_names:
    match = re.search(pattern2, file)
    # print(file)
    if match.group(1) == "20240901":
        print(f"取得パターン: {match.group(1)}")
        print(f"一致ファイル名: {file}")

```

正規表現でsearchした取得パターンと一致したファイル名をprintした結果を記載します。
```sh
取得パターン: 20240901
一致ファイル名: 0933_20240901_file_001.txt
```

こちらも想定通りの値を取得できております。

## 4. まとめ
今回はリストしたオブジェクト名から特定パターンにマッチした値のみ取得しました。
正規表現を活用することで特定オブジェクト配下から指定ファイルのみ取得するのは便利だなと実感したので今後も活用していきます。

## 参考URL

- [S3のバケット内のオブジェクトをすべて取得する](https://dev.classmethod.jp/articles/get-all-s3-objects/)
- [［解決！Python］re.search／re.match関数と正規表現を使って文字列から部分文字列を抽出するには](https://atmarkit.itmedia.co.jp/ait/articles/2103/09/news022.html)
