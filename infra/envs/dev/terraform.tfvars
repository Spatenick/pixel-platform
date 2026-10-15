# Dev environment inputs. No secrets live here -- it's safe to commit.
# Run `./scripts/configure.sh` once to fill in the placeholders.

repo_slug       = "YOUR_GITHUB_USER/YOUR_REPO"
gitops_repo_url = "https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git"

# Who gets cluster-admin. Must contain:
#   1. your own IAM Identity Center role ARN  (./scripts/whoami.sh prints it)
#   2. the CI apply role from the bootstrap stack outputs
cluster_admin_arns = [
  "arn:aws:iam::111111111111:role/REPLACE_WITH_YOUR_ROLE",
  "arn:aws:iam::111111111111:role/pixelpipe-gha-terraform-apply",
]

# Read-only cluster access for `terraform plan` in pull requests.
cluster_viewer_arns = [
  "arn:aws:iam::111111111111:role/pixelpipe-gha-terraform-plan",
]

# Lock the Kubernetes API down to your IP once things work: ["203.0.113.7/32"]
eks_public_access_cidrs = ["0.0.0.0/0"]

# Optional: a Route 53 hosted zone you own -> https://api.dev.<domain>
domain_name = ""

# Optional: get emailed when thumbnail jobs land in the dead-letter queue
alert_emails = []
