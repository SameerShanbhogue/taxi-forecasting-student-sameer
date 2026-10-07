# Model Card — taxi-fare-predictor

_Generated 2026-10-02 03:11 UTC_

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
| RMSE | 3.4717 | 3.3749 |
| MAE | 0.8151 | 0.7698 |
| MAPE | 8.6912 | 14.9431 |
| R2 | 0.9550 | 0.9553 |

## Top feature drivers (mean |SHAP|)

1. `trip_distance` — 7.1863
2. `trip_duration_min` — 3.8424
3. `PULocationID` — 0.7273
4. `DOLocationID` — 0.4765
5. `passenger_count` — 0.1150
6. `hour_cos` — 0.0775
7. `hour` — 0.0680
8. `hour_sin` — 0.0358
9. `dow_sin` — 0.0222
10. `day_of_week` — 0.0220

## Hyperparameters

```json
{
  "n_estimators": 300,
  "num_leaves": 244,
  "max_depth": 9,
  "learning_rate": 0.07661100707771368,
  "subsample": 0.6624074561769746,
  "colsample_bytree": 0.662397808134481,
  "min_child_samples": 10,
  "reg_lambda": 2.9154431891537547
}
```

## Limitations

- Trained on a single month of NYC TLC Yellow Taxi data; tariff changes or surge conditions outside the window are not represented.
- Extreme fares are filtered during cleaning, so very long/expensive trips may be under-predicted.
- Tolls, tips and surcharges are not part of the modelled fare amount.
