# 0002: Deploy with GitOps (Argo CD), not `kubectl`/`helm` from CI

**Status:** accepted

## Context

CI needs to get new versions running in the cluster. The traditional approach gives the CI runner cluster-admin credentials and runs `helm upgrade` (push-based). The GitOps approach has CI change Git, and an agent inside the cluster reconciles from Git (pull-based).

## Decision

**Argo CD**, using an app-of-apps per environment (`gitops/envs/<env>/`). CI only pushes images and commits the new tag. Prod is promoted by a pull request that copies dev's tags.

## Consequences

**Good**
- CI never holds cluster credentials, which removes a whole class of supply-chain risk.
- Git is the audit log and the rollback button: `git revert` the deploy commit.
- Drift is corrected automatically (`selfHeal`). A hand-edited Deployment is reverted within minutes.
- Promotion is a reviewable diff, and prod runs exactly the image dev ran.

**Bad**
- CI pushes commits to `main`, which needs care with branch protection. A bot exception is documented.
- There's a short delay between merge and deploy (Argo's poll interval, about 3 minutes). Webhooks would remove it.
- Argo CD itself must be installed and upgraded. Terraform installs it ([ADR 0007](0007-terraform-vs-argocd-boundary.md)).

## Alternatives considered

- **Flux:** equally valid, and lighter-weight. Argo CD was chosen for its UI, which helps when demoing.
- **`helm upgrade` from Actions:** simpler to start with, but it needs long-lived cluster access from CI and has no drift correction.
