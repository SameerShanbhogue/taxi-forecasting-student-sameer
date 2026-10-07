#!/usr/bin/env bash
#
# Tear down all AWS resources created by the deploy (stops all charges).
#
# Runs `terraform destroy`. ECR (force_delete) and ECS are removed, so no
# Fargate/ALB charges continue. Requires Terraform, AWS CLI and credentials.
#
# Usage:
#   scripts/aws/destroy.sh [--region us-east-1] [--tag latest]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"
TAG="latest"

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v terraform >/dev/null 2>&1 || { echo "Required tool 'terraform' not found on PATH." >&2; exit 1; }

cd "$REPO_ROOT"

echo "==> terraform destroy (region $REGION)"
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve \
  -var "aws_region=$REGION" -var "image_tag=$TAG"

echo "All resources destroyed. Charges stopped."
