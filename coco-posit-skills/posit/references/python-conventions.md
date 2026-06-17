# Python Conventions for Posit + Snowflake Workflows

## Core principle: push compute to Snowflake

Filter, join, and aggregate IN Snowflake; pull into pandas only the rows you
actually need to render or model. Don't `SELECT *` a fact table and filter in
pandas — push the WHERE/GROUP BY into the SQL.

```python
# Good: Snowflake does the work, pandas gets a small result
sql = f"""
    SELECT region, DATE_TRUNC('month', sale_date) AS month, SUM(amount) AS revenue
    FROM {FQN}.SALES_FACT
    WHERE sale_date >= '2025-01-01'
    GROUP BY region, month
"""
df = pd.read_sql(sql, conn)   # already aggregated, small
```

For dataframe-style pipelines against Snowflake, Snowpark is fine too:
```python
from snowflake.snowpark import Session
df = session.table(f"{FQN}.SALES_FACT").filter(col("region") == "EAST").group_by("product_id").agg(...)
```

## Connection — always via the Connect OAuth integration

NEVER use st.secrets, secrets.toml, st.connection("snowflake"), or
snowflake.snowpark.context in a deployed app. Use the canonical
get_connection() from connect-frameworks.md (PositAuthenticator + posit-sdk).
Bake fully-qualified DATABASE.SCHEMA.TABLE names into the SQL; do not route
table locations through env vars.

## Querying

```python
def query(sql: str) -> pd.DataFrame:
    cur = get_connection().cursor()
    try:
        cur.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d[0] for d in cur.description])
    finally:
        cur.close()
```
- Parameterize user input — never f-string raw user values into SQL.
- Snowflake returns UPPERCASE column names; reference them as returned or
  alias in SQL.
- Cache reference data, not per-user data: Streamlit `@st.cache_data` /
  Shiny `@reactive.calc`.

## Framework idioms

### Streamlit
- `st.set_page_config()` first line after imports.
- Cache the connection with `@st.cache_resource`, data with `@st.cache_data`.
- Use `st.column_config` for typed tables; `st.plotly_chart(fig, use_container_width=True)`.
- No `st.secrets` — connection comes from the OAuth integration.

### Shiny for Python
- Use `@reactive.calc` for derived data, `@render.*` for outputs.
- Open the connection once at module scope (or cache it); don't reconnect per reactive.
- `ui.page_sidebar` / `ui.card` for layout — modern API, not legacy.

### Dash
- `@callback` with explicit `Output`/`Input`.
- One connection per callback is fine; or use a connection pool for heavy apps.

### FastAPI
- Async endpoints; keep Snowflake calls in `def` (sync) handlers or run in a
  threadpool — the connector is sync.
- Return JSON-serializable types (convert numpy/pandas to native).

## Visualization

| Need | Package |
|---|---|
| Quick charts | plotly.express |
| Grammar of graphics (ggplot2-style) | plotnine |
| Static publication charts | matplotlib |
| Tables (publication) | great_tables |
| Tables (interactive) | itables |

```python
import plotly.express as px
fig = px.bar(df, x="REGION", y="REVENUE", title="Revenue by Region")
fig.update_layout(margin=dict(t=40, b=0))
```

## Package standards

| Task | Preferred package |
|---|---|
| Snowflake connection | snowflake-connector-python (+ posit-sdk for the token) |
| Dataframes | pandas (or polars for large local ops) |
| Snowflake dataframe API | snowflake-snowpark-python |
| Plots | plotly / plotnine / matplotlib |
| Tables | great_tables / itables |
| LLM chat | chatlas (Cortex backend) |
| NL→SQL | querychat |
| LLM over rows | mall |
| ML | scikit-learn + orbital (in-DB scoring) |
| Model serving/monitoring | vetiver + pins |
| Env management | a requirements.txt pinned with >= floors; include posit-sdk |

## requirements.txt essentials

Every deployed Python app needs, at minimum:
```
snowflake-connector-python>=3.12.0
posit-sdk
pandas>=2.0.0
```
Plus the framework (streamlit / shiny / dash / fastapi / panel) and any
charting/AI packages the app uses. Pin floors, not exact versions, so Connect
can resolve against its installed Python.

## Style
- PEP 8; type hints on functions that matter.
- Module-level constants for the FQN and warehouse.
- Small functions: `get_connection()`, `query()`, one function per view/output.
