#!/usr/bin/env bash
#
# One-command AWS deploy: provision infra, push the image, roll out the API.
#
# Handles the ECR chicken-and-egg problem by applying in two phases:
#   1. terraform apply (ECR repository only)
#   2. build + push the self-contained image into ECR (build_push.sh)
#   3. terraform apply (ECS service, ALB, everything else)
#   4. force a new ECS deployment so the task picks up the pushed image
#   5. print the public ALB URL
#
# Requires: Terraform, AWS CLI, Docker, and AWS credentials in the environment
# (AWS_PROFILE set, or `aws configure`).
#
# WARNING: this creates billable resources (Fargate + ALB, ~$25-35/month).
# Run scripts/aws/destroy.sh to tear everything down.
#
# Usage:
#   scripts/aws/deploy.sh [--region us-east-1] [--tag latest] \
#     [--var-file infra/terraform/staging.tfvars] [--allow-destroy]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"
TAG="latest"
VAR_FILE=""
ALLOW_DESTROY=0

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    --var-file) VAR_FILE="$2"; shift 2 ;;
    --allow-destroy) ALLOW_DESTROY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in terraform aws docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool '$tool' not found on PATH." >&2; exit 1; }
done

cd "$REPO_ROOT"

TF_ARGS=(-var "aws_region=$REGION" -var "image_tag=$TAG")
if [[ -n "$VAR_FILE" ]]; then
  [[ -f "$REPO_ROOT/$VAR_FILE" ]] || { echo "Variable file not found: $VAR_FILE" >&2; exit 1; }
  TF_ARGS+=(-var-file="$REPO_ROOT/$VAR_FILE")
fi

echo "==> terraform init"
terraform -chdir="$TF_DIR" init -input=false

echo "==> Step 1: create ECR repository"
terraform -chdir="$TF_DIR" apply -input=false -auto-approve -target=aws_ecr_repository.api "${TF_ARGS[@]}"

REPO_URL="$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url)"
echo "==> Step 2: build & push image to $REPO_URL"
"$SCRIPT_DIR/build_push.sh" --region "$REGION" --tag "$TAG" --repo-url "$REPO_URL"

echo "==> Step 3: apply full infrastructure"
PLAN_PATH="/tmp/taxi-forecasting-deploy.tfplan"
rm -f "$PLAN_PATH"
terraform -chdir="$TF_DIR" plan -input=false -out="$PLAN_PATH" "${TF_ARGS[@]}"

DELETES="$(terraform -chdir="$TF_DIR" show -json "$PLAN_PATH" | python3 -c '
import json, sys
plan = json.load(sys.stdin)
print(sum(1 for r in plan.get("resource_changes", [])
          if "delete" in (r.get("change") or {}).get("actions", [])))
')"
if [[ "$DELETES" -gt 0 && "$ALLOW_DESTROY" -ne 1 ]]; then
  rm -f "$PLAN_PATH"
  echo "Refusing a plan with $DELETES delete action(s). Review variables and state; use --allow-destroy only for an intentional teardown." >&2
  exit 1
fi

terraform -chdir="$TF_DIR" apply -input=false -auto-approve "$PLAN_PATH"
rm -f "$PLAN_PATH"

CLUSTER="$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)"
SERVICE="$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)"
echo "==> Step 4: force new ECS deployment"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --force-new-deployment --region "$REGION" >/dev/null

URL="$(terraform -chdir="$TF_DIR" output -raw api_url)"
echo ""
echo "Deployed. API URL: $URL"
echo "It may take 1-3 minutes for the task to become healthy."
echo "Check:  curl $URL/health"
echo "Teardown: scripts/aws/destroy.sh --region $REGION"
