################################################################################
# IAM for cluster add-ons, granted with EKS Pod Identity.
# Each role is bound to exactly one namespace/service-account pair.
################################################################################

locals {
  sa = {
    lbc         = { namespace = "kube-system", name = "aws-load-balancer-controller" }
    eso         = { namespace = "external-secrets", name = "external-secrets" }
    keda        = { namespace = "keda", name = "keda-operator" }
    fluentbit   = { namespace = "logging", name = "aws-for-fluent-bit" }
    externaldns = { namespace = "external-dns", name = "external-dns" }
  }
}

# --- AWS Load Balancer Controller ------------------------------------------------

resource "aws_iam_policy" "lbc" {
  name_prefix = "${var.cluster_name}-lbc-"
  description = "AWS Load Balancer Controller (upstream policy, pinned to the chart's app version)"
  policy      = file("${path.module}/policies/aws-load-balancer-controller.json")
  tags        = var.tags
}

resource "aws_iam_role" "lbc" {
  name_prefix        = "${var.cluster_name}-lbc-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = local.sa.lbc.namespace
  service_account = local.sa.lbc.name
  role_arn        = aws_iam_role.lbc.arn
  tags            = var.tags
}

# --- External Secrets Operator (read only the secrets we list) ---------------------

data "aws_iam_policy_document" "eso" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.external_secret_arns
  }
}

resource "aws_iam_role" "eso" {
  name_prefix        = "${var.cluster_name}-eso-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "eso" {
  name   = "read-app-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = local.sa.eso.namespace
  service_account = local.sa.eso.name
  role_arn        = aws_iam_role.eso.arn
  tags            = var.tags
}

# --- KEDA (reads SQS queue depth to scale the worker) --------------------------------

data "aws_iam_policy_document" "keda" {
  statement {
    actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = var.keda_sqs_queue_arns
  }
}

resource "aws_iam_role" "keda" {
  name_prefix        = "${var.cluster_name}-keda-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "keda" {
  name   = "read-queue-depth"
  role   = aws_iam_role.keda.id
  policy = data.aws_iam_policy_document.keda.json
}

resource "aws_eks_pod_identity_association" "keda" {
  cluster_name    = var.cluster_name
  namespace       = local.sa.keda.namespace
  service_account = local.sa.keda.name
  role_arn        = aws_iam_role.keda.arn
  tags            = var.tags
}

# --- Fluent Bit -> CloudWatch Logs -----------------------------------------------------

resource "aws_cloudwatch_log_group" "containers" {
  name              = "/aws/eks/${var.cluster_name}/containers"
  retention_in_days = var.container_log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "fluentbit" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.containers.arn}:*"]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "fluentbit" {
  name_prefix        = "${var.cluster_name}-fluentbit-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "fluentbit" {
  name   = "write-container-logs"
  role   = aws_iam_role.fluentbit.id
  policy = data.aws_iam_policy_document.fluentbit.json
}

resource "aws_eks_pod_identity_association" "fluentbit" {
  cluster_name    = var.cluster_name
  namespace       = local.sa.fluentbit.namespace
  service_account = local.sa.fluentbit.name
  role_arn        = aws_iam_role.fluentbit.arn
  tags            = var.tags
}

# --- ExternalDNS (only when a Route 53 domain is configured) -------------------------------

data "aws_iam_policy_document" "externaldns" {
  count = local.dns_enabled ? 1 : 0

  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "externaldns" {
  count = local.dns_enabled ? 1 : 0

  name_prefix        = "${var.cluster_name}-extdns-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "externaldns" {
  count = local.dns_enabled ? 1 : 0

  name   = "manage-dns-records"
  role   = aws_iam_role.externaldns[0].id
  policy = data.aws_iam_policy_document.externaldns[0].json
}

resource "aws_eks_pod_identity_association" "externaldns" {
  count = local.dns_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.sa.externaldns.namespace
  service_account = local.sa.externaldns.name
  role_arn        = aws_iam_role.externaldns[0].arn
  tags            = var.tags
}
