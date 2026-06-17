-- =============================================================================
-- Deploy to Posit Connect from CoCo via SPCS
-- =============================================================================
-- This stored procedure runs inside Snowpark Container Services where it can
-- reach the Connect server at https://connect. CoCo calls it with SQL to
-- deploy apps without leaving Snowsight.
--
-- Usage from CoCo:
--
--   CALL POSIT_DEPLOY(
--     'streamlit',                              -- framework
--     'loan-risk-dashboard',                    -- app name
--     'Loan Risk Dashboard',                    -- title (shown in Connect)
--     OBJECT_CONSTRUCT(                         -- files (filename → content)
--       'app.py', '<your app code>',
--       'requirements.txt', 'streamlit>=1.36.0\nsnowflake-connector-python>=3.12.0'
--     )
--   );
--
-- Prerequisites:
--   1. Posit Connect running in the same SPCS environment (Native App)
--   2. A Connect API key stored as a Snowflake secret
--   3. Network access from the procedure to https://connect
--
-- NOTE ON PYTHON VERSIONS:
--   The RUNTIME_VERSION in each procedure is the version that runs the
--   DEPLOY HELPER — not the version your app runs on Connect. Your app
--   uses whatever Python or R version Connect has installed. If 3.11 isn't
--   available in your Snowflake account, change it to 3.9 or 3.10.
--
-- Setup:
--   Run this script once to create the secret and procedure.
-- =============================================================================

-- ── 1. Store your Connect API key as a Snowflake secret ─────────────────────
-- Get your API key from Connect: Settings → API Keys → New API Key
-- Replace <YOUR_API_KEY> below.

CREATE SECRET IF NOT EXISTS POSIT_CONNECT_API_KEY
  TYPE = GENERIC_STRING
  SECRET_STRING = '<YOUR_CONNECT_API_KEY>';

-- ── 2. Create the deploy procedure ─────────────────────────────────────────

CREATE OR REPLACE PROCEDURE POSIT_DEPLOY(
  framework VARCHAR,        -- streamlit | shiny-python | dash | fastapi | bokeh | quarto | shiny-r | plumber
  app_name VARCHAR,         -- URL-safe name (e.g., 'loan-risk-dashboard')
  app_title VARCHAR,        -- Display title (e.g., 'Loan Risk Dashboard')
  files VARIANT             -- OBJECT_CONSTRUCT('filename', 'content', ...)
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'  -- Change to match your Snowflake account (3.8, 3.9, 3.10, 3.11)
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'deploy'
SECRETS = ('connect_api_key' = POSIT_CONNECT_API_KEY)
AS
$$
import json
import hashlib
import io
import os
import tarfile
import time
import requests
import _snowflake

CONNECT_URL = "https://connect"

# Map framework names to Connect appmode values
FRAMEWORK_MAP = {
    "streamlit":     {"appmode": "python-streamlit",  "entrypoint": "app.py",      "lang": "python"},
    "shiny-python":  {"appmode": "python-shiny",      "entrypoint": "app.py",      "lang": "python"},
    "shiny":         {"appmode": "python-shiny",      "entrypoint": "app.py",      "lang": "python"},
    "dash":          {"appmode": "python-dash",       "entrypoint": "app.py",      "lang": "python"},
    "fastapi":       {"appmode": "python-fastapi",    "entrypoint": "app.py",      "lang": "python"},
    "bokeh":         {"appmode": "python-bokeh",      "entrypoint": "app.py",      "lang": "python"},
    "panel":         {"appmode": "python-bokeh",      "entrypoint": "app.py",      "lang": "python"},
    "quarto":        {"appmode": "quarto-static",     "entrypoint": "index.qmd",   "lang": "python"},
    "shiny-r":       {"appmode": "shiny",             "entrypoint": "app.R",       "lang": "r"},
    "plumber":       {"appmode": "api",               "entrypoint": "plumber.R",   "lang": "r"},
}


def deploy(session, framework, app_name, app_title, files):
    """Deploy an app to Posit Connect via its REST API."""

    # Validate framework
    fw = framework.lower().strip()
    if fw not in FRAMEWORK_MAP:
        return f"ERROR: Unknown framework '{framework}'. Use one of: {', '.join(FRAMEWORK_MAP.keys())}"

    fw_config = FRAMEWORK_MAP[fw]

    # Get API key from Snowflake secret
    api_key = _snowflake.get_generic_secret_string('connect_api_key')
    headers = {
        "Authorization": f"Key {api_key}",
        "Content-Type": "application/json",
    }

    # Parse files from VARIANT
    if isinstance(files, str):
        file_dict = json.loads(files)
    else:
        file_dict = dict(files)

    if not file_dict:
        return "ERROR: No files provided. Pass files as OBJECT_CONSTRUCT('filename', 'content', ...)"

    # ── Step 1: Find or create the content item ─────────────────────────

    # Check if content with this name already exists
    resp = requests.get(
        f"{CONNECT_URL}/__api__/v1/content",
        headers=headers,
        params={"name": app_name},
        verify=False,
    )
    resp.raise_for_status()
    existing = resp.json()

    if existing:
        guid = existing[0]["guid"]
        # Update title if needed
        requests.patch(
            f"{CONNECT_URL}/__api__/v1/content/{guid}",
            headers=headers,
            json={"title": app_title},
            verify=False,
        )
    else:
        # Create new content item
        resp = requests.post(
            f"{CONNECT_URL}/__api__/v1/content",
            headers=headers,
            json={"name": app_name, "title": app_title},
            verify=False,
        )
        resp.raise_for_status()
        guid = resp.json()["guid"]

    # ── Step 2: Build the bundle (tar.gz) ───────────────────────────────

    # Generate manifest.json
    manifest_files = {}
    for filename, content in file_dict.items():
        content_bytes = content.encode("utf-8") if isinstance(content, str) else content
        md5 = hashlib.md5(content_bytes).hexdigest()
        manifest_files[filename] = {"checksum": md5}

    manifest = {
        "version": 1,
        "metadata": {
            "appmode": fw_config["appmode"],
            "entrypoint": fw_config["entrypoint"],
        },
        "files": manifest_files,
    }

    # Let Connect auto-detect the runtime version.
    # Only specify the package manager so Connect knows how to install deps.
    if fw_config["lang"] == "python":
        manifest["python"] = {
            "version": "3",
            "package_manager": {
                "name": "pip",
                "package_file": "requirements.txt",
            },
        }
    # For R, Connect detects the version from the renv.lock if present.
    # No version field needed in the manifest.

    # Add manifest to files
    manifest_json = json.dumps(manifest, indent=2)
    file_dict["manifest.json"] = manifest_json

    # Create tar.gz in memory
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for filename, content in file_dict.items():
            content_bytes = content.encode("utf-8") if isinstance(content, str) else content
            info = tarfile.TarInfo(name=filename)
            info.size = len(content_bytes)
            tar.addfile(info, io.BytesIO(content_bytes))

    bundle_bytes = buf.getvalue()

    # ── Step 3: Upload the bundle ───────────────────────────────────────

    resp = requests.post(
        f"{CONNECT_URL}/__api__/v1/content/{guid}/bundles",
        headers={"Authorization": f"Key {api_key}"},
        data=bundle_bytes,
        verify=False,
    )
    resp.raise_for_status()
    bundle_id = resp.json()["id"]

    # ── Step 4: Deploy the bundle ───────────────────────────────────────

    resp = requests.post(
        f"{CONNECT_URL}/__api__/v1/content/{guid}/deploy",
        headers=headers,
        json={"bundle_id": bundle_id},
        verify=False,
    )
    resp.raise_for_status()
    task_id = resp.json()["task_id"]

    # ── Step 5: Poll for completion ─────────────────────────────────────

    for _ in range(60):  # Wait up to 5 minutes
        resp = requests.get(
            f"{CONNECT_URL}/__api__/v1/content/{guid}/tasks/{task_id}",
            headers=headers,
            verify=False,
        )
        resp.raise_for_status()
        task = resp.json()

        if task.get("finished"):
            if task.get("code", 0) == 0:
                content_url = f"{CONNECT_URL}/content/{guid}/"
                return json.dumps({
                    "status": "SUCCESS",
                    "url": content_url,
                    "guid": guid,
                    "bundle_id": bundle_id,
                    "message": f"Deployed '{app_title}' to {content_url}",
                    "files": list(file_dict.keys()),
                })
            else:
                return json.dumps({
                    "status": "FAILED",
                    "error": task.get("error", "Unknown deployment error"),
                    "output": task.get("output", ""),
                })
        time.sleep(5)

    return json.dumps({
        "status": "TIMEOUT",
        "message": "Deployment started but did not complete within 5 minutes. Check Connect dashboard.",
        "guid": guid,
    })
$$;

-- ── 3. Grant access ─────────────────────────────────────────────────────────
-- Grant execute to roles that should be able to deploy from CoCo.
-- Adjust to match your environment.

-- GRANT USAGE ON PROCEDURE POSIT_DEPLOY(VARCHAR, VARCHAR, VARCHAR, VARIANT)
--   TO ROLE <your_role>;

-- ── 4. Test it ──────────────────────────────────────────────────────────────

-- Quick test with a minimal Streamlit app:
--
-- CALL POSIT_DEPLOY(
--   'streamlit',
--   'test-coco-deploy',
--   'Test CoCo Deploy',
--   OBJECT_CONSTRUCT(
--     'app.py', 'import streamlit as st\nst.title("Hello from CoCo!")\nst.write("Deployed via POSIT_DEPLOY procedure.")',
--     'requirements.txt', 'streamlit>=1.36.0'
--   )
-- );


-- =============================================================================
-- POSIT_STAGE_FILES — Write generated code to a stage for Workbench pickup
-- =============================================================================
-- Use this to get CoCo-generated code into a user's Posit Workbench home
-- directory. CoCo calls this from any surface (Snowsight, CLI, Desktop),
-- then the user pulls from Workbench with one command.
--
-- Usage from CoCo:
--
--   CALL POSIT_STAGE_FILES(
--     'loan-risk-dashboard',                     -- folder name
--     OBJECT_CONSTRUCT(
--       'app.py', '<code>',
--       'requirements.txt', '<deps>'
--     )
--   );
--
-- Then from a Workbench terminal:
--
--   python -c "
--   import snowflake.connector, os
--   conn = snowflake.connector.connect(host=os.environ['SNOWFLAKE_HOST'],
--     account=os.environ['SNOWFLAKE_ACCOUNT'],
--     token=open('/snowflake/session/token').read(),
--     authenticator='oauth')
--   conn.cursor().execute(\"GET @POSIT_FILE_STAGE/loan-risk-dashboard/ file://~/loan-risk-dashboard/\")
--   "
--
--   Or simply:  snowsql -q "GET @POSIT_FILE_STAGE/loan-risk-dashboard/ file://~/loan-risk-dashboard/"
-- =============================================================================

-- Create the shared stage for file transfer
CREATE STAGE IF NOT EXISTS POSIT_FILE_STAGE
  COMMENT = 'Bridge between CoCo and Posit Workbench home directories';

-- The staging procedure
CREATE OR REPLACE PROCEDURE POSIT_STAGE_FILES(
  folder_name VARCHAR,      -- Project folder name (e.g., 'loan-risk-dashboard')
  files VARIANT             -- OBJECT_CONSTRUCT('filename', 'content', ...)
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'  -- Change to match your Snowflake account (3.8, 3.9, 3.10, 3.11)
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'stage_files'
AS
$$
import json
import os
import tempfile

def stage_files(session, folder_name, files):
    """Write files to an internal stage for Workbench pickup."""

    if isinstance(files, str):
        file_dict = json.loads(files)
    else:
        file_dict = dict(files)

    if not file_dict:
        return "ERROR: No files provided."

    staged_files = []

    # Write each file to a temp location, then PUT to stage
    for filename, content in file_dict.items():
        with tempfile.NamedTemporaryFile(
            mode='w', suffix=f'_{filename}', delete=False
        ) as f:
            f.write(content if isinstance(content, str) else content.decode('utf-8'))
            tmp_path = f.name

        stage_path = f"@POSIT_FILE_STAGE/{folder_name}/{filename}"
        session.sql(
            f"PUT 'file://{tmp_path}' '{stage_path}' AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
        ).collect()

        os.unlink(tmp_path)
        staged_files.append(filename)

    # Generate the pull command for Workbench
    pull_cmd = f'GET @POSIT_FILE_STAGE/{folder_name}/ file://~/{folder_name}/'

    return json.dumps({
        "status": "STAGED",
        "stage": f"@POSIT_FILE_STAGE/{folder_name}/",
        "files": staged_files,
        "pull_command": pull_cmd,
        "message": (
            f"Files staged. From a Workbench terminal, run:\n"
            f"  snowsql -q \"{pull_cmd}\"\n"
            f"Or open a Python console and run:\n"
            f"  import subprocess; subprocess.run(['snowsql', '-q', '{pull_cmd}'])"
        ),
    })
$$;

-- =============================================================================
-- POSIT_PUSH — Generate, stage, AND deploy in one call
-- =============================================================================
-- Combines staging (for Workbench access) with deployment (to Connect).
-- Use when the user wants both: code in their IDE AND a running app.

CREATE OR REPLACE PROCEDURE POSIT_PUSH(
  framework VARCHAR,
  app_name VARCHAR,
  app_title VARCHAR,
  files VARIANT
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'  -- Change to match your Snowflake account (3.8, 3.9, 3.10, 3.11)
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'push'
SECRETS = ('connect_api_key' = POSIT_CONNECT_API_KEY)
AS
$$
import json

def push(session, framework, app_name, app_title, files):
    """Stage files for Workbench AND deploy to Connect."""

    results = {}

    # Stage files
    try:
        stage_result = session.sql(
            f"CALL POSIT_STAGE_FILES('{app_name}', PARSE_JSON('{json.dumps(dict(files) if not isinstance(files, str) else json.loads(files))}'))"
        ).collect()
        results["staged"] = json.loads(stage_result[0][0])
    except Exception as e:
        results["staged"] = {"status": "ERROR", "error": str(e)}

    # Deploy to Connect
    try:
        files_json = json.dumps(dict(files) if not isinstance(files, str) else json.loads(files))
        deploy_result = session.sql(
            f"CALL POSIT_DEPLOY('{framework}', '{app_name}', '{app_title}', PARSE_JSON('{files_json}'))"
        ).collect()
        results["deployed"] = json.loads(deploy_result[0][0])
    except Exception as e:
        results["deployed"] = {"status": "ERROR", "error": str(e)}

    return json.dumps(results, indent=2)
$$;

-- ── Grant access to all three procedures ────────────────────────────────────

-- GRANT USAGE ON PROCEDURE POSIT_DEPLOY(VARCHAR, VARCHAR, VARCHAR, VARIANT)
--   TO ROLE <your_role>;
-- GRANT USAGE ON PROCEDURE POSIT_STAGE_FILES(VARCHAR, VARIANT)
--   TO ROLE <your_role>;
-- GRANT USAGE ON PROCEDURE POSIT_PUSH(VARCHAR, VARCHAR, VARCHAR, VARIANT)
--   TO ROLE <your_role>;
-- GRANT READ, WRITE ON STAGE POSIT_FILE_STAGE
--   TO ROLE <your_role>;
