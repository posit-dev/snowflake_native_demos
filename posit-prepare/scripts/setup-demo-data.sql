-- =============================================================================
-- Posit CoCo Skill — Demo Environment Setup
-- =============================================================================
-- Run this script in Snowsight, CoCo CLI, or CoCo Desktop to create the
-- sample data needed for all demos in this skill.
--
-- Time:     ~60 seconds (2.2M loan rows)
-- Cleanup:  Run scripts/teardown-demo.sql
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ CONFIGURE THE THREE VARIABLES BELOW — NOTHING ELSE IS HARDCODED.       │
-- │                                                                         │
-- │ Requirements:                                                           │
-- │   • A role with CREATE SCHEMA on the target database                    │
-- │   • An existing warehouse you can USE                                   │
-- │   • SECURITYADMIN for Demo D (RBAC) — optional, skip if unavailable    │
-- └─────────────────────────────────────────────────────────────────────────┘
-- =============================================================================

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIGURE THESE THREE VARIABLES — EDIT THESE FOR YOUR ENVIRONMENT
-- ══════════════════════════════════════════════════════════════════════════════

SET DEMO_DATABASE  = 'SOL_ENG_DEMO';   -- Your existing database
SET DEMO_SCHEMA    = 'COCO_DEMO';      -- Schema to create (any name you want)
SET DEMO_WAREHOUSE = 'DEFAULT_WH';     -- Your existing warehouse

-- ══════════════════════════════════════════════════════════════════════════════
-- SETUP (edit nothing below this line)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Set context and create schema ────────────────────────────────────────

EXECUTE IMMEDIATE $$
DECLARE
  v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  v_wh     VARCHAR := (SELECT GETVARIABLE('DEMO_WAREHOUSE'));
BEGIN
  EXECUTE IMMEDIATE 'USE DATABASE '  || v_db;
  EXECUTE IMMEDIATE 'USE WAREHOUSE ' || v_wh;
  EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS ' || v_db || '.' || v_schema;
  EXECUTE IMMEDIATE 'USE SCHEMA '    || v_schema;
END;
$$;

-- ── 2. Product dimension ────────────────────────────────────────────────────

CREATE OR REPLACE TABLE PRODUCT_DIM AS
WITH products AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4()) AS product_id,
    CASE MOD(SEQ4(), 8)
      WHEN 0 THEN 'Electronics'
      WHEN 1 THEN 'Apparel'
      WHEN 2 THEN 'Home & Garden'
      WHEN 3 THEN 'Sports & Outdoors'
      WHEN 4 THEN 'Books & Media'
      WHEN 5 THEN 'Health & Beauty'
      WHEN 6 THEN 'Automotive'
      WHEN 7 THEN 'Food & Beverage'
    END AS category,
    CASE MOD(SEQ4(), 8)
      WHEN 0 THEN ARRAY_CONSTRUCT('Wireless Headphones','Smart Speaker','USB-C Hub','Portable Charger','Webcam','Keyboard','Monitor','Tablet Stand')
      WHEN 1 THEN ARRAY_CONSTRUCT('Running Shoes','Winter Jacket','Denim Jeans','Polo Shirt','Hiking Boots','Rain Coat','Beanie','Backpack')
      WHEN 2 THEN ARRAY_CONSTRUCT('Standing Desk','LED Lamp','Air Purifier','Coffee Maker','Throw Blanket','Plant Pot','Wall Art','Bookshelf')
      WHEN 3 THEN ARRAY_CONSTRUCT('Yoga Mat','Camping Tent','Water Bottle','Bike Lock','Jump Rope','Resistance Bands','Football','Fishing Rod')
      WHEN 4 THEN ARRAY_CONSTRUCT('Sci-Fi Novel','Cookbook','Board Game','Vinyl Record','Puzzle Set','Journal','Art Prints','Audiobook Credit')
      WHEN 5 THEN ARRAY_CONSTRUCT('Sunscreen SPF50','Vitamin D','Face Moisturizer','Electric Toothbrush','Shampoo Bar','Hand Cream','Sleep Mask','Protein Powder')
      WHEN 6 THEN ARRAY_CONSTRUCT('Floor Mats','Phone Mount','Tire Gauge','Dash Cam','Seat Cover','Wiper Blades','Oil Filter','Air Freshener')
      WHEN 7 THEN ARRAY_CONSTRUCT('Organic Coffee','Trail Mix','Hot Sauce','Olive Oil','Honey','Granola Bars','Sparkling Water','Dark Chocolate')
    END AS names_array,
    ROUND(UNIFORM(5.99, 299.99, RANDOM()), 2) AS unit_price
  FROM TABLE(GENERATOR(ROWCOUNT => 64))
)
SELECT
  product_id,
  GET(names_array, MOD(product_id - 1, 8))::STRING AS name,
  category,
  unit_price
FROM products;

-- ── 3. Customer dimension ───────────────────────────────────────────────────

CREATE OR REPLACE TABLE CUSTOMER_DIM AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SEQ4()) AS customer_id,
  CASE MOD(SEQ4(), 4)
    WHEN 0 THEN 'Enterprise'
    WHEN 1 THEN 'Mid-Market'
    WHEN 2 THEN 'SMB'
    WHEN 3 THEN 'Consumer'
  END AS segment,
  CASE MOD(SEQ4(), 6)
    WHEN 0 THEN 'United States'
    WHEN 1 THEN 'Canada'
    WHEN 2 THEN 'United Kingdom'
    WHEN 3 THEN 'Germany'
    WHEN 4 THEN 'Australia'
    WHEN 5 THEN 'Japan'
  END AS country,
  DATEADD('day', -UNIFORM(30, 1800, RANDOM()), CURRENT_DATE()) AS signup_date
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

-- ── 4. Sales fact table (2 years of transactions) ───────────────────────────

CREATE OR REPLACE TABLE SALES_FACT AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SEQ8()) AS sale_id,
  DATEADD('day', -UNIFORM(0, 730, RANDOM()), CURRENT_DATE()) AS sale_date,
  ROUND(UNIFORM(10.00, 2500.00, RANDOM()), 2) AS amount,
  CASE MOD(UNIFORM(0, 3, RANDOM()), 4)
    WHEN 0 THEN 'EAST'
    WHEN 1 THEN 'WEST'
    WHEN 2 THEN 'CENTRAL'
    WHEN 3 THEN 'SOUTH'
  END AS region,
  UNIFORM(1, 64, RANDOM()) AS product_id,
  UNIFORM(1, 2000, RANDOM()) AS customer_id
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

-- ── 5. Loan applications (for orbital / ML demo) ───────────────────────────
-- 2.2 million rows — large enough to make the orbital demo punchline land:
-- "2.2 million applications scored in native SQL. No R runtime. No data export."

CREATE OR REPLACE TABLE LOAN_APPLICATIONS AS
WITH base AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ8()) AS application_id,
    ROUND(UNIFORM(1000, 40000, RANDOM()), -2) AS loan_amount,
    UNIFORM(300, 850, RANDOM()) AS credit_score,
    CASE WHEN UNIFORM(0, 1, RANDOM()) > 0.5 THEN '36 months' ELSE '60 months' END AS term,
    ROUND(UNIFORM(20000, 200000, RANDOM()), -3) AS annual_income,
    ROUND(UNIFORM(0.05, 0.95, RANDOM()), 2) AS debt_to_income,
    UNIFORM(0, 30, RANDOM()) AS delinquencies_last_2y,
    CASE
      WHEN MOD(SEQ8(), 5) = 0 THEN 'TEST'
      ELSE 'TRAIN'
    END AS split
  FROM TABLE(GENERATOR(ROWCOUNT => 2200000))
)
SELECT
  *,
  CASE
    WHEN credit_score < 580 AND debt_to_income > 0.6 THEN 1
    WHEN credit_score < 580 AND UNIFORM(0, 1, RANDOM()) > 0.5 THEN 1
    WHEN credit_score < 670 AND debt_to_income > 0.7 AND delinquencies_last_2y > 5 THEN 1
    WHEN delinquencies_last_2y > 15 AND UNIFORM(0, 1, RANDOM()) > 0.4 THEN 1
    WHEN UNIFORM(0, 1, RANDOM()) > 0.92 THEN 1
    ELSE 0
  END AS default
FROM base;

-- ── 6. Pre-computed predictions view (simulates orbital output) ─────────────
-- In a real workflow, orbital generates this VIEW automatically.
-- For demo purposes we create it directly so the loan-dashboard app works
-- without needing to run R first.

CREATE OR REPLACE VIEW LOAN_PREDICTIONS AS
SELECT
  application_id,
  loan_amount,
  credit_score,
  term,
  annual_income,
  debt_to_income,
  delinquencies_last_2y,
  ROUND(
    GREATEST(0, LEAST(1,
      0.8
      - (credit_score - 300) / 700.0 * 0.6
      + debt_to_income * 0.3
      + delinquencies_last_2y / 30.0 * 0.2
      + (CASE WHEN term = '60 months' THEN 0.05 ELSE 0 END)
      - (annual_income - 20000) / 200000.0 * 0.15
    )), 4
  ) AS ".pred_default"
FROM LOAN_APPLICATIONS;

-- ── 7. RBAC demo roles and policies (for Streamlit RBAC demo) ───────────────
-- Requires: SECURITYADMIN (or ACCOUNTADMIN). If this section fails,
-- just stop here — Demos A/B/C still work without it.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS POSIT_DEMO_ANALYST;
CREATE ROLE IF NOT EXISTS POSIT_DEMO_MANAGER;
CREATE ROLE IF NOT EXISTS POSIT_DEMO_EXECUTIVE;

GRANT ROLE POSIT_DEMO_ANALYST   TO ROLE POSIT_DEMO_MANAGER;
GRANT ROLE POSIT_DEMO_MANAGER   TO ROLE POSIT_DEMO_EXECUTIVE;
GRANT ROLE POSIT_DEMO_EXECUTIVE TO ROLE SYSADMIN;

-- Grant access to the demo schema and warehouse
BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_wh     VARCHAR := (SELECT GETVARIABLE('DEMO_WAREHOUSE'));
  LET v_fqn    VARCHAR := v_db || '.' || v_schema;
  EXECUTE IMMEDIATE 'GRANT USAGE ON DATABASE '  || :v_db  || ' TO ROLE POSIT_DEMO_ANALYST';
  EXECUTE IMMEDIATE 'GRANT USAGE ON SCHEMA '    || :v_fqn || ' TO ROLE POSIT_DEMO_ANALYST';
  EXECUTE IMMEDIATE 'GRANT USAGE ON WAREHOUSE ' || :v_wh  || ' TO ROLE POSIT_DEMO_ANALYST';
  EXECUTE IMMEDIATE 'GRANT SELECT ON ALL TABLES IN SCHEMA ' || :v_fqn || ' TO ROLE POSIT_DEMO_ANALYST';
  EXECUTE IMMEDIATE 'GRANT SELECT ON ALL VIEWS IN SCHEMA '  || :v_fqn || ' TO ROLE POSIT_DEMO_ANALYST';
END;

-- Switch back to owner role to create policies
BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_wh     VARCHAR := (SELECT GETVARIABLE('DEMO_WAREHOUSE'));
  EXECUTE IMMEDIATE 'USE ROLE SYSADMIN';
  EXECUTE IMMEDIATE 'USE DATABASE '  || v_db;
  EXECUTE IMMEDIATE 'USE WAREHOUSE ' || v_wh;
  EXECUTE IMMEDIATE 'USE SCHEMA '    || v_schema;
END;

-- Row access policy: analysts see only EAST region, managers+ see all
CREATE OR REPLACE ROW ACCESS POLICY REGION_ACCESS_POLICY
  AS (region_val VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('POSIT_DEMO_MANAGER', 'POSIT_DEMO_EXECUTIVE', 'SYSADMIN', 'ACCOUNTADMIN')
    OR (CURRENT_ROLE() = 'POSIT_DEMO_ANALYST' AND region_val = 'EAST');

ALTER TABLE SALES_FACT
  ADD ROW ACCESS POLICY REGION_ACCESS_POLICY ON (region);

-- Masking policy: annual_income is visible only to executives and admins
CREATE OR REPLACE MASKING POLICY INCOME_MASK AS (val NUMBER) RETURNS NUMBER ->
  CASE
    WHEN CURRENT_ROLE() IN ('POSIT_DEMO_EXECUTIVE', 'SYSADMIN', 'ACCOUNTADMIN') THEN val
    ELSE NULL
  END;

ALTER TABLE LOAN_APPLICATIONS
  MODIFY COLUMN annual_income SET MASKING POLICY INCOME_MASK;

-- ── 8. Verify ───────────────────────────────────────────────────────────────

SELECT 'PRODUCT_DIM'       AS table_name, COUNT(*) AS row_count FROM PRODUCT_DIM
UNION ALL
SELECT 'CUSTOMER_DIM',      COUNT(*) FROM CUSTOMER_DIM
UNION ALL
SELECT 'SALES_FACT',        COUNT(*) FROM SALES_FACT
UNION ALL
SELECT 'LOAN_APPLICATIONS', COUNT(*) FROM LOAN_APPLICATIONS
UNION ALL
SELECT 'LOAN_PREDICTIONS',  COUNT(*) FROM LOAN_PREDICTIONS
ORDER BY table_name;

-- Expected output:
-- CUSTOMER_DIM            2,000
-- LOAN_APPLICATIONS   2,200,000
-- LOAN_PREDICTIONS    2,200,000
-- PRODUCT_DIM                64
-- SALES_FACT             50,000

-- Verify RBAC: analyst should see only EAST region sales
USE ROLE POSIT_DEMO_ANALYST;
BEGIN
  LET v_wh VARCHAR := (SELECT GETVARIABLE('DEMO_WAREHOUSE'));
  EXECUTE IMMEDIATE 'USE WAREHOUSE ' || :v_wh;
END;

BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_fqn    VARCHAR := v_db || '.' || v_schema;
  LET v_sql    VARCHAR;

  v_sql := 'SELECT ''ANALYST sees'' AS who, COUNT(*) AS sales_rows, COUNT(DISTINCT region) AS regions FROM ' || v_fqn || '.SALES_FACT';
  EXECUTE IMMEDIATE v_sql;
END;

USE ROLE POSIT_DEMO_MANAGER;
BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_fqn    VARCHAR := v_db || '.' || v_schema;
  LET v_sql    VARCHAR;

  v_sql := 'SELECT ''MANAGER sees'' AS who, COUNT(*) AS sales_rows, COUNT(DISTINCT region) AS regions FROM ' || v_fqn || '.SALES_FACT';
  EXECUTE IMMEDIATE v_sql;
END;

-- Verify masking: analyst should see NULL for annual_income
USE ROLE POSIT_DEMO_ANALYST;
BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_fqn    VARCHAR := v_db || '.' || v_schema;
  LET v_sql    VARCHAR;

  v_sql := 'SELECT ''ANALYST income visible?'' AS who, COUNT(annual_income) AS non_null_incomes FROM ' || v_fqn || '.LOAN_APPLICATIONS LIMIT 10';
  EXECUTE IMMEDIATE v_sql;
END;

USE ROLE POSIT_DEMO_EXECUTIVE;
BEGIN
  LET v_db     VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE'));
  LET v_schema VARCHAR := (SELECT GETVARIABLE('DEMO_SCHEMA'));
  LET v_fqn    VARCHAR := v_db || '.' || v_schema;
  LET v_sql    VARCHAR;

  v_sql := 'SELECT ''EXECUTIVE income visible?'' AS who, COUNT(annual_income) AS non_null_incomes FROM ' || v_fqn || '.LOAN_APPLICATIONS LIMIT 10';
  EXECUTE IMMEDIATE v_sql;
END;

USE ROLE SYSADMIN;

-- ✅  Demo environment ready.
-- ✅  All objects live in <DEMO_DATABASE>.<DEMO_SCHEMA>
-- ✅  RBAC policies active: ANALYST=EAST only + income masked,
--     MANAGER=all regions + income masked, EXECUTIVE=full access.
