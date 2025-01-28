---
title: "日本語ファイルを含めたZipファイルをpythonで解凍したら文字化けした.."
emoji: "🐙"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["S3", "boto3", "python"]
published: true # trueを指定する
published_at: 2025-01-29 12:00 # 未来の日時を指定する
---

## はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
普段はデータ分析基盤周りに関する業務を担当しております。

昨年、Zipファイル解凍の件で記事を書きました。
[S3バケットにあるzipファイルを解凍して配置する](https://zenn.dev/shimoj_tech/articles/2_zip_extractor_upload_)

そのため、Zip形式のファイルも解凍したらファイル単体でDWHに取込めるなと認識してました。
しかし、新たにきたZipを解凍するとファイル名が「*文字化け*」状態になってます。

同様の問題を解決した[Python で zip 展開（日本語ファイル名対応）](https://qiita.com/tohka383/items/b72970b295cbc4baf5ab)の記事を参照したところ、原因について以下のような記載を確認しまいた。

> ZipFile ライブラリでは、 UTF-8 フラグがあれば UTF-8 として、そうでなければ CP437 として、バイト列を文字列に変換する仕様となっています。
> https://github.com/python/cpython/blob/3.7/Lib/zipfile.py#L1358-L1365

解決方法は「cp437」でエンコードして、適切な文字コードでデコードをすれば良いとありましたので動作確認した内容をまとめたいと思います。

## 処理の確認方針
確認方針は以下の流れで実施します。
今回の圧縮解凍時に利用するOSはMacとなります。

1. pythonにて日本語名と英語名を含めたZipファイルを作成
2. 作成したZip内のファイル名をpythonにて取得
3. Zipファイルを解凍し、手動で圧縮したZip内のファイル名を再取得
4. 再圧縮したZipファイル内のファイル名取得時にエンコード/デコードを追加
5. Zipファイルを解凍して配置する

なお動作にあたり以下のpythonライブラリをインポートします。
```python
import os
import zipfile
import codecs
import tempfile
import shutil
```

### 1. pythonにて日本語名と英語名を含めたZipファイルを作成
まずは動作確認ように英語名と日本語名を含めたZipファイルを作成します。

:::details Zipファイル構築コード
```python
japanese_filenames = ["日本語ファイル1.txt", "日本語ファイル2.txt"]  # 日本語ファイル名
english_filenames = ["english_file1.txt", "english_file2.txt"]  # 英語ファイル名
all_filenames = japanese_filenames + english_filenames  # すべてのファイル名をリストに結合

# 一時ディレクトリを作成
with tempfile.TemporaryDirectory() as temp_dir:
    # ファイルを作成し、内容を書き込む
    for filename in all_filenames:
        file_path = os.path.join(temp_dir, filename)
        with codecs.open(file_path, 'w', 'utf-8') as f:
            f.write(f"This is the content of {filename}")
    
    # ZIPファイルを作成
    zip_filename = "mixed_language_files.zip"
    zip_path = os.path.join(os.getcwd(), zip_filename)
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for filename in all_filenames:
            file_path = os.path.join(temp_dir, filename)
            zipf.write(file_path, filename)

print(f"ZIP file '{zip_filename}' has been created with {len(all_filenames)} files.")
```
:::

実行結果のprint文の出力です。対象の「mixed_language_files.zip」ファイルを作成しました。

```sh
ZIP file 'mixed_language_files.zip' has been created with 5 files.    
```

### 2. 作成したZip内のファイル名をpythonにて取得
続いて、作成したZipファイル内のファイル名を取得します。

```python
# ZIPファイル内のファイルリストを取得
with zipfile.ZipFile(zip_filename, 'r') as zip_ref:
    file_list = zip_ref.infolist()
    for file_info in file_list:
        print(file_info.filename)
```

pythonで圧縮したファイル内のファイル名は「文字化け」せずに取得できました。

```sh
日本語ファイル1.txt
日本語ファイル2.txt
english_file1.txt
english_file2.txt
```

### 3. Zipファイルを解凍し、手動で圧縮したZip内のファイル名を再取得
次に、pythonで作成したZipファイルを解凍、4つのファイルを手動で圧縮し、圧縮したZipファイル内のファイル名を確認します。

```python
re_zip_filename = "mixed_language_files/アーカイブ.zip"
# 再圧縮したZIPファイル内のファイルリストを取得
with zipfile.ZipFile(re_zip_filename, 'r') as zip_ref:
    file_list = zip_ref.infolist()
    for file_info in file_list:
        print(file_info.filename)
```

結果として、日本語が含まれるファイル名は「文字化け」して表示されることが確認できました。

```sh
µùÑµ£¼Φ¬₧πâòπéíπéñπâ½1.txt
µùÑµ£¼Φ¬₧πâòπéíπéñπâ½2.txt
english_file1.txt
english_file2.txt
```

### 4. 再圧縮したZipファイル内のファイル名取得時にエンコード/デコードを追加
ファイル名のデコードが適切ではないということを確認しておりますので、「cp437」で一旦エンコードし、「utf8」でデコードした結果を確認します。

```python
# 再圧縮したZIPファイル内のファイルリストを取得
	# エンコードとデコード追加
with zipfile.ZipFile(re_zip_filename, 'r') as zip_ref:
    file_list = zip_ref.infolist()
    for file_info in file_list:
        print(file_info.filename.encode('cp437').decode('utf8'))
```

エンコード/デコードを追加することで、日本語名ファイルも適切に取得することができました！

```sh
日本語ファイル1.txt
日本語ファイル2.txt
english_file1.txt
english_file2.txt
```

### 5. Zipファイルを解凍して配置する
なお、そのまま解凍しただけでは文字化けした状態のままですので、一時フォルダに配置しファイルをコピーする方法にてファイル名を戻酢コードを記載します。

:::details Zipファイルを日本語名で保存
```python
re_zip_extractall_filename = "配置先フォルダ"

with tempfile.TemporaryDirectory() as temp_dir:
    # Zipファイルを一時ディレクトリに解凍
    with zipfile.ZipFile(re_zip_filename, 'r') as zip_ref:
        zip_ref.extractall(temp_dir)

    # ファイルをリネームして目的のディレクトリに移動
    for root, dirs, files in os.walk(temp_dir):
        for file in files:
            old_file_path = os.path.join(root, file)
            re_file_name = file.encode('cp437').decode('utf8')
            re_file_path = os.path.join(re_zip_extractall_filename, re_file_name)

            # 必要に応じてディレクトリを作成
            os.makedirs(os.path.dirname(re_file_path), exist_ok=True)
            # ファイルを移動
            shutil.move(old_file_path, re_file_path)
:::


## まとめ
Zipファイル解凍時の文字化けではまり、調査した内容をまとめました。
文字化けを見た時は焦りましたが先人の知恵を探すことができ本当に良かったです。
なお、動作確認ではMacOSのみを利用しておりますが圧縮と解凍を行うOSの差異があるとデコード時の文字コードも異なるのでまた注意だなと実感しております。
本記事がどなたか助けになれば幸いです。

## 参考URL

- [Python で zip 展開（日本語ファイル名対応）](https://qiita.com/tohka383/items/b72970b295cbc4baf5ab)