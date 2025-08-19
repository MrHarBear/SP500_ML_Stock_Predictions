## SP500 ML Stock Demo — Project Requirements

### Storytelling intro
A portfolio manager heads into earnings season seeking explainable, timely signals across hundreds of S&P 500 names—without exporting data or breaking governance. This demo shows how their team curates market data, engineers features, trains a classic ML model, explains predictions, monitors drift, and shares an interactive app—entirely inside Snowflake. The outcome: faster iteration, built‑in governance, and a workflow that scales from demo to production.

### Business objectives
- **Showcase end‑to‑end ML in Snowflake**: data prep → feature store → training → registry → inference → monitoring → retrain.
- **Demonstrate explainability and observability** using Snowflake Model Registry and simple drift metrics.
- **Deliver a demo‑ready experience** with a Streamlit UI for non‑technical stakeholders.

### Target audience
- **Business stakeholders** evaluating Snowflake’s ML capabilities.
- **Data science and platform teams** assessing in‑platform governance, versioning, and reproducibility.

### Key Snowflake features highlighted
- **Snowpark for Python** for data prep and feature engineering.
- **Snowflake ML (Modeling, Registry, Experiment Tracking)** for training, explainability, and versioning.
- **Feature Store** for reusable features and entity/feature views.
- **Streamlit in Snowsight** for interactive visualization.
- **Model monitoring options**: simple PSI drift and optional native Model Monitor.

### Technical architecture and data flow
```mermaid
graph TD
  A[Daily Source<br/>CORTEX_DEMO.FSI_STOCKS_INSIGHT.DAILY_STOCK_PRICE] --> B[Subset to SP500<br/>(SP_500_LIST)]
  B --> C[Simulate Hourly OHLCV<br/>HOURLY_SP500_SIM]
  C --> D[Feature Engineering<br/>PRICE_FEATURES]
  D --> E[Feature Store<br/>Entity/FeatureView]
  D --> F[Train + Tune<br/>XGBRegressor]
  F --> G[Model Registry<br/>XGB_SP500_RET3M]
  D --> H[Batch Inference<br/>PREDICTIONS_SP500_RET3M]
  D --> I[Drift (PSI)
DRIFT_PSI_SP500]
  G --> J[Explainability<br/>SHAP via Registry]
  H --> K[Model Monitor<br/>(optional)]
  D --> L[Streamlit App<br/>Predictions/Drift/Explain]
  G --> L
  I --> L
```

### Deliverables (mapped to repo)
- Notebooks (`Notebooks/`):
  - `01_data_prep.ipynb`: SP500 subset, hourly simulation, housekeeping views.
  - `02_feature_store.ipynb`: feature engineering; register Feature Store `Entity(TICKER)` and `FeatureView(price_features@V2)`.
  - `03_train_register.ipynb`: label creation (lead +378h), time‑based split, compact sweep, experiment logging, registry logging with explainability, SHAP aggregation to `FEATURE_SHAP_GLOBAL_TOP`.
  - `04_infer_monitor.ipynb`: batch scoring to `PREDICTIONS_SP500_RET3M`, PSI drift table, optional native Model Monitor & paused alert DDL.
  - `05_retrain_compare.ipynb`: shift windows, retrain, compare with previous registry version, conditional re‑registration.
  - `07_task_setup.ipynb`: daily task (suspended) for inference/drift; email integration stub.
  - `environment.yml`: Snowflake ML/Snowpark + plotting.
- SQL orchestration (`sql/`):
  - `SETUP.sql`: DB/schema/warehouse/stages bootstrap.
  - `RUN_STEP_1_2.sql`: `SP500_PREP`, `SP500_FEATURES_FS` (tables + Feature Store).
  - `RUN_STEP_2_FEATURE_STORE_VERIFY.sql`: enriched features with `SECTOR`, register `price_features@V2`, preview join.
  - `RUN_STEP_3_TRAIN.sql`: `SP500_TRAIN_REGISTER` (train/evaluate/register/set default).
  - `RUN_STEP_4_INFER.sql`: `SP500_INFER_DRIFT` (batch inference + PSI tables).
  - `LOAD_SP500_LIST.sql`: helper to create `SP_500_LIST` when needed.
- App: `streamlit_app.py` renders predictions, drift (PSI), and SHAP/global importance with model version selection.

### Functional requirements
- **Data preparation**
  - Subset daily OHLCV to S&P 500 tickers (`SP_500_LIST`).
  - Simulate hourly OHLCV from daily using a bounded path and volume allocation; persist `HOURLY_SP500_SIM`.
- **Feature engineering**
  - Compute `RET_1`, `SMA_5`, `SMA_20`, `VOL_20`, `RSI_PROXY` (and `SECTOR` enrichment in V2); persist `PRICE_FEATURES`.
  - Register Feature Store `Entity(TICKER)` and `FeatureView(price_features@V2)`.
- **Supervised dataset**
  - Label `TARGET_PCT_3M = lead(CLOSE, 378h)/CLOSE − 1` per `TICKER`.
  - Time‑based split with backoff ensuring non‑empty train/test.
- **Training and tracking**
  - Compact sweep over XGBoost params; compute RMSE, MAPE, R².
  - Log parameters/metrics to Experiment Tracking; record final selection.
- **Registry and explainability**
  - Log model `XGB_SP500_RET3M`, set default version, enable explainability with background sample.
  - Aggregate SHAP importances; persist `FEATURE_SHAP_GLOBAL_TOP`.
- **Inference and drift**
  - Batch score last 5 days; persist `PREDICTIONS_SP500_RET3M`.
  - Compute PSI drift over key features; persist `DRIFT_PSI_SP500`.
- **Monitoring and automation (optional)**
  - Create a Model Monitor bound to predictions and a paused PSI alert.
  - Create a daily Snowflake Task to run inference/drift (left suspended).
- **UI**
  - Streamlit app with model version picker, ticker/time filters, charts for predictions and close price, drift table, and SHAP bar chart.

### Non‑functional requirements
- Entire pipeline runs in Snowflake; no data egress.
- Governed, versioned, and auditable artifacts (experiments, registry versions, tables).
- Demo‑friendly runtime: scale warehouse up for heavy steps, down afterward.
- Idempotent procedures and notebooks for repeatable runs.

### Model selection and compatibility
- **Model**: XGBoost Regressor (Snowflake ML) for strong tabular performance and compatibility with:
  - **Explainability** (SHAP) in Model Registry: see Snowflake docs on [Model Explainability](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-explainability).
  - **Model monitoring/observability**: see [Model Observability](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability) and [Explainability Visualization](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-explainability-visualization/force-plots).

### Data sources and prerequisites
- Source daily OHLCV: `CORTEX_DEMO.FSI_STOCKS_INSIGHT.DAILY_STOCK_PRICE`.
- SP500 mapping: `SP_500_LIST` (load via `sql/LOAD_SP500_LIST.sql` if needed).
- Snowflake objects: `SP500_STOCK_DEMO.DATA` schema, warehouse `DEMO_WH_M`.
- Packages: `snowflake-ml-python`, `snowflake-snowpark-python`, plotting per `Notebooks/environment.yml`.
- Privileges: create/manage DB/schema/tables/stages; Model Registry access; optional email integration.

### Implementation steps (aligned to repo)
1. Run `sql/SETUP.sql` (create database/schema/warehouse/stages).
2. Run `Notebooks/01_data_prep.ipynb` or `sql/RUN_STEP_1_2.sql` (SP500 subset + hourly simulation + features base).
3. Run `Notebooks/02_feature_store.ipynb` or `sql/RUN_STEP_2_FEATURE_STORE_VERIFY.sql` (register Feature Store V2).
4. Run `Notebooks/03_train_register.ipynb` or `sql/RUN_STEP_3_TRAIN.sql` (train, evaluate, register, set default, SHAP background).
5. Run `Notebooks/04_infer_monitor.ipynb` or `sql/RUN_STEP_4_INFER.sql` (batch inference + PSI; optional monitor/alert DDL).
6. Optional: `Notebooks/05_retrain_compare.ipynb` (shift windows, retrain, compare, conditional re‑register).
7. Optional: `Notebooks/07_task_setup.ipynb` (daily task suspended).
8. Open `streamlit_app.py` in Snowsight Streamlit.

### Success criteria / Acceptance
- `DAILY_SP500`, `HOURLY_SP500_SIM`, `PRICE_FEATURES` populated.
- Feature Store `Entity(TICKER)` and `FeatureView(price_features@V2)` registered.
- Registry model `XGB_SP500_RET3M` exists with default set; explainability enabled.
- `PREDICTIONS_SP500_RET3M`, `DRIFT_PSI_SP500`, `FEATURE_SHAP_GLOBAL_TOP` populated.
- Streamlit app renders predictions, drift, and SHAP for selected ticker/time range.

### Risks and mitigations
- **Simulated intraday realism**: clearly communicated as demo‑oriented; can swap to real intraday if available.
- **MAPE instability near zero**: prioritize RMSE/R²; report MAPE with caveats.
- **Cost during demo**: temporary warehouse scale‑up only for heavy steps; scale down after.

### Demo script (3–5 minutes)
- “All data stays in Snowflake. We subset SP500, simulate hourly signals, compute features, and register a Feature Store.”
- “We train an XGBoost model and register it—explainability is enabled, so we can inspect SHAP.”
- “We score the last 5 days, review predictions, and compute PSI drift.”
- “We shift the window, retrain, compare against the prior registered version, and only promote if improved.”
- “In Streamlit, pick a model version, filter by ticker and time, and explore predictions, drift, and top SHAP features.”

### Appendix: references
- Snowflake ML Model Explainability: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-explainability
- Explainability Visualization (force plots): https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-explainability-visualization/force-plots
- Model Observability: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability


