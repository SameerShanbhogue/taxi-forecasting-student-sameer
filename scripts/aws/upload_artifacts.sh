#!/usr/bin/env bash
#
# Upload the baked build artifacts CodeBuild needs into the CI/CD S3 bucket.
#
# The self-contained API image bakes in mlruns/, mlflow.db and the demand-history
# parquet, which are gitignored and therefore absent from CodeBuild's checkout.
# This uploads them to the CI/CD artifacts bucket (Terraform output
# `cicd_artifacts_bucket`) so the CodeBuild `build` phase can pull them.
#
# Re-run this whenever you retrain the models locally.
#
# Usage:
#   scripts/aws/upload_artifacts.sh [--region us-east-1] [--bucket NAME]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"
BUCKET=""

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -b|--bucket) BUCKET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "Required tool 'aws' not found on PATH." >&2; exit 1; }
cd "$REPO_ROOT"

if [[ -z "$BUCKET" ]]; then
  command -v terraform >/dev/null 2>&1 || { echo "Required tool 'terraform' not found on PATH." >&2; exit 1; }
  echo "==> Reading CI/CD artifacts bucket from Terraform output"
  BUCKET="$(terraform -chdir="$TF_DIR" output -raw cicd_artifacts_bucket)"
fi
[[ -n "$BUCKET" ]] || { echo "Could not determine the CI/CD artifacts bucket." >&2; exit 1; }

for p in mlruns mlflow.db data/processed/demand_hourly.parquet; do
  [[ -e "$p" ]] || { echo "Missing '$p'. Train the models first (python scripts/train_models.py)." >&2; exit 1; }
done

echo "==> Uploading artifacts to s3://$BUCKET"
aws s3 sync mlruns "s3://$BUCKET/mlruns" --region "$REGION" --only-show-errors
aws s3 cp mlflow.db "s3://$BUCKET/mlflow.db" --region "$REGION" --only-show-errors
aws s3 cp data/processed/demand_hourly.parquet "s3://$BUCKET/demand_hourly.parquet" --region "$REGION" --only-show-errors

echo "OK: artifacts uploaded to s3://$BUCKET"
