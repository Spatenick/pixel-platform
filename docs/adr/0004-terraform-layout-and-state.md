# 0004: Thin env roots + a composition module; S3-native state locking

**Status:** accepted

## Context

Dev and prod must have the same shape with different sizes. The common patterns are:

1. One root module plus `-var-file` per environment, or workspaces.
2. A directory per environment that copies the module calls.
3. A directory per environment containing a **single call** to a composition module.

## Decision

Option 3. `infra/modules/environment` wires vpc → eks → rds → app-resources → platform-addons together. `infra/envs/dev` and `infra/envs/prod` each call it once with their own sizing, and each has its **own state file** (`envs/<env>/terraform.tfstate`).

State lives in S3 with **`use_lockfile = true`**, the native S3 locking added in Terraform 1.10 (GA in 1.11). The DynamoDB lock table that tutorials still show is deprecated.

The bootstrap stack (state bucket, CI roles, ECR, budget) is separate with local state, because it has to exist before any remote state can.

## Consequences

**Good**
- Environments can't drift structurally: a new resource lands in both, by construction.
- Separate state means a `destroy` in dev can never touch prod, and the blast radius of a bad apply is one environment.
- No workspaces, which are easy to apply to the wrong environment by accident.
- Modules are written from scratch (no community modules), so every resource can be explained.

**Bad**
- One big state per environment: a plan refreshes everything (about 100 resources in dev, still fast). Splitting into layers (network / cluster / apps) with `terraform_remote_state` would cut plan times and blast radius further. This is a natural next step if it grows.
- The Helm provider is configured from outputs of resources in the same apply (the cluster). This works for create and destroy but is a known Terraform sharp edge if the cluster is ever *replaced*. The fix in that case is a targeted apply or splitting the add-ons into their own layer.
