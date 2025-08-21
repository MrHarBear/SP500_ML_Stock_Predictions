# SP500 ML Stock Demo — End‑to‑End Guide

This repository demonstrates an end‑to‑end ML workflow fully inside Snowflake: data prep → feature engineering → Feature Store → training + registry → batch inference → drift → Streamlit app and optional Snowflake Intelligence integration.

Choose your path:
- Run with SQL only (fastest to demo)
- Or run the Notebooks (interactive)


## Prerequisites

- A Snowflake account with permissions to create database/schema/warehouse/stages and use Model Registry
- A role with sufficient privileges (examples in `sql/SETUP.sql`)
- Subscribe to Marketplace database providing `FINANCIAL_DATA_PACKAGE.CYBERSYN.STOCK_PRICE_TIMESERIES`
- `SETUP.sql` materializes `DAILY_STOCK_PRICE` from Cybersyn and creates `SP_500_LIST` from the repo CSV
- Python packages are handled server‑side by Snowflake procedures; for local use of Notebooks see `Notebooks/environment.yml`

Snowflake objects used
- Database/Schema: `SP500_STOCK_DEMO.DATA`
- Warehouse: `DEMO_WH_S` (SMALL)
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

- What `SETUP.sql` also does now:
  - Creates a Git integration and Git repository (`SP500_ML_REPO`) and fetches from `https://github.com/MrHarBear/SP500_ML_Stock_Predictions/`
  - Creates and loads `SP_500_LIST` from `datasets/sp500_constituents.csv`
  - Builds `DAILY_STOCK_PRICE` from `FINANCIAL_DATA_PACKAGE.CYBERSYN.STOCK_PRICE_TIMESERIES`
  - Creates Snowsight notebooks from the repo with prefix `SP500_`

2) Optional: customize S&P 500 mapping

`SP_500_LIST` is created by `SETUP.sql` from the repo CSV. To override or add metadata, you can run:

```sql
!source sql/LOAD_SP500_LIST.sql
-- Then insert/update rows as needed
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

Note: `SETUP.sql` creates Snowsight notebooks from the repo automatically with names:
- `SP500_01_DATA_PREP`, `SP500_02_FEATURE_STORE`, `SP500_03_TRAIN_REGISTER`, `SP500_04_INFER_MONITOR`, `SP500_05_RETRAIN_COMPARE`, `SP500_07_TASK_SETUP`, `SP500_08_NOTEBOOK`


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
- Marketplace data: ensure subscription to `FINANCIAL_DATA_PACKAGE` providing `CYBERSYN.STOCK_PRICE_TIMESERIES`
- Missing `SP_500_LIST`: rerun `SETUP.sql` or use `sql/LOAD_SP500_LIST.sql` to repopulate
- Git repo: verify `SP500_ML_REPO` is fetched (`ALTER GIT REPOSITORY SP500_ML_REPO FETCH;`) and reachable
- Notebooks: DDL uses `FROM '@SP500_ML_REPO/branches/main/Notebooks'` with `MAIN_FILE='…ipynb'` and `QUERY_WAREHOUSE=DEMO_WH_S`
- Model Registry API: the app uses Registry first, then falls back to `SNOWFLAKE_ML_MODELS` view parsing
- Empty charts/tables: confirm `PRICE_FEATURES`, `PREDICTIONS_SP500_RET3M`, and `DRIFT_PSI_SP500` have rows for your selected ticker/date


## What’s created where

- Data tables: `SP500_STOCK_DEMO.DATA.*`
- Marketplace-derived: `DAILY_STOCK_PRICE`
- Feature Store: Entity `TICKER`; FeatureView `price_features@V1` and `@V2`
- Model Registry: `XGB_SP500_RET3M` (default version set by training step)
- Stages: `SP500_STOCK_DEMO.DATA.MONITORING`, `SP500_STOCK_DEMO.DATA.LANDING`
- Git: API integration `GITHUB_SP500_API`; repo `SP500_ML_REPO`
- Notebook objects: `SP500_*` created from repo notebooks


## Notes

- Warehousing cost: Steps 3–4 are compute‑heavier; scale `DEMO_WH_S` up temporarily if needed
- All steps run inside Snowflake; no data egress
- Objects and names align with `PROJECT_REQUIREMENTS.md`
