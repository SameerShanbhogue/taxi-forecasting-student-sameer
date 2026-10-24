# Model Card — taxi-demand-forecaster

_Generated: 2026-10-23 11:35 UTC_

## Model details

- **Problem:** demand
- **Algorithm:** XGBRegressor
- **Target:** `pickup_count`
- **Registry version:** n/a

## Intended use

Operational forecasting of pickup_count to support fleet positioning and rider fare estimates. Not intended for individual pricing decisions or any use with legal/financial consequences for individuals.

## Evaluation — overall (test split)

| Metric | Value |
|--------|-------|
| rmse | 8.6826 |
| mae | 2.5227 |
| mape | 39.5291 |
| r2 | 0.9709 |

## Evaluation — subgroup fairness

### By borough

Disparity ratio (worst/best RMSE): **217.03** (threshold 1.5) — ⚠️ **flagged**. Worst: `Manhattan`, best: `Staten Island`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| Manhattan | 3862 | 15.760 | 7.671 | 29.66 |
| Queens | 3971 | 5.848 | 1.165 | 51.29 |
| Unknown | 116 | 3.198 | 2.002 | 46.32 |
| Brooklyn | 3457 | 0.738 | 0.451 | 52.31 |
| Bronx | 2476 | 0.442 | 0.275 | 62.52 |
| EWR | 58 | 0.269 | 0.110 | 97.00 |
| Staten Island | 633 | 0.073 | 0.051 | 93.48 |

### By time_of_day

Disparity ratio (worst/best RMSE): **2.67** (threshold 1.5) — ⚠️ **flagged**. Worst: `evening`, best: `overnight`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| evening | 4554 | 11.965 | 3.353 | 36.68 |
| afternoon | 3947 | 8.376 | 2.942 | 35.60 |
| morning | 3036 | 5.981 | 2.317 | 38.46 |
| overnight | 3036 | 4.489 | 0.938 | 56.70 |

### By day_type

Disparity ratio (worst/best RMSE): **1.00** (threshold 1.5) — ok. Worst: `weekday`, best: `weekday`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| weekday | 14573 | 8.683 | 2.523 | 39.53 |

### By holiday

Disparity ratio (worst/best RMSE): **1.00** (threshold 1.5) — ok. Worst: `non-holiday`, best: `non-holiday`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| non-holiday | 14573 | 8.683 | 2.523 | 39.53 |

### By airport

Disparity ratio (worst/best RMSE): **4.12** (threshold 1.5) — ⚠️ **flagged**. Worst: `airport`, best: `non-airport`.

| Group | n | RMSE | MAE | MAPE |
|-------|---|------|-----|------|
| airport | 116 | 33.696 | 25.095 | 35.72 |
| non-airport | 14457 | 8.178 | 2.342 | 39.61 |

## Top features (SHAP)

| Feature | Mean |SHAP| |
|---------|-----------|
| lag_1 | 11.7255 |
| lag_168 | 8.0159 |
| lag_24 | 4.2984 |
| rolling_mean_3 | 1.4842 |
| hour_cos | 0.7002 |
| lag_3 | 0.4131 |
| hour | 0.3527 |
| rolling_mean_168 | 0.2930 |
| rolling_std_24 | 0.2690 |
| rolling_std_3 | 0.2368 |

## Limitations

- Trained on a single month of NYC Yellow Taxi data; may not generalise to other periods, boroughs served sparsely, or green/for-hire vehicles.
- Predictions degrade under distribution shift (see drift monitoring).

## Ethical considerations

- No demographic or protected attributes are used or available; fairness is assessed as geographic/temporal service equity, not demographic parity.
- Large borough-level disparities could translate into unequal service quality across neighbourhoods and should be monitored.
