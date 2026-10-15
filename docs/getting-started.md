# Getting started: zero to a running platform

Plan on one evening for the setup (steps 1–6) and about 25 minutes for the first `make up`. Everything assumes **eu-west-2 (London)**. To use another region, see [Changing region](#changing-region).

> **Before you start: cost.** Dev costs about $0.30/hour while it exists. Create a budget alert (step 4 does this) and get into the habit of running `make down` when you're finished. See [cost.md](cost.md).

## 0. Tools

| Tool | Version | Check |
|---|---|---|
| AWS CLI | v2 | `aws --version` |
| Terraform *or* OpenTofu | ≥ 1.11 / ≥ 1.10 | `terraform version` |
| kubectl | within one minor version of the cluster (1.36) | `kubectl version --client` |
| GitHub CLI | any recent | `gh --version` |
| Docker | any recent (local dev and load tests only) | `docker version` |
| make, python3, git | any | |

If you use OpenTofu, add `TF=tofu` to every `make` command (or `export TF=tofu`).

## 1. Set up the AWS account properly

Do this even for a throwaway account. It's also the first thing an interviewer will ask about.

1. **Secure the root user**: turn on MFA, then stop using root.
2. **Enable IAM Identity Center** (AWS Console → IAM Identity Center → Enable). Create a user for yourself and give it the `AdministratorAccess` permission set on this account.
3. **Log in from the CLI with SSO** (no access keys):
   ```bash
   aws configure sso             # profile name e.g. "pixelpipe", region eu-west-2
   export AWS_PROFILE=pixelpipe
   aws sso login
   aws sts get-caller-identity   # should show an assumed-role ARN with AWSReservedSSO_...
   ```

## 2. Put the code in your own GitHub repo

Argo CD reads this repo to deploy the apps, so for the simplest setup make it **public**. A private repo also works, but you then need to give Argo CD credentials; see the Argo CD docs on private repositories.

```bash
git init -b main && git add . && git commit -m "Initial commit"
gh repo create pixelpipe-platform --public --source . --remote origin --push
```

## 3. Fill in the placeholders

```bash
make configure
```

This replaces `YOUR_GITHUB_USER/YOUR_REPO`, the AWS account ID and your IAM role ARN throughout `infra/`, `gitops/` and the docs. It also creates `infra/bootstrap/terraform.tfvars`.

**Then edit `infra/bootstrap/terraform.tfvars` and add your email to `budget_alert_emails`.** Review the changes with `git diff`, then commit and push.

## 4. Bootstrap the account (once)

```bash
make bootstrap
```

This creates:

- the S3 bucket for Terraform state (versioned, encrypted, TLS-only, with S3-native locking)
- the GitHub OIDC provider plus three CI roles: **plan** (read-only), **apply** (bound to GitHub environments) and **ecr-push** (main branch only)
- ECR repositories `pixelpipe-api` and `pixelpipe-worker`
- a monthly budget with email alerts at 50%, 80% and 100%

AWS emails you to confirm the budget alert subscription. Click the link.

<details><summary>Optional: move the bootstrap state into S3 too</summary>

The bootstrap stack starts with local state, because the bucket doesn't exist yet. Once it does, you can migrate:

```hcl
# add to infra/bootstrap/versions.tf inside terraform {}
backend "s3" {
  bucket       = "<state_bucket output>"
  key          = "bootstrap/terraform.tfstate"
  region       = "eu-west-2"
  encrypt      = true
  use_lockfile = true
}
```

```bash
terraform -chdir=infra/bootstrap init -migrate-state
```
</details>

## 5. Connect GitHub Actions to AWS

```bash
gh auth login        # if you haven't already
make github-vars
```

This sets the repository **variables** (not secrets; nothing here is secret) that the workflows use, and creates the `dev` and `prod` environments. Then, in the GitHub UI:

1. **Settings → Environments → prod → Required reviewers**: add yourself. Prod infrastructure changes and destroys now wait for your approval.
2. **Settings → Actions → General → Workflow permissions**: tick *Allow GitHub Actions to create and approve pull requests*. The `promote` workflow needs this.
3. If you add branch protection to `main`, allow the `github-actions[bot]` to push, because CI commits image tags to `gitops/`.

## 6. Build the first images

The cluster needs images to deploy. Trigger the app pipeline once: **Actions → app → Run workflow** (or push any change under `apps/`).

It runs the tests (including Postgres integration tests), lints and renders the Helm chart, unit-tests the alert rules, builds both images, scans them with Trivy, pushes them to ECR and commits the new tags to `gitops/envs/dev/values/`.

## 7. Create the dev environment

```bash
make up ENV=dev
```

Terraform shows the plan (about 100 resources). Type `yes`. Creation takes 20–25 minutes, mostly EKS and RDS. In order, it builds:

1. VPC: subnets, NAT gateway, route tables, S3 endpoint, flow logs
2. EKS cluster: KMS key, log group, access entries, VPC CNI / kube-proxy / Pod Identity add-ons, spot node group, CoreDNS, EBS CSI
3. RDS Postgres (password generated and stored by RDS in Secrets Manager)
4. S3 uploads bucket, SQS queue + DLQ, IAM roles for the API and worker, CloudWatch alarms
5. Helm releases: AWS Load Balancer Controller, metrics-server, External Secrets, KEDA, kube-prometheus-stack, Fluent Bit, Argo CD, plus the "platform glue" (gp3 StorageClass, ClusterSecretStore, infra ConfigMap, DB ExternalSecret)
6. The Argo CD root application, which deploys `gitops/envs/dev/*`

> You can do the same from GitHub instead: **Actions → infra-apply → Run workflow → dev / apply**. After this first run, every merged change under `infra/` applies automatically.

## 8. Look around

```bash
make status ENV=dev     # Argo CD apps, pods, HPA/KEDA, the API's URL
make smoke ENV=dev      # upload an image through the ALB and wait for the thumbnail
make argocd             # http://localhost:8080 (prints the admin password)
make grafana            # http://localhost:3000 -> Dashboards -> "pixelpipe / service overview"
make load-test          # k6: watch the HPA and KEDA scale out in Grafana
```

Things worth looking at:

- **CloudWatch → Logs Insights** on `/aws/eks/pixelpipe-dev/containers`: `filter level = "ERROR" | stats count() by logger`
- **Argo CD**: try deleting a pod or editing a Deployment by hand and watch self-heal undo it.
- **KEDA**: the worker sits at 0 replicas until a job arrives, then scales out.

## 9. Make a change the GitOps way

1. Edit something in `apps/api` (the `root()` response, for example) and open a PR. CI runs the tests but pushes nothing.
2. Merge it. CI builds and pushes `pixelpipe-api:<sha>` and commits the new tag to `gitops/envs/dev/values/api.yaml`.
3. Argo CD notices the commit and rolls it out. It never needed cluster credentials from CI.

For an infrastructure change, edit something in `infra/` and open a PR. The **infra-plan** workflow comments the `terraform plan` for dev and prod (and a cost diff if you add an `INFRACOST_API_KEY` secret). Merging applies it.

## 10. Prod (optional, costs more)

```bash
make up ENV=prod                              # or Actions -> infra-apply -> prod / apply (needs your approval)
# then: Actions -> promote-to-prod -> Run      # opens a PR copying dev's image tags to prod
```

Merging the promotion PR is the deploy. To have infra merges flow on to prod automatically after dev, set the repository variable `PROD_ENABLED=true`.

## 11. Tear down

```bash
make down ENV=dev       # deletes K8s-created ALBs/volumes first, then terraform destroy
```

To make forgetting impossible, set the repository variable `AUTO_TEARDOWN_ENABLED=true` and the `nightly-teardown` workflow destroys dev at 21:00 UTC every weekday.

Prod's database has deletion protection. To destroy prod, first set `db_deletion_protection = false` in `infra/envs/prod/main.tf` and apply; RDS still takes a final snapshot.

What stays after teardown, costing pennies a month: the state bucket, ECR images and the budget. Those belong to the bootstrap stack.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `plan` fails: *"You are running as … which is in neither cluster_admin_arns nor cluster_viewer_arns"* | Run `./scripts/whoami.sh` and put that exact ARN in `infra/envs/<env>/terraform.tfvars`. |
| A `helm_release` times out on the very first apply | Usually spot capacity or image pulls being slow. Run `make up` again; it's idempotent. |
| Pods in `ImagePullBackOff` with tag `initial` | CI hasn't pushed images yet. Do step 6. |
| Argo CD app shows *repository not accessible* | The repo is private. Make it public, or add repo credentials to Argo CD. |
| Ingress has no address | `kubectl -n kube-system logs deploy/aws-load-balancer-controller`. Usually subnet tags or IAM. |
| `pixelpipe-db` Secret missing, pods stuck in `CreateContainerConfigError` | `kubectl -n pixelpipe describe externalsecret pixelpipe-db`, then check the ESO logs in `external-secrets`. |
| Worker never scales up | `kubectl -n pixelpipe describe scaledobject pixelpipe-worker` and `kubectl -n keda logs deploy/keda-operator`. |
| Node group stuck creating | Spot capacity or a vCPU quota on a new account. Switch `node_capacity_type` to `ON_DEMAND` in `infra/envs/dev/main.tf`, or request a quota increase. |
| `destroy` hangs on subnets or the VPC | An ALB or ENI created by Kubernetes was orphaned. See [runbooks/teardown-stuck.md](runbooks/teardown-stuck.md). |

## Changing region

Edit: `region` in `infra/bootstrap/terraform.tfvars`, `region` in both `infra/envs/*/versions.tf` backend blocks, the `REGION` default in the `Makefile`, the ECR hostnames and `keda.sqs.awsRegion` in `gitops/envs/*/values/*.yaml`, and `aws-region` in `.github/workflows` (or just the `AWS_REGION` repo variable).
