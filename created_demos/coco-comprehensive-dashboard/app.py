import os
import streamlit as st
import snowflake.connector
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# --- Snowflake connection (Posit Connect OAuth + local fallback) ---

def get_connection():
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE")
    try:
        from posit.connect.external.snowflake import PositAuthenticator
        auth = PositAuthenticator(local_authenticator="EXTERNALBROWSER")
        if auth.token:
            return snowflake.connector.connect(
                account=account,
                authenticator=auth.authenticator,
                token=auth.token,
                warehouse=warehouse,
            )
    except Exception:
        pass
    # Local fallback: PAT in Workbench, browser SSO on desktop
    params = dict(account=account, warehouse=warehouse)
    if os.environ.get("SNOWFLAKE_PASSWORD"):
        params["user"] = os.environ["SNOWFLAKE_USER"]
        params["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    else:
        params["user"] = os.environ["SNOWFLAKE_USER"]
        params["authenticator"] = "externalbrowser"
    return snowflake.connector.connect(**params)


@st.cache_resource
def init_connection():
    return get_connection()


def query(sql: str) -> pd.DataFrame:
    cur = init_connection().cursor()
    try:
        cur.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])
    finally:
        cur.close()


# --- Page config ---
st.set_page_config(
    page_title="COCO Demo — Comprehensive Dashboard",
    page_icon="📊",
    layout="wide",
)

# --- Navigation ---
page = st.sidebar.radio(
    "Navigate",
    ["Sales Overview", "Product Analysis", "Customer Insights", "Loan Risk Analysis"],
)

# ═══════════════════════════════════════════════════════════════════════════════
# PAGE 1: Sales Overview
# ═══════════════════════════════════════════════════════════════════════════════
if page == "Sales Overview":
    st.title("Sales Overview")
    st.caption("SOL_ENG_DEMO.COCO_DEMO — Revenue trends and regional performance")

    # Filters
    col_f1, col_f2 = st.columns(2)
    with col_f1:
        region = st.selectbox("Region", ["ALL", "CENTRAL", "EAST", "SOUTH", "WEST"])
    with col_f2:
        category = st.selectbox(
            "Product Category",
            ["ALL", "Apparel", "Automotive", "Books & Media", "Electronics",
             "Food & Beverage", "Health & Beauty", "Home & Garden", "Sports & Outdoors"],
        )

    conditions = []
    if region != "ALL":
        conditions.append(f"s.REGION = '{region}'")
    if category != "ALL":
        conditions.append(f"p.CATEGORY = '{category}'")
    where = "WHERE " + " AND ".join(conditions) if conditions else ""

    # KPIs
    kpi_sql = f"""
        SELECT
            COUNT(*) AS total_orders,
            SUM(s.AMOUNT) AS total_revenue,
            AVG(s.AMOUNT) AS avg_order_value,
            COUNT(DISTINCT s.CUSTOMER_ID) AS unique_customers
        FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
        JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
        {where}
    """
    kpi = query(kpi_sql).iloc[0]

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total Revenue", f"${kpi['TOTAL_REVENUE']:,.0f}")
    c2.metric("Total Orders", f"{kpi['TOTAL_ORDERS']:,}")
    c3.metric("Avg Order Value", f"${kpi['AVG_ORDER_VALUE']:,.0f}")
    c4.metric("Unique Customers", f"{kpi['UNIQUE_CUSTOMERS']:,}")

    # Monthly revenue trend
    trend_sql = f"""
        SELECT DATE_TRUNC('month', s.SALE_DATE) AS MONTH, SUM(s.AMOUNT) AS REVENUE
        FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
        JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
        {where}
        GROUP BY MONTH ORDER BY MONTH
    """
    trend_df = query(trend_sql)
    fig_trend = px.area(trend_df, x="MONTH", y="REVENUE",
                        title="Monthly Revenue Trend",
                        labels={"REVENUE": "Revenue ($)", "MONTH": ""})
    fig_trend.update_layout(margin=dict(t=40, b=0))
    st.plotly_chart(fig_trend, use_container_width=True)

    # Revenue by region
    col1, col2 = st.columns(2)
    with col1:
        region_sql = f"""
            SELECT s.REGION, SUM(s.AMOUNT) AS REVENUE
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
            {where}
            GROUP BY s.REGION ORDER BY REVENUE DESC
        """
        region_df = query(region_sql)
        fig_region = px.bar(region_df, x="REGION", y="REVENUE", color="REGION",
                            title="Revenue by Region")
        fig_region.update_layout(showlegend=False, margin=dict(t=40, b=0))
        st.plotly_chart(fig_region, use_container_width=True)

    with col2:
        cat_sql = f"""
            SELECT p.CATEGORY, SUM(s.AMOUNT) AS REVENUE
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
            {where}
            GROUP BY p.CATEGORY ORDER BY REVENUE DESC
        """
        cat_df = query(cat_sql)
        fig_cat = px.bar(cat_df, x="REVENUE", y="CATEGORY", orientation="h",
                         title="Revenue by Category", color="CATEGORY")
        fig_cat.update_layout(showlegend=False, margin=dict(t=40, b=0),
                              yaxis=dict(categoryorder="total ascending"))
        st.plotly_chart(fig_cat, use_container_width=True)

# ═══════════════════════════════════════════════════════════════════════════════
# PAGE 2: Product Analysis
# ═══════════════════════════════════════════════════════════════════════════════
elif page == "Product Analysis":
    st.title("Product Analysis")
    st.caption("Top performers, pricing distribution, and category deep-dive")

    # Top 15 products by revenue
    top_sql = """
        SELECT p.NAME AS PRODUCT, p.CATEGORY, p.UNIT_PRICE,
               COUNT(*) AS ORDERS, SUM(s.AMOUNT) AS REVENUE
        FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
        JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
        GROUP BY p.NAME, p.CATEGORY, p.UNIT_PRICE
        ORDER BY REVENUE DESC
        LIMIT 15
    """
    top_df = query(top_sql)

    fig_top = px.bar(top_df, x="REVENUE", y="PRODUCT", color="CATEGORY",
                     orientation="h", title="Top 15 Products by Revenue")
    fig_top.update_layout(yaxis=dict(categoryorder="total ascending"),
                          margin=dict(t=40, b=0))
    st.plotly_chart(fig_top, use_container_width=True)

    col1, col2 = st.columns(2)

    with col1:
        # Price distribution by category
        price_sql = """
            SELECT CATEGORY, UNIT_PRICE
            FROM SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM
        """
        price_df = query(price_sql)
        fig_price = px.box(price_df, x="CATEGORY", y="UNIT_PRICE",
                           title="Price Distribution by Category",
                           color="CATEGORY")
        fig_price.update_layout(showlegend=False, margin=dict(t=40, b=0))
        st.plotly_chart(fig_price, use_container_width=True)

    with col2:
        # Revenue share by category (pie)
        share_sql = """
            SELECT p.CATEGORY, SUM(s.AMOUNT) AS REVENUE
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
            GROUP BY p.CATEGORY
        """
        share_df = query(share_sql)
        fig_share = px.pie(share_df, names="CATEGORY", values="REVENUE",
                           title="Revenue Share by Category")
        fig_share.update_layout(margin=dict(t=40, b=0))
        st.plotly_chart(fig_share, use_container_width=True)

    # Monthly trend by category
    cat_trend_sql = """
        SELECT DATE_TRUNC('month', s.SALE_DATE) AS MONTH,
               p.CATEGORY, SUM(s.AMOUNT) AS REVENUE
        FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
        JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
        GROUP BY MONTH, p.CATEGORY
        ORDER BY MONTH
    """
    cat_trend_df = query(cat_trend_sql)
    fig_cat_trend = px.line(cat_trend_df, x="MONTH", y="REVENUE", color="CATEGORY",
                            title="Monthly Revenue by Category")
    fig_cat_trend.update_layout(margin=dict(t=40, b=0))
    st.plotly_chart(fig_cat_trend, use_container_width=True)

# ═══════════════════════════════════════════════════════════════════════════════
# PAGE 3: Customer Insights
# ═══════════════════════════════════════════════════════════════════════════════
elif page == "Customer Insights":
    st.title("Customer Insights")
    st.caption("Segment analysis, geographic distribution, and cohort trends")

    col1, col2 = st.columns(2)

    with col1:
        seg_sql = """
            SELECT c.SEGMENT, COUNT(DISTINCT c.CUSTOMER_ID) AS CUSTOMERS,
                   SUM(s.AMOUNT) AS REVENUE,
                   AVG(s.AMOUNT) AS AVG_ORDER
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_DIM c ON s.CUSTOMER_ID = c.CUSTOMER_ID
            GROUP BY c.SEGMENT
            ORDER BY REVENUE DESC
        """
        seg_df = query(seg_sql)
        fig_seg = px.bar(seg_df, x="SEGMENT", y="REVENUE", color="SEGMENT",
                         title="Revenue by Customer Segment",
                         text="CUSTOMERS")
        fig_seg.update_layout(showlegend=False, margin=dict(t=40, b=0))
        st.plotly_chart(fig_seg, use_container_width=True)

    with col2:
        geo_sql = """
            SELECT c.COUNTRY, COUNT(DISTINCT c.CUSTOMER_ID) AS CUSTOMERS,
                   SUM(s.AMOUNT) AS REVENUE
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_DIM c ON s.CUSTOMER_ID = c.CUSTOMER_ID
            GROUP BY c.COUNTRY ORDER BY REVENUE DESC
        """
        geo_df = query(geo_sql)
        fig_geo = px.bar(geo_df, x="COUNTRY", y="REVENUE", color="COUNTRY",
                         title="Revenue by Country", text="CUSTOMERS")
        fig_geo.update_layout(showlegend=False, margin=dict(t=40, b=0))
        st.plotly_chart(fig_geo, use_container_width=True)

    # Segment revenue over time
    seg_trend_sql = """
        SELECT DATE_TRUNC('month', s.SALE_DATE) AS MONTH,
               c.SEGMENT, SUM(s.AMOUNT) AS REVENUE
        FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
        JOIN SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_DIM c ON s.CUSTOMER_ID = c.CUSTOMER_ID
        GROUP BY MONTH, c.SEGMENT ORDER BY MONTH
    """
    seg_trend_df = query(seg_trend_sql)
    fig_seg_trend = px.area(seg_trend_df, x="MONTH", y="REVENUE", color="SEGMENT",
                            title="Monthly Revenue by Segment (Stacked)")
    fig_seg_trend.update_layout(margin=dict(t=40, b=0))
    st.plotly_chart(fig_seg_trend, use_container_width=True)

    # Signup cohort analysis
    cohort_sql = """
        SELECT DATE_TRUNC('quarter', c.SIGNUP_DATE) AS COHORT,
               c.SEGMENT,
               COUNT(DISTINCT c.CUSTOMER_ID) AS CUSTOMERS
        FROM SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_DIM c
        GROUP BY COHORT, c.SEGMENT
        ORDER BY COHORT
    """
    cohort_df = query(cohort_sql)
    fig_cohort = px.bar(cohort_df, x="COHORT", y="CUSTOMERS", color="SEGMENT",
                        title="Customer Signups by Quarter & Segment",
                        barmode="stack")
    fig_cohort.update_layout(margin=dict(t=40, b=0))
    st.plotly_chart(fig_cohort, use_container_width=True)

# ═══════════════════════════════════════════════════════════════════════════════
# PAGE 4: Loan Risk Analysis
# ═══════════════════════════════════════════════════════════════════════════════
elif page == "Loan Risk Analysis":
    st.title("Loan Risk Analysis")
    st.caption("SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS — Credit risk and default patterns")

    # Overview KPIs
    loan_kpi_sql = """
        SELECT COUNT(*) AS TOTAL_APPS,
               SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) AS DEFAULTS,
               AVG(LOAN_AMOUNT) AS AVG_LOAN,
               AVG(CREDIT_SCORE) AS AVG_CREDIT_SCORE,
               AVG(DEBT_TO_INCOME) AS AVG_DTI
        FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
    """
    lkpi = query(loan_kpi_sql).iloc[0]
    default_rate = lkpi["DEFAULTS"] / lkpi["TOTAL_APPS"] * 100

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Total Applications", f"{lkpi['TOTAL_APPS']:,.0f}")
    c2.metric("Default Rate", f"{default_rate:.1f}%")
    c3.metric("Avg Loan Amount", f"${lkpi['AVG_LOAN']:,.0f}")
    c4.metric("Avg Credit Score", f"{lkpi['AVG_CREDIT_SCORE']:.0f}")
    c5.metric("Avg DTI Ratio", f"{lkpi['AVG_DTI']:.2f}")

    col1, col2 = st.columns(2)

    with col1:
        # Default rate by term
        term_sql = """
            SELECT TERM,
                   COUNT(*) AS TOTAL,
                   SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) AS DEFAULTS,
                   SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DEFAULT_RATE
            FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
            GROUP BY TERM
        """
        term_df = query(term_sql)
        fig_term = px.bar(term_df, x="TERM", y="DEFAULT_RATE", color="TERM",
                          title="Default Rate by Loan Term",
                          labels={"DEFAULT_RATE": "Default Rate (%)"})
        fig_term.update_layout(showlegend=False, margin=dict(t=40, b=0))
        st.plotly_chart(fig_term, use_container_width=True)

    with col2:
        # Credit score distribution by default status
        credit_sql = """
            SELECT
                CASE WHEN "DEFAULT" = 1 THEN 'Defaulted' ELSE 'Performing' END AS STATUS,
                FLOOR(CREDIT_SCORE / 50) * 50 AS SCORE_BIN,
                COUNT(*) AS CNT
            FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
            GROUP BY STATUS, SCORE_BIN
            ORDER BY SCORE_BIN
        """
        credit_df = query(credit_sql)
        fig_credit = px.bar(credit_df, x="SCORE_BIN", y="CNT", color="STATUS",
                            barmode="overlay", title="Credit Score Distribution",
                            labels={"SCORE_BIN": "Credit Score", "CNT": "Count"},
                            opacity=0.7)
        fig_credit.update_layout(margin=dict(t=40, b=0))
        st.plotly_chart(fig_credit, use_container_width=True)

    # Default rate by credit score bucket
    bucket_sql = """
        SELECT
            CASE
                WHEN CREDIT_SCORE < 550 THEN '300-549'
                WHEN CREDIT_SCORE < 650 THEN '550-649'
                WHEN CREDIT_SCORE < 700 THEN '650-699'
                WHEN CREDIT_SCORE < 750 THEN '700-749'
                ELSE '750+'
            END AS CREDIT_BUCKET,
            COUNT(*) AS TOTAL,
            SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DEFAULT_RATE,
            AVG(LOAN_AMOUNT) AS AVG_LOAN,
            AVG(DEBT_TO_INCOME) AS AVG_DTI
        FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
        GROUP BY CREDIT_BUCKET
        ORDER BY CREDIT_BUCKET
    """
    bucket_df = query(bucket_sql)

    col3, col4 = st.columns(2)
    with col3:
        fig_bucket = px.bar(bucket_df, x="CREDIT_BUCKET", y="DEFAULT_RATE",
                            title="Default Rate by Credit Score Bucket",
                            labels={"DEFAULT_RATE": "Default Rate (%)", "CREDIT_BUCKET": "Credit Score"},
                            color="DEFAULT_RATE",
                            color_continuous_scale="Reds")
        fig_bucket.update_layout(margin=dict(t=40, b=0))
        st.plotly_chart(fig_bucket, use_container_width=True)

    with col4:
        # DTI vs Default rate
        dti_sql = """
            SELECT
                FLOOR(DEBT_TO_INCOME * 10) / 10 AS DTI_BIN,
                COUNT(*) AS TOTAL,
                SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DEFAULT_RATE
            FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
            GROUP BY DTI_BIN
            ORDER BY DTI_BIN
        """
        dti_df = query(dti_sql)
        fig_dti = px.line(dti_df, x="DTI_BIN", y="DEFAULT_RATE",
                          title="Default Rate by Debt-to-Income Ratio",
                          labels={"DTI_BIN": "DTI Ratio", "DEFAULT_RATE": "Default Rate (%)"},
                          markers=True)
        fig_dti.update_layout(margin=dict(t=40, b=0))
        st.plotly_chart(fig_dti, use_container_width=True)

    # Delinquency impact
    del_sql = """
        SELECT DELINQUENCIES_LAST_2Y AS DELINQUENCIES,
               COUNT(*) AS TOTAL,
               SUM(CASE WHEN "DEFAULT" = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DEFAULT_RATE
        FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
        WHERE DELINQUENCIES_LAST_2Y <= 20
        GROUP BY DELINQUENCIES_LAST_2Y
        ORDER BY DELINQUENCIES_LAST_2Y
    """
    del_df = query(del_sql)
    fig_del = px.bar(del_df, x="DELINQUENCIES", y="DEFAULT_RATE",
                     title="Default Rate by Prior Delinquencies (Last 2 Years)",
                     labels={"DELINQUENCIES": "# Delinquencies", "DEFAULT_RATE": "Default Rate (%)"},
                     color="DEFAULT_RATE", color_continuous_scale="YlOrRd")
    fig_del.update_layout(margin=dict(t=40, b=0))
    st.plotly_chart(fig_del, use_container_width=True)

    # Data table sample
    with st.expander("View Sample Data"):
        sample_sql = """
            SELECT APPLICATION_ID, LOAN_AMOUNT, CREDIT_SCORE, TERM,
                   DEBT_TO_INCOME, DELINQUENCIES_LAST_2Y, "DEFAULT"
            FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
            LIMIT 100
        """
        st.dataframe(query(sample_sql), use_container_width=True)
