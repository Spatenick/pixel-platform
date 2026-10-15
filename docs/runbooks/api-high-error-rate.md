# Runbook: API error budget burn / slow reads / no healthy targets

**Alerts:** `PixelpipeApiErrorBudgetFastBurn` (critical), `PixelpipeApiErrorBudgetSlowBurn`, `PixelpipeApiSlowReads`, `PixelpipeApiNoHealthyTargets`
**SLO:** 99.5% of API requests return non-5xx; p95 GET latency under 500 ms.

## 1. How bad is it? (2 minutes)

Open Grafana → **pixelpipe / service overview** (`make grafana`).

- Is the error ratio spiking on **one route** or all of them? (*Requests per second by route*)
- Did it start at a **deploy**? Check Argo CD (`make argocd`) → `pixelpipe-api` → History.

```bash
kubectl -n pixelpipe get pods -l app.kubernetes.io/name=pixelpipe-api
kubectl -n pixelpipe get events --sort-by=.lastTimestamp | tail -20
```

## 2. Most likely causes

| Looks like | Check | Fix |
|---|---|---|
| Started right after a deploy | Argo CD history; `kubectl -n pixelpipe rollout history deploy/pixelpipe-api` | **Roll back by reverting the deploy commit** in Git (`git revert <sha>`). Argo CD syncs it back. |
| 503s, `/readyz` failing | `kubectl -n pixelpipe logs deploy/pixelpipe-api \| grep -i database` | Database issue: check the RDS console (CPU, connections, events). Pods recover by themselves when the DB returns, because readiness pulls them from the ALB meanwhile. |
| 503 on uploads only | API logs: `failed to enqueue job` | SQS or IAM problem. Check the Pod Identity association, and run `aws sqs get-queue-attributes` on the queue. |
| 500s with stack traces | CloudWatch Logs Insights on `/aws/eks/pixelpipe-<env>/containers`: `filter level="ERROR" \| stats count() by msg` | Code bug: roll back, then fix forward with a test. |
| `CreateContainerConfigError` | `kubectl -n pixelpipe describe pod <pod>` | `pixelpipe-db` Secret missing: `kubectl -n pixelpipe describe externalsecret pixelpipe-db`. |
| No healthy targets / ALB 502 | `kubectl -n pixelpipe describe ingress pixelpipe-api`; target group health in the EC2 console | Pods not ready, or a NetworkPolicy blocking the ALB (the CIDR must match the VPC). |
| Slow reads, errors fine | p95 panel; RDS Performance Insights / slow-query log (`log_min_duration_statement=500`) | Missing index or DB too small. Scale `db_instance_class` with a Terraform PR. |
| CPU-bound, HPA at max | `kubectl -n pixelpipe get hpa` | Raise `autoscaling.maxReplicas` in the values file (PR), and check node capacity. |

## 3. After

- If the error budget burned noticeably, write a postmortem ([template](../postmortems/TEMPLATE.md)).
- Add the test or alert that would have caught it earlier.
