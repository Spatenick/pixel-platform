################################################################################
# One complete environment: network -> cluster -> data -> app resources ->
# platform add-ons. infra/envs/dev and infra/envs/prod both call this module
# with different inputs, so the environments can't drift structurally.
################################################################################

data "aws_caller_identity" "current" {}

# Fail fast (at plan time) if whoever is running Terraform wouldn't be able to
# talk to the cluster afterwards -- otherwise every helm_release errors with
# "Unauthorized" and it's not obvious why.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn

  lifecycle {
    postcondition {
      condition     = contains(concat(var.cluster_admin_arns, var.cluster_viewer_arns), self.issuer_arn)
      error_message = "You are running as ${self.issuer_arn}, which is in neither cluster_admin_arns nor cluster_viewer_arns. Add it to terraform.tfvars (scripts/whoami.sh prints the exact value)."
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  dns_enabled = var.domain_name != ""
  app_host    = local.dns_enabled ? "api.${var.environment}.${var.domain_name}" : ""
}

module "vpc" {
  source = "../vpc"

  name                = local.name
  region              = var.region
  cidr                = var.vpc_cidr
  az_count            = var.az_count
  single_nat_gateway  = var.single_nat_gateway
  interface_endpoints = var.interface_endpoints
  enable_flow_logs    = var.enable_flow_logs
  tags                = local.tags
}

module "eks" {
  source = "../eks"

  cluster_name          = local.name
  kubernetes_version    = var.kubernetes_version
  subnet_ids            = module.vpc.private_subnet_ids
  public_access_cidrs   = var.eks_public_access_cidrs
  admin_principal_arns  = var.cluster_admin_arns
  viewer_principal_arns = var.cluster_viewer_arns
  node_instance_types   = var.node_instance_types
  node_capacity_type    = var.node_capacity_type
  node_desired_size     = var.node_desired_size
  node_min_size         = var.node_min_size
  node_max_size         = var.node_max_size
  log_retention_days    = var.log_retention_days
  tags                  = local.tags
}

module "rds" {
  source = "../rds-postgres"

  identifier                 = local.name
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.database_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  instance_class             = var.db_instance_class
  multi_az                   = var.db_multi_az
  backup_retention_days      = var.db_backup_retention_days
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = !var.db_deletion_protection
  log_retention_days         = var.log_retention_days
  tags                       = local.tags
}

module "app" {
  source = "../app-resources"

  name                      = local.name
  cluster_name              = module.eks.cluster_name
  namespace                 = var.app_namespace
  pod_identity_trust_policy = module.eks.pod_identity_trust_policy
  force_destroy_bucket      = var.environment != "prod"
  alert_emails              = var.alert_emails
  tags                      = local.tags
}

# --- optional: real domain + TLS ---------------------------------------------

data "aws_route53_zone" "this" {
  count        = local.dns_enabled ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "wildcard" {
  count = local.dns_enabled ? 1 : 0

  domain_name       = "*.${var.environment}.${var.domain_name}"
  validation_method = "DNS"
  tags              = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.dns_enabled ? {
    for o in aws_acm_certificate.wildcard[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  count = local.dns_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# --- platform add-ons + GitOps bootstrap ---------------------------------------

module "platform" {
  source = "../platform-addons"

  cluster_name              = module.eks.cluster_name
  environment               = var.environment
  region                    = var.region
  vpc_id                    = module.vpc.vpc_id
  pod_identity_trust_policy = module.eks.pod_identity_trust_policy
  ha_addons                 = var.ha_addons

  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  gitops_path     = "gitops/envs/${var.environment}"

  domain_name     = var.domain_name
  route53_zone_id = local.dns_enabled ? data.aws_route53_zone.this[0].zone_id : ""

  app_namespace        = var.app_namespace
  db_secret_arn        = module.rds.master_user_secret_arn
  external_secret_arns = [module.rds.master_user_secret_arn]
  keda_sqs_queue_arns  = [module.app.queue_arn]

  app_config = {
    ENVIRONMENT   = var.environment
    AWS_REGION    = var.region
    S3_BUCKET     = module.app.bucket_name
    SQS_QUEUE_URL = module.app.queue_url
    DB_HOST       = module.rds.address
    DB_PORT       = tostring(module.rds.port)
    DB_NAME       = module.rds.database_name
    DB_SSLMODE    = "require"
    PUBLIC_HOST   = local.app_host
  }

  container_log_retention_days   = var.log_retention_days
  prometheus_persistence_enabled = var.prometheus_persistence_enabled
  prometheus_retention           = var.prometheus_retention
  tags                           = local.tags

  # Helm installs need a cluster with nodes and DNS running, and the ALB
  # controller needs the certificate issued before it can attach it.
  depends_on = [module.eks, aws_acm_certificate_validation.wildcard]
}
