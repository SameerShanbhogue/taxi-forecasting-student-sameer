#!/usr/bin/env bash
#
# Build the Streamlit dashboard image and push it to Amazon ECR.
#
# 1. Logs Docker in to ECR.
# 2. Builds docker/Dockerfile.dashboard and pushes <repo>:<tag>.
#
# The dashboard image is stateless (no models / MLflow); it talks to the API
# over HTTP via API_BASE_URL, which the Terraform task definition injects.
#
# Requires: AWS CLI, Docker, Terraform. Run after `enable_dashboard=true` has
# been applied so the dashboard ECR repo exists.
#
# Usage:
#   scripts/aws/build_push_dashboard.sh [--region us-east-1] [--tag latest] [--repo-url URL]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"
TAG="latest"
REPO_URL=""

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in aws docker terraform; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool '$tool' not found on PATH." >&2; exit 1; }
done

cd "$REPO_ROOT"

if [[ -z "$REPO_URL" ]]; then
  echo "==> Reading dashboard ECR repository URL from Terraform output"
  REPO_URL="$(terraform -chdir="$TF_DIR" output -raw dashboard_ecr_repository_url)"
fi
[[ -n "$REPO_URL" ]] || { echo "Could not determine dashboard ECR repository URL (is enable_dashboard applied?)." >&2; exit 1; }
REGISTRY="${REPO_URL%%/*}"
IMAGE="${REPO_URL}:${TAG}"

echo "==> Logging in to ECR: $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Building dashboard image $IMAGE"
docker build -f docker/Dockerfile.dashboard -t "$IMAGE" .

echo "==> Pushing dashboard image $IMAGE"
docker push "$IMAGE"

echo "OK: pushed $IMAGE"
