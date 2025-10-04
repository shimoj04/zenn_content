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


resource "sakuracloud_switch" "my_switch" {
  name = "my-open-tofu-switch"
  description = "Created via OpenTofu"
  tags        = ["202507", "tofu"]
}


############################################################
# 4. 出力
############################################################

output "disk_id" {
  value = sakuracloud_disk.disk_from_tofu.id
  description = "作成したディスクの ID（UUID）"
}

output "disk_name" {
  value = sakuracloud_disk.disk_from_tofu.name
  description = "作成したディスク名"
}

output "server_id" {
  value = sakuracloud_server.srv_from_tofu.id
  description = "作成したサーバの ID（UUID）"
}

output "server_public_ip" {
  description = "サーバーの公開IPアドレス (user_ip_address)"
  value       = sakuracloud_server.srv_from_tofu.ip_address
}
