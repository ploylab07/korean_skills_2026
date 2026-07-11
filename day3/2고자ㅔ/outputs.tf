output "cdn_distribution_domain" {
  value = module.cdn.distribution_domain
}

output "analytics_ec2_public_ip" {
  value = module.analytics.ec2_public_ip
}

output "analytics_nlb_dns" {
  value = module.analytics.nlb_dns
}

output "event_ec2_public_ip" {
  value = module.event.ec2_public_ip
}

output "keycloak_ec2_public_ip" {
  value = module.keycloak.keycloak_public_ip
}

output "ssh_private_key_pem" {
  value     = local.ssh_private_key_pem
  sensitive = true
}
