module "environment" {
  source = "../../modules/environment"

  environment = "prod"
  region      = var.region

  # Network: 3 AZs, a NAT gateway per AZ (no cross-AZ single point of failure)
  # and interface endpoints so AWS API calls never leave the VPC.
  vpc_cidr            = "10.20.0.0/16"
  az_count            = 3
  single_nat_gateway  = false
  interface_endpoints = ["ecr.api", "ecr.dkr", "sts", "sqs", "secretsmanager", "logs"]

  # Cluster: on-demand nodes, HA add-on controllers.
  kubernetes_version      = var.kubernetes_version
  eks_public_access_cidrs = var.eks_public_access_cidrs
  cluster_admin_arns      = var.cluster_admin_arns
  cluster_viewer_arns     = var.cluster_viewer_arns
  node_instance_types     = ["m5.large", "m5a.large", "m6i.large"]
  node_capacity_type      = "ON_DEMAND"
  node_desired_size       = 3
  node_min_size           = 3
  node_max_size           = 6
  ha_addons               = true

  # Database: Multi-AZ standby, a week of backups, protected from destroy.
  db_instance_class        = "db.t4g.small"
  db_multi_az              = true
  db_backup_retention_days = 7
  db_deletion_protection   = true

  gitops_repo_url = var.gitops_repo_url
  domain_name     = var.domain_name
  alert_emails    = var.alert_emails

  log_retention_days             = 30
  prometheus_persistence_enabled = true
  prometheus_retention           = "7d"
}
