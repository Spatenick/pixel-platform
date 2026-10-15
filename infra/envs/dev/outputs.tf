output "cluster_name" {
  value = module.environment.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.environment.cluster_name} --alias pixelpipe-dev"
}

output "bucket_name" {
  value = module.environment.bucket_name
}

output "queue_url" {
  value = module.environment.queue_url
}

output "dlq_url" {
  value = module.environment.dlq_url
}

output "db_address" {
  value = module.environment.db_address
}

output "container_log_group" {
  value = module.environment.container_log_group
}

output "api_host" {
  value = module.environment.api_host
}

output "nat_public_ips" {
  value = module.environment.nat_public_ips
}
