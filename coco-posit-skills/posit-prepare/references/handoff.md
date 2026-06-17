# Handoff to Posit Assistant

This is the bridge between CoCo and the IDE. Every time this skill creates
or profiles a Snowflake object, it should end with a handoff summary the
user can paste into Posit Assistant's chat pane in Positron, RStudio, or
VS Code.

The handoff has three parts: what exists, how to connect, and what to do next.

---

## Handoff format

Generate this at the end of every task. Adapt the content to what was
actually created — don't include sections that don't apply.

```
## Data ready for analysis

**Object:** <database>.<schema>.<object_name> (<VIEW | DYNAMIC TABLE | TABLE>)
**Rows:** <row_count>
**Refresh:** <schedule or "live view — always current">
**Access:** Granted to <role(s)>

**Columns:**
- <column_name> — <type> — <description>
- <column_name> — <type> — <description>
- ...

**Notes:**
- <any quality issues, caveats, or design decisions the analyst should know>

**Connect from R:**
```r
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
data <- dplyr::tbl(con, DBI::Id(database = "<db>", schema = "<schema>", table = "<object>"))
```

**Connect from Python:**
```python
import snowflake.connector
conn = snowflake.connector.connect(...)  # uses session credentials
df = conn.cursor().execute("SELECT * FROM <db>.<schema>.<object> LIMIT 100").fetch_pandas_all()
```

**Suggested next steps for Posit Assistant:**
- "<natural language prompt the user can paste into Posit Assistant>"
- "<another suggested prompt>"
```

---

## Principles for good handoffs

### Be specific about what was created

Don't say "I created a view." Say "I created SOL_ENG_DEMO.CHURN.CUSTOMER_MONTHLY
with 24,000 rows and 8 columns, refreshing hourly." The analyst needs to know
exactly what to query.

### Include the connection snippet for both languages

The user might be in Positron (R or Python), RStudio (R), or VS Code (Python).
Always provide both R and Python connection snippets. The `dsn = "snowflake"`
pattern works inside the Posit Team Native App. Outside it, use environment
variables.

### Suggest what Posit Assistant should do next

The analyst will paste the handoff into Posit Assistant and ask it to start
the analysis. Make the suggested prompts specific to the data that was
prepared, not generic. 

Good: "Build a logistic regression predicting is_churned from monthly_revenue,
transaction_count, and days_since_last_purchase using tidymodels."

Bad: "Analyze this data."

The suggested prompts should reference actual column names from the object
that was just created.

### Flag anything the analyst should know

If the profiling revealed issues that weren't fixed in the view (e.g.,
some NULL values were left in intentionally, a date column has a gap,
the data is a sample not the full population), say so in the notes.
Posit Assistant doesn't have CoCo's context — the handoff is the only
way this information transfers.

### Don't generate analysis code

The handoff gives Posit Assistant enough context to generate the right code.
This skill should NOT generate the R/Python analysis code itself — that
crosses the boundary. The connection snippets are the exception because
they're infrastructure, not analysis.

---

## Example handoff (adapt to the actual task)

```
## Data ready for analysis

**Object:** SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_MONTHLY (VIEW)
**Rows:** ~24,000 (2,000 customers × 12 months avg)
**Refresh:** Live view — always reflects current SALES_FACT data
**Access:** Granted to SOLENG role

**Columns:**
- customer_id — INT — Unique customer identifier
- segment — VARCHAR — Enterprise | Mid-Market | SMB | Consumer
- country — VARCHAR — Customer country
- month — DATE — First day of the month
- transaction_count — INT — Number of purchases that month
- monthly_revenue — DECIMAL — Total spend in USD
- days_since_last_purchase — INT — Days since most recent transaction
- is_churned — BOOLEAN — TRUE if no purchase in 90+ days

**Notes:**
- 3% of customers have no transactions (new signups) — they appear
  with NULL monthly metrics. Filter or handle in your model.
- Revenue is pre-tax. No refunds are excluded.

**Connect from R:**
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
data <- dplyr::tbl(con, DBI::Id(
  database = "SOL_ENG_DEMO", schema = "COCO_DEMO", table = "CUSTOMER_MONTHLY"
))

**Connect from Python:**
cur = conn.cursor()
df = cur.execute("SELECT * FROM SOL_ENG_DEMO.COCO_DEMO.CUSTOMER_MONTHLY").fetch_pandas_all()

**Suggested prompts for Posit Assistant:**
- "Build a tidymodels logistic regression predicting is_churned from
   monthly_revenue, transaction_count, and days_since_last_purchase"
- "Create a ggplot2 faceted chart showing monthly_revenue trends by segment"
- "Profile the is_churned rate by country and segment"
```

The example above uses specific column names and notes from a hypothetical
task. Always adapt to the actual objects and columns that were created.
Never use this example verbatim.
