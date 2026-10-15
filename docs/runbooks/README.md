# Runbooks

Every alert links to one of these via its `runbook_url` annotation or alarm description.

| Runbook | Alerts |
|---|---|
| [api-high-error-rate.md](api-high-error-rate.md) | `PixelpipeApiErrorBudgetFastBurn`, `…SlowBurn`, `PixelpipeApiSlowReads`, `PixelpipeApiNoHealthyTargets` |
| [queue-backlog-or-dlq.md](queue-backlog-or-dlq.md) | CloudWatch DLQ / queue-age alarms, `PixelpipeWorkerJobsFailing`, `PixelpipeWorkerStuck` |
| [node-or-spot-interruption.md](node-or-spot-interruption.md) | Nodes NotReady, Pending pods, spot reclaims |
| [database-restore.md](database-restore.md) | Data loss or corruption; restore rehearsal |
| [teardown-stuck.md](teardown-stuck.md) | `terraform destroy` hangs or a state lock is stuck |

Format for new runbooks: **symptoms → triage commands → likely causes table → fix → follow-up**. Keep them short enough to use at 3 a.m.
