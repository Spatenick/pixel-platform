# 0001: Run workloads on EKS rather than ECS Fargate

**Status:** accepted

## Context

Two stateless services need to run on AWS with autoscaling, a load balancer and IAM per service. ECS on Fargate and EKS both do this well. This project is also a portfolio piece for cloud and platform roles, and nearly every current job ad in that space asks for Kubernetes.

## Decision

Use **EKS** with a managed node group.

## Consequences

**Good**
- Kubernetes is the most transferable skill, and it's what the target roles use.
- The ecosystem does a lot of work for us: Argo CD (GitOps), KEDA (event-driven scaling), Prometheus Operator, External Secrets, NetworkPolicies.
- A reusable Helm chart gives a "golden path" for new services, which is platform engineering in miniature.

**Bad**
- About $73/month for the control plane before any workload runs. ECS has no control-plane fee.
- More moving parts: add-on versions, cluster upgrades, node lifecycle. ECS Fargate would have far less to operate.
- Upgrades are our job. Mitigated with `upgrade_policy = STANDARD` and managed add-ons.

## When I'd choose ECS instead

A small team running a handful of services with no Kubernetes expertise, where operational simplicity beats ecosystem breadth. For this app alone, ECS Fargate plus SQS-based scaling would be the cheaper, simpler choice. Saying so is part of the point.
