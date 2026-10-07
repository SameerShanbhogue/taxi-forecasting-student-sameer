# Model Card — taxi-fare-predictor

_Generated 2026-10-02 04:05 UTC_

## Overview
Predicts the fare amount for a single taxi trip from its distance, zones, passenger count and calendar context (fare prediction).

- **Problem:** fare
- **Best algorithm:** lightgbm
- **Registry name:** `taxi-fare-predictor`
- **Training data window:** 2024-01
- **Training rows:** 2,181,879

## Test-set performance

| Metric | Test | Validation |
|--------|------|------------|
| RMSE | 3.4482 | 3.3316 |
| MAE | 0.8086 | 0.7597 |
| MAPE | 8.6980 | 14.8717 |
| R2 | 0.9556 | 0.9564 |

## Top feature drivers (mean |SHAP|)

1. `trip_distance` — 6.9048
2. `trip_duration_min` — 4.5564
3. `PULocationID` — 0.4844
4. `DOLocationID` — 0.4709
5. `hour_cos` — 0.1606
6. `hour` — 0.1246
7. `passenger_count` — 0.1012
8. `hour_sin` — 0.0400
9. `dow_sin` — 0.0304
10. `day_of_week` — 0.0291

## Hyperparameters

```json
{
  "n_estimators": 350,
  "num_leaves": 241,
  "max_depth": 11,
  "learning_rate": 0.09699713612032222,
  "subsample": 0.7936619659120334,
  "colsample_bytree": 0.6968819347785113,
  "min_child_samples": 83,
  "reg_lambda": 5.274657850809935
}
```

## Limitations

- Trained on a single month of NYC TLC Yellow Taxi data; tariff changes or surge conditions outside the window are not represented.
- Extreme fares are filtered during cleaning, so very long/expensive trips may be under-predicted.
- Tolls, tips and surcharges are not part of the modelled fare amount.
