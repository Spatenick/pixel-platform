output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}

output "bucket_name" {
  value = module.app.bucket_name
}

output "queue_url" {
  value = module.app.queue_url
}

output "dlq_url" {
  value = module.app.dlq_url
}

output "db_address" {
  value = module.rds.address
}

output "db_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "container_log_group" {
  value = module.platform.container_log_group
}

output "api_host" {
  description = "Public hostname for the API when a domain is configured (otherwise use the ALB DNS name)."
  value       = local.app_host
}

output "alerts_topic_arn" {
  value = module.app.alerts_topic_arn
}

output "terraform_caller_role_arn" {
  description = "The IAM role this plan/apply ran as (checked against cluster_admin_arns)."
  value       = data.aws_iam_session_context.current.issuer_arn
}
