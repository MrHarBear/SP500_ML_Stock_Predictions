-- -------------------------------------------------------------------
-- Snowflake Setup for SP500 Stock ML Demo
-- -------------------------------------------------------------------
-- Creates database, schema, warehouse, stages, and basic grants.
-- Adjust ROLE names as appropriate for your account.
-- -------------------------------------------------------------------

-- 1) Core objects
CREATE DATABASE IF NOT EXISTS SP500_STOCK_DEMO;
CREATE SCHEMA IF NOT EXISTS SP500_STOCK_DEMO.DATA;

-- Warehouse for development/training (MEDIUM per updated requirement)
CREATE WAREHOUSE IF NOT EXISTS DEMO_WH_S
  WITH WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- Default stage for monitoring reports and artifacts
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;
CREATE STAGE IF NOT EXISTS MONITORING;

-- Optional: stage for transient data or uploads
CREATE STAGE IF NOT EXISTS LANDING;

-- 3) GitHub API integration and Git repository (public repo; no secrets needed)

-- Create API integration for Git over HTTPS
CREATE OR REPLACE API INTEGRATION GITHUB_SP500_API
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/MrHarBear/')
  ENABLED = TRUE;

-- Register the Git repository in Snowflake and fetch latest
CREATE OR REPLACE GIT REPOSITORY SP500_ML_REPO
  ORIGIN = 'https://github.com/MrHarBear/SP500_ML_Stock_Predictions.git'
  API_INTEGRATION = GITHUB_SP500_API
  COMMENT = 'Git repo for SP500 ML Stock Predictions';

ALTER GIT REPOSITORY SP500_ML_REPO FETCH;

-- 2) Grants (adjust roles to your environment)
-- Replace DEMO_ROLE with an existing role that your user has
-- and that will own/run the demo objects.
-- Example grants:
-- GRANT USAGE ON WAREHOUSE DEMO_WH_S TO ROLE DEMO_ROLE;
-- GRANT USAGE ON DATABASE SP500_STOCK_DEMO TO ROLE DEMO_ROLE;
-- GRANT USAGE, CREATE SCHEMA ON DATABASE SP500_STOCK_DEMO TO ROLE DEMO_ROLE;
-- GRANT USAGE ON SCHEMA SP500_STOCK_DEMO.DATA TO ROLE DEMO_ROLE;
-- GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TABLE ON SCHEMA SP500_STOCK_DEMO.DATA TO ROLE DEMO_ROLE;
-- GRANT USAGE ON STAGE SP500_STOCK_DEMO.DATA.MONITORING TO ROLE DEMO_ROLE;
-- GRANT USAGE ON STAGE SP500_STOCK_DEMO.DATA.LANDING TO ROLE DEMO_ROLE;

-- 3) Optional: Email Notification Integration (requires ACCOUNTADMIN)
-- Uncomment and configure if you want automatic email alerts.
-- Replace placeholders: <INTEGRATION_NAME>, <ALLOWED_RECIPIENTS>
-- CREATE NOTIFICATION INTEGRATION IF NOT EXISTS <INTEGRATION_NAME>
--   TYPE = EMAIL
--   ENABLED = TRUE
--   ALLOWED_RECIPIENTS = ('your.name@example.com');
-- SHOW INTEGRATIONS LIKE '<INTEGRATION_NAME>';

-- 4) Optional: External Access Integration for GitHub
-- Ensure your Notebook has access to fetch S and P 500 constituents if needed.
-- Example (adjust to your environment): GITHUB_EXTERNAL_ACCESS_INTEGRATION

-- 5) Bootstrap SP_500_LIST from repo CSV (datasets/sp500_constituents.csv)
--    Creates table and loads from the Git repository registered above.
--    This table is required by subsequent steps.
CREATE OR REPLACE FILE FORMAT CSV_HEADER_F1
  TYPE = CSV
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1;

CREATE OR REPLACE TABLE SP_500_LIST (
  SYMBOL STRING,
  SECURITY STRING,
  SECTOR STRING,
  SUB_INDUSTRY STRING,
  HEADQUARTERS STRING,
  DATE_ADDED DATE,
  CIK STRING,
  FOUNDED STRING
);

-- Create a dedicated internal stage for the CSV
CREATE STAGE IF NOT EXISTS SP500_CSV_STAGE
  FILE_FORMAT = CSV_HEADER_F1;
-- Load the staged CSV into the table
COPY FILES
  INTO @SP500_CSV_STAGE
  FROM '@SP500_ML_REPO/branches/main/datasets/sp500_constituents.csv';
COPY INTO SP_500_LIST (SYMBOL, SECURITY, SECTOR, SUB_INDUSTRY, HEADQUARTERS, DATE_ADDED, CIK, FOUNDED)
FROM (
  SELECT $1, $2, $3, $4, $5, TRY_TO_DATE($6), $7, $8
  FROM @SP500_CSV_STAGE/sp500_constituents.csv
)
FILE_FORMAT = (FORMAT_NAME = CSV_HEADER_F1);

-- 5) BRING IN DAILY DATA FROM SNOWFLAKE MARKET DATA
--    This table is required by subsequent steps.
-- https://app.snowflake.com/marketplace/listing/GZTSZAS2KF7/snowflake-public-data-products-finance-economics?originTab=provider&providerName=Snowflake%20Public%20Data%20Products&profileGlobalName=GZTSZAS2KCS
-- CALL THIS DATABASE FINANCIAL_DATA_PACKAGE
CREATE OR REPLACE TABLE DAILY_STOCK_PRICE AS
WITH base AS (
SELECT
  TICKER,
  ASSET_CLASS,
  PRIMARY_EXCHANGE_NAME,
  DATE,
  LOWER(VARIABLE) AS variable_name,
  VALUE
FROM FINANCIAL_DATA_PACKAGE.CYBERSYN.STOCK_PRICE_TIMESERIES
WHERE LOWER(VARIABLE) IN (
  'pre-market_open','post-market_close','all-day_high','all-day_low','nasdaq_volume'
)
),
mapped AS (
SELECT
  TICKER,
  ASSET_CLASS,
  PRIMARY_EXCHANGE_NAME,
  DATE,
  CASE
    WHEN variable_name = 'pre-market_open'   THEN 'OPEN'
    WHEN variable_name = 'all-day_high'      THEN 'HIGH'
    WHEN variable_name = 'all-day_low'       THEN 'LOW'
    WHEN variable_name = 'post-market_close' THEN 'CLOSE'
    WHEN variable_name = 'nasdaq_volume'     THEN 'VOLUME'
  END AS var_std,
  VALUE
FROM base
),
pivoted AS (
SELECT
  TICKER,
  ASSET_CLASS,
  PRIMARY_EXCHANGE_NAME,
  DATE,
  MAX(CASE WHEN var_std = 'LOW' THEN VALUE END)    AS LOW,
  MAX(CASE WHEN var_std = 'HIGH' THEN VALUE END)   AS HIGH,
  MAX(CASE WHEN var_std = 'CLOSE' THEN VALUE END)  AS CLOSE,
  MAX(CASE WHEN var_std = 'OPEN' THEN VALUE END)   AS OPEN,
  MAX(CASE WHEN var_std = 'VOLUME' THEN VALUE END) AS VOLUME
FROM mapped
GROUP BY TICKER, ASSET_CLASS, PRIMARY_EXCHANGE_NAME, DATE
)
SELECT
ci.COMPANY_NAME,
p.TICKER,
p.ASSET_CLASS,
p.PRIMARY_EXCHANGE_NAME,
p.DATE,
p.LOW,
p.HIGH,
p.CLOSE,
p.OPEN,
p.VOLUME
FROM pivoted p
LEFT JOIN FINANCIAL_DATA_PACKAGE.CYBERSYN.COMPANY_INDEX ci
ON ci.PRIMARY_TICKER = p.TICKER;

select top 10 * from DAILY_STOCK_PRICE;

select count(1) from DAILY_STOCK_PRICE;
-- End of setup

-- -------------------------------------------------------------------
-- 7) Create Snowflake Notebooks from Git repo (prefix: SP500_)
-- -------------------------------------------------------------------
-- Requires the Git repo object SP500_ML_REPO and warehouse DEMO_WH_S
-- Notebooks are created from files under @SP500_ML_REPO/branches/main/Notebooks/

CREATE OR REPLACE NOTEBOOK SP500_01_DATA_PREP
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '01_data_prep.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_02_FEATURE_STORE
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '02_feature_store.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_03_TRAIN_REGISTER
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '03_train_register.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_04_INFER_MONITOR
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '04_infer_monitor.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_05_RETRAIN_COMPARE
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '05_retrain_compare.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_07_TASK_SETUP
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '07_task_setup.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;

CREATE OR REPLACE NOTEBOOK SP500_08_NOTEBOOK
  FROM '@SP500_ML_REPO/branches/main/Notebooks'
  MAIN_FILE = '08_notebook.ipynb'
  QUERY_WAREHOUSE = DEMO_WH_S;