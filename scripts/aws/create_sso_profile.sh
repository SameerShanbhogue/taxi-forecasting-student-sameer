#!/usr/bin/env bash
#
# Create (or update) an AWS IAM Identity Center (SSO) profile in ~/.aws/config
# and sign in.
#
# Writes an [sso-session] block plus a [profile] block, runs `aws sso login`,
# then discovers the account and role automatically when they are not supplied.
#
# Requires: AWS CLI v2 and Python 3. The only interactive part is the browser
# SSO approval.
#
# Usage:
#   scripts/aws/create_sso_profile.sh \
#     --start-url https://d-9f67587607.awsapps.com/start \
#     --sso-region ap-south-1 \
#     [--profile week5-lab] [--region ap-south-1] \
#     [--account-id 123456789012] [--role-name AdministratorAccess] \
#     [--device-code]
#
set -euo pipefail

PROFILE="week5-lab"
START_URL=""
SSO_REGION="ap-south-1"
CLI_REGION=""
ACCOUNT_ID=""
ROLE_NAME=""
DEVICE_CODE=0

usage() {
  awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); if (length($0)) print; next } else exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --start-url) START_URL="$2"; shift 2 ;;
    --sso-region) SSO_REGION="$2"; shift 2 ;;
    --region) CLI_REGION="$2"; shift 2 ;;
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --role-name) ROLE_NAME="$2"; shift 2 ;;
    --device-code) DEVICE_CODE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$CLI_REGION" ]] || CLI_REGION="$SSO_REGION"
command -v aws >/dev/null 2>&1 || { echo "Required tool 'aws' not found on PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Required tool 'python3' not found on PATH." >&2; exit 1; }
[[ -n "$START_URL" ]] || { echo "--start-url is required (e.g. https://d-9f67587607.awsapps.com/start)." >&2; exit 1; }

# --- write the sso-session + profile blocks -------------------------------
write_profile() {
  local acct="$1" role="$2"
  PROFILE="$PROFILE" START_URL="$START_URL" SSO_REGION="$SSO_REGION" \
  CLI_REGION="$CLI_REGION" ACCOUNT_ID="$acct" ROLE_NAME="$role" python3 - <<'PY'
import os, pathlib

cfg = pathlib.Path(os.environ.get("AWS_CONFIG_FILE") or (pathlib.Path.home() / ".aws" / "config"))
cfg.parent.mkdir(parents=True, exist_ok=True)
text = cfg.read_text() if cfg.exists() else ""

profile = os.environ["PROFILE"]
remove = {f"[sso-session {profile}]", f"[profile {profile}]",
          f"[profile 'sso-session {profile}']"}

out, skip = [], False
for line in text.splitlines():
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        skip = s in remove
    if not skip:
        out.append(line)
while out and not out[-1].strip():
    out.pop()

block = [
    f"[sso-session {profile}]",
    f"sso_start_url = {os.environ['START_URL']}",
    f"sso_region = {os.environ['SSO_REGION']}",
    "sso_registration_scopes = sso:account:access",
    "",
    f"[profile {profile}]",
    f"sso_session = {profile}",
]
if os.environ.get("ACCOUNT_ID"):
    block.append(f"sso_account_id = {os.environ['ACCOUNT_ID']}")
if os.environ.get("ROLE_NAME"):
    block.append(f"sso_role_name = {os.environ['ROLE_NAME']}")
block += [f"region = {os.environ['CLI_REGION']}", "output = json"]

out.append("")
out.extend(block)
if cfg.exists():
    cfg.with_suffix(".bak").write_text(text)
cfg.write_text("\n".join(out).lstrip("\n") + "\n")
print(f"Wrote profile '{profile}' to {cfg}")
PY
}

# --- discover account / role from the cached SSO token ---------------------
discover() {
  local token accounts roles
  token="$(START_URL="$START_URL" SSO_REGION="$SSO_REGION" python3 - <<'PY'
import glob, json, os, pathlib
cfg = pathlib.Path(os.environ.get("AWS_CONFIG_FILE") or (pathlib.Path.home() / ".aws" / "config"))
cache = cfg.parent / "sso" / "cache"
for f in glob.glob(str(cache / "*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if (d.get("startUrl") == os.environ["START_URL"]
            and d.get("region") == os.environ["SSO_REGION"]
            and d.get("accessToken")):
        print(d["accessToken"])
        break
PY
)"
  [[ -n "$token" ]] || { echo "Could not find a cached SSO token for $START_URL." >&2; exit 1; }

  accounts="$(aws sso list-accounts --access-token "$token" --region "$SSO_REGION" \
    --query 'accountList[].accountId' --output text)"
  local count
  count="$(wc -w <<<"$accounts")"
  if [[ "$count" -eq 0 ]]; then
    echo "SSO returned no accounts." >&2; exit 1
  elif [[ "$count" -gt 1 ]]; then
    echo "Multiple accounts available: $accounts" >&2
    echo "Re-run with --account-id <id>." >&2; exit 1
  fi
  ACCOUNT_ID="$accounts"

  roles="$(aws sso list-account-roles --access-token "$token" --account-id "$ACCOUNT_ID" \
    --region "$SSO_REGION" --query 'roleList[].roleName' --output text)"
  count="$(wc -w <<<"$roles")"
  if [[ "$count" -eq 0 ]]; then
    echo "No roles available for account $ACCOUNT_ID." >&2; exit 1
  elif [[ "$count" -gt 1 ]]; then
    echo "Multiple roles available: $roles" >&2
    echo "Re-run with --account-id $ACCOUNT_ID --role-name <role>." >&2; exit 1
  fi
  ROLE_NAME="$roles"
}

# --- run -------------------------------------------------------------------
echo "==> Writing SSO session and profile"
write_profile "$ACCOUNT_ID" "$ROLE_NAME"

echo "==> Signing in to AWS SSO (profile: $PROFILE)"
if [[ "$DEVICE_CODE" -eq 1 ]]; then
  aws sso login --profile "$PROFILE" --use-device-code
else
  aws sso login --profile "$PROFILE"
fi

if [[ -z "$ACCOUNT_ID" || -z "$ROLE_NAME" ]]; then
  echo "==> Discovering account and role"
  discover
  echo "==> Finalizing profile with account $ACCOUNT_ID and role $ROLE_NAME"
  write_profile "$ACCOUNT_ID" "$ROLE_NAME"
  aws sso login --profile "$PROFILE" >/dev/null
fi

echo "==> Verifying identity"
export AWS_PROFILE="$PROFILE" AWS_REGION="$CLI_REGION" AWS_DEFAULT_REGION="$CLI_REGION"
aws sts get-caller-identity

echo
echo "OK. In new shells use:"
echo "  export AWS_PROFILE=$PROFILE AWS_REGION=$CLI_REGION AWS_DEFAULT_REGION=$CLI_REGION"
