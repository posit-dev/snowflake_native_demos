# Demo Runbook for Snowflake Sellers

Total time: ~10 minutes live, including setup.

---

## Prerequisites

- A Snowflake account (any demo, trial, or SE account works)
- CoCo CLI, CoCo Desktop, or Snowsight
- Both skills installed: `$posit` and `$posit-prepare`
- (Optional) Posit Team Native App for the deployment step

### Access requirements

| Requirement | Demos A/B/C | Demo D (RBAC) |
|---|---|---|
| Role needed | Any role with CREATE SCHEMA on an existing database | Also needs SECURITYADMIN |
| Warehouse | Any existing warehouse | Same |
| If SECURITYADMIN unavailable | Demos still work | Skip Demo D |

---

## Step 1 — Set up demo data (~60 seconds)

In CoCo, type:

```
$posit-prepare set up demo data
```

CoCo will ask you for the database, schema, and warehouse names. Use
whatever works in your environment — there are no hardcoded names.

Alternatively, open `posit-prepare/scripts/setup-demo-data.sql` in
Snowsight and edit the three variables at the top:

```sql
SET DEMO_DATABASE  = '<your_database>';    -- e.g. SOL_ENG_DEMO
SET DEMO_SCHEMA    = '<your_schema>';      -- e.g. POSIT_DEMO
SET DEMO_WAREHOUSE = '<your_warehouse>';   -- e.g. DEFAULT_WH
```

This creates in your chosen schema:

| Table / View | Rows | Purpose |
|---|---|---|
| `PRODUCT_DIM` | 64 | Product catalog |
| `CUSTOMER_DIM` | 2,000 | CRM-style customer records |
| `SALES_FACT` | 50,000 | 2 years of sales transactions |
| `LOAN_APPLICATIONS` | **2,200,000** | Loan data with train/test split |
| `LOAN_PREDICTIONS` | **2,200,000** | Pre-scored predictions (simulates orbital) |

All generated in-place via Snowflake's `GENERATOR()`. No uploads, no external
files, works on any account.

---

## Step 2 — Run the demos

**You don't need pre-built apps.** The `$posit` skill generates everything
from scratch. Just tell CoCo what you want and point it at your data.

### Demo A: "CoCo writes idiomatic R for Snowflake" (~3 min)

```
$posit show me revenue by region from <your_database>.<your_schema>.SALES_FACT
using tidyverse conventions with a ggplot2 chart
```

CoCo generates credential-free R code using `dbplyr` (lazy evaluation,
no `collect()` until the final plot), a styled ggplot2 chart, and the
Snowflake OAuth connection pattern.

**Talking point:** "CoCo doesn't just write generic R — it writes R that
follows Posit's recommended conventions for Snowflake: lazy evaluation,
managed credentials, no data leaving the warehouse until the last step."

### Demo B: "Build and deploy a Streamlit app" (~4 min)

```
$posit create and deploy a streamlit app showing loan default risk
from <your_database>.<your_schema>.LOAN_PREDICTIONS with a risk
threshold slider and charts by credit score band
```

CoCo generates the complete Streamlit app with Snowflake connection,
interactive filters, plotly charts, and the `rsconnect deploy streamlit`
command. No pre-built app needed — CoCo builds it live.

**Talking point:** "The SE just described what they wanted in plain English.
CoCo generated a working app connected to 2.2 million rows of Snowflake
data, with the deploy command ready to go. That's $posit."

### Demo C: "Translate an ML model to Snowflake SQL" (~4 min)

```
$posit walk me through building a tidymodels loan default classifier
on <your_database>.<your_schema>.LOAN_APPLICATIONS and translating it
to a Snowflake VIEW with orbital
```

CoCo generates the full tidymodels workflow, the `orbital::orbital()` call,
and the `CREATE VIEW` SQL.

**Talking point:** "The model trains in R, but predictions run as native
SQL — 2.2 million applications scored in Snowflake without an R runtime,
without exporting data, without spinning up a separate scoring service."

### Demo D: "Zero-code RBAC — Streamlit on Posit Connect" (~5 min)

This is the security demo. Instead of using a pre-built app, have CoCo
build it live:

```
$posit create a streamlit app that shows sales by region and a sample
of loan applications including annual_income from
<your_database>.<your_schema>
```

The setup script created three roles with different access:

| Role | Sales regions | Income column |
|---|---|---|
| `POSIT_DEMO_ANALYST` | EAST only | Masked → NULL |
| `POSIT_DEMO_MANAGER` | All 4 regions | Masked → NULL |
| `POSIT_DEMO_EXECUTIVE` | All 4 regions | Fully visible |

**Demo script:**

1. Deploy the app CoCo just generated (or use `assets/rbac-streamlit-app/`
   as a backup)
2. Open the app as `POSIT_DEMO_ANALYST` — one region, income masked
3. Open the same URL as `POSIT_DEMO_EXECUTIVE` — everything visible
4. Show the code: "Where's the WHERE clause that filters by role?" There
   isn't one. Snowflake does it all.

**Talking point:** "This app has zero lines of access-control code. Posit
Connect passes the viewer's Snowflake identity through via OAuth. Snowflake's
row access policies and masking policies decide what they see. Compare that
to building permission logic in every app from scratch."

### Demo E: "Full lifecycle — prepare → build → deploy" (~5 min)

Chain the skills together to show the complete story:

```
$posit-prepare profile the SALES_FACT table in <your_database>.<your_schema>
```

```
$posit-prepare create a curated view joining SALES_FACT to CUSTOMER_DIM
with monthly revenue by segment and a churn flag
```

Then hand off to app building:

```
$posit build a python shiny app from the view that was just created
with filters for segment and country
```

**Talking point:** "CoCo prepared the data layer. Posit Assistant helps
the analyst write R or Python in their IDE. CoCo builds and deploys the
app. Three agents, one lifecycle, zero credential management."

---

## Step 3 — Tear down

```
$posit-prepare tear down the demo environment
```

Or run `posit-prepare/scripts/teardown-demo.sql` in Snowsight.

---

## If they ask…

**"Does this work without the Posit Native App?"**
Yes. Posit Workbench connects to Snowflake externally via managed OAuth.
The Native App removes setup friction (zero-ops, marketplace install).

**"What about Python?"**
$posit supports 10 frameworks including Streamlit, Dash, FastAPI, and
Shiny for Python. The orbital package also supports scikit-learn → SQL.

**"How is this different from Snowpark ML?"**
Snowpark ML is Snowflake-native AutoML. Orbital is for teams that already
have tidymodels or scikit-learn workflows. Complementary, not competing.

**"Do I need to use the pre-built demo apps?"**
No. The `$posit` skill generates apps from scratch for any framework.
The apps in `assets/` are backup examples in case CoCo isn't available
or you want something pre-tested.

**"CoCo isn't responding in Snowsight"**
CoCo in Snowsight requires cross-region inference enabled on the account.
CoCo CLI and Desktop don't have this restriction.

**"The Shiny app can't connect — dsn 'snowflake' not found"**
The `snowflake` DSN only exists inside the Posit Team Native App. Outside
it, the skill generates code using environment variables instead.

**"What does it cost?"**
Posit Team Native App is licensed via the Snowflake Marketplace. CoCo is
billed on token consumption. Demo data uses an XSMALL warehouse.
