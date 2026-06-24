# Sales Dashboard — coco-demo-dashboard

Shiny for Python dashboard reading from `SOL_ENG_DEMO.COCO_DEMO` (SALES_FACT, PRODUCT_DIM, CUSTOMER_DIM).

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

    shiny run app.py

Before running locally, set two environment variables so browser SSO can
authenticate your session:

    export SNOWFLAKE_ACCOUNT=<your-account>      # e.g. ORG-ACCOUNT
    export SNOWFLAKE_USER=<your-login>           # e.g. FIRST.LAST@COMPANY.COM

The app connects to Snowflake via the Posit Connect OAuth integration when
deployed (no user needed); locally it falls back to browser SSO using
SNOWFLAKE_USER. No secrets file needed.

## Deploy to Connect

Click Publish in Positron, or: `rsconnect deploy shiny .`
