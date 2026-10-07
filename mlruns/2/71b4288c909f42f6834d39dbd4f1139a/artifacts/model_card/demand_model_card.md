# Model Card — taxi-demand-forecaster

_Generated 2026-10-03 11:36 UTC_

## Overview
Predicts the number of taxi pickups for a given zone and hour (demand forecasting).

- **Problem:** demand
- **Best algorithm:** lightgbm
- **Registry name:** `taxi-demand-forecaster`
- **Training data window:** 2024-01
- **Training rows:** 116,582

## Test-set performance

| Metric | Test | Validation |
|--------|------|------------|
| RMSE | 8.7022 | 8.4189 |
| MAE | 2.5350 | 2.5616 |
| MAPE | 40.1919 | 43.5492 |
| R2 | 0.9707 | 0.9622 |

## Top feature drivers (mean |SHAP|)

1. `lag_1` — 11.5359
2. `lag_168` — 7.1794
3. `lag_24` — 3.8574
4. `rolling_mean_3` — 0.8824
5. `hour_cos` — 0.5851
6. `rolling_std_24` — 0.4144
7. `lag_3` — 0.4019
8. `rolling_std_3` — 0.3970
9. `hour` — 0.3802
10. `rolling_mean_168` — 0.2990

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

- Trained on a single month of NYC TLC Yellow Taxi data; seasonal effects beyond the training window are not captured.
- Lag/rolling features require recent history — cold-start zones/hours are less reliable.
- Only Yellow Taxi pickups are modelled (no green taxi / FHV).
