# Model Card — taxi-fare-predictor

_Generated: 2026-10-03 11:29 UTC_

## Model details

- **Problem:** fare
- **Algorithm:** LGBMRegressor
- **Target:** `fare_amount`
- **Registry version:** n/a

## Intended use

Operational forecasting of fare_amount to support fleet positioning and rider fare estimates. Not intended for individual pricing decisions or any use with legal/financial consequences for individuals.

## Evaluation — overall (test split)

| Metric | Value |
|--------|-------|
| rmse | 3.4482 |
| mae | 0.8086 |
| mape | 8.6980 |
| r2 | 0.9556 |

## Evaluation — subgroup fairness

### By borough

Disparity ratio (worst/best RMSE): **7.63** (threshold 1.5) — ⚠️ **flagged**. Worst: `Unknown`, best: `Manhattan`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| Unknown | 815 | 17.319 | 3.381 | 14.29 |
| Bronx | 580 | 10.342 | 5.918 | 489.64 |
| Brooklyn | 1946 | 8.822 | 4.560 | 17.15 |
| Queens | 23747 | 7.963 | 2.587 | 15.47 |
| Manhattan | 245640 | 2.270 | 0.585 | 6.82 |

### By time_of_day

Disparity ratio (worst/best RMSE): **1.86** (threshold 1.5) — ⚠️ **flagged**. Worst: `overnight`, best: `evening`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| overnight | 8572 | 5.634 | 1.385 | 6.67 |
| afternoon | 101213 | 3.623 | 0.823 | 8.93 |
| morning | 68332 | 3.362 | 0.886 | 7.98 |
| evening | 94618 | 3.033 | 0.685 | 9.15 |

### By day_type

Disparity ratio (worst/best RMSE): **1.33** (threshold 1.5) — ok. Worst: `weekend`, best: `weekday`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| weekend | 3150 | 4.570 | 1.134 | 4.89 |
| weekday | 269585 | 3.433 | 0.805 | 8.74 |

### By holiday

Disparity ratio (worst/best RMSE): **1.00** (threshold 1.5) — ok. Worst: `non-holiday`, best: `non-holiday`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| non-holiday | 272735 | 3.448 | 0.809 | 8.70 |

### By airport

Disparity ratio (worst/best RMSE): **2.57** (threshold 1.5) — ⚠️ **flagged**. Worst: `airport`, best: `non-airport`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| airport | 20957 | 7.400 | 2.212 | 15.07 |
| non-airport | 251778 | 2.885 | 0.692 | 8.17 |

## Top features (SHAP)

| Feature | Mean |SHAP| |
|---------|-----------|
| trip_distance | 6.6160 |
| trip_duration_min | 4.3717 |
| DOLocationID | 0.4938 |
| PULocationID | 0.4271 |
| hour_cos | 0.1672 |
| hour | 0.1252 |
| passenger_count | 0.0942 |
| hour_sin | 0.0398 |
| dow_sin | 0.0260 |
| day_of_week | 0.0254 |

## Limitations

- Trained on a single month of NYC Yellow Taxi data; may not generalise to other periods, boroughs served sparsely, or green/for-hire vehicles.
- Predictions degrade under distribution shift (see drift monitoring).

## Ethical considerations

- No demographic or protected attributes are used or available; fairness is assessed as geographic/temporal service equity, not demographic parity.
- Large borough-level disparities could translate into unequal service quality across neighbourhoods and should be monitored.
