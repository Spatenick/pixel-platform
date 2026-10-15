# 0005: Three subnet tiers; one NAT in dev, one per AZ in prod

**Status:** accepted

## Context

Pods need outbound internet access (image pulls, AWS APIs) but must not be reachable from it. The database should have no internet path at all. NAT gateways are the usual answer and also one of the biggest fixed costs: about $36/month each plus a per-GB charge.

## Decision

- **Three tiers per AZ:** public (ALB, NAT), private (nodes and pods, sized /19 because the VPC CNI gives every pod a VPC IP), database (no default route).
- **Dev:** 2 AZs, a **single** NAT gateway shared by all private subnets, no interface endpoints.
- **Prod:** 3 AZs, **one NAT per AZ**, interface endpoints for ECR (API and DKR), STS, SQS, Secrets Manager and CloudWatch Logs.
- **Both:** a free S3 gateway endpoint (ECR layer pulls and our uploads go through it, not the NAT), and VPC flow logs for REJECTed traffic only.

## Consequences

**Good**
- Dev saves about $36–72/month on NAT and about $145/month on endpoints.
- Prod survives an AZ outage: each AZ's pods egress through their own NAT.
- In prod, AWS API calls (credentials, secrets, queue polling) never leave the VPC.

**Bad**
- In dev, losing the NAT's AZ breaks egress for every AZ. That's acceptable for dev, and the classic interview trade-off question.
- Cross-AZ traffic to a single NAT incurs inter-AZ data charges (small at dev volumes).

## Alternatives considered

- **NAT instances** (fck-nat and similar): around $3/month, but self-managed and a single point of failure.
- **IPv6 with an egress-only internet gateway:** removes NAT for IPv6 traffic, but EKS IPv6 clusters add complexity and some AWS endpoints are still IPv4.
- **No NAT, endpoints for everything:** breaks pulls from public registries (Docker Hub, quay.io) that the add-on charts need.
