output "state_bucket" {
  description = "S3 bucket holding Terraform state for every environment."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  value = var.region
}

output "terraform_plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "terraform_apply_role_arn" {
  value = aws_iam_role.apply.arn
}

output "ecr_push_role_arn" {
  value = aws_iam_role.ecr_push.arn
}

output "ecr_registry" {
  description = "Registry host to log in to."
  value       = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "github_actions_variables" {
  description = "Paste these into GitHub -> Settings -> Secrets and variables -> Actions -> Variables (or run scripts/set-github-vars.sh)."
  value = {
    AWS_REGION              = var.region
    TF_STATE_BUCKET         = aws_s3_bucket.state.bucket
    TF_PLAN_ROLE_ARN        = aws_iam_role.plan.arn
    TF_APPLY_ROLE_ARN       = aws_iam_role.apply.arn
    ECR_PUSH_ROLE_ARN       = aws_iam_role.ecr_push.arn
    ECR_REGISTRY            = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    AUTO_TEARDOWN_ENABLED   = "false"
    DRIFT_DETECTION_ENABLED = "false"
  }
}
