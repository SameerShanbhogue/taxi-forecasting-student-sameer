# AWS Setup, Deploy, Run, and Remove on Linux with CodeBuild

**Linux/bash port of the Week 5 command guide.** This mirrors the hosted release
route used by the course API, but replaces every PowerShell-specific step with a
Debian/Ubuntu (bash) equivalent.

This guide uses:

```text
GitHub
  -> AWS CodeBuild
  -> Docker runs inside CodeBuild
  -> image pushed to ECR
  -> ECS service rollout
  -> ALB public API
```

You do **not** need Docker on your Linux workstation for this route. You need:

- your own authorized AWS account;
- your own GitHub repository containing this project;
- AWS CLI v2;
- Terraform >= 1.5;
- Git;
- the Python 3.11 environment and trained model artifacts.

The deployment creates billable AWS resources. Use only an authorized account and
reserve time for teardown.

## Differences from the Windows guide

| Concern | Windows guide | This Linux guide |
| --- | --- | --- |
| Virtualenv | `.\.venv\Scripts\python.exe` | `.venv/bin/python` |
| Env vars | `$env:VAR = "x"` | `export VAR=x` |
| Temp dir | `$env:TEMP` | `/tmp` |
| Artifact upload | `scripts/aws/upload_artifacts.ps1` | inline `aws s3` commands (below) |
| Build wait loop | PowerShell `do/while` | bash `while` + `aws ... --query` |
| Health check | `Invoke-RestMethod` | `curl -s ... \| python3 -m json.tool` |
| Open docs | `Start-Process` | `xdg-open` |

> The original `scripts/aws/*.ps1` helpers are PowerShell-only. Bash companions
> are provided next to them (see below), and this document also shows the inline
> equivalents where useful.

## Companion shell helpers

These mirror the PowerShell scripts and take `--region` (default
`us-east-1`, or `AWS_REGION`):

| Bash helper | Mirrors | Purpose |
| --- | --- | --- |
| `scripts/aws/upload_artifacts.sh` | `upload_artifacts.ps1` | Upload `mlruns/`, `mlflow.db`, `demand_hourly.parquet` to the CodeBuild bucket |
| `scripts/aws/build_push.sh` | `build_push.ps1` | Build the self-contained API image and push to ECR |
| `scripts/aws/build_push_dashboard.sh` | `build_push_dashboard.ps1` | Build and push the Streamlit dashboard image |
| `scripts/aws/upload_dashboard_artifacts.sh` | `upload_dashboard_artifacts.ps1` | Seed `dashboard/` static artifacts in the bucket |
| `scripts/aws/deploy.sh` | `deploy.ps1` | Local one-command deploy (requires Docker) |
| `scripts/aws/destroy.sh` | `destroy.ps1` | `terraform destroy` |

Each supports `--help`. The CodeBuild route (Parts H–K) does not need Docker
locally; `deploy.sh`/`build_push.sh` are for the alternative local-Docker route.
The showcase helpers `prepare_dashboard_staging.ps1` and
`publish_fairness_evidence.ps1` remain PowerShell-only.

## Why the First Deployment Has Two Terraform Applies

```text
ECS needs an image in ECR before it can start a task.
CodeBuild needs the AWS build resources before it can create that image.
```

Solved without local Docker:

```text
1. Terraform creates AWS resources with desired_count = 0
2. CodeBuild builds and pushes the first image
3. Terraform changes desired_count from 0 to 1
4. ECS starts the task from the image now stored in ECR
```

Later releases do not need the bootstrap step. A Git push can trigger CodeBuild
directly.

## Part A: Prepare the Repository

### A1. Enter the repository and virtual environment

```bash
cd /path/to/taxi-forecasting-student
source .venv/bin/activate
git status --short
```

If `.venv` does not exist yet, create it first (see Part B3 and
[docs/SETUP.md](SETUP.md)).

### A2. Confirm the repository is in your GitHub account

```bash
git remote -v
git branch --show-current
git push -u origin main
```

The remote must be a repository you administer (CodeBuild clones from it and
registers a webhook). If you deploy from another branch, record it and use the
same value for `deploy_branch`.

### A3. Confirm the current commit

```bash
Commit=$(git rev-parse --short HEAD)
Tag="w5-$Commit"
echo "$Tag"
```

This connects:

```text
Git commit -> CodeBuild source -> ECR image tag -> ECS task definition
```

## Part B: Install and Check Local Tools

### B1. Check what is already installed

```bash
aws --version
terraform version
git --version
.venv/bin/python --version
```

### B2. Install missing tools (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip ca-certificates
```

**AWS CLI v2** (official installer):

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
aws --version
```

> On ARM64 hosts (for example AWS Graviton or Apple silicon VMs), use
> `awscli-exe-linux-aarch64.zip` in the URL above.

**Terraform** (HashiCorp apt repository):

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
terraform version
```

> On distributions that do not ship `lsb_release`, replace `$(lsb_release -cs)`
> with your codename (for example `jammy`). Official reference:
> <https://developer.hashicorp.com/terraform/install>.

### B3. Python 3.11 environment

```bash
python3.11 --version
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

On Ubuntu 22.04 or older, `python3.11` may need the deadsnakes PPA
(`sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt-get install -y
python3.11 python3.11-venv`). Do not install similarly named Python packages with
`pip` for the CLI tools above.

## Part C: Authenticate to AWS

Use exactly one authorized route.

### C1. AWS IAM Identity Center / SSO

```bash
aws configure sso --profile week5-lab
aws sso login --profile week5-lab

export AWS_PROFILE=week5-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

### C2. Temporary AWS lab credentials

Write the temporary values to a named profile in `~/.aws/credentials`:

```ini
[week5-lab]
aws_access_key_id=ENTER_LOCALLY
aws_secret_access_key=ENTER_LOCALLY
aws_session_token=ENTER_LOCALLY
```

Then:

```bash
aws configure set region us-east-1 --profile week5-lab
aws configure set output json --profile week5-lab

export AWS_PROFILE=week5-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

Never put AWS credentials in Git, Terraform variables, documentation,
screenshots, or chat.

### C3. Privately confirm identity

```bash
aws sts get-caller-identity
```

Privately confirm the expected account, the expected role/user, and that this is
not a shared production account. Do not expose the account ID or ARN.

### C4. Region

```bash
Region="us-east-1"
aws configure get region
```

The AWS Console must also be set to **US East (N. Virginia) / us-east-1**.

## Part D: Check AWS and Model Prerequisites

### D1. Confirm the default VPC

Terraform uses the account's default VPC:

```bash
aws ec2 describe-vpcs \
  --region "$Region" \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[].VpcId" --output text
```

Stop if the result is empty. Check the default subnets:

```bash
aws ec2 describe-subnets \
  --region "$Region" \
  --filters "Name=default-for-az,Values=true" \
  --query "Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone}" \
  --output table
```

### D2. Confirm the model build inputs

CodeBuild gets source from GitHub, but the trained model files are not in Git.
They must exist locally before being uploaded to the CodeBuild S3 bucket.

```bash
ls -l mlflow.db data/processed/demand_hourly.parquet
ls mlruns | head
```

Required:

```text
mlflow.db
mlruns/
data/processed/demand_hourly.parquet
```

Stop if any are missing. Complete training and registration first
(`.venv/bin/python -m scripts.run_pipeline --year 2024 --month 1` then
`.venv/bin/python -m scripts.train_models --n-trials 1`; see
[docs/SETUP.md](SETUP.md)).

### D3. The two input sources

```text
GitHub
  -> Python source, Terraform, Dockerfile, buildspec

S3 artifact bucket
  -> mlflow.db
  -> mlruns/
  -> demand_hourly.parquet

CodeBuild combines both
  -> self-contained Docker image
```

## Part E: Prepare GitHub Access for CodeBuild

Terraform creates the CodeBuild project, the GitHub source connection, and the
webhook. The current Terraform implementation expects a personal access token
with access to the repository and permission to administer its webhook. For a
classic token, the required scopes are:

```text
repo
admin:repo_hook
```

Create the token directly in GitHub. Do not send it to anyone or paste it into
chat. Read it into the current shell without echoing it:

```bash
read -rsp "Enter the authorized GitHub token: " TF_VAR_github_token
echo
export TF_VAR_github_token
```

Terraform receives the value through `TF_VAR_github_token`. Do **not** put it in
`student-codebuild.tfvars`.

## Part F: Create the Student CodeBuild Configuration

Create `infra/terraform/student-codebuild.tfvars`:

```hcl
aws_region   = "us-east-1"
project_name = "taxi-w5"
environment  = "student"

desired_count = 1
task_cpu      = 256
task_memory   = 512

enable_cicd       = true
github_repo_url   = "https://github.com/REPLACE_WITH_STUDENT/REPLACE_WITH_REPO.git"
deploy_branch     = "main"

enable_monitoring = false
enable_datalake   = false
enable_athena     = false
enable_dashboard  = false
```

Replace only the GitHub repository URL and, when necessary, the deployment
branch. `.gitignore` excludes `*.tfvars`, so this file stays untracked — keep it
that way.

This creates:

```text
core API:
  ECR + ECS + Fargate + ALB + logs

release path:
  S3 artifact bucket + CodeBuild + GitHub webhook + IAM
```

It does not create the optional monitoring, data-lake, or dashboard stacks.

## Part G: Validate Before Creating Anything

```bash
terraform -chdir=infra/terraform init -input=false
terraform -chdir=infra/terraform fmt student-codebuild.tfvars
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
```

Validation proves structure, not AWS creation.

## Part H: Bootstrap AWS with Zero Running Tasks

### H1. Review the bootstrap plan

The command-line value temporarily overrides `desired_count=1`:

```bash
BootstrapPlan=/tmp/taxi-w5-codebuild-bootstrap.tfplan

terraform -chdir=infra/terraform plan \
  -input=false \
  -out="$BootstrapPlan" \
  -var-file=student-codebuild.tfvars \
  -var "image_tag=$Tag" \
  -var "desired_count=0"
```

Check:

- resource prefix is `taxi-w5-student`;
- CodeBuild and the artifact bucket will be created;
- ECS desired count is zero;
- optional stacks are disabled;
- no unrelated delete action appears.

### H2. Apply the bootstrap plan

```bash
terraform -chdir=infra/terraform apply -input=false "$BootstrapPlan"
```

At this point AWS resources exist, the ECS service exists with
`desired task count = 0`, and no application image has been built yet. This is
expected.

## Part I: Upload Model Artifacts to the CodeBuild Bucket

Use the Linux helper (the bash companion to `upload_artifacts.ps1`):

```bash
scripts/aws/upload_artifacts.sh --region "$Region"
```

It reads the bucket from the Terraform output and uploads `mlruns/`,
`mlflow.db`, and `demand_hourly.parquet`. Inline equivalent:

```bash
Bucket=$(terraform -chdir=infra/terraform output -raw cicd_artifacts_bucket)

aws s3 sync mlruns "s3://$Bucket/mlruns" --region "$Region" --only-show-errors
aws s3 cp mlflow.db "s3://$Bucket/mlflow.db" --region "$Region" --only-show-errors
aws s3 cp data/processed/demand_hourly.parquet \
  "s3://$Bucket/demand_hourly.parquet" --region "$Region" --only-show-errors

echo "Uploaded to s3://$Bucket"
```

Verify only the object count or command success. Do not expose the private bucket
name in screenshots. Re-run this whenever a newly trained model should enter the
next image.

## Part J: Start the First CodeBuild Release

### J1. Read the CodeBuild project name

```bash
CodeBuildProject=$(terraform -chdir=infra/terraform output -raw cicd_project_name)
```

Do not expose the project ARN.

### J2. Start the build

A manual CodeBuild start deploys by default in the current `buildspec.yml`:

```bash
BuildId=$(aws codebuild start-build \
  --region "$Region" \
  --project-name "$CodeBuildProject" \
  --query 'build.id' --output text)
echo "Started build"
```

Do not put the build ID in public evidence because it contains account-specific
context.

### J3. Wait for CodeBuild

```bash
while :; do
  BuildStatus=$(aws codebuild batch-get-builds \
    --region "$Region" --ids "$BuildId" \
    --query 'builds[0].buildStatus' --output text)
  echo "CodeBuild status: $BuildStatus"
  case "$BuildStatus" in
    SUCCEEDED|FAILED|FAULT|STOPPED|TIMED_OUT) break ;;
  esac
  sleep 15
done

[ "$BuildStatus" = "SUCCEEDED" ] || { echo "CodeBuild failed: $BuildStatus"; exit 1; }
```

### J4. What the build does

```text
install
  -> install Python requirements

pre_build
  -> Ruff
  -> pytest + coverage

build
  -> download MLflow files from S3
  -> create portable mlflow.container.db
  -> Docker login to ECR
  -> Docker build inside CodeBuild
  -> Docker push commit-tagged image
  -> also publish latest when needed

post_build
  -> request ECS service update
```

The service still has desired count zero, so no API task starts yet.

### J5. Inspect build logs

```bash
aws codebuild batch-get-builds --region "$Region" --ids "$BuildId" \
  --query 'builds[0].logs.groupName' --output text
```

Or in the Console: **CodeBuild -> Build projects -> taxi-w5-student-ci -> Build
history -> latest build**. Read the failed phase. Do not rerun before
understanding the error.

## Part K: Start the ECS Task

Now that the image exists in ECR, apply the real desired count from the variable
file:

```bash
RunPlan=/tmp/taxi-w5-codebuild-run.tfplan

terraform -chdir=infra/terraform plan \
  -input=false -out="$RunPlan" \
  -var-file=student-codebuild.tfvars \
  -var "image_tag=$Tag"

terraform -chdir=infra/terraform apply -input=false "$RunPlan"
```

This changes `desired_count: 0 -> 1`. ECS can now pull the image CodeBuild pushed
to ECR.

## Part L: Wait for ECS and Read Outputs

```bash
Cluster=$(terraform -chdir=infra/terraform output -raw ecs_cluster_name)
Service=$(terraform -chdir=infra/terraform output -raw ecs_service_name)
ApiUrl=$(terraform -chdir=infra/terraform output -raw api_url)

aws ecs wait services-stable \
  --region "$Region" --cluster "$Cluster" --services "$Service"

aws ecs describe-services \
  --region "$Region" --cluster "$Cluster" --services "$Service" \
  --query "services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}" \
  --output table
```

Expected:

```text
Status  = ACTIVE
Desired = 1
Running = 1
Pending = 0
```

## Part M: Prove the Correct Image Is Running

```bash
TaskDefinition=$(aws ecs describe-services \
  --region "$Region" --cluster "$Cluster" --services "$Service" \
  --query "services[0].taskDefinition" --output text)

aws ecs describe-task-definition \
  --region "$Region" --task-definition "$TaskDefinition" \
  --query "taskDefinition.containerDefinitions[0].image" --output text
```

The image reference should end with `:w5-<current-commit>`. If the task
definition references `latest`, confirm that CodeBuild published both the current
commit image and the matching `latest` manifest before accepting the release.

## Part N: Prove the API Is Ready

### N1. Health body

```bash
curl -s "$ApiUrl/health" | python3 -m json.tool
```

Require:

```text
status = ok
demand_model_loaded = true
fare_model_loaded = true
history_hours > 0
zones > 0
```

HTTP 200 alone is not sufficient because this application can return a degraded
body with HTTP 200.

### N2. Full smoke test

```bash
.venv/bin/python scripts/aws/verify_staging.py --api-url "$ApiUrl" --timeout 60
```

Expected:

```text
passed = true
process exit code = 0
```

The script checks health, fare prediction, demand prediction, recursive forecast,
explanations, metrics, and invalid-input behavior.

### N3. Swagger

```bash
xdg-open "$ApiUrl/docs"
```

Send one fare request and one demand request.

## Part O: Find the Flow in the AWS Console

Use region **US East (N. Virginia) / us-east-1**.

| Console area | Evidence |
| --- | --- |
| CodeBuild | Successful build phases |
| S3 | Build-input objects exist |
| ECR | Commit-tagged image exists |
| ECS cluster | API service is active |
| ECS service | Desired 1, running 1 |
| ECS task | Expected image is running |
| EC2 > Load Balancers | ALB is active |
| Target groups | One target is healthy |
| CloudWatch Logs | Container startup and request logs |

Do not capture: account IDs, ARNs, private bucket names, ECR hostnames, role
names, the GitHub token, temporary credentials, or personal email.

## Part P: Release the Next Code Change

After the first deployment the webhook handles later releases.

### P1. Change, check, commit, push

`ci_local.ps1` is PowerShell-only. On Linux either run it with PowerShell 7, or
run the underlying commands directly:

```bash
.venv/bin/python -m ruff check .
.venv/bin/python -m pytest --cov=src --cov-report=term-missing --cov-report=xml

git add <approved-files>
git commit -m "Describe the approved change"
git push origin main
```

The push starts:

```text
GitHub webhook -> CodeBuild -> Ruff + pytest -> Docker build -> ECR push -> ECS update
```

### P2. Model-only release

After retraining locally, re-upload the artifacts (Part I), then start an
approved CodeBuild release (Part J) or push the corresponding revision.
Uploading artifacts alone does not update ECS.

### P3. Pull requests

The declared webhook runs checks for pull requests. The buildspec does not deploy
a pull-request build because it is not the deployment branch.

## Part Q: Teardown

Teardown is mandatory. The GitHub token environment variable is still required
while `enable_cicd=true` remains in the configuration.

### Q1. Review the destroy plan

```bash
terraform -chdir=infra/terraform plan \
  -destroy -input=false \
  -var-file=student-codebuild.tfvars \
  -var "image_tag=$Tag"
```

Confirm it targets only `taxi-w5-student` resources.

### Q2. Destroy

```bash
terraform -chdir=infra/terraform destroy \
  -input=false -auto-approve \
  -var-file=student-codebuild.tfvars \
  -var "image_tag=$Tag"
```

This removes the Terraform-managed CodeBuild project, webhook registration, S3
artifact bucket and uploaded inputs, ECR repository and images, ECS
service/task definition/cluster, ALB and target group, log groups, and IAM roles
and security groups.

### Q3. Verify empty state

```bash
terraform -chdir=infra/terraform show
```

Expected:

```text
The state file is empty. No resources are represented.
```

### Q4. Clear secrets and profile selection

```bash
unset TF_VAR_github_token
unset AWS_PROFILE
unset AWS_REGION
unset AWS_DEFAULT_REGION
```

Revoke the temporary GitHub token when the exercise is complete if it was created
only for this lab. Remove only the temporary `week5-lab` AWS profile; do not
delete unrelated profiles.

## Troubleshooting

| Problem | First check |
| --- | --- |
| `aws: command not found` | Re-run the AWS CLI v2 installer; open a new shell |
| `terraform: command not found` | Add the HashiCorp apt repo and install; open a new shell |
| `Unable to locate credentials` | `export AWS_PROFILE=...`; run `aws sts get-caller-identity` |
| `ExpiredToken` | Repeat `aws sso login`, or refresh lab credentials |
| Terraform says `github_token` is required | `export TF_VAR_github_token` in the current shell |
| GitHub credential or webhook creation fails | Confirm repository ownership and token permissions |
| Default VPC not found | Use an instructor-prepared account/configuration |
| Artifact upload says file missing | Complete model training and registration |
| CodeBuild cannot download S3 objects | Check upload success and CodeBuild IAM policy |
| CodeBuild fails at Ruff or pytest | Fix the code; do not bypass the quality gate |
| CodeBuild fails at Docker build | Read the first Docker error and confirm all downloaded files |
| CodeBuild cannot push ECR | Check its service role and repository policy |
| ECS stays at running zero | Read ECS service events and container logs |
| ALB returns 503 | Wait for a healthy target; inspect task startup |
| `/health` is degraded | Read CloudWatch logs for model or history loading failure |
| `mlflow ui` or API model load fails in the image | Confirm SQLAlchemy is pinned `<2.1` in `requirements.txt` (mlflow 2.14.1 needs `FallbackAsyncAdaptedQueuePool`) |

### Read ECS service events

```bash
aws ecs describe-services \
  --region "$Region" --cluster "$Cluster" --services "$Service" \
  --query "services[0].events[0:10].[createdAt,message]" \
  --output table
```

## Safe Evidence Checklist

Record: Git commit; CodeBuild status and phase names; image tag without account
hostname; ECS desired/running counts; target health; sanitized `/health` body;
smoke-test summary; empty Terraform state after teardown.

Redact: account ID; ARN; IAM identity; CodeBuild build ID; S3 bucket name; ECR
hostname; ALB hostname; GitHub token; AWS credentials; personal email.

## Completion Checklist

- [ ] Student GitHub repository and deployment branch confirmed.
- [ ] AWS identity and region confirmed privately.
- [ ] AWS CLI, Terraform, Git, and Python available.
- [ ] Model build inputs present.
- [ ] GitHub token entered only through the shell environment.
- [ ] Bootstrap apply completed with desired count zero.
- [ ] Model artifacts uploaded to S3.
- [ ] First CodeBuild run succeeded.
- [ ] Final apply changed desired count to one.
- [ ] ECS desired/running is 1/1.
- [ ] Health body says `ok`.
- [ ] Smoke tests pass.
- [ ] Later push-to-CodeBuild flow understood.
- [ ] Terraform destroy completed.
- [ ] Local Terraform state is empty.
- [ ] Temporary credentials and token cleared.
