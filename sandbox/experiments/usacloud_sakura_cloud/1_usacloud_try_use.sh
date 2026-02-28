## 0. API登録場所
$ pwd
~/.usacloud/profile/config.json

## 1. ディスク作成

$ usacloud disk create \
  --name test-disk \
  --disk-plan hdd \
  --size 40 \
  --source-archive-id ubuntu2204 \
  --zone tk1a


## 2. 特定ゾーンのディスク（リストで出力される）
$ usacloud disk list --zone tk1a
$ usacloud disk list --zone tk1a --query "[].ID"
[
    ***
]


## 3. 特定ゾーンのディスクを削除
$ usacloud disk delete *** --zone tk1a   


## 4. zoneリスト取得
$ usacloud zone list  

| ゾーン名     | エリア | 説明                            |
| -------- | --- | ----------------------------- |
| **is1a** | 石狩  | 最も標準的な石狩リージョン                 |
| **is1b** | 石狩  | is1a の兄弟ゾーン。冗長化やマルチAZに利用      |
| **tk1a** | 東京  | 東京リージョンのメインゾーン                |
| **tk1v** | 東京  | 高火力（GPUなど）。AI/ML向けの東京バーチャルゾーン |

