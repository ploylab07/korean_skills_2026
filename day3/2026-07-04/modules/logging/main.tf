provider "aws" {
  region = var.region
}

locals {
  az_a = "ap-northeast-1a"
  az_c = "ap-northeast-1c"
  tags = { Project = "wsc-logging" }

  grafana_admin_user     = "wsc2026-admin-${var.participant_id}"
  grafana_admin_password = "admin${var.participant_id}!"
}
