# Offline tests for the environment composition: no AWS account needed.
# Providers are mocked, so this checks wiring and logic (counts, conditionals,
# guardrails) -- not whether AWS accepts the values. Run with:
#   terraform -chdir=infra/modules/environment init -backend=false
#   terraform -chdir=infra/modules/environment test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/admin/me"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/admin"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:eu-west-2:123456789012:cluster/test"
      endpoint              = "https://ABC.gr7.eu-west-2.eks.amazonaws.com"
      certificate_authority = [{ data = "LS0tLS1CRUdJTg==" }]
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address            = "db.example.internal"
      port               = 5432
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds!db-abc", kms_key_id = "", secret_status = "active" }]
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-west-2:123456789012:jobs"
      url = "https://sqs.eu-west-2.amazonaws.com/123456789012/jobs"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-2:123456789012:key/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-2:123456789012:log-group:mock"
    }
  }
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:eu-west-2:123456789012:certificate/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-2:123456789012:alerts"
    }
  }
  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

mock_provider "helm" {}

variables {
  environment        = "dev"
  vpc_cidr           = "10.10.0.0/16"
  az_count           = 2
  single_nat_gateway = true
  cluster_admin_arns = ["arn:aws:iam::123456789012:role/admin"]
  gitops_repo_url    = "https://github.com/example/pixelpipe-platform.git"
}

run "dev_shape" {
  command = apply

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 2 && length(module.vpc.database_subnet_ids) == 2
    error_message = "dev should span exactly 2 AZs"
  }

  assert {
    condition     = length(output.nat_public_ips) == 1
    error_message = "dev should have a single shared NAT gateway"
  }

  assert {
    condition     = output.api_host == ""
    error_message = "no domain configured, so no API hostname"
  }

  assert {
    condition     = output.cluster_name == "pixelpipe-dev"
    error_message = "cluster name should be <project>-<env>"
  }
}

run "prod_shape" {
  command = apply

  variables {
    environment         = "prod"
    vpc_cidr            = "10.20.0.0/16"
    az_count            = 3
    single_nat_gateway  = false
    interface_endpoints = ["ecr.api", "ecr.dkr", "sts"]
  }

  assert {
    condition     = length(output.nat_public_ips) == 3
    error_message = "prod should have one NAT gateway per AZ"
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 3
    error_message = "prod should span 3 AZs"
  }
}

run "with_domain_enables_dns_and_tls" {
  command = apply

  variables {
    domain_name = "example.com"
  }

  assert {
    condition     = output.api_host == "api.dev.example.com"
    error_message = "API host should be api.<env>.<domain>"
  }

  assert {
    condition     = aws_acm_certificate.wildcard[0].domain_name == "*.dev.example.com"
    error_message = "certificate should be a per-environment wildcard"
  }
}

run "rejects_caller_without_cluster_access" {
  command = plan

  variables {
    cluster_admin_arns = ["arn:aws:iam::123456789012:role/someone-else"]
  }

  expect_failures = [data.aws_iam_session_context.current]
}

run "rejects_bad_environment_name" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
