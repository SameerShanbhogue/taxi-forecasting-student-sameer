#!/usr/bin/env bash
#
# Publish L11 fairness evidence to S3 and retain object metadata for review.
#
# Uploads each fairness report, SHAP summary, and model card to both a stable
# latest prefix and an immutable UTC-stamped prefix in the CI/CD artifacts
# bucket. S3 head-object responses for the immutable objects are saved as a
# JSON manifest under artifacts/verification/.
#
# Usage:
#   scripts/aws/publish_fairness_evidence.sh \
#     [--region us-east-1] [--bucket NAME] [--version VERSION]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"
VERIFICATION_DIR="$REPO_ROOT/artifacts/verification"

REGION="${AWS_REGION:-us-east-1}"
BUCKET=""
VERSION="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -b|--bucket) BUCKET="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "Required tool 'aws' not found on PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Required tool 'python3' not found on PATH." >&2; exit 1; }
cd "$REPO_ROOT"

# problem | evidence kind | local path (relative to the repository root)
ITEMS=(
  "demand|fairness-report|artifacts/responsible/demand_fairness.json"
  "fare|fairness-report|artifacts/responsible/fare_fairness.json"
  "demand|shap-summary|artifacts/responsible/demand_shap_summary.png"
  "fare|shap-summary|artifacts/responsible/fare_shap_summary.png"
  "demand|model-card|docs/model_cards/demand.md"
  "fare|model-card|docs/model_cards/fare.md"
)

if [[ -z "$BUCKET" ]]; then
  command -v terraform >/dev/null 2>&1 || { echo "Required tool 'terraform' not found on PATH." >&2; exit 1; }
  echo "==> Reading CI/CD artifacts bucket from Terraform output"
  BUCKET="$(terraform -chdir="$TF_DIR" output -raw cicd_artifacts_bucket)"
fi
[[ -n "$BUCKET" ]] || { echo "Could not determine the CI/CD artifacts bucket." >&2; exit 1; }

if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Version may contain only letters, numbers, periods, underscores, and hyphens." >&2
  exit 1
fi

mkdir -p "$VERIFICATION_DIR"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
NDJSON="$WORKDIR/manifest.ndjson"
: > "$NDJSON"

for item in "${ITEMS[@]}"; do
  IFS='|' read -r problem kind path <<<"$item"
  source="$REPO_ROOT/$path"
  [[ -f "$source" ]] || { echo "Required L11 artifact is missing: $path" >&2; exit 1; }

  fileName="${path##*/}"
  latestKey="dashboard/responsible/latest/$fileName"
  versionedKey="dashboard/responsible/versions/$VERSION/$fileName"
  metadata="lesson=l11,problem=$problem,evidence-kind=$kind,evidence-version=$VERSION"

  echo "==> Uploading $fileName"
  aws s3 cp "$source" "s3://$BUCKET/$latestKey" \
      --region "$REGION" --metadata "$metadata" --only-show-errors \
    || { echo "Failed to upload s3://$BUCKET/$latestKey" >&2; exit 1; }
  aws s3 cp "$source" "s3://$BUCKET/$versionedKey" \
      --region "$REGION" --metadata "$metadata" --only-show-errors \
    || { echo "Failed to upload s3://$BUCKET/$versionedKey" >&2; exit 1; }

  headFile="$WORKDIR/head.json"
  aws s3api head-object --bucket "$BUCKET" --key "$versionedKey" \
      --region "$REGION" --output json > "$headFile" \
    || { echo "Failed to read metadata for s3://$BUCKET/$versionedKey" >&2; exit 1; }

  PROBLEM="$problem" KIND="$kind" BUCKET="$BUCKET" KEY="$versionedKey" HEAD_FILE="$headFile" \
  python3 - >> "$NDJSON" <<'PY'
import json, os

head = json.load(open(os.environ["HEAD_FILE"]))
entry = {
    "problem": os.environ["PROBLEM"],
    "evidence_kind": os.environ["KIND"],
    "s3_uri": "s3://{}/{}".format(os.environ["BUCKET"], os.environ["KEY"]),
    "etag": head.get("ETag"),
    "content_length": head.get("ContentLength"),
    "last_modified": head.get("LastModified"),
    "version_id": head.get("VersionId"),
    "metadata": head.get("Metadata"),
}
print(json.dumps(entry))
PY
done

MANIFEST_PATH="$VERIFICATION_DIR/l11-fairness-s3-$VERSION.json"
python3 - "$NDJSON" "$MANIFEST_PATH" <<'PY'
import json, sys

entries = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
with open(sys.argv[2], "w") as f:
    json.dump(entries, f, indent=2)
    f.write("\n")
PY

echo "OK: published L11 evidence version $VERSION to s3://$BUCKET/dashboard/responsible/"
echo "OK: retained object metadata in $MANIFEST_PATH"
