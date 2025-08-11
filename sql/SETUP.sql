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

-- 5) Context helpers (optional)
-- USE ROLE DEMO_ROLE;
-- USE WAREHOUSE DEMO_WH_M;
-- USE DATABASE SP500_STOCK_DEMO;
-- USE SCHEMA DATA;

-- End of setup

