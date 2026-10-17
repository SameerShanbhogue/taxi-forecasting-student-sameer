# API Examples

**Linux/bash port of [API Examples](API_EXAMPLES.md).** The original guide and
the recordings use Windows PowerShell commands; this port uses the bash
equivalents.

Start the API after data preparation and model registration as described in
[setup](SETUP_LINUX.md). These examples use <http://127.0.0.1:8000>. Swagger is at
`/docs`, OpenAPI at `/openapi.json`, and Prometheus metrics at `/metrics`.

## Readiness

```bash
curl -s http://127.0.0.1:8000/health | python3 -m json.tool
```

Inspect the body, not just the status code. Require both model flags and
`status: ok` for prediction readiness.

## Fare

```bash
curl -s -X POST http://127.0.0.1:8000/predict/fare -H "Content-Type: application/json" -d '{
    "trip_distance": 3.4,
    "pu_location_id": 132,
    "do_location_id": 230,
    "passenger_count": 1,
    "pickup_datetime": "2024-01-15T18:30:00"
  }' | python3 -m json.tool
curl -s -X POST http://127.0.0.1:8000/explain/fare -H "Content-Type: application/json" -d '{
    "trip_distance": 3.4,
    "pu_location_id": 132,
    "do_location_id": 230,
    "passenger_count": 1,
    "pickup_datetime": "2024-01-15T18:30:00"
  }' | python3 -m json.tool
```

The response predicts `fare_amount` in dollars, not `total_amount`. Duration is
estimated when `trip_duration_min` is omitted, indicated by `duration_estimated`.
Include a valid duration when it is available at the intended prediction time.
SHAP contributions describe model arithmetic, not causal effects.

## Recursive Demand Forecast

```bash
curl -s -X POST http://127.0.0.1:8000/forecast/demand -H "Content-Type: application/json" -d '{"horizon_hours": 3, "zones": [132, 161, 230]}' | python3 -m json.tool
```

Without a start time, forecasting begins one hour after the latest stored demand
history. It does not automatically advance historical data to the present.
The response includes forecast points, request ID and model reference. Later
recursive hours use previous predicted counts as history.

## Single Demand Prediction

For the default January 2024 history, this requests the following hour:

```bash
curl -s -X POST http://127.0.0.1:8000/predict/demand -H "Content-Type: application/json" -d '{"zone": 132, "target_hour": "2024-02-01T00:00:00"}' | python3 -m json.tool
curl -s -X POST http://127.0.0.1:8000/explain/demand -H "Content-Type: application/json" -d '{"zone": 132, "target_hour": "2024-02-01T00:00:00"}' | python3 -m json.tool
```

Choose a time with sufficient prior lag/rolling history for other datasets.
The feature builder fills missing prior hours with zero counts; it does not
reject an incomplete history window. A successful response therefore does not
prove that the required history was observed. Single-step requests do not
recursively predict intervening hours; use `/forecast/demand` for consecutive
future hours starting immediately after the saved history. Invalid schemas
return 422; demand requests for unknown zones return 400.
Responses include an `X-Request-ID` header for tracing.

## Python Client

```python
from clients.python.taxi_client import TaxiClient

client = TaxiClient("http://127.0.0.1:8000")
print(client.health())
print(client.forecast_demand(horizon_hours=3, zones=[132, 161, 230]))
```

Do not compare predictions to fixed expected amounts across differently trained
model versions. Validate the input contract and inspect the current model output.

## Showcase Inputs

For the finished-product demonstration, use 17.0 miles, pickup zone 132 (JFK),
drop-off zone 230 (Times Square), one passenger, and 15 January 2024 at 18:30.
Change `trip_distance` in the fare request above to `17.0`. This is an illustrative
input, not a routing calculation or an official fare quote. The 3.4-mile API
example is a schema exercise, not a realistic distance for that zone pair.

For the matching demand preview, set `horizon_hours` to `6` with zones 132, 161,
and 230. The three-hour example above remains suitable for a smaller API check.
The forecast starts after saved history, not the current clock. Actual values
depend on your registered models and data; no exact dollar/count match is required.
