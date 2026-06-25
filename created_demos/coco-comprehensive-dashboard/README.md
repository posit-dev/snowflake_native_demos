# COCO Comprehensive Dashboard

Multi-page Streamlit dashboard covering the full `SOL_ENG_DEMO.COCO_DEMO` dataset:

- **Sales Overview** — Revenue trends, regional performance, category breakdown
- **Product Analysis** — Top products, pricing distribution, category trends
- **Customer Insights** — Segment analysis, geography, signup cohorts
- **Loan Risk Analysis** — Default rates, credit score impact, DTI analysis

## Run locally in Posit Workbench / Positron

Using uv (fast, recommended):

    uv venv
    source .venv/bin/activate
    uv pip install -r requirements.txt

Or with the standard library venv:

    python -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt

Then run:

    streamlit run app.py

**Viewing the app:** In Posit Workbench, open it in the Positron **Viewer
pane** (or the Workbench-proxied URL) — NOT `localhost:<port>` in your laptop
browser, which can't reach the container and shows "localhost refused to
connect."

**Authenticating to Snowflake locally** — set environment variables for your
context before running:

In Posit Workbench (recommended — no browser needed):

    export SNOWFLAKE_ACCOUNT=<your-account>      # e.g. ORG-ACCOUNT
    export SNOWFLAKE_USER=<your-login>           # e.g. FIRST.LAST@COMPANY.COM
    export SNOWFLAKE_PASSWORD=<a PAT>            # Programmatic Access Token

On a local laptop (Cortex Desktop — opens a browser to sign in):

    export SNOWFLAKE_ACCOUNT=<your-account>
    export SNOWFLAKE_USER=<your-login>
    # no password; a browser SSO window opens

When deployed to Connect, none of these are needed — the OAuth integration
provides the token automatically. No secrets file, ever. NOTE: browser SSO
(externalbrowser) does NOT work inside Workbench — use a PAT there.

## Deploy to Connect

Click Publish in Positron, or: `rsconnect deploy streamlit .`
