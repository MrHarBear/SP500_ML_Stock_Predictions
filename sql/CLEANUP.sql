-- -------------------------------------------------------------------
-- Cleanup for SP500 Stock ML Demo
-- Drops demo objects created by SETUP and notebooks.
-- WARNING: This will drop data and feature store registrations.
-- -------------------------------------------------------------------

-- Set context as needed
-- USE ROLE DEMO_ROLE;
-- USE WAREHOUSE DEMO_WH;

-- Drop Feature Store tables/registrations created in this demo
-- Adjust if your FS metadata lives elsewhere.

-- Drop objects in schema (safe order)
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

-- Notebook 02 objects
DROP VIEW IF EXISTS HOURLY_SP500_SIM_VIEW;
DROP TABLE IF EXISTS PRICE_FEATURES;

-- Notebook 01 objects
DROP TABLE IF EXISTS HOURLY_SP500_SIM;
DROP TABLE IF EXISTS DAILY_SP500;
DROP TABLE IF EXISTS SP500_TICKERS;

-- Stages
DROP STAGE IF EXISTS MONITORING;

DROP STAGE IF EXISTS LANDING;

-- Optionally drop schema and database (uncomment if desired)
-- DROP SCHEMA IF EXISTS SP500_STOCK_DEMO.DATA;
-- DROP DATABASE IF EXISTS SP500_STOCK_DEMO;

-- Warehouse (uncomment if created solely for this demo)
-- DROP WAREHOUSE IF EXISTS DEMO_WH;

-- End cleanup
