#!/usr/bin/env bash
# Prints the IAM *role* ARN behind your current AWS credentials -- the value
# that belongs in cluster_admin_arns. (SSO sessions show up as an STS
# assumed-role ARN; EKS access entries need the underlying role, path included.)
set -euo pipefail

arn=$(aws sts get-caller-identity --query Arn --output text)

case "$arn" in
  arn:aws:sts::*:assumed-role/*)
    role_name=$(cut -d/ -f2 <<<"$arn")
    aws iam get-role --role-name "$role_name" --query Role.Arn --output text
    ;;
  arn:aws:iam::*:user/*)
    echo "$arn"
    echo "warning: you're using an IAM user with long-lived keys; IAM Identity Center (SSO) is recommended" >&2
    ;;
  *)
    echo "$arn"
    ;;
esac
