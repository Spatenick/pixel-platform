module "environment" {
  source = "../../modules/environment"

  environment = "dev"
  region      = var.region

  # Network: one NAT gateway, two AZs, no interface endpoints -> cheapest.
  vpc_cidr            = "10.10.0.0/16"
  az_count            = 2
  single_nat_gateway  = true
  interface_endpoints = []

  # Cluster: 2 spot nodes.
  kubernetes_version      = var.kubernetes_version
  eks_public_access_cidrs = var.eks_public_access_cidrs
  cluster_admin_arns      = var.cluster_admin_arns
  cluster_viewer_arns     = var.cluster_viewer_arns
  node_capacity_type      = "SPOT"
  node_desired_size       = 2
  node_min_size           = 2
  node_max_size           = 4

  # Database: smallest instance, no standby, destroyable.
  db_instance_class        = "db.t4g.micro"
  db_multi_az              = false
  db_backup_retention_days = 1
  db_deletion_protection   = false

  gitops_repo_url = var.gitops_repo_url
  domain_name     = var.domain_name
  alert_emails    = var.alert_emails

  log_retention_days             = 3
  prometheus_persistence_enabled = false
  prometheus_retention           = "2d"
}
