terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Partial configuration: the bucket name comes from `make init ENV=dev`
  # (-backend-config="bucket=..."), so no account IDs are committed to Git.
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # S3-native locking; no DynamoDB table
  }
}
