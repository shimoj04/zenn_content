---
title: "Opentofuでさくらのクラウドをデプロイしてみる"
emoji: "🌊"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [さくらのクラウド, Opentofu]
published: true
published_at: 2025-06-23 08:30
---

## 1. はじめに
こんにちは。（心の内では）健康を目指して日々精進しているshimojです。
IaCを利用したインフラ管理はとても便利です。
本記事では、Opentofu（tofu）を利用してさくらのクラウドを実装しましたので内容を整理します。

## 2. やること
本記事では、tofuを利用してサーバーを構築しSSH接続するところまでを実装します。
なお、実行はMac環境にて行います。

1. APIキーと公開鍵/秘密鍵の準備
2. 構築用コード
3. 構築の実施
4. コンソール画面からサーバーへの接続
5. ユーザー作成とSSH接続


### 2.1. APIキーと公開鍵/秘密鍵の準備
まずは、さくらのクラウドのAPIキーと、SSH公開鍵の作成を実施します。

#### APIキーの発行
APIキーの取得は図のようにホーム画面の「APIキー」項目から取得します。
取得したアクセストークンとシークレットアクセストークンは後ほど利用するため値を控えておきます。

![](/images/12_sakura_cloud_tofu/1_2_api_key.png)

#### SSHの公開鍵を登録
続いて、公開鍵と秘密鍵を作成します。
こちらも後ほど利用するので控えておきます。

:::details 公開鍵と秘密鍵の作成
```bash

# 鍵の保存先フォルダを作成
$ cd ~/.ssh
$ mkdir test
$ cd test
$ pwd  
~/.ssh/test

# 鍵の生成
$ ssh-keygen -t rsa
Generating public/private rsa key pair.
Enter file in which to save the key (~/.ssh/id_rsa): ~/.ssh/test/id_rsa  ## 保存先のパスを指定
Enter passphrase for "~/.ssh/test/id_rsa" (empty for no passphrase):     ## 登録しない
Enter same passphrase again:                                             ## 登録しない
Your identification has been saved in ~/.ssh/test/id_rsa
Your public key has been saved in ~/.ssh/test/id_rsa.pub
The key fingerprint is:
SHA256:************************** {**}@{PC**}
The key's randomart image is:
+---[RSA 3072]----+
..
..
+----[SHA256]-----+

# 鍵の確認
$ ls
id_rsa          id_rsa.pub

$ cat id_rsa.pub
{公開鍵の登録内容}

```
:::


### 2.2. 構築用コード
さて、今回は共通用スイッチに接続したサーバーを構築します。
リソースを作成するコードの全体を記載し、それぞれの項目の説明を記載します。


| セクション番号 | セクション名 | 内容                                |
| ------- | ------ | --------------------------------- |
| 1       | プロバイダー | Terraform のプロバイダーと利用ゾーンを指定        |
| 2       | データソース | `Rocky Linux`の公式イメージを参照する  |
| 3       | リソース作成 | ディスクとサーバーの構築 |
| 4       | 出力     | 作成／参照したリソースの情報を出力<br>- disk_id: 構築ディスクのID<br>- server_id: 構構築サーバのID <br> - server_public_ip: サーバーの公開IPアドレス           |



:::details main.tf
```hcl
############################################################
# 1. プロバイダー
############################################################

terraform {
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

# 設定するパスワードの変数を定義
variable "password" {
  description = "サーバーの root パスワード"
  type        = string
  sensitive   = true
}

############################################################
# 2. データソース
############################################################
data "sakuracloud_archive" "linux_test" {
  os_type = "rockylinux"
}

############################################################
# 3. 構築リソース
############################################################

# 作成するディスクを定義
resource "sakuracloud_disk" "disk_from_tofu" {
  name              = "disk_from_tofu"
  plan              = "ssd"
  connector         = "virtio"
  size              = 20
  source_archive_id = data.sakuracloud_archive.linux_test.id
}

resource "sakuracloud_server" "srv_from_tofu" {
  name        = "srv_from_tofu"
  disks       = [sakuracloud_disk.disk_from_tofu.id]
  core        = 1
  memory      = 2
  description = "server from OpenTofu"
  tags        = ["opentofu", "202506"]

  # サーバのNICの接続先の定義。sharedだと共有セグメント(インターネット)に接続される。
  network_interface {
    upstream = "shared"
  }

  disk_edit_parameter {
    hostname = "example"
    password = var.password
    disable_pw_auth = true
  }

}


############################################################
# 4. 出力
############################################################

output "disk_id" {
  value = sakuracloud_disk.disk_from_tofu.id
  description = "作成したディスクの ID（UUID）"
}

output "server_id" {
  value = sakuracloud_server.srv_from_tofu.id
  description = "作成したサーバの ID（UUID）"
}

output "server_public_ip" {
  description = "サーバーの公開IPアドレス"
  value       = sakuracloud_server.srv_from_tofu.ip_address
}


```
:::

### 2.3. 構築の実施
それでは構築したリソースを作成していきます。
まずは、先ほど取得したAPIキーとdisk用のパスワードをexportしてtofu実行時に利用できるようにします。


```bash
$ export SAKURACLOUD_ACCESS_TOKEN={取得したアクセストークン}
$ export SAKURACLOUD_ACCESS_TOKEN_SECRET={取得したシークレットアクセストークン}
$ export TF_VAR_password=A1234567890
```

続いて以下の順番で処理を実行します。
tofu applyを実行することでさくらのクラウドにリソースが作成されますので順番に実行します。

:::details init（プラグインのダウンロードやbackend設定の検証）
```bash
$ tofu init

Initializing the backend...

Initializing provider plugins...
...(省略)
commands will detect it and remind you to do so if necessary.
```
:::


:::details validate（構文チェック）
```bash
$ tofu validate
Success! The configuration is valid.

```
:::

:::details plan（実行プランの確認）
```bash
$ tofu plan

data.sakuracloud_archive.linux_test: Reading...
data.sakuracloud_archive.linux_test: Read complete after 0s [id=00000000b]

OpenTofu used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

OpenTofu will perform the following actions:

  # sakuracloud_disk.disk_from_tofu will be created
  + resource "sakuracloud_disk" "disk_from_tofu" {
      + connector         = "virtio"
      + id                = (known after apply)
      + name              = "disk_from_tofu"
      + plan              = "ssd"
      + server_id         = (known after apply)
      + size              = 20
      + source_archive_id = "113700103137"
      + zone              = (known after apply)
    }

  # sakuracloud_server.srv_from_tofu will be created
  + resource "sakuracloud_server" "srv_from_tofu" {
      + commitment        = "standard"
      + core              = 1
      + description       = "server from OpenTofu"
      + disks             = (known after apply)
      + dns_servers       = (known after apply)
      + gateway           = (known after apply)
      + hostname          = (known after apply)
      + id                = (known after apply)
      + interface_driver  = "virtio"
      + ip_address        = (known after apply)
      + memory            = 1
      + name              = "srv_from_tofu"
      + netmask           = (known after apply)
      + network_address   = (known after apply)
      + private_host_name = (known after apply)
      + tags              = [
          + "202506",
          + "opentofu",
        ]
      + zone              = (known after apply)

      + disk_edit_parameter {
          + disable_pw_auth = true
          + hostname        = "example"
          + password        = (sensitive value)
          + ssh_key_ids     = [
              + "113701620629",
            ]
        }

      + network_interface {
          + mac_address     = (known after apply)
          + upstream        = "shared"
          + user_ip_address = (known after apply)
        }
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + disk_id          = (known after apply)
  + server_id        = (known after apply)
  + server_public_ip = (known after apply)

```
:::


:::details apply（実際の適用を実施）
```bash
$ tofu apply

data.sakuracloud_archive.linux_test: Reading...
...

Do you want to perform these actions?
  OpenTofu will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

sakuracloud_disk.disk_from_tofu: Creating...
...
sakuracloud_disk.disk_from_tofu: Creation complete after 2m14s [id=000000001]
sakuracloud_server.srv_from_tofu: Creating...
...
[id=000000002]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

disk_id = "000000001"
server_id = "000000002"
server_public_ip = "XXX.XX.XX.XXX"

```
:::


#### 構築されたリソースの確認
コントロールパネルのマップを見に行きます。
main.tfで定義されたリソースが作成されていることが確認できました！

![](/images/12_sakura_cloud_tofu/2_1_map.png)

続いてサーバーのタブに移動します。
ここで作成されたリソースがありますので選択して「詳細」をクリックします。

![](/images/12_sakura_cloud_tofu/2_2_1_server.png)

「コンソール」に移動して、「root」と入力することでサーバーへ接続ができます

![](/images/12_sakura_cloud_tofu/2_2_2_server.png)


### 2.4. ユーザー作成とSSH接続
最後にユーザーを作成し、Mac環境からSSH接続を試します。

#### ユーザー作成
まず、コントロールパネルから構築したサーバーに接続し新規ユーザーを作成します。

```bash
### ユーザー作成
$ useradd -m -s /bin/bash ssh_user

### ユーザーのパスワード設定（任意のパスワードを登録）
$ passwd ssh_user

### 新規ユーザーのみパスワードでssh接続可能にする
    # 最終行に以下項目を追加して更新
    # Match User ssh_user
    #    PasswordAuthentication yes
$ vi /etc/ssh/sshd_config


### sudo設定
$ usermod -aG wheel ssh_user
```

#### パスワードを利用したSSH接続
ここからはMacのterminal環境から接続を行います。
まずは、パスワード認証を行います。

```bash
$ ssh ssh_user@XXX.XXX.XX.XX
ssh ssh_user@XXX.XXX.XX.XX
The authenticity of host 'XXX.XXX.XX.XX (XXX.XXX.XX.XX)' can't be established.
ED25519 key fingerprint is SHA256:x+********:.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'XXX.XXX.XX.XX' (ED25519) to the list of known hosts.
ssh_user@XXX.XXX.XX.XX's password: 

[ssh_user@sv-000000002 ~]$ 
```

パスワードを利用した接続が確認できました。

#### 公開鍵の登録とログイン
続いて、公開鍵を登録しログインする方法を実行します。

```bash
### ホームに.sshディレクトリを作成
[ssh_user@sv-000000002 ~]$  mkdir -p ~/.ssh
[ssh_user@sv-000000002 ~]$  chmod 700 ~/.ssh

### 公開鍵の登録
[ssh_user@sv-000000002 ~]$  echo {~/.ssh/test/id_rsa.pubを登録} >> ~/.ssh/authorized_keys
[ssh_user@sv-000000002 ~]$  chmod 600 ~/.ssh/authorized_keys

### サーバーからログアウトする
[ssh_user@sv-000000002 ~]$ exit

### 鍵を利用して接続する
$ ssh -i ~/.ssh/test/id_rsa ssh_user@XXX.XXX.XX.XX
Last login:....

```

鍵を登録し、パスワードを利用せずにログインすることができました！

#### パスワード認証で登録できないようにする
パスワード認証は便利ですがセキュリティ上よくないので、接続できないように変更します。



```bash
### sshd_configファイルの最終行でssh_userは鍵認証のみに変更
[ssh_user@sv-000000002 ~]$ sudo vi /etc/ssh/sshd_config
    # Match User ssh_user
    #     PasswordAuthentication no
    #     PubkeyAuthentication yes

### サーバーからログアウトする
[ssh_user@sv-000000002 ~]$ exit

### パスワード認証を実行
$ ssh ssh_user@XXX.XXX.XX.XX
ssh_user@XXX.XXX.XX.XX: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).

```

## 3. まとめ
さくらのクラウドをOpentofuでリリースしSSH接続するまでを実行しました。
インフラ管理をコードで実行できるのは便利だなと感じつつ、ユーザー作成などの手動処理が発生しましたのでこのあたりも構築時に自動化できたらより便利だなと思いました。


## 4. 参考

- [さくらのクラウドでTerraformを使ってみる](https://knowledge.sakura.ad.jp/31560/)
- [さくらのクラウドをTerraformで遊ぶ](https://qiita.com/kameneko/items/384d8ac5216c1733a64a)
- [sakuracloud_server](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs/resources/server)
- [sakuracloud_disk](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs/resources/disk)
- [sakuracloud_ssh_key](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs/resources/ssh_key#description-1)
- [アーカイブ: sakuracloud_archive](https://docs.usacloud.jp/terraform/d/archive/)
- [Macで公開鍵と秘密鍵を生成する方法](https://qiita.com/wakahara3/items/52094d476774f3a2f619)


## おまけ
さくらのクラウドで利用できるゾーンコードを記載します。
今回はis1a（石狩第1ゾーン）を利用しました。

| ゾーンコード | ゾーン名称           |
|-------------|-------------------|
| tk1a      | 東京第1ゾーン        |
| tk1b      | 東京第2ゾーン        |
| is1a      | 石狩第1ゾーン        |
| is1b      | 石狩第2ゾーン        |
| tk1v      | Sandbox（テスト用ゾーン） |
