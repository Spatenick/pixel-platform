################################################################################
# GitHub Actions -> AWS with OIDC. No long-lived access keys anywhere.
#
# Three roles, each trusted by a narrow set of GitHub token "sub" claims:
#   plan     - read-only + state lock, assumable from PRs and main
#   apply    - admin, assumable ONLY from jobs bound to the dev/prod GitHub
#              environments (so prod can require a human approval)
#   ecr-push - push images, assumable only from the main branch
################################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    plan     = ["repo:${local.repo}:pull_request", "repo:${local.repo}:ref:refs/heads/main"]
    apply    = ["repo:${local.repo}:environment:dev", "repo:${local.repo}:environment:prod"]
    ecr-push = ["repo:${local.repo}:ref:refs/heads/main"]
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# --- plan -------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-terraform-plan"
  description          = "Assumed by GitHub Actions to run terraform plan (read-only)."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  # plan takes a lock, so it must be able to write/delete *only* the lock file
  statement {
    sid       = "ManageLockFileOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# --- apply ------------------------------------------------------------------

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-gha-terraform-apply"
  description          = "Assumed by GitHub Actions jobs in the dev/prod environments to run terraform apply."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["apply"].json
  max_session_duration = var.apply_role_max_session_seconds
}

# Terraform creates IAM roles, KMS keys, VPCs, EKS... so the apply role needs
# broad rights. The guardrails are on *who* can assume it (environment-bound
# OIDC subjects + required reviewers on the prod environment). See
# docs/adr/0003-github-oidc-for-ci.md for the trade-off.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- ecr push ---------------------------------------------------------------

resource "aws_iam_role" "ecr_push" {
  name                 = "${var.project}-gha-ecr-push"
  description          = "Assumed by GitHub Actions on main to push container images."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["ecr-push"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "GetAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
