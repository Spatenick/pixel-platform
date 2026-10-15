#!/usr/bin/env bash
# One-time setup: replaces the placeholders in this repo with your values.
#
#   ./scripts/configure.sh                      # auto-detects everything it can
#   ./scripts/configure.sh --repo you/pixelpipe-platform --region eu-west-2
#
# Placeholders replaced:
#   YOUR_GITHUB_USER/YOUR_REPO   GitHub owner/repo (from `git remote get-url origin`)
#   ACCOUNT_ID / 111111111111    AWS account ID      (from `aws sts get-caller-identity`)
#   REPLACE_WITH_YOUR_ROLE       your IAM role ARN   (from scripts/whoami.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

repo="" account="" admin_arn="" project="pixelpipe"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --account) account="$2"; shift 2 ;;
    --admin-role-arn) admin_arn="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$repo" ]]; then
  url=$(git remote get-url origin 2>/dev/null || true)
  repo=$(sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' <<<"$url")
fi
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Could not work out owner/repo; pass --repo owner/repo" >&2; exit 1; }

account=${account:-$(aws sts get-caller-identity --query Account --output text)}
admin_arn=${admin_arn:-$(./scripts/whoami.sh)}

echo "GitHub repo : $repo"
echo "AWS account : $account"
echo "Admin role  : $admin_arn"
read -r -p "Write these into the repo? [y/N] " ok
[[ "$ok" =~ ^[Yy]$ ]] || exit 1

files=$(grep -rlE 'YOUR_GITHUB_USER|ACCOUNT_ID|111111111111|REPLACE_WITH_YOUR_ROLE' \
  infra gitops observability .github README.md 2>/dev/null || true)
owner=${repo%%/*}

for f in $files; do
  # Replace the whole placeholder ARN for the admin role first (it may contain a path).
  sed -i.bak \
    -e "s#arn:aws:iam::111111111111:role/REPLACE_WITH_YOUR_ROLE#${admin_arn}#g" \
    -e "s#YOUR_GITHUB_USER/YOUR_REPO#${repo}#g" \
    -e "s#@YOUR_GITHUB_USER#@${owner}#g" \
    -e "s#111111111111#${account}#g" \
    -e "s#ACCOUNT_ID#${account}#g" \
    "$f"
  rm -f "$f.bak"
  echo "  updated $f"
done

if [[ ! -f infra/bootstrap/terraform.tfvars ]]; then
  name=${repo##*/}
  sed -e "s#your-github-username#${owner}#" -e "s#\"pixelpipe-platform\"#\"${name}\"#" \
    infra/bootstrap/terraform.tfvars.example > infra/bootstrap/terraform.tfvars
  echo "  created infra/bootstrap/terraform.tfvars (add your email for budget alerts!)"
fi

echo "Done. Review with: git diff"
echo "Project prefix is '${project}' (change it in infra/bootstrap/terraform.tfvars before bootstrapping if you want)."
