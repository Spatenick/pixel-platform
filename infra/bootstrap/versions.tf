terraform {
  # 1.11+ is needed for S3-native state locking (use_lockfile) in the env stacks.
  # Works with Terraform >= 1.11 or OpenTofu >= 1.10.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bootstrap stack creates the remote-state bucket, so it starts with
  # local state. Once it has been applied you can optionally migrate it into
  # the bucket it created -- see docs/getting-started.md, step 3.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "bootstrap"
      ManagedBy = "terraform"
      Repo      = "${var.github_owner}/${var.github_repo}"
    }
  }
}
