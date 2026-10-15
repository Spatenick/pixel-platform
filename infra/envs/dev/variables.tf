variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "repo_slug" {
  description = "owner/repo, used for tagging."
  type        = string
  default     = "unset"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "eks_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "cluster_admin_arns" {
  type = list(string)
}

variable "cluster_viewer_arns" {
  type    = list(string)
  default = []
}

variable "gitops_repo_url" {
  type = string
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "alert_emails" {
  type    = list(string)
  default = []
}
