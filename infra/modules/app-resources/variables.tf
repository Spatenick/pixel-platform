variable "name" {
  description = "Prefix, e.g. pixelpipe-dev."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "namespace" {
  description = "Kubernetes namespace the services run in."
  type        = string
  default     = "pixelpipe"
}

variable "api_service_account" {
  type    = string
  default = "pixelpipe-api"
}

variable "worker_service_account" {
  type    = string
  default = "pixelpipe-worker"
}

variable "pod_identity_trust_policy" {
  description = "Trust policy JSON for EKS Pod Identity (output of the eks module)."
  type        = string
}

variable "object_expiration_days" {
  description = "Uploaded images are demo data; delete them after this many days."
  type        = number
  default     = 7
}

variable "force_destroy_bucket" {
  description = "Allow terraform destroy to delete a non-empty bucket (true in dev)."
  type        = bool
  default     = false
}

variable "alert_emails" {
  description = "Emails subscribed to the CloudWatch alarm SNS topic (confirm the subscription email)."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
