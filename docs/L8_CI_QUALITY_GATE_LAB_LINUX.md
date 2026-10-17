# L8: Break and Repair the CI Quality Gate

**Linux/bash port of [L8 — Break and Repair the CI Quality Gate](L8_CI_QUALITY_GATE_LAB.md).** The original lab and the recordings use Windows PowerShell commands; this port uses the bash equivalents.

- **Duration:** 35 to 45 minutes
- **Cloud required:** Optional instructor demonstration; students need no credentials
- **Docker required on the learner machine:** **No**
- **Outcome:** A reversible controlled lint failure, an honestly reported
  repository-wide gate result, and a read-only hosted-build inspection.

> **Docker boundary:** do not install or start Docker for this lab. The learner
> runs Ruff, pytest/coverage, and optionally Terraform through
> `scripts/ci_local.ps1` (PowerShell) or the equivalent direct bash commands
> shown in Task 4. References to `docker build`, image push, ECR, and ECS
> describe stages executed by AWS CodeBuild. You inspect those lines in
> `buildspec.yml`; you do not execute them locally.

## Task 1: Inspect the Gates

Open `scripts/ci_local.ps1` and `buildspec.yml`. Both run lint, tests, and
coverage. Terraform formatting/validation checks belong to the local script;
the hosted buildspec does not run Terraform. Image build, push, and the ECS
update belong to the hosted deployment path. The local script does not deploy.

## Task 2: Create a Controlled Lint Failure

First confirm the file does not exist:

```bash
test -e scratch_ci_failure.py && echo "already present - stop" || echo "absent"
```

If it already exists, stop and preserve it rather than overwriting someone
else's file. Create the temporary file containing an unused import:

```bash
printf 'import os\n' > scratch_ci_failure.py
.venv/bin/python -m ruff check scratch_ci_failure.py
```

Confirm Ruff reports `F401`. This file is intentionally outside application
code and will be removed in the next task.

## Task 3: Repair and Recheck

```bash
rm scratch_ci_failure.py
.venv/bin/python -m ruff check .
```

Record the repository-wide result separately from repairing the deliberate
scratch error. Verify the temporary file is gone:

```bash
test -e scratch_ci_failure.py && echo "still present" || echo "absent"
```

The final command should print `absent`.

In the finalized R8 recording, the scratch repair is complete while three
separate Ruff findings keep the wider gate red; pytest passes. That is historical
evidence, not the required result of today's checkout. Report current findings
honestly, do not conceal them, and do not repair unrelated code just to force a
green demonstration. A failed required lint stage is not overridden by passing tests.

## Task 4: Run the Local CI Workflow

`scripts/ci_local.ps1` is PowerShell-only (no `.sh` companion exists). On Linux,
either run it with PowerShell 7 (`pwsh -File scripts/ci_local.ps1
-NoTerraform`) or run the same gates directly, as in
[AWS setup (Linux)](AWS_SETUP_LINUX.md) Part P.

When Terraform is installed:

```bash
.venv/bin/python -m ruff check .
.venv/bin/python -m pytest --cov=src --cov-report=term-missing --cov-report=xml
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false -input=false
terraform -chdir=infra/terraform validate
```

When Terraform is unavailable:

```bash
.venv/bin/python -m ruff check .
.venv/bin/python -m pytest --cov=src --cov-report=term-missing --cov-report=xml
```

Record which route was used and the final result.

## Task 5: Trace the Cloud-Only Stages

In `buildspec.yml`, identify where the pipeline logs in to ECR, builds the
Docker image, pushes the immutable tag, and requests an ECS service update.
Confirm that this buildspec has no ECS stability waiter or smoke test. Those are
separate post-deployment checks, so a successful CodeBuild run does not by
itself prove that the new task became healthy. Inspect these steps without
running them locally or exposing AWS credentials, account identifiers, or
repository URLs.

## Task 6: Inspect One Hosted Build

The instructor runs this read-only extension with the authorized staging profile. Students should
not enter credentials. Keep account IDs, ARNs, and repository URLs off screen.

```bash
Region="us-east-1"
Project="$(terraform -chdir=infra/terraform output -raw cicd_project_name)"
BuildId="$(aws codebuild list-builds-for-project \
  --project-name "$Project" --region "$Region" --sort-order DESCENDING \
  --query "ids[0]" --output text)"
aws codebuild batch-get-builds --ids "$BuildId" --region "$Region" \
  --query "builds[0].{Status:buildStatus,Revision:resolvedSourceVersion,Phase:currentPhase,Phases:phases[].{Name:phaseType,Status:phaseStatus}}"
```

Compare the hosted phases with `buildspec.yml`. A successful build supports that those configured
stages ran and the ECS update was requested for one revision; it does not prove
service stability, smoke-test success, or that every future build or runtime
request will succeed.

## Completion Check

- A controlled `F401` failure is visible.
- The temporary file was removed and the repository-wide lint result was
  recorded separately, including any remaining failures.
- The local CI script completed or the failing gate was identified.
- Local quality checks are distinguished from cloud build and deployment.
- One hosted CodeBuild status and its phase results were inspected, or the optional cloud step was
  explicitly skipped.
- No credentials or private AWS identifiers are visible.
