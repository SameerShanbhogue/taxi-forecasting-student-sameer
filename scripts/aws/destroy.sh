#!/usr/bin/env bash
#
# Tear down all AWS resources created by the deploy (stops all charges).
#
# Runs `terraform destroy`. ECR (force_delete) and ECS are removed, so no
# Fargate/ALB charges continue. Requires Terraform, AWS CLI and credentials.
#
# Pass the same --var-file used for the deploy so resource names, feature
# counts and provider config match the state being destroyed (mirrors
# deploy.sh). While enable_cicd=true remains in that file, also export
# TF_VAR_github_token first (it is needed while the CodeBuild resources are
# planned for destruction).
#
# Usage:
#   scripts/aws/destroy.sh [--region us-east-1] [--tag latest] \
#     [--var-file infra/terraform/student-codebuild.tfvars]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"
TAG="latest"
VAR_FILE=""

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    -f|--var-file) VAR_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in terraform aws; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool '$tool' not found on PATH." >&2; exit 1; }
done

cd "$REPO_ROOT"

TF_ARGS=(-var "aws_region=$REGION" -var "image_tag=$TAG")
if [[ -n "$VAR_FILE" ]]; then
  [[ -f "$REPO_ROOT/$VAR_FILE" ]] || { echo "Variable file not found: $VAR_FILE" >&2; exit 1; }
  TF_ARGS+=(-var-file="$REPO_ROOT/$VAR_FILE")
fi

echo "==> terraform destroy (region $REGION)"
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve "${TF_ARGS[@]}"

echo "All resources destroyed. Charges stopped."
