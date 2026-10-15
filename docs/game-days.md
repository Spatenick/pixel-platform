# Game days: break it on purpose

Reading about resilience is one thing. Watching your platform absorb a failure and writing down what happened is what gives you real interview stories. Run each exercise against **dev** with Grafana open (`make grafana`) and a load test running (`make load-test`). Afterwards, write a short postmortem from the [template](postmortems/TEMPLATE.md), even when nothing broke.

| # | Exercise | How | What *should* happen | What to record |
|---|---|---|---|---|
| 1 | **Kill pods** | `kubectl -n pixelpipe delete pod -l app.kubernetes.io/name=pixelpipe-api --wait=false` | Deployment replaces them, readiness gates traffic, and the error ratio barely moves | Errors seen by k6; time to recover |
| 2 | **Lose a node** | Terminate one node's EC2 instance in the console (or `aws ec2 terminate-instances`) | The ASG replaces it, pods reschedule, PDB and topology spread keep the API serving | Time until a new node is Ready; any 5xx |
| 3 | **Bad deploy** | Merge a change that makes `/readyz` return 503 | The rollout stalls (`maxUnavailable: 0`), old pods keep serving, Argo CD shows Degraded | Then roll back with `git revert`; time from detection to fix |
| 4 | **Poison and transient failures** | Upload a file renamed to `.png` that's really text (`curl -F file=@notes.txt;type=image/png …`); separately, `kubectl -n pixelpipe scale deploy/pixelpipe-worker --replicas=0` for 10 minutes | Garbage gets a 415 at the API, so no job is created. With workers gone, the oldest-message alarm fires, then KEDA scales back up | Which alarms fired and how fast; whether the runbook was enough |
| 5 | **Database failover** *(prod, or set `db_multi_az = true` in dev first)* | `aws rds reboot-db-instance --db-instance-identifier pixelpipe-dev --force-failover` | 30–60 s of `/readyz` failures, pods leave and rejoin the ALB, no restarts | Exact downtime; whether the error budget alert fired |
| 6 | **Restore from backup** | Follow [runbooks/database-restore.md](runbooks/database-restore.md) | A new instance with data as of the chosen time | Your **measured RTO** — a great number to quote |
| 7 | **Manual drift** | Add a tag to the uploads bucket in the console, then run the `drift-detection` workflow | An issue titled *Infrastructure drift detected in dev* | Decide: codify the change or revert it |
| 8 | **Secret rotation** | Secrets Manager → the RDS secret → *Rotate secret immediately* | ESO re-syncs within the hour (or force it: `kubectl annotate externalsecret pixelpipe-db force-sync=$(date +%s) -n pixelpipe`), then pods need a restart | This exposes the gap noted in [ADR 0006](adr/0006-pod-identity-and-external-secrets.md). Propose the fix. |

> Exercise 8 deliberately surfaces a known weakness. Finding it yourself and proposing Reloader or IAM DB auth is a better interview story than a platform with no flaws.
