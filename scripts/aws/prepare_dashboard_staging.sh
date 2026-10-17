#!/usr/bin/env bash
#
# Prepare the local L12 dashboard to use the staging AWS API and optional S3 evidence.
#
# Reads Terraform outputs and verifies the public API health endpoint. Emits
# `export` lines for API_BASE_URL (and, with --download-s3-artifacts, also
# RESPONSIBLE_DIR / MODEL_CARDS_DIR / DRIFT_DIR / S3_SOURCE_MANIFEST) pointing
# the local Streamlit dashboard at the deployed stack and its S3 evidence.
#
# Unlike the PowerShell original (which sets the variables in its own process),
# a bash child cannot modify the caller's environment. Progress therefore goes
# to stderr and the export lines go to stdout. Apply them to the current shell:
#
#     eval "$(scripts/aws/prepare_dashboard_staging.sh)"
#     eval "$(scripts/aws/prepare_dashboard_staging.sh --download-s3-artifacts)"
#
# With --download-s3-artifacts this also downloads the latest fairness evidence
# (CI/CD bucket, dashboard/responsible/latest/) and the drift reports
# (monitoring bucket, drift-reports/) into an isolated local cache under
# artifacts/aws-showcase/, and retains an l12-s3-sources manifest (ETags, sizes,
# version IDs) under artifacts/verification/.
#
# Usage:
#   scripts/aws/prepare_dashboard_staging.sh [--region us-east-1] [--download-s3-artifacts]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"
CACHE_ROOT="$REPO_ROOT/artifacts/aws-showcase"
VERIFICATION_DIR="$REPO_ROOT/artifacts/verification"

REGION="${AWS_REGION:-us-east-1}"
DOWNLOAD=0

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -d|--download-s3-artifacts) DOWNLOAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in terraform aws python3 curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool '$tool' not found on PATH." >&2; exit 1; }
done
cd "$REPO_ROOT"

# --- resolve and verify the staging API ---------------------------------------
apiUrl="$(terraform -chdir="$TF_DIR" output -raw api_url)"
[[ -n "$apiUrl" ]] || { echo "Terraform output api_url is empty." >&2; exit 1; }
while [[ "$apiUrl" == */ ]]; do apiUrl="${apiUrl%/}"; done

echo "==> Verifying staging API at $apiUrl" >&2
health="$(curl -fsS --max-time 60 "$apiUrl/health")" \
  || { echo "Failed to reach $apiUrl/health" >&2; exit 1; }
API_URL="$apiUrl" HEALTH_JSON="$health" python3 - <<'PY' || exit 1
import json, os, sys

h = json.loads(os.environ["HEALTH_JSON"])
if (h.get("status") != "ok"
        or not h.get("demand_model_loaded")
        or not h.get("fare_model_loaded")):
    sys.stderr.write("The staging API responded but did not report both models ready.\n")
    sys.exit(1)
for key in ("status", "demand_model_loaded", "fare_model_loaded", "history_hours", "zones"):
    print(f"{key} : {h.get(key)}", file=sys.stderr)
PY

responsibleCache=""
driftCache=""
manifestPath=""

if [[ "$DOWNLOAD" -eq 1 ]]; then
  cicdBucket="$(terraform -chdir="$TF_DIR" output -raw cicd_artifacts_bucket)"
  monitoringBucket="$(terraform -chdir="$TF_DIR" output -raw monitoring_bucket)"
  [[ -n "$cicdBucket" ]] || { echo "Terraform output cicd_artifacts_bucket is empty." >&2; exit 1; }
  [[ -n "$monitoringBucket" ]] || { echo "Terraform output monitoring_bucket is empty." >&2; exit 1; }

  responsibleCache="$CACHE_ROOT/responsible"
  driftCache="$CACHE_ROOT/drift"
  mkdir -p "$responsibleCache" "$driftCache" "$VERIFICATION_DIR"

  echo "==> Downloading latest fairness evidence" >&2
  aws s3 sync "s3://$cicdBucket/dashboard/responsible/latest" "$responsibleCache" \
      --region "$REGION" --only-show-errors --delete \
    || { echo "Failed to download the latest fairness evidence." >&2; exit 1; }

  echo "==> Downloading drift evidence" >&2
  aws s3 sync "s3://$monitoringBucket/drift-reports" "$driftCache" \
      --region "$REGION" --only-show-errors --delete \
    || { echo "Failed to download the drift evidence." >&2; exit 1; }

  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  NDJSON="$WORKDIR/sources.ndjson"
  : > "$NDJSON"

  for spec in "fairness|$cicdBucket|dashboard/responsible/latest/" \
              "drift|$monitoringBucket|drift-reports/"; do
    IFS='|' read -r kind bucket prefix <<<"$spec"
    echo "==> Verifying S3 evidence under s3://$bucket/$prefix" >&2
    KIND="$kind" BUCKET="$bucket" PREFIX="$prefix" REGION="$REGION" NDJSON="$NDJSON" \
    python3 - <<'PY' || exit 1
import json, os, subprocess, sys

region = os.environ["REGION"]

def run_aws(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)

listing = run_aws(["aws", "s3api", "list-objects-v2",
                   "--bucket", os.environ["BUCKET"],
                   "--prefix", os.environ["PREFIX"],
                   "--region", region, "--output", "json"])
with open(os.environ["NDJSON"], "a") as out:
    for obj in listing.get("Contents", []):
        head = run_aws(["aws", "s3api", "head-object",
                        "--bucket", os.environ["BUCKET"],
                        "--key", obj["Key"],
                        "--region", region, "--output", "json"])
        entry = {
            "evidence_kind": head.get("Metadata", {}).get("evidence-kind")
                             or os.environ["KIND"],
            "s3_uri": "s3://{}/{}".format(os.environ["BUCKET"], obj["Key"]),
            "etag": head.get("ETag"),
            "content_length": head.get("ContentLength"),
            "last_modified": head.get("LastModified"),
            "version_id": head.get("VersionId"),
            "metadata": head.get("Metadata"),
        }
        out.write(json.dumps(entry) + "\n")
PY
  done

  checkedAt="$(date -u +%Y%m%dT%H%M%SZ)"
  manifestPath="$VERIFICATION_DIR/l12-s3-sources-$checkedAt.json"
  API_URL="$apiUrl" CHECKED_AT="$checkedAt" NDJSON="$NDJSON" MANIFEST="$manifestPath" \
  python3 - <<'PY'
import json, os

sources = [json.loads(line) for line in open(os.environ["NDJSON"]) if line.strip()]
manifest = {
    "api_url": os.environ["API_URL"],
    "checked_at": os.environ["CHECKED_AT"],
    "sources": sources,
}
with open(os.environ["MANIFEST"], "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
fi

# --- emit the environment for the caller's shell (stdout) ---------------------
echo "export API_BASE_URL='$apiUrl'"
if [[ "$DOWNLOAD" -eq 1 ]]; then
  echo "export RESPONSIBLE_DIR='$responsibleCache'"
  echo "export MODEL_CARDS_DIR='$responsibleCache'"
  echo "export DRIFT_DIR='$driftCache'"
  echo "export S3_SOURCE_MANIFEST='$manifestPath'"
fi
echo "Apply with: eval \"\$(scripts/aws/prepare_dashboard_staging.sh ...)\"" >&2
echo "OK: start Streamlit from a shell with the exported environment." >&2
