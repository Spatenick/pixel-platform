variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "pod_identity_trust_policy" {
  type = string
}

variable "ha_addons" {
  description = "Run two replicas of add-on controllers (prod)."
  type        = bool
  default     = false
}

variable "chart_versions" {
  description = "Pinned Helm chart versions. Renovate/Dependabot-style bumps go through a PR + plan."
  type = object({
    aws_load_balancer_controller = optional(string, "3.6.0")
    metrics_server               = optional(string, "3.14.0")
    external_secrets             = optional(string, "2.12.0")
    external_dns                 = optional(string, "1.23.0")
    keda                         = optional(string, "2.21.0")
    kube_prometheus_stack        = optional(string, "92.9.0")
    aws_for_fluent_bit           = optional(string, "0.2.0")
    argo_cd                      = optional(string, "10.10.5")
    argocd_apps                  = optional(string, "2.0.6")
  })
  default = {}
}

# --- GitOps ------------------------------------------------------------------

variable "gitops_repo_url" {
  description = "HTTPS URL of this Git repository (must be public, or add credentials to Argo CD)."
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "gitops_path" {
  description = "Directory holding this environment's Argo CD Applications, e.g. gitops/envs/dev."
  type        = string
}

# --- DNS (optional) --------------------------------------------------------------

variable "domain_name" {
  description = "Route 53 hosted zone domain for ExternalDNS. Empty disables ExternalDNS."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

# --- application wiring --------------------------------------------------------

variable "app_namespace" {
  type    = string
  default = "pixelpipe"
}

variable "app_config" {
  description = "Non-secret infra outputs exposed to the apps as the pixelpipe-infra ConfigMap."
  type        = map(string)
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB username/password (RDS-managed)."
  type        = string
}

variable "external_secret_arns" {
  description = "Secrets External Secrets Operator may read."
  type        = list(string)
}

variable "keda_sqs_queue_arns" {
  description = "Queues KEDA may read depth from."
  type        = list(string)
}

# --- observability ---------------------------------------------------------------

variable "container_log_retention_days" {
  type    = number
  default = 7
}

variable "prometheus_retention" {
  type    = string
  default = "3d"
}

variable "prometheus_persistence_enabled" {
  description = "Store Prometheus data on an EBS volume (survives pod restarts; costs a little)."
  type        = bool
  default     = false
}

variable "prometheus_storage_size" {
  type    = string
  default = "20Gi"
}

variable "tags" {
  type    = map(string)
  default = {}
}
