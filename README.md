# SP500 ML Stock Demo — End‑to‑End Guide

This repository demonstrates an end‑to‑end ML workflow fully inside Snowflake: data prep → feature engineering → Feature Store → training + registry → batch inference → drift → Streamlit app and optional Snowflake Intelligence integration.

Choose your path:
- Run with SQL only (fastest to demo)
- Or run the Notebooks (interactive)


## Prerequisites

- A Snowflake account with permissions to create database/schema/warehouse/stages and use Model Registry
- A role with sufficient privileges (examples in `sql/SETUP.sql`)
- Access to source table `CORTEX_DEMO.FSI_STOCKS_INSIGHT.DAILY_STOCK_PRICE`
- S&P 500 mapping (`SP_500_LIST`). If missing, use `sql/LOAD_SP500_LIST.sql`
- Python packages are handled server‑side by Snowflake procedures; for local use of Notebooks see `Notebooks/environment.yml`

Snowflake objects used
- Database/Schema: `SP500_STOCK_DEMO.DATA`
- Warehouse: `DEMO_WH_M` (MEDIUM)
- Feature Store Entity/FeatureView: `TICKER`, `price_features@V2`
- Registry Model: `XGB_SP500_RET3M`
- Core Tables: `DAILY_SP500`, `HOURLY_SP500_SIM`, `PRICE_FEATURES`, `PREDICTIONS_SP500_RET3M`, `DRIFT_PSI_SP500`


## Quick Start (SQL path)

1) Bootstrap Snowflake objects

Run in a Snowflake worksheet:

```sql
-- Create DB/Schema/Warehouse/Stages
!source sql/SETUP.sql
```

If your role setup differs, execute the grant examples in `sql/SETUP.sql` with your role.

2) Ensure S&P 500 mapping table exists

If `SP_500_LIST` is not present in `SP500_STOCK_DEMO.DATA`, create a minimal version:

```sql
!source sql/LOAD_SP500_LIST.sql
-- Insert tickers and optionally sectors into SP_500_LIST as needed
```

3) Data prep + base features + Feature Store V1

```sql
!source sql/RUN_STEP_1_2.sql
```
This creates `DAILY_SP500`, `HOURLY_SP500_SIM`, `PRICE_FEATURES` and registers Feature Store `price_features@V1`.

4) Enrich features with sector + register Feature Store V2 (and verify)

```sql
!source sql/RUN_STEP_2_FEATURE_STORE_VERIFY.sql
```
This overwrites `PRICE_FEATURES`, registers `price_features@V2`, and writes `PRICE_FEATURES_JOINED_PREVIEW`.

5) Train and register the model

```sql
!source sql/RUN_STEP_3_TRAIN.sql
```
This trains an `XGBRegressor`, logs it to the Model Registry as `XGB_SP500_RET3M`, and sets the default version.

6) Batch inference + drift

```sql
!source sql/RUN_STEP_4_INFER.sql
```
This persists `PREDICTIONS_SP500_RET3M` and `DRIFT_PSI_SP500`.


## Run the Streamlit App (Snowsight)

Open `streamlit_app.py` in Snowsight Streamlit:
- The app auto‑connects to your active Snowflake session
- Pick a model version, ticker, and date range
- Switch between “Existing predictions” and “On‑demand scoring”
- Explore tabs: Overview, Predictions, AI Trading Signals, Drift (PSI), Explainability (global SHAP if available)

Required objects (created by steps above):
- Tables: `DAILY_SP500`, `HOURLY_SP500_SIM`, `PRICE_FEATURES`, `PREDICTIONS_SP500_RET3M`, `DRIFT_PSI_SP500`
- Registry model: `XGB_SP500_RET3M` with at least one version
- Optional: `FEATURE_SHAP_GLOBAL_TOP` for Explainability tab


## Notebook path (interactive)

If you prefer Notebooks, run these inside Snowflake (or locally if you configure a connection):
1. `Notebooks/01_data_prep.ipynb`
2. `Notebooks/02_feature_store.ipynb`
3. `Notebooks/03_train_register.ipynb`
4. `Notebooks/04_infer_monitor.ipynb`
5. Optional: `Notebooks/05_retrain_compare.ipynb`, `Notebooks/07_task_setup.ipynb`

Environment for local Jupyter: see `Notebooks/environment.yml`.


## Optional: Snowflake Intelligence integration

An Intelligence tool `GET_TRADING_SIGNAL(ticker_symbol STRING, days_back INTEGER DEFAULT 7)` is referenced by this demo. See `INTELLIGENCE_DEMO_READY.md` for the latest status and `INTELLIGENCE_AGENT_SETUP.md` (if present) for setup. In the app, the “AI Trading Signals” tab calls this function for demo analysis.

Note: If you create Python functions/UDFs in Snowflake for this repo, use `RUNTIME_VERSION = '3.12'`.


## Validation and testing utilities

- Batch subset generator: `sql/RUN_BATCH_TEST.sql`
- Metrics signature tests: `sql/TEST_METRICS_AUTODETECT.sql`, `sql/TEST_METRICS_SIG.sql`


## Cleanup

To remove demo objects:

```sql
!source sql/CLEANUP.sql
```

Adjust or uncomment lines inside if you also want to drop schema/database/warehouse.


## Troubleshooting

- Permissions: ensure your role has USAGE/CREATE on database/schema, USAGE on warehouse/stages, and Registry access
- Source data access: verify `CORTEX_DEMO.FSI_STOCKS_INSIGHT.DAILY_STOCK_PRICE` is accessible to your role
- Missing `SP_500_LIST`: create via `sql/LOAD_SP500_LIST.sql` and populate tickers (and `SECTOR` if you plan to run V2 features)
- Model Registry API: the app uses Registry first, then falls back to `SNOWFLAKE_ML_MODELS` view parsing
- Empty charts/tables: confirm `PRICE_FEATURES`, `PREDICTIONS_SP500_RET3M`, and `DRIFT_PSI_SP500` have rows for your selected ticker/date


## What’s created where

- Data tables: `SP500_STOCK_DEMO.DATA.*`
- Feature Store: Entity `TICKER`; FeatureView `price_features@V1` and `@V2`
- Model Registry: `XGB_SP500_RET3M` (default version set by training step)
- Stages: `SP500_STOCK_DEMO.DATA.MONITORING`, `SP500_STOCK_DEMO.DATA.LANDING`


## Notes

- Warehousing cost: Steps 3–4 are compute‑heavier; scale `DEMO_WH_M` up temporarily if needed
- All steps run inside Snowflake; no data egress
- Objects and names align with `PROJECT_REQUIREMENTS.md`
