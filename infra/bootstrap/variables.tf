variable "project" {
  description = "Short project name, used as a prefix for every resource."
  type        = string
  default     = "pixelpipe"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project must be 3-21 chars of lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "AWS region for the shared resources."
  type        = string
  default     = "eu-west-2"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository (e.g. \"janedoe\")."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. \"pixelpipe-platform\")."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the token.actions.githubusercontent.com OIDC provider."
  type        = bool
  default     = true
}

variable "ecr_repositories" {
  description = "Container image repositories shared by every environment (build once, promote everywhere)."
  type        = list(string)
  default     = ["pixelpipe-api", "pixelpipe-worker"]
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the whole account, in USD. Alerts fire at 50%, 80% and 100%."
  type        = number
  default     = 40
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget alerts. Leave empty to skip creating the budget."
  type        = list(string)
  default     = []
}

variable "apply_role_max_session_seconds" {
  description = "Maximum session length for the CI apply role. EKS creates/destroys can take 20+ minutes."
  type        = number
  default     = 7200
}
