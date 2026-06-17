"""
Snowflake RBAC Demo — Streamlit on Posit Connect
==================================================
Demonstrates that Posit Connect inherits Snowflake role-based access control
via viewer OAuth passthrough. Each viewer sees only the data their Snowflake
role permits — no app-level filtering logic required.

BEFORE YOUR FIRST RUN:
  Run scripts/setup-demo-data.sql to create demo data and RBAC roles.

CONFIGURE via environment variables (or edit the defaults below):
  DEMO_DATABASE       — database name (default: SOL_ENG_DEMO)
  DEMO_SCHEMA         — schema name (default: COCO_DEMO)
  SNOWFLAKE_WAREHOUSE — warehouse name (default: DEFAULT_WH)

DEPLOY:
  rsconnect deploy streamlit . --name rbac-demo --title "RBAC Demo"

DEMO FLOW:
  1. Open the app as POSIT_DEMO_ANALYST → sees EAST only, income masked
  2. Open as POSIT_DEMO_EXECUTIVE → sees everything
  3. Point out: ZERO lines of filtering code in this app.
"""

import os
import streamlit as st
import pandas as pd
import plotly.express as px
import snowflake.connector

# ── Configuration ────────────────────────────────────────────────────────────
# Set these env vars to match your setup-demo-data.sql, or edit the defaults.

DEMO_DATABASE = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA   = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
DEMO_WH       = os.environ.get("SNOWFLAKE_WAREHOUSE", "DEFAULT_WH")
FQN           = f"{DEMO_DATABASE}.{DEMO_SCHEMA}"

# ── Page config ──────────────────────────────────────────────────────────────

st.set_page_config(
    page_title="RBAC Demo — Posit + Snowflake",
    page_icon="🔐",
    layout="wide",
)

# ── Snowflake connection ─────────────────────────────────────────────────────

@st.cache_resource
def get_connection():
    """Connect using viewer's Snowflake identity passed through by Posit Connect."""

    # Option 1: Posit Connect viewer OAuth (production)
    if os.environ.get("SNOWFLAKE_TOKEN"):
        return snowflake.connector.connect(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            token=os.environ["SNOWFLAKE_TOKEN"],
            authenticator="oauth",
            warehouse=DEMO_WH,
            database=DEMO_DATABASE,
            schema=DEMO_SCHEMA,
        )

    # Option 2: External browser SSO (local dev / demo without Connect)
    if os.environ.get("SNOWFLAKE_ACCOUNT"):
        return snowflake.connector.connect(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            authenticator="externalbrowser",
            warehouse=DEMO_WH,
            database=DEMO_DATABASE,
            schema=DEMO_SCHEMA,
        )

    st.error(
        "No Snowflake credentials found. Set SNOWFLAKE_ACCOUNT and either "
        "SNOWFLAKE_TOKEN (Connect OAuth) or use externalbrowser auth."
    )
    st.stop()


conn = get_connection()

# ── Helper to run queries ────────────────────────────────────────────────────

def run_query(sql: str) -> pd.DataFrame:
    cur = conn.cursor()
    try:
        cur.execute(sql)
        cols = [desc[0] for desc in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)
    finally:
        cur.close()

# ── Discover current role and access ─────────────────────────────────────────

role_df = run_query("SELECT CURRENT_ROLE() AS role, CURRENT_USER() AS username")
current_role = role_df["ROLE"].iloc[0]
current_user = role_df["USERNAME"].iloc[0]

sales_stats = run_query(f"""
    SELECT
        COUNT(*)            AS total_rows,
        COUNT(DISTINCT region) AS regions_visible,
        LISTAGG(DISTINCT region, ', ') WITHIN GROUP (ORDER BY region) AS region_list
    FROM {FQN}.SALES_FACT
""")

loan_stats = run_query(f"""
    SELECT
        COUNT(*)              AS total_rows,
        COUNT(annual_income)  AS income_visible_count
    FROM {FQN}.LOAN_APPLICATIONS
    LIMIT 1000
""")

total_sales_rows = int(sales_stats["TOTAL_ROWS"].iloc[0])
regions_visible = int(sales_stats["REGIONS_VISIBLE"].iloc[0])
region_list = sales_stats["REGION_LIST"].iloc[0]
income_visible = int(loan_stats["INCOME_VISIBLE_COUNT"].iloc[0]) > 0

# ── Header ───────────────────────────────────────────────────────────────────

st.title("🔐 Snowflake RBAC on Posit Connect")
st.markdown(
    "This app has **zero data-filtering logic**. Every restriction you see "
    "is enforced by Snowflake's row access policies and masking policies, "
    "inherited through Posit Connect's viewer OAuth passthrough."
)

# ── Role badge and access summary ────────────────────────────────────────────

role_colors = {
    "POSIT_DEMO_ANALYST": "🟡",
    "POSIT_DEMO_MANAGER": "🟠",
    "POSIT_DEMO_EXECUTIVE": "🟢",
}
role_icon = role_colors.get(current_role, "⚪")

st.divider()

col_role, col_user = st.columns([2, 1])
with col_role:
    st.metric("Your Snowflake Role", f"{role_icon}  {current_role}")
with col_user:
    st.metric("Logged in as", current_user)

# ── Access metrics ───────────────────────────────────────────────────────────

st.divider()
st.subheader("What your role can see")

col1, col2, col3, col4 = st.columns(4)
col1.metric("Sales rows visible", f"{total_sales_rows:,}")
col2.metric("Regions accessible", f"{regions_visible} of 4")
col3.metric("Regions", region_list or "None")
col4.metric("Income data", "✅ Visible" if income_visible else "🚫 Masked")

# ── Comparison table ─────────────────────────────────────────────────────────

st.divider()
st.subheader("Role comparison")
st.markdown("Same app, same URL, same code — different data based on Snowflake role:")

comparison_data = {
    "Role": ["POSIT_DEMO_ANALYST", "POSIT_DEMO_MANAGER", "POSIT_DEMO_EXECUTIVE"],
    "Regions": ["EAST only", "All 4 regions", "All 4 regions"],
    "Sales rows": ["~12,500", "~50,000", "~50,000"],
    "Loan rows": ["2,200,000", "2,200,000", "2,200,000"],
    "Annual income": ["🚫 Masked (NULL)", "🚫 Masked (NULL)", "✅ Visible"],
    "Enforced by": ["Row access policy", "Row access policy", "No restrictions"],
}
comparison_df = pd.DataFrame(comparison_data)

def highlight_current_role(row):
    if row["Role"] == current_role:
        return ["background-color: #e6f3ff; font-weight: bold"] * len(row)
    return [""] * len(row)

st.dataframe(
    comparison_df.style.apply(highlight_current_role, axis=1),
    use_container_width=True,
    hide_index=True,
)

# ── Live data: Sales by region ───────────────────────────────────────────────

st.divider()
st.subheader("📊 Sales data (filtered by your role's row access policy)")

sales_by_region = run_query(f"""
    SELECT
        region,
        COUNT(*)       AS transactions,
        ROUND(SUM(amount), 2) AS total_revenue
    FROM {FQN}.SALES_FACT
    GROUP BY region
    ORDER BY total_revenue DESC
""")

if not sales_by_region.empty:
    col_chart, col_table = st.columns([3, 2])

    with col_chart:
        fig = px.bar(
            sales_by_region,
            x="REGION", y="TOTAL_REVENUE", color="REGION",
            title="Revenue by Region",
            labels={"TOTAL_REVENUE": "Revenue ($)", "REGION": "Region"},
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        fig.update_layout(showlegend=False)
        st.plotly_chart(fig, use_container_width=True)

    with col_table:
        st.dataframe(
            sales_by_region.rename(columns={
                "REGION": "Region",
                "TRANSACTIONS": "Transactions",
                "TOTAL_REVENUE": "Revenue",
            }),
            use_container_width=True,
            hide_index=True,
        )

    if regions_visible < 4:
        st.info(
            f"🔒 You're seeing **{regions_visible} of 4 regions**. "
            f"The row access policy on `SALES_FACT` restricts your role "
            f"(`{current_role}`) to: **{region_list}**. "
            f"Switch to POSIT_DEMO_MANAGER or POSIT_DEMO_EXECUTIVE to see all."
        )
else:
    st.warning("No sales data visible for your current role.")

# ── Live data: Loan applications (masking demo) ─────────────────────────────

st.divider()
st.subheader("🏦 Loan applications (masking policy demo)")

loan_sample = run_query(f"""
    SELECT
        application_id, loan_amount, credit_score, term,
        annual_income, debt_to_income, delinquencies_last_2y
    FROM {FQN}.LOAN_APPLICATIONS
    LIMIT 20
""")

if not loan_sample.empty:
    if income_visible:
        st.success(
            f"✅ Your role (`{current_role}`) has full access. "
            f"`annual_income` is visible."
        )
    else:
        st.warning(
            f"🚫 Your role (`{current_role}`) has `annual_income` masked by a "
            f"Snowflake masking policy. The column shows as NULL. "
            f"Switch to POSIT_DEMO_EXECUTIVE to see actual values."
        )
    st.dataframe(loan_sample, use_container_width=True, hide_index=True)

# ── Footer ───────────────────────────────────────────────────────────────────

st.divider()
st.markdown(
    f"""
    ### The takeaway

    This Streamlit app contains **no `if role == ...` logic**. No `WHERE`
    clauses filter by user. No column is hidden in Python.

    Everything you see — which rows appear, which columns are masked — is
    enforced by **Snowflake's row access policies and masking policies**.
    Posit Connect simply passes the viewer's Snowflake identity through via
    OAuth. The app code is identical for every viewer; Snowflake decides what
    they see.

    **That's the value of Posit Connect + Snowflake RBAC.**

    ---
    *Demo data: `{FQN}` · Setup: `scripts/setup-demo-data.sql`*
    """
)
