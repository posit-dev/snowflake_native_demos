# Posit CoCo Skills for Snowflake

Two [Snowflake CoCo](https://www.snowflake.com/en/product/snowflake-coco/) skills that make CoCo natively aware of the Posit data science platform, plus a demo kit for Snowflake SEs.

## Repo structure

```
coco-posit-skills/
│
├── posit/                          ← SKILL: Build & deploy apps ($posit)
│   ├── SKILL.md
│   ├── LICENSE
│   ├── references/
│   │   ├── connect-frameworks.md      Scaffold templates for 10 frameworks
│   │   ├── snowflake-auth.md          Credential-free connection patterns
│   │   ├── r-conventions.md           tidyverse, ggplot2, dbplyr, Shiny, Quarto
│   │   ├── orbital-patterns.md        tidymodels/scikit-learn → Snowflake SQL
│   │   ├── connect-deploy.md          rsconnect, OAuth passthrough, scheduling
│   │   └── cortex-ai-tools.md         chatlas, querychat, Positron Assistant
│   └── assets/                        Demo apps + runbook (CoCo can reference these)
│       ├── DEMO-RUNBOOK.md            4 scripted demos with talking points
│       ├── rbac-streamlit-app/        Zero-filtering-logic RBAC demo
│       ├── loan-dashboard/            Shiny dashboard on orbital predictions
│       └── example-nl-dashboard.R     Shiny + querychat + Cortex NL interface
│
├── posit-prepare/                  ← SKILL: Prepare Snowflake data layer ($posit-prepare)
│   ├── SKILL.md
│   ├── LICENSE
│   ├── references/
│   │   ├── decisions.md               When to use views vs dynamic tables vs CTAS
│   │   ├── principles.md              Universal rules for data preparation
│   │   └── handoff.md                 Bridge format to Posit Assistant in IDE
│   └── scripts/                       Demo data setup (CoCo can run these)
│       ├── setup-demo-data.sql        2.2M rows + RBAC policies (configurable)
│       └── teardown-demo.sql          Clean removal of demo schema + roles
│
└── README.md                       ← This file
```

## Two skills, one story

| Skill | Prefix | What it does | What it produces |
|---|---|---|---|
| **posit** | `$posit` | Build and deploy data apps | Code files (R/Python) + deploy commands |
| **posit-prepare** | `$posit-prepare` | Prepare Snowflake data for analysis | Snowflake objects (views, tables, policies) |

They hand off to each other and to Posit Assistant:

```
$posit-prepare          →  Snowflake objects  →  Posit Assistant  →  $posit
(discover, profile,        (views, dynamic        (writes R/Python    (deploys to
 curate, govern)            tables, tags)           analysis code)     Connect)
```

**`$posit-prepare`** operates on the Snowflake side: catalog search, data profiling, creating curated views and dynamic tables, applying governance. Everything it creates is a Snowflake object that appears instantly in any IDE's connections pane.

**Posit Assistant** (inside Positron, RStudio, or VS Code) picks up where `$posit-prepare` left off. It writes R/Python code against the objects that were just created. The handoff summary gives it the context it needs.

**`$posit`** handles the last mile: generating app scaffolds in any of 10 frameworks (Shiny, Streamlit, Dash, FastAPI, Plumber, Quarto, Panel, Bokeh, Jupyter, R Markdown) and deploying to Posit Connect.

---

## Quick start

### For customers

**Install both skills** (CoCo CLI or Desktop):

```
Install the skill at https://github.com/posit-dev/snowflake_native_demos/tree/main/coco-posit-skills/posit
```

```
Install the skill at https://github.com/posit-dev/snowflake_native_demos/tree/main/coco-posit-skills/posit-prepare
```

**Start using them:**

```
$posit-prepare find tables related to customer churn in my database and create a curated view
```

```
$posit build a python shiny app showing loan risk from my LOAN_PREDICTIONS table
```

```
$posit create and deploy a streamlit dashboard with sales by region from my data
```

CoCo generates the app from scratch — you don't need pre-built code.

### For Snowflake SEs

Everything above, plus set up demo data. You can do this two ways:

**From CoCo (recommended):**
```
$posit-prepare set up demo data
```
CoCo will ask for your database, schema, and warehouse names.

**Or manually in Snowsight:**
1. Open `posit-prepare/scripts/setup-demo-data.sql`
2. Edit the three variables at the top to match your environment:
   ```sql
   SET DEMO_DATABASE  = '<your_database>';
   SET DEMO_SCHEMA    = '<your_schema>';
   SET DEMO_WAREHOUSE = '<your_warehouse>';
   ```
3. Execute the script (~60 seconds, creates 2.2M rows + RBAC policies)

**Then use the skills to demo — CoCo generates everything live:**
```
$posit create and deploy a streamlit app showing loan risk from <your_schema>.LOAN_PREDICTIONS
$posit build a python shiny app with sales by region from <your_schema>.SALES_FACT
$posit-prepare profile the LOAN_APPLICATIONS table and create a curated view for churn analysis
```

No pre-built apps needed. See [`posit/assets/DEMO-RUNBOOK.md`](posit/assets/DEMO-RUNBOOK.md) for scripted demos with talking points.

---

## Supported frameworks ($posit)

| Framework | Language | Example prompt |
|---|---|---|
| Shiny | R or Python | `$posit build a python shiny app showing sales by region from my data` |
| Streamlit | Python | `$posit create a streamlit dashboard for loan risk with filters` |
| Dash | Python | `$posit build a dash app with plotly revenue charts` |
| FastAPI | Python | `$posit create a fastapi endpoint serving predictions above a threshold` |
| Plumber | R | `$posit build a plumber API for my scoring model` |
| Quarto | R or Python | `$posit write a quarto report on quarterly revenue parameterised by region` |
| Panel | Python | `$posit build a panel dashboard from my Snowflake tables` |
| Bokeh | Python | `$posit create an interactive bokeh visualization` |
| Jupyter | Python | `$posit set up a jupyter notebook as a scheduled report` |
| R Markdown | R | `$posit convert this rmarkdown to a parameterised report` |

CoCo generates the entire app from scratch — connected to your Snowflake data, with the right auth pattern and a deploy command for Posit Connect. No pre-built code needed.

---

## How `$posit-prepare` works with Posit Assistant

`$posit-prepare` creates Snowflake objects. Posit Assistant writes code. They don't overlap.

| Task | Who handles it | Why |
|---|---|---|
| "What tables are relevant for my analysis?" | **$posit-prepare** | CoCo sees the Snowflake catalog |
| "Create a curated view joining these tables" | **$posit-prepare** | This is Snowflake DDL |
| "Profile this data for quality issues" | **$posit-prepare** | SQL-level profiling at warehouse scale |
| "Tag this column as PII" | **$posit-prepare** | Snowflake governance |
| "Write the feature engineering code" | **Posit Assistant** | R/Python in the IDE |
| "Fit a model and evaluate it" | **Posit Assistant** | Interactive, IDE-native |
| "Deploy this app to Connect" | **$posit** | Infrastructure + deployment |

Every `$posit-prepare` task ends with a handoff summary: what was created, connection snippets for R and Python, and suggested prompts the user can paste into Posit Assistant.

---

## Using in CoCo Snowsight (browser)

CoCo in Snowsight doesn't support `/skill install` from URLs yet. To use there:

1. Open a Snowsight **Workspace**
2. Create `AGENTS.md` at the workspace root
3. Paste the contents of `posit/SKILL.md` and/or `posit-prepare/SKILL.md` into it
4. CoCo reads it automatically for every conversation in that workspace

Note: CoCo in Snowsight requires [cross-region inference](https://docs.snowflake.com/user-guide/snowflake-cortex/cross-region-inference) enabled on the account.

---

## Cleanup (SEs)

From CoCo:
```
$posit-prepare tear down the demo environment
```

Or manually — run `posit-prepare/scripts/teardown-demo.sql` in Snowsight (edit variables to match your setup).

Drops the demo schema and RBAC roles. Database and warehouse untouched.

---

## Learn more

- [Snowflake CoCo](https://www.snowflake.com/en/product/snowflake-coco/) — AI coding agent
- [Posit + Snowflake](https://posit.co/solutions/snowflake) — Partnership overview
- [Posit Team Native App](https://posit.co/use-cases/snowflake/) — Marketplace listing
- [Posit Connect](https://posit.co/products/enterprise/connect) — Publishing platform
- [orbital](https://orbital.tidymodels.org) — In-database ML scoring
- [CoCo Skills reference](https://docs.snowflake.com/en/user-guide/cortex-code/extensibility) — How skills work
