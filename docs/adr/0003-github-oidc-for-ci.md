# 0003: GitHub Actions authenticates to AWS with OIDC; three scoped roles

**Status:** accepted

## Context

CI needs AWS access to run `terraform plan`/`apply` and to push images. Storing an IAM user's access keys as GitHub secrets is the classic approach, and the classic source of leaked credentials.

## Decision

Use **GitHub's OIDC provider**. Each job exchanges a short-lived GitHub-signed token for temporary AWS credentials. There are three roles, each trusting a narrow set of token `sub` claims:

| Role | Trusted subjects | Permissions |
|---|---|---|
| `gha-terraform-plan` | `pull_request`, `ref:refs/heads/main` | `ReadOnlyAccess` + read state + write **only** `*.tflock`; EKS read-only access entry |
| `gha-terraform-apply` | `environment:dev`, `environment:prod` | `AdministratorAccess` |
| `gha-ecr-push` | `ref:refs/heads/main` | push to the two ECR repos |

## Consequences

**Good**
- No stored AWS secrets at all, so there's nothing to leak or rotate.
- Pull requests, including from anyone who can open one, only ever get read-only credentials.
- The apply role can only be assumed by jobs bound to a GitHub **environment**, and the `prod` environment requires a human approval. Approval in GitHub becomes an IAM-enforced control.

**Bad / accepted risk**
- The apply role has `AdministratorAccess`. Terraform creates IAM roles, KMS keys and so on, so a tightly-scoped policy would be long and brittle. The mitigation is controlling *who can assume it* (environment-bound subjects plus required reviewers).
  - *Next step in a real org:* a permissions boundary on roles Terraform creates, an SCP denying the riskiest actions, and per-environment accounts (AWS Organizations) so the dev apply role can't touch prod at all.
- Anyone with write access to `main` can change workflows. Branch protection and CODEOWNERS on `.github/` are the control for that.
