# 0006: EKS Pod Identity for AWS access; RDS-managed password via External Secrets

**Status:** accepted

## Context

Pods need AWS permissions (S3, SQS) and the database password. The anti-patterns are putting permissions on the node role (every pod gets everything), putting keys in environment variables, and keeping passwords in Terraform variables (which end up in state and Git).

## Decision

1. **EKS Pod Identity** for every workload and add-on. One IAM role per service account, bound with `aws_eks_pod_identity_association`. Trust policies are generic (`pods.eks.amazonaws.com`), so there's no per-cluster OIDC provider plumbing as with IRSA.
2. **RDS manages the master password** (`manage_master_user_password = true`). RDS generates it, stores it in Secrets Manager and can rotate it. Terraform never sees it.
3. **External Secrets Operator** syncs that secret into the `pixelpipe-db` Kubernetes Secret. ESO's own role can read *only* that secret ARN.

## Consequences

**Good**
- Least privilege per pod. The API role can `PutObject` only under `originals/`, and the worker can write only `thumbnails/`.
- No secret ever appears in Git, Terraform state, CI logs or a Helm values file.
- Rotation-ready: ESO re-syncs hourly (`refreshInterval: 1h`).

**Bad**
- Apps read the password from an environment variable at start-up, so after a rotation pods need a restart. A reloader (stakater/Reloader) or having apps re-read credentials on auth failure would close this gap.
- Pod Identity requires the agent add-on and doesn't work on Fargate pods. That's irrelevant here, but worth knowing.
- The app uses a password at all. RDS IAM authentication is enabled on the instance as a next step, which would remove the password entirely.

## Alternatives considered

- **IRSA:** the previous standard and still common in job ads. It works, but needs an OIDC provider per cluster and trust policies that embed it.
- **Secrets Store CSI driver:** mounts secrets as files, but syncing to env vars still needs a K8s Secret, so ESO is simpler here.
