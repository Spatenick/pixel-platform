# 0007: What Terraform installs vs what Argo CD deploys

**Status:** accepted

## Context

With both Terraform and Argo CD in play, every Kubernetes object needs exactly one owner. Two owners means they fight, and an unclear owner means nobody knows where to change things.

## Decision

**Terraform owns** anything that needs AWS resources or IAM wired to it, and anything everything else depends on:
- cluster add-ons with IAM: the Load Balancer Controller, External Secrets, KEDA, Fluent Bit, ExternalDNS
- CRD providers that apps assume exist: kube-prometheus-stack, KEDA, ESO
- Argo CD itself and its root Application
- the **platform-glue** chart: the gp3 StorageClass, the ClusterSecretStore, the `pixelpipe-infra` ConfigMap (Terraform outputs) and the DB ExternalSecret

**Argo CD owns** application workloads (`gitops/envs/<env>/`) and dashboards.

The **contract** between them is two names: the `pixelpipe-infra` ConfigMap and the `pixelpipe-db` Secret. The app chart and values contain no bucket names, queue URLs or ARNs.

## Consequences

**Good**
- Infra outputs reach apps without anyone copy-pasting ARNs into YAML.
- An app team can ship without touching Terraform, and the platform team can resize a database without touching app config.
- The first `terraform apply` produces a working environment end to end.

**Bad**
- Add-on upgrades go through Terraform plans rather than Git-driven syncs. That's fine at this scale. A larger platform would move add-ons into Argo CD too (with values templated from Terraform outputs, for example via ApplicationSet cluster generators).
- Helm releases managed by Terraform are opaque in `plan` output: you see a values diff, not a manifest diff.
