import os
import snowflake.connector
import pandas as pd
import plotly.express as px
from shiny import App, ui, render, reactive
from shinywidgets import render_plotly, output_widget

# --- Snowflake connection (Posit Connect OAuth + local browser SSO fallback) ---

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
    return snowflake.connector.connect(
        account=account,
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="externalbrowser",
        warehouse=warehouse,
    )


def query(sql: str) -> pd.DataFrame:
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])
    finally:
        cur.close()
        conn.close()


# --- UI ---

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.input_select(
            "region", "Region",
            choices=["ALL", "CENTRAL", "EAST", "SOUTH", "WEST"],
        ),
        ui.input_select(
            "category", "Product Category",
            choices=[
                "ALL", "Apparel", "Automotive", "Books & Media", "Electronics",
                "Food & Beverage", "Health & Beauty", "Home & Garden",
                "Sports & Outdoors",
            ],
        ),
        ui.input_select(
            "segment", "Customer Segment",
            choices=["ALL", "Consumer", "Enterprise", "Mid-Market", "SMB"],
        ),
        width=280,
    ),
    ui.layout_columns(
        ui.value_box("Total Revenue", ui.output_text("total_revenue"), theme="primary"),
        ui.value_box("Total Orders", ui.output_text("total_orders"), theme="info"),
        ui.value_box("Avg Order Value", ui.output_text("avg_order"), theme="success"),
        col_widths=[4, 4, 4],
    ),
    ui.layout_columns(
        ui.card(
            ui.card_header("Monthly Revenue Trend"),
            output_widget("revenue_trend"),
        ),
        ui.card(
            ui.card_header("Revenue by Region"),
            output_widget("region_chart"),
        ),
        col_widths=[8, 4],
    ),
    ui.layout_columns(
        ui.card(
            ui.card_header("Top 10 Products"),
            output_widget("top_products"),
        ),
        ui.card(
            ui.card_header("Revenue by Customer Segment"),
            output_widget("segment_chart"),
        ),
        col_widths=[6, 6],
    ),
    title="Sales Dashboard — SOL_ENG_DEMO.COCO_DEMO",
    fillable=True,
)


# --- Server ---

def server(input, output, session):

    @reactive.calc
    def filtered_data() -> pd.DataFrame:
        conditions = []
        if input.region() != "ALL":
            conditions.append(f"s.REGION = '{input.region()}'")
        if input.category() != "ALL":
            conditions.append(f"p.CATEGORY = '{input.category()}'")
        if input.segment() != "ALL":
            conditions.append(f"c.SEGMENT = '{input.segment()}'")

        where = "WHERE " + " AND ".join(conditions) if conditions else ""

        sql = f"""
            SELECT
                s.SALE_ID, s.SALE_DATE, s.AMOUNT, s.REGION,
                p.NAME AS PRODUCT_NAME, p.CATEGORY,
                c.SEGMENT, c.COUNTRY
            FROM SOL_ENG_DEMO.COCO_DEMO.SALES_FACT s
            JOIN SOL_ENG_DEMO.COCO_DEMO.PRODUCT_DIM p ON s.PRODUCT_ID = p.PRODUCT_ID
            JOIN SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_DIM c ON s.CUSTOMER_ID = c.CUSTOMER_ID
            {where}
        """
        return query(sql)

    @render.text
    def total_revenue():
        df = filtered_data()
        return f"${df['AMOUNT'].sum():,.0f}"

    @render.text
    def total_orders():
        return f"{len(filtered_data()):,}"

    @render.text
    def avg_order():
        df = filtered_data()
        avg = df["AMOUNT"].mean() if len(df) > 0 else 0
        return f"${avg:,.0f}"

    @render_plotly
    def revenue_trend():
        df = filtered_data().copy()
        df["MONTH"] = pd.to_datetime(df["SALE_DATE"]).dt.to_period("M").dt.to_timestamp()
        monthly = df.groupby("MONTH", as_index=False)["AMOUNT"].sum()
        fig = px.line(monthly, x="MONTH", y="AMOUNT", labels={"AMOUNT": "Revenue", "MONTH": "Month"})
        fig.update_layout(margin=dict(t=10, b=0, l=0, r=0))
        return fig

    @render_plotly
    def region_chart():
        df = filtered_data()
        by_region = df.groupby("REGION", as_index=False)["AMOUNT"].sum()
        fig = px.bar(by_region, x="REGION", y="AMOUNT", color="REGION",
                     labels={"AMOUNT": "Revenue"})
        fig.update_layout(margin=dict(t=10, b=0, l=0, r=0), showlegend=False)
        return fig

    @render_plotly
    def top_products():
        df = filtered_data()
        top = df.groupby("PRODUCT_NAME", as_index=False)["AMOUNT"].sum() \
                .nlargest(10, "AMOUNT")
        fig = px.bar(top, x="AMOUNT", y="PRODUCT_NAME", orientation="h",
                     labels={"AMOUNT": "Revenue", "PRODUCT_NAME": "Product"})
        fig.update_layout(margin=dict(t=10, b=0, l=0, r=0), yaxis=dict(categoryorder="total ascending"))
        return fig

    @render_plotly
    def segment_chart():
        df = filtered_data()
        by_seg = df.groupby("SEGMENT", as_index=False)["AMOUNT"].sum()
        fig = px.pie(by_seg, names="SEGMENT", values="AMOUNT")
        fig.update_layout(margin=dict(t=10, b=0, l=0, r=0))
        return fig


app = App(app_ui, server)
