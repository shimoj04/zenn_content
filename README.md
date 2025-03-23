# Docs for zenn.dev（参照リンク含む）
https://zenn.dev/zenn

- [Zenn CLIで記事・本を管理する方法](https://zenn.dev/zenn/articles/zenn-cli-guide)
- [ZennのMarkdown記法一覧](https://zenn.dev/zenn/articles/markdown-guide)

# zenn実行時の利用コマンド

```sh
# 処理実行階層（gitの西行衣改装
$ pwd
{ローカル配置パス}/zenn_content

# 新しい記事作成（article直下に作成される）
$ npx zenn new:article 
created: articles/29539f94a6b7b5.md

# 記事のプレビューができる（便利）
$ npx zenn preview # プレビュー開始
👀 Preview: http://localhost:8000

# 記事の公開
	## gitリポジトリに登録して記事内「published」をtrueにすることで可能
$ git add {ファイル}
$ git commit -m "{コメント}"
$ git push

```sh
test
test2
