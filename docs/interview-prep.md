# Interview prep: talking about this project

The project only helps if you can explain **every** part of it and the trade-offs behind it. Before putting it on your CV, make sure you can answer each question below without notes, have deployed it yourself, and have run at least three [game days](game-days.md).

## The 30-second version

> "I built a production-style platform on AWS with Terraform: a three-tier VPC, EKS with spot nodes, RDS, S3 and SQS, all in my own modules with separate dev and prod environments. Apps are deployed with GitOps through Argo CD, and CI uses GitHub OIDC so there are no stored AWS keys. It has SLO-based alerting, KEDA autoscaling on queue depth, runbooks, and I've run failure drills against it. Dev costs about 30 cents an hour, and it tears itself down every night."

## The 2-minute walkthrough (whiteboard order)

1. **Request path:** user → ALB → API pods → S3 + Postgres + SQS → worker → thumbnail.
2. **Network:** public, private and database tiers; why the DB has no route out; NAT per AZ in prod vs one in dev.
3. **Identity:** SSO for humans, OIDC for CI, Pod Identity for pods. No long-lived keys anywhere.
4. **Delivery:** PR → tests → merge → image to ECR → CI commits the tag → Argo CD syncs dev → promotion PR → prod.
5. **Operations:** SLOs and burn-rate alerts, dashboards as code, runbooks, a game day you ran and what you learned.

## CV bullets (pick 2–3, use your real numbers)

- Designed and built an AWS platform with **Terraform** (6 custom modules, dev/prod environments, S3-native state locking): VPC, **EKS**, RDS PostgreSQL, S3, SQS, KMS, IAM, provisioned from an empty account in ~25 minutes.
- Implemented **GitOps** with Argo CD and GitHub Actions using **OIDC federation** (zero stored credentials), with Terraform plans posted to PRs, Checkov/tflint/Trivy scanning, and approval-gated production applies.
- Built observability with **Prometheus/Grafana** and **SLO burn-rate alerting** (unit-tested with promtool), plus event-driven autoscaling with **KEDA** on SQS depth that scales to zero in dev.
- Cut idle cost to **~$0.30/hour** with spot nodes, a single-NAT dev topology and an automated nightly teardown; documented trade-offs in 8 ADRs and ran failure drills (node loss, DB failover, restore with **measured RTO of X min**).

## Questions you should expect

**Terraform**
- *How is your state stored and locked?* S3 with versioning and encryption, and `use_lockfile` (native S3 locking, Terraform 1.10+). DynamoDB locking is deprecated. The plan role can only write the `.tflock` object.
- *How do you keep dev and prod the same?* A composition module called once per environment, so differences are only inputs. Each environment has its own state. No workspaces.
- *How do you handle drift?* A daily plan with `-detailed-exitcode` opens an issue on exit code 2.
- *What's the problem with configuring the Helm provider from cluster outputs?* Provider config depends on resources in the same apply. Fine for create and destroy, but painful if the cluster is replaced. The fix is splitting the state into layers.
- *Why write your own modules?* To understand and explain every resource. In a team I'd weigh community modules (maintained, battle-tested) against the control and readability of our own.

**AWS / networking**
- *Why three subnet tiers?* Blast radius and egress control. The DB tier has no route out.
- *What does a NAT gateway cost and how do you reduce it?* About $36/month plus per-GB charges. Use an S3 gateway endpoint, interface endpoints in prod, and a single NAT in dev (accepting the AZ-failure trade-off).
- *Public vs private subnets for nodes?* Private. Only the ALB and NAT are public. The ALB uses IP targets, so traffic goes straight to pod IPs.

**Kubernetes / EKS**
- *How do pods get AWS permissions?* EKS Pod Identity: a role per service account, bound with an association. Compare it with IRSA and node roles.
- *Liveness vs readiness?* Liveness = "restart me". Readiness = "send me traffic". The API's liveness deliberately ignores the DB.
- *What happens on a spot interruption?* 2-minute notice, drain, PDBs limit evictions, topology spread keeps replicas across nodes and AZs.
- *HPA vs KEDA?* Resource metrics vs event metrics. KEDA can scale to zero and reacts to backlog before CPU rises.
- *How are secrets handled?* RDS generates the password into Secrets Manager, and ESO syncs it with a narrowly scoped role. Know the rotation gap and how to fix it (Reloader, IAM auth).
- *What's a NetworkPolicy and what enforces it here?* The VPC CNI's network policy agent. The policy is default-deny ingress with explicit allows.

**CI/CD & GitOps**
- *Why not `kubectl apply` from CI?* Credentials in CI, no drift correction, no Git audit trail.
- *How does promotion work?* A workflow copies dev's image tags into prod's values and opens a PR. The merge is the deploy, and the same image runs in both.
- *How do you roll back?* `git revert` the deploy commit, and Argo CD syncs.
- *How is CI authenticated to AWS?* OIDC. Explain the `sub` claim conditions and why the apply role trusts only environment-bound jobs.

**Observability / SRE**
- *What are your SLOs and why burn-rate alerts?* 99.5% availability and p95 under 500 ms. Multi-window burn rates page on fast budget loss without flapping on short spikes. The promtool tests prove that.
- *Why route templates in metric labels?* Cardinality. A label per image ID would blow up Prometheus.
- *Tell me about an incident.* Use a game-day postmortem: what broke, how you detected it, timeline, root cause, action items.

**Reliability / data**
- *At-least-once delivery: how do you avoid double processing harm?* Idempotent writes and monotonic status updates.
- *What's in the DLQ and what do you do with it?* Messages that failed 3 times. An alarm fires; fix the cause, then redrive.
- *What's your RPO/RTO?* About 5 minutes / your measured restore time.

**Cost & trade-offs**
- *Where does the money go?* The EKS control plane, NAT, nodes, ALB and public IPv4 addresses. See [cost.md](cost.md).
- *What would you change for a real company?* Answer from [hardening.md](hardening.md): separate accounts, endpoint restrictions, WAF, image signing, policy enforcement.
- *When would you not use Kubernetes?* See [ADR 0001](adr/0001-eks-over-ecs.md). Showing judgement here scores points.

## Make it visible

- Pin the repo on your GitHub profile. Keep the README diagram and badges green.
- Record a 3-minute demo: `make up` sped up, the Argo CD UI, an upload, a load test with scaling in Grafana, killing a node, then `make down`.
- Write one blog post or LinkedIn post about one specific lesson (for example, "the orphaned-ALB teardown problem" or "SLO alerts I unit-test").
