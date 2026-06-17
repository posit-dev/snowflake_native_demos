# Posit Connect Frameworks — Scaffold Templates

**These templates are for Posit Connect, NOT Streamlit-in-Snowflake.**
Every template uses `snowflake.connector.connect()` (Python) or
`DBI::dbConnect(odbc::odbc(), ...)` (R) — never `st.connection("snowflake")`
or `snowflake.snowpark.context`. The apps are standalone files that deploy
to Posit Connect via `rsconnect deploy` or the `POSIT_REQUEST_DEPLOY` bridge.

## CRITICAL: how a deployed app connects to Snowflake on Connect

**NEVER use `st.secrets`, `secrets.toml`, `st.connection("snowflake")`, or
hardcoded credentials.** A deployed app has no secrets file — using
`st.secrets` throws `StreamlitSecretNotFoundError` at runtime.

On Posit Connect with the Snowflake OAuth integration, the platform injects
the Snowflake token at runtime. Get it via posit-sdk and pass it to the
connector. Use this exact `get_connection()` in EVERY Python app (Streamlit,
Dash, FastAPI, Panel, Bokeh):

```python
import os
import snowflake.connector

def get_connection():
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE")

    # On Posit Connect: get the Snowflake token from the OAuth integration
    try:
        from posit.connect.external.snowflake import PositAuthenticator
        auth = PositAuthenticator(
            local_authenticator="EXTERNALBROWSER",  # used only in local dev
        )
        return snowflake.connector.connect(
            account=account,
            authenticator=auth.authenticator,   # "oauth" on Connect
            token=auth.token,                    # injected by Connect
            warehouse=warehouse,
        )
    except Exception:
        pass

    # Local development fallback (browser SSO)
    return snowflake.connector.connect(
        account=account,
        authenticator="externalbrowser",
        warehouse=warehouse,
    )
```

This requires `posit-sdk` in requirements.txt and a Snowflake OAuth
integration attached to the content (Connect does this automatically in
the Native App when the integration is configured). Table names are baked
into the SQL as fully-qualified `DATABASE.SCHEMA.TABLE` — not env vars.

Every template below includes the Snowflake connection and is ready to deploy
to Posit Connect.

---

## Shiny for Python

```python
# app.py
import os
from shiny import App, ui, render, reactive
import snowflake.connector
import pandas as pd

DEMO_DB = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
FQN = f"{DEMO_DB}.{DEMO_SCHEMA}"

def get_conn():
    # Posit Connect injects the Snowflake token via the OAuth integration.
    # NEVER use st.secrets / SNOWFLAKE_TOKEN env vars. Requires posit-sdk.
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    wh = os.environ.get("SNOWFLAKE_WAREHOUSE")
    try:
        from posit.connect.external.snowflake import PositAuthenticator
        auth = PositAuthenticator(local_authenticator="EXTERNALBROWSER")
        return snowflake.connector.connect(
            account=account, authenticator=auth.authenticator,
            token=auth.token, warehouse=wh,
        )
    except Exception:
        return snowflake.connector.connect(
            account=account, authenticator="externalbrowser", warehouse=wh,
        )

def query(sql):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(sql)
    df = pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])
    cur.close()
    conn.close()
    return df

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.input_select("region", "Region", ["ALL", "EAST", "WEST", "CENTRAL", "SOUTH"]),
    ),
    ui.card(ui.output_data_frame("table")),
    title="My Dashboard",
)

def server(input, output, session):
    @reactive.calc
    def filtered_data():
        sql = f"SELECT * FROM {FQN}.SALES_FACT"
        if input.region() != "ALL":
            sql += f" WHERE region = '{input.region()}'"
        sql += " LIMIT 1000"
        return query(sql)

    @render.data_frame
    def table():
        return filtered_data()

app = App(app_ui, server)
```

**Deploy:** `rsconnect deploy shiny . --name my-shiny-app`

---

## Shiny for R

```r
# app.R
library(shiny)
library(bslib)
library(DBI)
library(dplyr)

DEMO_DB     <- Sys.getenv("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA <- Sys.getenv("DEMO_SCHEMA", "COCO_DEMO")
FQN         <- paste(DEMO_DB, DEMO_SCHEMA, sep = ".")

ui <- page_sidebar(
  title = "My Dashboard",
  sidebar = sidebar(
    selectInput("region", "Region", c("ALL", "EAST", "WEST", "CENTRAL", "SOUTH"))
  ),
  card(DT::dataTableOutput("table"))
)

server <- function(input, output, session) {
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  onStop(function() DBI::dbDisconnect(con))

  data <- reactive({
    q <- tbl(con, in_schema(FQN, "SALES_FACT"))
    if (input$region != "ALL") q <- q |> filter(region == !!input$region)
    q |> head(1000) |> collect()
  })

  output$table <- DT::renderDataTable(data())
}

shinyApp(ui, server)
```

**Deploy:** `rsconnect::deployApp(appDir = ".", appName = "my-shiny-app")`

---

## Streamlit

```python
# app.py
import os
import streamlit as st
import snowflake.connector
import pandas as pd

DEMO_DB = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
FQN = f"{DEMO_DB}.{DEMO_SCHEMA}"

@st.cache_resource
def get_conn():
    # Posit Connect injects the Snowflake token via the OAuth integration.
    # NEVER use st.secrets / SNOWFLAKE_TOKEN env vars. Requires posit-sdk.
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    wh = os.environ.get("SNOWFLAKE_WAREHOUSE")
    try:
        from posit.connect.external.snowflake import PositAuthenticator
        auth = PositAuthenticator(local_authenticator="EXTERNALBROWSER")
        return snowflake.connector.connect(
            account=account, authenticator=auth.authenticator,
            token=auth.token, warehouse=wh,
        )
    except Exception:
        return snowflake.connector.connect(
            account=account, authenticator="externalbrowser", warehouse=wh,
        )

def query(sql):
    cur = get_conn().cursor()
    cur.execute(sql)
    return pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])

st.title("My Dashboard")
region = st.selectbox("Region", ["ALL", "EAST", "WEST", "CENTRAL", "SOUTH"])

sql = f"SELECT * FROM {FQN}.SALES_FACT"
if region != "ALL":
    sql += f" WHERE region = '{region}'"
sql += " LIMIT 1000"

st.dataframe(query(sql))
```

**Deploy:** `rsconnect deploy streamlit . --name my-streamlit-app`

---

## Dash (Plotly)

```python
# app.py
import os
from dash import Dash, html, dcc, callback, Output, Input
import plotly.express as px
import snowflake.connector
import pandas as pd

DEMO_DB = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
FQN = f"{DEMO_DB}.{DEMO_SCHEMA}"

def query(sql):
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        # On Connect, obtain token via posit-sdk PositAuthenticator (see the
        # canonical get_connection() in the CRITICAL section). Do not rely on
        # SNOWFLAKE_TOKEN env vars.
        token=os.environ.get("SNOWFLAKE_TOKEN", ""),
        authenticator="oauth" if os.environ.get("SNOWFLAKE_TOKEN") else "externalbrowser",
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "DEFAULT_WH"),
        database=DEMO_DB, schema=DEMO_SCHEMA,
    )
    cur = conn.cursor()
    cur.execute(sql)
    df = pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])
    conn.close()
    return df

app = Dash(__name__)

app.layout = html.Div([
    html.H1("Sales Dashboard"),
    dcc.Dropdown(["ALL", "EAST", "WEST", "CENTRAL", "SOUTH"],
                 value="ALL", id="region-dropdown"),
    dcc.Graph(id="revenue-chart"),
])

@callback(Output("revenue-chart", "figure"), Input("region-dropdown", "value"))
def update_chart(region):
    sql = f"""SELECT region, SUM(amount) AS revenue
              FROM {FQN}.SALES_FACT"""
    if region != "ALL":
        sql += f" WHERE region = '{region}'"
    sql += " GROUP BY region"
    df = query(sql)
    return px.bar(df, x="REGION", y="REVENUE")

if __name__ == "__main__":
    app.run(debug=True)
```

**Deploy:** `rsconnect deploy dash . --name my-dash-app`

---

## FastAPI

```python
# app.py
import os
from fastapi import FastAPI
import snowflake.connector
import pandas as pd

DEMO_DB = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
FQN = f"{DEMO_DB}.{DEMO_SCHEMA}"

app = FastAPI(title="Sales API")

def get_conn():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        # On Connect, obtain token via posit-sdk PositAuthenticator (see the
        # canonical get_connection() in the CRITICAL section). Do not rely on
        # SNOWFLAKE_TOKEN env vars.
        token=os.environ.get("SNOWFLAKE_TOKEN", ""),
        authenticator="oauth" if os.environ.get("SNOWFLAKE_TOKEN") else "externalbrowser",
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "DEFAULT_WH"),
        database=DEMO_DB, schema=DEMO_SCHEMA,
    )

@app.get("/sales")
def get_sales(region: str = None, limit: int = 100):
    conn = get_conn()
    sql = f"SELECT * FROM {FQN}.SALES_FACT"
    if region:
        sql += f" WHERE region = '{region}'"
    sql += f" LIMIT {limit}"
    cur = conn.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    conn.close()
    return [dict(zip(cols, row)) for row in rows]

@app.get("/predictions")
def get_predictions(min_risk: float = 0.5, limit: int = 100):
    conn = get_conn()
    sql = f"""SELECT * FROM {FQN}.LOAN_PREDICTIONS
              WHERE ".pred_default" >= {min_risk}
              ORDER BY ".pred_default" DESC LIMIT {limit}"""
    cur = conn.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    conn.close()
    return [dict(zip(cols, row)) for row in rows]
```

**Deploy:** `rsconnect deploy fastapi . --name my-api`

---

## Plumber (R API)

```r
# plumber.R
library(plumber)
library(DBI)
library(dplyr)

DEMO_DB     <- Sys.getenv("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA <- Sys.getenv("DEMO_SCHEMA", "COCO_DEMO")
FQN         <- paste(DEMO_DB, DEMO_SCHEMA, sep = ".")

#* @get /sales
#* @param region Filter by region (optional)
#* @param limit Max rows (default 100)
function(region = NULL, limit = 100) {
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  on.exit(DBI::dbDisconnect(con))

  q <- tbl(con, in_schema(FQN, "SALES_FACT"))
  if (!is.null(region)) q <- q |> filter(region == !!region)
  q |> head(as.integer(limit)) |> collect()
}

#* @get /predictions
#* @param min_risk Minimum default probability (default 0.5)
function(min_risk = 0.5) {
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  on.exit(DBI::dbDisconnect(con))

  tbl(con, in_schema(FQN, "LOAN_PREDICTIONS")) |>
    filter(.pred_default >= as.numeric(min_risk)) |>
    arrange(desc(.pred_default)) |>
    head(100) |>
    collect()
}
```

**Deploy:** `rsconnect::deployAPI(api = ".", appName = "my-api")`

---

## Quarto (report / parameterised dashboard)

```yaml
---
title: "Sales Report"
format:
  html:
    toc: true
    code-fold: true
execute:
  echo: false
params:
  region: "ALL"
  database: "SOL_ENG_DEMO"
  schema: "COCO_DEMO"
---
```

````python
#| label: setup
import snowflake.connector, pandas as pd, plotly.express as px, os

FQN = f"{params['database']}.{params['schema']}"
conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    token=os.environ.get("SNOWFLAKE_TOKEN", ""),
    authenticator="oauth" if os.environ.get("SNOWFLAKE_TOKEN") else "externalbrowser",
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "DEFAULT_WH"),
)
````

````python
#| label: fig-revenue
#| fig-cap: "Revenue by region"
sql = f"SELECT region, SUM(amount) AS revenue FROM {FQN}.SALES_FACT GROUP BY region"
df = pd.read_sql(sql, conn)
px.bar(df, x="REGION", y="REVENUE")
````

**Deploy:** `rsconnect deploy quarto . --name my-report`

**Schedule:** Set a cron schedule in the Connect UI to auto-refresh.

---

## Panel

```python
# app.py
import os
import panel as pn
import snowflake.connector
import pandas as pd

DEMO_DB = os.environ.get("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA = os.environ.get("DEMO_SCHEMA", "COCO_DEMO")
FQN = f"{DEMO_DB}.{DEMO_SCHEMA}"

pn.extension("tabulator")

region_select = pn.widgets.Select(
    name="Region", options=["ALL", "EAST", "WEST", "CENTRAL", "SOUTH"]
)

def get_data(region):
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        # On Connect, obtain token via posit-sdk PositAuthenticator (see the
        # canonical get_connection() in the CRITICAL section). Do not rely on
        # SNOWFLAKE_TOKEN env vars.
        token=os.environ.get("SNOWFLAKE_TOKEN", ""),
        authenticator="oauth" if os.environ.get("SNOWFLAKE_TOKEN") else "externalbrowser",
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "DEFAULT_WH"),
        database=DEMO_DB, schema=DEMO_SCHEMA,
    )
    sql = f"SELECT * FROM {FQN}.SALES_FACT"
    if region != "ALL":
        sql += f" WHERE region = '{region}'"
    sql += " LIMIT 1000"
    df = pd.read_sql(sql, conn)
    conn.close()
    return df

table = pn.bind(lambda r: pn.widgets.Tabulator(get_data(r)), region_select)

pn.template.FastListTemplate(
    title="Sales Dashboard",
    sidebar=[region_select],
    main=[table],
).servable()
```

**Deploy:** `rsconnect deploy bokeh . --name my-panel-app`

---

## Deploy command reference

| Framework | CLI command | R package equivalent |
|---|---|---|
| Shiny (Python) | `rsconnect deploy shiny .` | — |
| Shiny (R) | — | `rsconnect::deployApp(".")` |
| Streamlit | `rsconnect deploy streamlit .` | — |
| Dash | `rsconnect deploy dash .` | — |
| FastAPI | `rsconnect deploy fastapi .` | — |
| Plumber | — | `rsconnect::deployAPI(".")` |
| Quarto | `rsconnect deploy quarto .` | `rsconnect::deployDoc("report.qmd")` |
| Panel / Bokeh | `rsconnect deploy bokeh .` | — |
| Jupyter | `rsconnect deploy notebook notebook.ipynb` | — |

All Python CLI deploys use `rsconnect-python`: `pip install rsconnect-python`
