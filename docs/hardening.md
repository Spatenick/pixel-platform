# Hardening backlog

What a real production rollout would add next, roughly in priority order. Knowing what's *missing*, and why, matters as much as what's built.

| # | Item | Why | Effort |
|---|---|---|---|
| 1 | **Separate AWS accounts per environment** (AWS Organizations, SCPs, IAM Identity Center per account) | The strongest blast-radius boundary. A dev apply role physically can't touch prod. | M |
| 2 | **Restrict the EKS API endpoint** (`eks_public_access_cidrs` = your IP, or private-only with self-hosted runners or SSM) | The public endpoint is IAM-authenticated, but reducing exposure is cheap. | S |
| 3 | **IMDS hop limit 1** in the node launch template | Stops pods reaching node credentials through IMDS. Everything here uses Pod Identity, so verify the add-ons and set it. | S |
| 4 | **Pin GitHub Actions to commit SHAs** (Dependabot keeps them updated) | Tags are mutable, which is a supply-chain risk. | S |
| 5 | **HTTPS everywhere**: set `domain_name`, switch the Ingress to 443 with redirect | TLS in transit for users. ACM + ExternalDNS are already wired. | S |
| 6 | **AWS WAF** on the ALB (managed rule groups, rate limiting) | Basic L7 protection for a public upload endpoint. | S |
| 7 | **IAM database authentication** (already enabled on RDS) | Removes the DB password entirely, so there's nothing to rotate or leak. | M |
| 8 | **Stakater Reloader** | Restart pods automatically when `pixelpipe-db` changes after rotation. | S |
| 9 | **Kyverno / Pod Security Admission `restricted`** | Enforce what the chart already does (non-root, read-only rootfs) for *every* workload. | M |
| 10 | **Image signing** (cosign) and **admission verification** | Only images built by CI can run. | M |
| 11 | **Permissions boundary** on IAM roles Terraform creates | Limits what a compromised apply could grant. | M |
| 12 | **GuardDuty (EKS protection), Security Hub, CloudTrail org trail** | Detection and audit at the account level. | S (cost) |
| 13 | **Karpenter** | Node autoscaling that matches pod demand; better spot handling. | M |
| 14 | **Argo Rollouts** canaries gated on the SLO metrics | Progressive delivery with automatic rollback. | M |
| 15 | **Backups for cluster state** (Velero), **cross-region RDS snapshot copy** | DR beyond a single region. | M |
| 16 | **Layered Terraform state** (network / cluster / apps) | Faster plans, smaller blast radius ([ADR 0004](adr/0004-terraform-layout-and-state.md)). | M |
