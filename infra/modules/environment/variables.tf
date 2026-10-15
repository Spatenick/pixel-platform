variable "project" {
  type    = string
  default = "pixelpipe"
}

variable "environment" {
  description = "dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- network -------------------------------------------------------------------

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "interface_endpoints" {
  type    = list(string)
  default = []
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

# --- cluster -------------------------------------------------------------------

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "eks_public_access_cidrs" {
  description = "Who can reach the Kubernetes API endpoint. Set to [\"<your-ip>/32\"] for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_arns" {
  description = "IAM role ARNs with cluster-admin. Must include YOUR role and the CI apply role."
  type        = list(string)
}

variable "cluster_viewer_arns" {
  description = "IAM role ARNs with read-only cluster access (the CI plan role)."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
}

variable "node_capacity_type" {
  type    = string
  default = "SPOT"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "ha_addons" {
  type    = bool
  default = false
}

# --- database ------------------------------------------------------------------

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}

variable "db_deletion_protection" {
  description = "Also controls final snapshots: protected DBs keep a final snapshot on destroy."
  type        = bool
  default     = false
}

# --- app + gitops ------------------------------------------------------------------

variable "app_namespace" {
  type    = string
  default = "pixelpipe"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of your fork, e.g. https://github.com/you/pixelpipe-platform.git"
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "domain_name" {
  description = "Optional Route 53 public hosted zone (e.g. example.com). Enables HTTPS + DNS for the API."
  type        = string
  default     = ""
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

# --- observability ------------------------------------------------------------------

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "prometheus_persistence_enabled" {
  type    = bool
  default = false
}

variable "prometheus_retention" {
  type    = string
  default = "3d"
}
