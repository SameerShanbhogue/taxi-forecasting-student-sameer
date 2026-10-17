# L7: Call and Package the Prediction API

**Linux/bash port of [L7 — API & Docker Lab](L7_API_DOCKER_LAB.md).** The original
lab and the recordings use Windows PowerShell commands; this port uses bash
equivalents.

- **Duration:** 45 to 60 minutes
- **Cloud required:** No
- **Docker required:** Optional; a local Python fallback is provided
- **Outcome:** Valid and invalid API evidence plus a verified container or local runtime.

## Prerequisites

From the repository root, confirm that the project environment and serving
artifacts exist:

```bash
.venv/bin/python --version
test -e mlflow.db
test -e mlruns
test -e data/processed/demand_hourly.parquet
```

Path existence alone does not prove that models are registered. In the MLflow
UI, confirm both `taxi-demand-forecaster` and `taxi-fare-predictor` have registered
versions with accessible artifacts. L5's `--no-register` run does not satisfy
this requirement, and L6 may have registered only fare.

If inputs or registered models are missing, complete the pipeline and
model-training steps in [SETUP_LINUX.md](SETUP_LINUX.md). For a bounded teaching run that
registers both models, use:

```bash
.venv/bin/python -m scripts.train_models --n-trials 1
```

If you plan to use Route A, create and verify the portable registry required by
the Docker image:

```bash
.venv/bin/python -m scripts.make_mlflow_portable \
	--src mlflow.db \
	--dest mlflow.container.db \
	--new-base "file:///app/mlruns"
test -e mlflow.container.db   # should exit 0
```

Repeat this command after retraining so the container uses the latest registry.
Route B does not require `mlflow.container.db`.

## Task 1: Predict the Runtime Result

Record the expected health status, one valid prediction result, and the status
code expected from an invalid request before starting the service.

## Task 2: Start the API

Choose one route.

### Route A: Docker Compose

Confirm Docker is available, then build and start the API and MLflow UI:

```bash
docker version
docker compose -f docker/docker-compose.yml up --build
```

If `docker version` reports that the command is unavailable, cannot connect to
the Docker daemon, or does not include Compose, skip the second command and use
Route B. Docker is optional for L7; record that you used the local fallback.

Keep this terminal open. The API is available at `http://localhost:8000` and
the MLflow UI at `http://localhost:5000`.

### Route B: Local Python

Use this route when Docker is unavailable:

```bash
.venv/bin/python -m uvicorn src.serving.api:app --host 127.0.0.1 --port 8000
```

Keep this terminal open. This route starts the API at `http://localhost:8000`;
it does not start the MLflow UI, which is not required to complete L7.

## Task 3: Verify Health and Documentation

In another terminal:

```bash
curl -s http://localhost:8000/health | python3 -m json.tool
xdg-open http://localhost:8000/docs
```

Record the health response and identify the fare and demand prediction
endpoints in Swagger UI.

## Task 4: Exercise Valid and Invalid Requests

Use the request examples in `docs/API_EXAMPLES_LINUX.md` to send:

1. One valid fare request.
2. One valid demand request.
3. One invalid request with a missing or out-of-range field.

Record the prediction fields from the valid responses. For the invalid request,
record the HTTP status and the validation message without changing server code.

## Task 5: Inspect the Packaging Boundary

Open `docker/Dockerfile` and identify:

- The builder and runtime stages.
- The copied source, model registry, model artifacts, and demand history.
- Port `8000`.
- The Uvicorn startup command.

Then open `docker/docker-compose.yml` and identify:

- The `api` and `mlflow-ui` services and their port mappings.
- The development `mlflow.db`, model-artifact, and data mounts that override
	the corresponding files baked into the image.
- The API `/health` container check.

If you used Route B, inspect these files as packaging evidence but state that
you did not execute the image build, Compose wiring, or container health check.

Explain why Docker packages the API and its dependencies but does not train the
models or prove that the service is deployed to AWS.

## Task 6: Stop the Runtime

For Docker Compose, press `Ctrl+C`, then run:

```bash
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml ps   # should show no running services
```

For local Python, press `Ctrl+C` in the Uvicorn terminal.

## Result Record

### Runtime route and evidence

```text

```

### Valid response finding

```text

```

### Invalid response finding

```text

```

### Packaging explanation and limitation

```text

```

## Completion Check

- The expected result was recorded before starting the service.
- Health and Swagger documentation were inspected.
- Valid fare and demand requests returned interpretable responses.
- An invalid request returned an explained validation error.
- Docker was exercised, or its absence and the local fallback were recorded.
- The result distinguishes local packaging from AWS deployment.
