# Cost

These are rough list-price estimates for **eu-west-2 (London)** in 2026. Prices change, so check with `make cost` (Infracost) or the AWS Pricing Calculator before trusting them. "Hourly" means while the environment exists, whether or not anyone is using it.

## Dev, while it's up

| Item | ~$/hour | ~$/month if left on | Notes |
|---|---|---|---|
| EKS control plane | 0.10 | 73 | Flat fee per cluster (standard support). |
| NAT gateway (1) | 0.05 | 36 | Plus about $0.05/GB processed. The S3 endpoint keeps image pulls off it. |
| 2 × spot t3/m5.large nodes | ~0.06 | ~45 | Spot is roughly 60–70% below on-demand. |
| ALB | ~0.03 | ~20 | Plus LCUs, which are tiny at demo traffic. |
| RDS db.t4g.micro + 20 GB gp3 | ~0.02 | ~16 | Single-AZ. |
| Public IPv4 addresses (~3) | 0.015 | ~11 | AWS charges for every public IPv4 address: NAT EIP plus the ALB's. |
| EBS (node root volumes), KMS, Secrets Manager, CloudWatch, SQS, S3 | ~0.01 | ~10 | Logs retained 3 days in dev. |
| **Total** | **≈ 0.30** | **≈ 210** | |

**A typical working session (4 hours) costs about $1.20.** Twenty such sessions a month comes to about $25.

## Always on (bootstrap stack)

State bucket and ECR images cost cents a month. The first two AWS Budgets are free. This stays after `make down`.

## Prod

Prod adds three NAT gateways, six interface endpoints in three AZs (about $0.20/hour on their own), three on-demand m5.large nodes and Multi-AZ RDS. That's roughly **$0.85/hour, or ~$600/month**. Spin it up to demo promotions and approvals, then destroy it.

## How this repo keeps the bill small

- **Budget alerts** at 50/80/100% of a monthly limit, plus a forecast alert (`infra/bootstrap`).
- **`make down`**, which cleans up the ALB and EBS volumes Kubernetes created before destroying, so nothing is left orphaned and billing.
- **Nightly teardown**: set `AUTO_TEARDOWN_ENABLED=true` and dev is destroyed at 21:00 UTC on weekdays.
- **Spot nodes** in dev, spread over four instance types for availability.
- **One NAT gateway in dev**, and no interface endpoints. ([ADR 0005](adr/0005-network-design-and-nat.md))
- **S3 gateway endpoint**: free, and keeps ECR layer pulls off the NAT's per-GB charge.
- **KEDA scales the worker to zero** when the queue is empty.
- **Short log retention** (3 days dev, 30 days prod), with flow logs for REJECTs only.
- **EKS `upgrade_policy = STANDARD`** so the cluster never silently drifts into extended support pricing.
- **ECR lifecycle policy** keeps only the last 30 images.
- **Uploaded images expire** after 7 days (S3 lifecycle).

## Talking about cost in an interview

"Dev costs about 30 cents an hour. The biggest fixed costs are the EKS control plane and the NAT gateway. In dev I traded AZ-resilience for cost with a single NAT and spot nodes, and in prod I pay for a NAT per AZ and interface endpoints. I tear dev down every night with a scheduled workflow, and the teardown script handles the resources Kubernetes creates outside Terraform, which is the usual way people end up with surprise bills."
