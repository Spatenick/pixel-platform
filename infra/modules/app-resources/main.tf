################################################################################
# AWS resources owned by the pixelpipe application, plus least-privilege IAM
# for each service, bound to Kubernetes service accounts with EKS Pod Identity.
#
#   api    -> put originals in S3, send jobs to SQS, read thumbnails
#   worker -> read originals, write thumbnails, consume SQS
################################################################################

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.name}-uploads-${data.aws_caller_identity.current.account_id}"
}

# --- uploads bucket -------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-demo-data"
    status = "Enabled"
    filter {}

    expiration {
      days = var.object_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.uploads]
}

data "aws_iam_policy_document" "uploads_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.uploads.arn, "${aws_s3_bucket.uploads.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket     = aws_s3_bucket.uploads.id
  policy     = data.aws_iam_policy_document.uploads_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.uploads]
}

# --- job queue + dead-letter queue ---------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-thumbnail-jobs-dlq"
  message_retention_seconds = 1209600 # 14 days to investigate
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name}-thumbnail-jobs"
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20 # long polling: fewer empty receives, lower cost
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}

# --- IAM: api ---------------------------------------------------------------------

data "aws_iam_policy_document" "api" {
  statement {
    sid       = "WriteOriginals"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/originals/*"]
  }

  statement {
    sid       = "ReadImages"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/originals/*", "${aws_s3_bucket.uploads.arn}/thumbnails/*"]
  }

  statement {
    sid       = "EnqueueJobs"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.jobs.arn]
  }
}

resource "aws_iam_role" "api" {
  name_prefix        = "${var.name}-api-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "api" {
  name   = "pixelpipe-api"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.api_service_account
  role_arn        = aws_iam_role.api.arn
  tags            = var.tags
}

# --- IAM: worker ------------------------------------------------------------------

data "aws_iam_policy_document" "worker" {
  statement {
    sid       = "ReadOriginals"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/originals/*"]
  }

  statement {
    sid       = "WriteThumbnails"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/thumbnails/*"]
  }

  statement {
    sid = "ConsumeJobs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }
}

resource "aws_iam_role" "worker" {
  name_prefix        = "${var.name}-worker-"
  assume_role_policy = var.pod_identity_trust_policy
  tags               = var.tags
}

resource "aws_iam_role_policy" "worker" {
  name   = "pixelpipe-worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_eks_pod_identity_association" "worker" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.worker_service_account
  role_arn        = aws_iam_role.worker.arn
  tags            = var.tags
}

# --- AWS-native alerting: anything in the DLQ means jobs are failing ------------

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-thumbnail-dlq-not-empty"
  alarm_description   = "Thumbnail jobs are failing repeatedly. Runbook: docs/runbooks/queue-backlog-or-dlq.md"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "queue_age" {
  alarm_name          = "${var.name}-thumbnail-queue-oldest-message"
  alarm_description   = "Oldest job has waited > 5 minutes: workers are down or can't keep up. Runbook: docs/runbooks/queue-backlog-or-dlq.md"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.jobs.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}
