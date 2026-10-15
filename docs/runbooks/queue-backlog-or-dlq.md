# Runbook: queue backlog, DLQ messages, worker stuck

**Alerts:** CloudWatch `…-thumbnail-dlq-not-empty`, `…-thumbnail-queue-oldest-message`; Prometheus `PixelpipeWorkerJobsFailing`, `PixelpipeWorkerStuck`

## 1. Triage

```bash
ENV=dev
Q=$(terraform -chdir=infra/envs/$ENV output -raw queue_url)
DLQ=$(terraform -chdir=infra/envs/$ENV output -raw dlq_url)
aws sqs get-queue-attributes --queue-url "$Q" --attribute-names ApproximateNumberOfMessages ApproximateAgeOfOldestMessage
aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages

kubectl -n pixelpipe get pods -l app.kubernetes.io/name=pixelpipe-worker
kubectl -n pixelpipe describe scaledobject pixelpipe-worker
kubectl -n pixelpipe logs deploy/pixelpipe-worker --tail=50
```

## 2. Causes

| Looks like | Check | Fix |
|---|---|---|
| Backlog growing, **0 worker pods** | `describe scaledobject` events; `kubectl -n keda logs deploy/keda-operator` | KEDA can't read the queue: check its Pod Identity association and IAM role (`sqs:GetQueueAttributes`). |
| Backlog growing, pods at max | Grafana *Job duration p95* | Raise `keda.maxReplicaCount` (PR). If pods are Pending, the node group is full: add nodes or adopt Karpenter. |
| Pods restarting | `kubectl describe pod`: liveness failures? OOMKilled? | OOM means huge images. Raise the memory limit, or lower `Image.MAX_IMAGE_PIXELS`. |
| `PixelpipeWorkerStuck` | worker logs: `poll failed`? | SQS or IAM errors, or the DB unreachable at startup. |
| Messages in the DLQ | Read one: `aws sqs receive-message --queue-url "$DLQ" --attribute-names All` | These failed 3 times with a *transient* error (S3 or DB). Fix the cause, then redrive. |

## 3. Redrive the DLQ after fixing the cause

```bash
DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names QueueArn --query Attributes.QueueArn --output text)
aws sqs start-message-move-task --source-arn "$DLQ_ARN"
```

Redriven jobs are safe to reprocess because processing is idempotent ([architecture](../architecture.md#the-application)). Their DB rows are `failed`, and they flip to `done` when the job succeeds.
