locals {
  account_id    = data.aws_caller_identity.current.account_id
  player_number = var.player_number

  grafana_admin_user     = "skills${local.player_number}"
  grafana_admin_password = "GoodJob!Skills${local.player_number}^^"

  common_tags = {
    Project = "korean-skills-2026-day2-007"
    Player  = local.player_number
  }

  landing_bucket_name = "skillsphone-landing-ab-${local.account_id}"
}
