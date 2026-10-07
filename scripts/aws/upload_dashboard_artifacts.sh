#!/usr/bin/env bash
#
# Seed the CI/CD artifacts bucket with the gitignored static files the
# dashboard image bakes in (Responsible-AI reports, drift reports, taxi zone
# lookup).
#
# The dashboard image (docker/Dockerfile.dashboard) COPYs artifacts/responsible/,
# artifacts/drift/, and data/raw/taxi_zone_lookup.csv, which are gitignored and
# therefore absent from the CodeBuild GitHub checkout. buildspec-dashboard.yml
# pulls them from s3://<cicd_artifacts_bucket>/dashboard/ at build time. Run this
# once (and again whenever those artifacts change).
#
# Usage:
#   scripts/aws/upload_dashboard_artifacts.sh [--region us-east-1]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

REGION="${AWS_REGION:-us-east-1}"

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "Required tool 'aws' not found on PATH." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Required tool 'terraform' not found on PATH." >&2; exit 1; }
cd "$REPO_ROOT"

echo "==> Reading CI/CD artifacts bucket from Terraform output"
BUCKET="$(terraform -chdir="$TF_DIR" output -raw cicd_artifacts_bucket)"
[[ -n "$BUCKET" ]] || { echo "cicd_artifacts_bucket output is empty; is enable_cicd applied?" >&2; exit 1; }

echo "==> Uploading dashboard artifacts to s3://$BUCKET/dashboard"
aws s3 sync "$REPO_ROOT/artifacts/responsible" "s3://$BUCKET/dashboard/responsible" --region "$REGION" --only-show-errors
aws s3 sync "$REPO_ROOT/artifacts/drift" "s3://$BUCKET/dashboard/drift" --region "$REGION" --only-show-errors
aws s3 cp "$REPO_ROOT/data/raw/taxi_zone_lookup.csv" "s3://$BUCKET/dashboard/taxi_zone_lookup.csv" --region "$REGION" --only-show-errors

echo "OK: dashboard artifacts uploaded to s3://$BUCKET/dashboard"
