#!/usr/bin/env bash
# Copies the bootstrap stack's outputs into GitHub Actions repository
# variables and creates the dev/prod environments. Needs the GitHub CLI (gh)
# logged in with admin rights on the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

TF=${TF:-terraform}
repo=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

echo "Setting Actions variables on ${repo}"
"$TF" -chdir=infra/bootstrap output -json github_actions_variables |
  python3 -c 'import json,sys; [print(f"{k}\t{v}") for k,v in json.load(sys.stdin).items()]' |
  while IFS=$'\t' read -r key value; do
    gh variable set "$key" --repo "$repo" --body "$value"
    echo "  $key"
  done

echo "Creating GitHub environments"
for env in dev prod; do
  gh api --method PUT "repos/${repo}/environments/${env}" --silent
  echo "  ${env}"
done

cat <<EOF

Next (in the GitHub UI):
  1. Settings -> Environments -> prod -> Required reviewers -> add yourself.
     That's what makes prod deploys wait for a human.
  2. Settings -> Actions -> General -> Workflow permissions ->
     "Allow GitHub Actions to create and approve pull requests" (for promote.yml).
EOF
