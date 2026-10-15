# 0008: Scale the worker on queue depth with KEDA

**Status:** accepted

## Context

The worker's load is the SQS backlog, not its CPU. A CPU-based HPA reacts late (CPU rises only after work piles up) and can't scale to zero, so an idle worker would run around the clock.

## Decision

Use **KEDA** with the `aws-sqs-queue` scaler: one replica per 5 visible messages, 0 to 5 in dev and 1 to 10 in prod. The queue URL is read from the container's environment (`queueURLFromEnv`), so the chart stays environment-agnostic. KEDA authenticates with its own Pod Identity role, which can only call `GetQueueAttributes`.

The API keeps a normal **CPU HPA**: its load is request-driven and it must never be at zero.

## Consequences

**Good**
- Scales out *before* latency suffers, because it watches the backlog itself.
- Scale-to-zero in dev: no worker pods (or their resource requests) when nothing is happening.
- Shows the difference between resource-based and event-driven autoscaling, a common interview question.

**Bad**
- Cold start: the first job after idle waits for a pod (about 10–20 s on a warm node). Prod keeps `minReplicaCount: 1` for this reason.
- Another controller to run and upgrade.
- Pod autoscaling only helps if there is node capacity. The node group is fixed-size here; **Karpenter** would add nodes on demand (stretch goal).
