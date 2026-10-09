# Demand API Testing (Deployed AWS)

How to send demand predictions, recursive forecasts, and explanations to the
deployed API. Commands are bash/`curl` and work on Linux or macOS.

The API is served by the Application Load Balancer created by Terraform. Get the
base URL from the deployment outputs:

```bash
API=$(terraform -chdir=infra/terraform output -raw api_url)
echo "$API"
```

Example for the `taxi-w5-student` deployment in `ap-south-1`
(`http://taxi-w5-student-alb-19365179.ap-south-1.elb.amazonaws.com`). This hostname
is public and is destroyed by `terraform destroy`, so do not treat it as stable.

## 1. Single demand prediction

`POST /predict/demand` — fields `zone` (int) and `target_hour` (ISO datetime):

```bash
curl -s -X POST "$API/predict/demand" -H "Content-Type: application/json" \
  -d '{"zone":132,"target_hour":"2024-02-01T00:00:00"}' | python3 -m json.tool
```

Example response:

```json
{
    "zone": 132,
    "target_hour": "2024-02-01T00:00:00",
    "predicted_pickups": 142.04,
    "request_id": "551bc63c-9792-48eb-abbb-89885346579a"
}
```

## 2. Recursive multi-hour forecast

`POST /forecast/demand` — fields `horizon_hours` (int) and optional `zones`
(list of ints; defaults to all known zones):

```bash
curl -s -X POST "$API/forecast/demand" -H "Content-Type: application/json" \
  -d '{"horizon_hours":3,"zones":[132,161,230]}' | python3 -m json.tool
```

Example response (truncated):

```json
{
    "horizon_hours": 3,
    "zones": 3,
    "points": [
        {"zone": 132, "pickup_hour": "2024-02-01T00:00:00", "predicted_pickups": 142.04},
        {"zone": 132, "pickup_hour": "2024-02-01T01:00:00", "predicted_pickups": 23.79},
        {"zone": 132, "pickup_hour": "2024-02-01T02:00:00", "predicted_pickups": 7.52}
    ]
}
```

Forecasting starts one hour after the latest stored demand history; later
recursive hours use previous predicted counts as history.

## 3. Explanation (SHAP contributions)

`POST /explain/demand` — same fields as the single prediction:

```bash
curl -s -X POST "$API/explain/demand" -H "Content-Type: application/json" \
  -d '{"zone":132,"target_hour":"2024-02-01T00:00:00"}' | python3 -m json.tool
```

SHAP contributions describe model arithmetic, not causal effects.

## 4. From the repository's own test scripts

```bash
# Comprehensive smoke test (all endpoints, 9 checks)
.venv/bin/python scripts/aws/verify_staging.py --api-url "$API" --timeout 60

# Python client
.venv/bin/python -c "from clients.python.taxi_client import TaxiClient; \
c = TaxiClient('$API'); print(c.forecast_demand(horizon_hours=3, zones=[132, 161, 230]))"
```

The smoke test exits `0` and reports `passed = true` when every check succeeds.

## Notes

- No authentication: the ALB serves HTTP on port 80 publicly, so anyone with the
  URL can call the API.
- `target_hour` must follow the saved history (default January 2024 history means
  the next hour is `2024-02-01T00:00:00`). Requests for unknown zones return
  `400`; invalid schemas return `422`.
- Responses include an `X-Request-ID` header for tracing.
- Interactive docs: open `"$API/docs"` (Swagger UI); OpenAPI at `"$API/openapi.json"`,
  metrics at `"$API/metrics"`.
- Tear the stack down when finished (ALB + Fargate are billable):
  ```bash
  export TF_VAR_github_token="$(cat /tmp/gh_token)"
  terraform -chdir=infra/terraform destroy -input=false -auto-approve \
    -var-file=student-codebuild.tfvars -var "image_tag=w5-bf5897c"
  ```
