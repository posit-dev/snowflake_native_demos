import os
import snowflake.connector
import pandas as pd
import plotly.express as px
from shiny import App, ui, render, reactive

def get_connection():
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE")
    try:
        from posit.connect.external.snowflake import PositAuthenticator
        auth = PositAuthenticator(local_authenticator="EXTERNALBROWSER")
        return snowflake.connector.connect(
            account=account,
            authenticator=auth.authenticator,
            token=auth.token,
            warehouse=warehouse,
        )
    except Exception:
        return snowflake.connector.connect(
            account=account,
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

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.input_select("term", "Loan Term", choices=["ALL", "36 months", "60 months"]),
        ui.input_slider("credit_range", "Credit Score Range", min=300, max=900, value=(300, 900)),
        ui.input_slider("max_rows", "Max Rows", min=100, max=5000, value=1000, step=100),
    ),
    ui.layout_columns(
        ui.value_box("Total Applications", ui.output_text("total_count")),
        ui.value_box("Avg Loan Amount", ui.output_text("avg_loan")),
        ui.value_box("Default Rate", ui.output_text("default_rate")),
        col_widths=[4, 4, 4],
    ),
    ui.layout_columns(
        ui.card(
            ui.card_header("Loan Amount Distribution"),
            ui.output_ui("hist_chart"),
        ),
        ui.card(
            ui.card_header("Default Rate by Credit Score Bin"),
            ui.output_ui("default_chart"),
        ),
        col_widths=[6, 6],
    ),
    ui.card(
        ui.card_header("Application Data"),
        ui.output_data_frame("table"),
    ),
    title="Loan Explorer",
)


def server(input, output, session):
    @reactive.calc
    def filtered_data():
        credit_min, credit_max = input.credit_range()
        sql = f"""
            SELECT APPLICATION_ID, LOAN_AMOUNT, CREDIT_SCORE, TERM,
                   DEBT_TO_INCOME, DELINQUENCIES_LAST_2Y, "DEFAULT"
            FROM SOL_ENG_DEMO.COCO_DEMO.LOAN_APPLICATIONS
            WHERE CREDIT_SCORE BETWEEN {credit_min} AND {credit_max}
        """
        if input.term() != "ALL":
            sql += f" AND TERM = '{input.term()}'"
        sql += f" LIMIT {input.max_rows()}"
        return query(sql)

    @render.text
    def total_count():
        return f"{len(filtered_data()):,}"

    @render.text
    def avg_loan():
        df = filtered_data()
        if df.empty:
            return "$0"
        return f"${df['LOAN_AMOUNT'].mean():,.0f}"

    @render.text
    def default_rate():
        df = filtered_data()
        if df.empty:
            return "0%"
        return f"{df['DEFAULT'].mean() * 100:.1f}%"

    @render.ui
    def hist_chart():
        df = filtered_data()
        if df.empty:
            return ui.p("No data")
        fig = px.histogram(df, x="LOAN_AMOUNT", nbins=30, title="")
        fig.update_layout(margin=dict(t=10, b=40), xaxis_title="Loan Amount", yaxis_title="Count")
        return ui.HTML(fig.to_html(full_html=False, include_plotlyjs="cdn"))

    @render.ui
    def default_chart():
        df = filtered_data()
        if df.empty:
            return ui.p("No data")
        df["CREDIT_BIN"] = pd.cut(df["CREDIT_SCORE"], bins=6)
        agg = df.groupby("CREDIT_BIN", observed=True)["DEFAULT"].mean().reset_index()
        agg["CREDIT_BIN"] = agg["CREDIT_BIN"].astype(str)
        agg["DEFAULT_RATE"] = agg["DEFAULT"] * 100
        fig = px.bar(agg, x="CREDIT_BIN", y="DEFAULT_RATE", title="")
        fig.update_layout(margin=dict(t=10, b=40), xaxis_title="Credit Score Bin", yaxis_title="Default Rate (%)")
        return ui.HTML(fig.to_html(full_html=False, include_plotlyjs="cdn"))

    @render.data_frame
    def table():
        return filtered_data()


app = App(app_ui, server)
