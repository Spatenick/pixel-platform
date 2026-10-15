# Architecture decision records

Short records of decisions that had real alternatives. Each one gives the context, the decision, and the consequences, good and bad. New decisions get a new number; superseded ones are marked, not deleted.

| # | Decision |
|---|---|
| [0001](0001-eks-over-ecs.md) | Run workloads on EKS rather than ECS Fargate |
| [0002](0002-gitops-with-argocd.md) | Deploy with GitOps (Argo CD), not `kubectl`/`helm` from CI |
| [0003](0003-github-oidc-for-ci.md) | GitHub Actions authenticates to AWS with OIDC; three scoped roles |
| [0004](0004-terraform-layout-and-state.md) | Thin env roots + composition module; S3-native state locking |
| [0005](0005-network-design-and-nat.md) | Three subnet tiers; one NAT in dev, one per AZ in prod |
| [0006](0006-pod-identity-and-external-secrets.md) | EKS Pod Identity for AWS access; RDS-managed password via External Secrets |
| [0007](0007-terraform-vs-argocd-boundary.md) | What Terraform installs vs what Argo CD deploys |
| [0008](0008-keda-for-queue-workers.md) | Scale the worker on queue depth with KEDA |
