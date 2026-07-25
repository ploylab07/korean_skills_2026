output "workflow_bucket" {
  value = module.workflow.bucket_name
}

output "analytics_alb_dns" {
  value = module.analytics.alb_dns
}

output "event_instance_id" {
  value = module.event.instance_id
}

output "msk_cluster_arn" {
  value = module.msk.cluster_arn
}
