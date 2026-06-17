-- =============================================================================
-- Posit CoCo Skill — Demo Environment Teardown
-- =============================================================================
-- Removes the schema and RBAC roles created by setup-demo-data.sql.
-- Safe to run multiple times. Does NOT drop the database or warehouse.
-- =============================================================================

-- Match these to whatever you set in setup-demo-data.sql
SET DEMO_DATABASE = 'SOL_ENG_DEMO';
SET DEMO_SCHEMA   = 'COCO_DEMO';

-- Drop RBAC roles (requires SECURITYADMIN — skip if unavailable)
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS POSIT_DEMO_EXECUTIVE;
DROP ROLE IF EXISTS POSIT_DEMO_MANAGER;
DROP ROLE IF EXISTS POSIT_DEMO_ANALYST;

-- Drop the demo schema (all tables, views, and policies inside it)
USE ROLE SYSADMIN;
BEGIN
  LET v_fqn VARCHAR := (SELECT GETVARIABLE('DEMO_DATABASE')) || '.' || (SELECT GETVARIABLE('DEMO_SCHEMA'));
  EXECUTE IMMEDIATE 'DROP SCHEMA IF EXISTS ' || :v_fqn || ' CASCADE';
END;

-- ✅  Demo schema and RBAC roles removed. Database and warehouse untouched.
