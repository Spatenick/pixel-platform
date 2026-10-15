#!/usr/bin/env bash
# Safely destroy an environment.
#
#   ./scripts/teardown.sh dev          # asks for confirmation
#   ./scripts/teardown.sh dev --yes    # CI / nightly teardown
#
# Why not just `terraform destroy`? Kubernetes creates AWS resources that
# Terraform doesn't know about: the ALB (from the Ingress) and EBS volumes
# (from PersistentVolumeClaims). If the cluster disappears before they're
# cleaned up, they're orphaned -- the ALB keeps the VPC from being deleted and
# both keep billing. So: delete them through Kubernetes first, wait for AWS to
# confirm, *then* destroy.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV=${1:?usage: teardown.sh <dev|prod> [--yes]}
YES=${2:-}
REGION=${AWS_REGION:-eu-west-2}
CLUSTER="pixelpipe-${ENV}"
TF=${TF:-terraform}
TF_DIR="infra/envs/${ENV}"

log() { printf '\n==> %s\n' "$*"; }

if [[ "$YES" != "--yes" ]]; then
  read -r -p "Destroy EVERYTHING in '${ENV}' (cluster, database, bucket)? Type the env name to confirm: " answer
  [[ "$answer" == "$ENV" ]] || { echo "aborted"; exit 1; }
fi

if [[ ! -d "${TF_DIR}/.terraform" ]]; then
  bucket=${TF_STATE_BUCKET:?set TF_STATE_BUCKET (or run make init ENV=${ENV} first)}
  "$TF" -chdir="$TF_DIR" init -input=false -backend-config="bucket=${bucket}" -backend-config="region=${REGION}"
fi

if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.resourcesVpcConfig.vpcId --output text)
  KUBECONFIG=$(mktemp)
  export KUBECONFIG
  trap 'rm -f "$KUBECONFIG"' EXIT
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

  log "Deleting Argo CD applications (cascades to everything they deployed)"
  kubectl -n argocd delete applications.argoproj.io --all --wait=false 2>/dev/null || true
  for _ in $(seq 1 60); do
    left=$(kubectl -n argocd get applications.argoproj.io -o name 2>/dev/null | wc -l || echo 0)
    [[ "$left" -eq 0 ]] && break
    sleep 5
  done

  log "Deleting any remaining Ingresses (-> ALBs)"
  kubectl delete ingress --all --all-namespaces --timeout=180s 2>/dev/null || true

  log "Deleting Prometheus and its volumes (-> EBS)"
  kubectl -n monitoring delete prometheus --all --timeout=180s 2>/dev/null || true
  kubectl -n monitoring delete pvc --all --timeout=180s 2>/dev/null || true

  log "Waiting for AWS to delete the load balancers in ${VPC_ID}"
  for _ in $(seq 1 60); do
    n=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" --output text)
    [[ "$n" == "0" ]] && break
    echo "   ${n} load balancer(s) still deleting..."
    sleep 10
  done
else
  log "Cluster ${CLUSTER} not found -- skipping Kubernetes cleanup"
fi

log "terraform destroy (${ENV})"
"$TF" -chdir="$TF_DIR" destroy -auto-approve -input=false -lock-timeout=10m

log "Checking for orphaned EBS volumes from this environment"
orphans=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" "Name=tag:KubernetesCluster,Values=${CLUSTER}" \
  --query 'Volumes[].VolumeId' --output text)
if [[ -n "$orphans" ]]; then
  echo "   deleting: $orphans"
  for v in $orphans; do aws ec2 delete-volume --region "$REGION" --volume-id "$v"; done
fi

log "Done. ${ENV} is gone. Nothing from it should be billing now."
