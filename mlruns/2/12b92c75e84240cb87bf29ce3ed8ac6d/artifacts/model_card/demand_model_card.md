# Model Card — taxi-demand-forecaster

_Generated 2026-10-03 11:40 UTC_

## Overview
Predicts the number of taxi pickups for a given zone and hour (demand forecasting).

- **Problem:** demand
- **Best algorithm:** xgboost
- **Registry name:** `taxi-demand-forecaster`
- **Training data window:** 2024-01
- **Training rows:** 116,582

## Test-set performance

| Metric | Test | Validation |
|--------|------|------------|
| RMSE | 8.6826 | 8.1606 |
| MAE | 2.5227 | 2.4981 |
| MAPE | 39.5291 | 43.2263 |
| R2 | 0.9709 | 0.9645 |

## Top feature drivers (mean |SHAP|)

1. `lag_1` — 10.8711
2. `lag_168` — 7.2464
3. `lag_24` — 4.1981
4. `rolling_mean_3` — 1.4073
5. `hour_cos` — 0.6890
6. `lag_3` — 0.4127
7. `hour` — 0.3526
8. `rolling_mean_168` — 0.3017
9. `rolling_std_24` — 0.2589
10. `rolling_std_3` — 0.2349

## Hyperparameters

```json
{
  "n_estimators": 450,
  "max_depth": 10,
  "learning_rate": 0.014592001902692407,
  "subsample": 0.7074401095643522,
  "colsample_bytree": 0.6056971959182325,
  "min_child_weight": 10,
  "reg_lambda": 0.01953916575547041
}
```

## Limitations

- Trained on a single month of NYC TLC Yellow Taxi data; seasonal effects beyond the training window are not captured.
- Lag/rolling features require recent history — cold-start zones/hours are less reliable.
- Only Yellow Taxi pickups are modelled (no green taxi / FHV).
