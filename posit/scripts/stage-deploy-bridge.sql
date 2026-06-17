-- =============================================================================
-- Stage-Deploy Bridge — install ONCE per account (no admin, no EAI)
-- =============================================================================
-- One central deploy queue for the whole account. Users in ANY database or
-- schema call the procedure fully-qualified; nothing is hardcoded per app.
--
--   CoCo (any surface, any schema)          Connect watcher (inside SPCS)
--   ──────────────────────────────          ─────────────────────────────
--   CALL <BRIDGE>.POSIT_REQUEST_DEPLOY(     Polls <BRIDGE>.POSIT_DEPLOY_REQUESTS,
--     framework, name, title, files,        pulls files from the bridge stage,
--     env_vars)                             deploys via https://connect,
--   → poll status via SQL                   sets env vars on the content,
--                                           writes back COMPLETE + URL
--
-- INSTALL: pick a home for the bridge, then run this script as-is.
--   USE DATABASE <your_db>;          -- e.g. a shared utility database
--   CREATE SCHEMA IF NOT EXISTS POSIT_BRIDGE;
--   USE SCHEMA POSIT_BRIDGE;
--   -- then execute everything below
--
-- The watcher needs exactly two Vars (one-time, on the watcher content only):
--   BRIDGE_DATABASE, BRIDGE_SCHEMA  → where you installed this.
-- =============================================================================

-- ── 1. Bridge stage (optional) ──────────────────────────────────────────────
-- No longer required for the request path \u2014 files now travel in-row. Kept only
-- if you also want a stage-based handoff to Workbench. Safe to skip.

CREATE STAGE IF NOT EXISTS POSIT_FILE_STAGE
  COMMENT = 'Optional: stage-based handoff to Workbench. Not used by the in-row deploy path.';

-- ── 2. Deploy requests queue ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS POSIT_DEPLOY_REQUESTS (
  request_id    VARCHAR DEFAULT UUID_STRING(),
  framework     VARCHAR,
  app_name      VARCHAR,
  app_title     VARCHAR,
  files         VARIANT,           -- {filename: content} \u2014 carried in-row, no stage/PUT needed
  env_vars      VARIANT,           -- optional: {"NAME": "value"} set on the content at deploy
  status        VARCHAR DEFAULT 'PENDING',   -- PENDING | IN_PROGRESS | COMPLETE | FAILED
  result        VARIANT,
  requested_by  VARCHAR DEFAULT CURRENT_USER(),
  requested_at  TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  completed_at  TIMESTAMP_LTZ
);

-- ── 3. Request procedure — pure SQL INSERT, NO PUT, callable from anywhere ──
-- Files are embedded in the request row as a VARIANT. The watcher reads them
-- directly from the table. No stage, no PUT (PUT is unavailable inside stored
-- procedures \u2014 they have no client filesystem), works from every CoCo surface.

CREATE OR REPLACE PROCEDURE POSIT_REQUEST_DEPLOY(
  framework VARCHAR,
  app_name VARCHAR,
  app_title VARCHAR,
  files VARIANT,
  env_vars VARIANT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  new_id VARCHAR;
BEGIN
  new_id := UUID_STRING();
  INSERT INTO POSIT_DEPLOY_REQUESTS (request_id, framework, app_name, app_title, files, env_vars)
    SELECT :new_id, :framework, :app_name, :app_title, :files, :env_vars;
  RETURN OBJECT_CONSTRUCT(
    'status', 'REQUESTED',
    'request_id', :new_id,
    'message', 'Deploy request queued. Poll: SELECT status, result FROM '
               || 'POSIT_DEPLOY_REQUESTS WHERE request_id = ''' || :new_id || ''''
  )::VARCHAR;
END;
$$;

-- ── 4. Grant account-wide access ────────────────────────────────────────────
-- Adjust the role(s) to whoever should be able to deploy from CoCo.
-- Because the procedure is owner's-rights, callers need only USAGE.

-- GRANT USAGE ON DATABASE  <bridge_db>                       TO ROLE PUBLIC;
-- GRANT USAGE ON SCHEMA    <bridge_db>.POSIT_BRIDGE          TO ROLE PUBLIC;
-- GRANT USAGE ON PROCEDURE POSIT_REQUEST_DEPLOY(VARCHAR, VARCHAR, VARCHAR, VARIANT, VARIANT)
--   TO ROLE PUBLIC;
-- GRANT SELECT ON TABLE POSIT_DEPLOY_REQUESTS                TO ROLE PUBLIC;  -- for status polling
