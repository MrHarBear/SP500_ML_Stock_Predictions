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
CREATE WAREHOUSE IF NOT EXISTS DEMO_WH_M
  WITH WAREHOUSE_SIZE = 'MEDIUM'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 120
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
-- GRANT USAGE ON WAREHOUSE DEMO_WH_M TO ROLE DEMO_ROLE;
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

COPY INTO SP_500_LIST (SYMBOL, SECURITY, SECTOR, SUB_INDUSTRY, HEADQUARTERS, DATE_ADDED, CIK, FOUNDED)
FROM (
  SELECT $1, $2, $3, $4, $5, TRY_TO_DATE($6), $7, $8
  FROM @SP500_ML_REPO/branches/main/datasets/sp500_constituents.csv
)
FILE_FORMAT = (FORMAT_NAME = CSV_HEADER_F1);

-- 5) Context helpers (optional)
-- USE ROLE DEMO_ROLE;
-- USE WAREHOUSE DEMO_WH_M;
-- USE DATABASE SP500_STOCK_DEMO;
-- USE SCHEMA DATA;

-- End of setup

