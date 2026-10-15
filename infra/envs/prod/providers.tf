provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "pixelpipe"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repo        = var.repo_slug
    }
  }
}

# The Helm provider authenticates to EKS with a short-lived token from the AWS
# CLI (same IAM identity Terraform is using), so no kubeconfig file is needed.
provider "helm" {
  kubernetes = {
    host                   = module.environment.cluster_endpoint
    cluster_ca_certificate = base64decode(module.environment.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.environment.cluster_name, "--region", var.region]
    }
  }
}
