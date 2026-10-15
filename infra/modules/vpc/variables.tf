variable "name" {
  description = "Name prefix for all VPC resources."
  type        = string
}

variable "region" {
  description = "AWS region (used for VPC endpoint service names)."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block. Must be a /16 for the built-in subnet plan."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && endswith(var.cidr, "/16")
    error_message = "cidr must be a valid /16 block, e.g. 10.0.0.0/16."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (2 or 3)."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway(s) so private subnets can reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheap, dev) instead of one per AZ (resilient, prod)."
  type        = bool
  default     = true
}

variable "interface_endpoints" {
  description = "Interface VPC endpoints to create, e.g. [\"ecr.api\", \"ecr.dkr\", \"sts\", \"sqs\"]. Each costs money per AZ."
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Send REJECTed traffic flow logs to CloudWatch."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
