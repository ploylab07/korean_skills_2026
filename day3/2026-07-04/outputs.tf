output "scaling_bastion_ip" {
  value = module.scaling.bastion_public_ip
}

output "scaling_sqs_url" {
  value = module.scaling.sqs_url
}

output "scaling_karpenter_role" {
  value = module.scaling.karpenter_node_role
}


output "lattice_bastion_ip" {
  value = module.lattice.bastion_public_ip
}

output "logging_app_ip" {
  value = module.logging.app_public_ip
}

output "logging_loki_lb" {
  value = module.logging.loki_lb_hostname
}

output "logging_grafana_lb" {
  value = module.logging.grafana_lb_hostname
}

output "rest_api_url" {
  value = module.rest_api.invoke_url
}

output "rest_api_key" {
  value     = module.rest_api.api_key_value
  sensitive = true
}
