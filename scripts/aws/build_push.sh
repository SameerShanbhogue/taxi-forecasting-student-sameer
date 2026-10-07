#!/usr/bin/env bash
#
# Build the self-contained API image and push it to Amazon ECR.
#
# 1. Regenerates the container-ready MLflow DB (mlflow.container.db) so baked
#    artifact paths resolve at /app/mlruns inside the Linux image.
# 2. Logs Docker in to ECR.
# 3. Builds docker/Dockerfile and pushes <repo>:<tag>.
#
# Requires: AWS CLI, Docker, and the project venv (for the portability script).
# Called by deploy.sh, or run standalone once the ECR repo exists.
#
# Usage:
#   scripts/aws/build_push.sh [--region us-east-1] [--tag latest] [--repo-url URL]
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

PYTHON="$REPO_ROOT/.venv/bin/python"
[[ -x "$PYTHON" ]] || PYTHON="python3"

cd "$REPO_ROOT"

echo "==> Generating portable MLflow DB (mlflow.container.db)"
"$PYTHON" scripts/make_mlflow_portable.py --src mlflow.db --dest mlflow.container.db --new-base "file:///app/mlruns"

if [[ -z "$REPO_URL" ]]; then
  echo "==> Reading ECR repository URL from Terraform output"
  REPO_URL="$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url)"
fi
[[ -n "$REPO_URL" ]] || { echo "Could not determine ECR repository URL." >&2; exit 1; }
REGISTRY="${REPO_URL%%/*}"
IMAGE="${REPO_URL}:${TAG}"

echo "==> Logging in to ECR: $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Building image $IMAGE"
docker build -f docker/Dockerfile -t "$IMAGE" .

echo "==> Pushing image $IMAGE"
docker push "$IMAGE"

echo "OK: pushed $IMAGE"
