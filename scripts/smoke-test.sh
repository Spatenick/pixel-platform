#!/usr/bin/env bash
# End-to-end check of a deployed environment: upload an image through the ALB
# and wait for the worker to turn it into a thumbnail.
#
#   ./scripts/smoke-test.sh dev
#   BASE_URL=https://api.dev.example.com ./scripts/smoke-test.sh dev
set -euo pipefail

ENV=${1:-dev}
REGION=${AWS_REGION:-eu-west-2}

if [[ -z "${BASE_URL:-}" ]]; then
  KUBECONFIG=$(mktemp)
  export KUBECONFIG
  trap 'rm -f "$KUBECONFIG"' EXIT
  aws eks update-kubeconfig --name "pixelpipe-${ENV}" --region "$REGION" >/dev/null
  host=""
  for _ in $(seq 1 30); do
    host=$(kubectl -n pixelpipe get ingress pixelpipe-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [[ -n "$host" ]] && break
    echo "waiting for the ALB hostname..."
    sleep 10
  done
  [[ -n "$host" ]] || { echo "no ALB hostname yet -- is Argo CD synced?"; exit 1; }
  BASE_URL="http://${host}"
fi

echo "Testing ${BASE_URL}"

# A new ALB's DNS name can take a couple of minutes to resolve.
for _ in $(seq 1 30); do
  curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1 && break
  echo "waiting for ${BASE_URL}/healthz ..."
  sleep 10
done
curl -fsS "${BASE_URL}/healthz" && echo

# 1x1 red PNG
img=$(mktemp -t pixelpipe-smoke.XXXXXX)
base64 -d > "$img" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=='

json_field() { python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

id=$(curl -fsS -F "file=@${img};type=image/png;filename=smoke.png" "${BASE_URL}/v1/images" | json_field id)
echo "uploaded image ${id}"

for _ in $(seq 1 30); do
  status=$(curl -fsS "${BASE_URL}/v1/images/${id}" | json_field status)
  echo "  status=${status}"
  case "$status" in
    done) echo "SMOKE TEST PASSED"; exit 0 ;;
    failed) echo "SMOKE TEST FAILED: job failed"; exit 1 ;;
  esac
  sleep 5 # first job may wait for KEDA to scale the worker from zero
done

echo "SMOKE TEST FAILED: thumbnail not ready after 150s"
exit 1
