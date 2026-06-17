# orbital — In-Database ML Scoring on Snowflake

`{orbital}` translates a fitted `{tidymodels}` workflow (preprocessing recipe +
model) into native SQL so predictions run directly inside Snowflake without
exporting data or maintaining an R process in production.

**Maintainer:** Posit / tidymodels team  
**Docs:** https://orbital.tidymodels.org

---

## When to use orbital vs Snowpark ML

| Scenario | Use |
|---|---|
| Model built in R with tidymodels | **orbital** |
| Model built in Python with scikit-learn | **orbital** (Python version) |
| Need Snowflake-native AutoML or deep learning | Snowpark ML / Cortex ML |
| Real-time serving via API | Posit Connect + vetiver |

---

## Core workflow (R)

### 1. Build and fit a tidymodels workflow

```r
library(tidymodels)
library(orbital)
library(DBI)
library(dplyr)

# Pull a training sample into R for model fitting
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")

train_df <- tbl(con, in_schema("ML", "LOAN_APPLICATIONS")) |>
  filter(split == "TRAIN") |>
  collect()

# Define recipe (preprocessing)
rec <- recipe(default ~ loan_amount + credit_score + term + annual_income,
              data = train_df) |>
  step_normalize(all_numeric_predictors()) |>
  step_dummy(all_nominal_predictors())

# Define model
spec <- logistic_reg() |>
  set_engine("glm")

# Bundle into workflow and fit
wf_fit <- workflow() |>
  add_recipe(rec) |>
  add_model(spec) |>
  fit(data = train_df)
```

### 2. Check orbital compatibility

```r
# Verify the workflow can be translated before committing
orbital::orbital_requirements(wf_fit)
# Returns list of required SQL functions — confirm Snowflake supports them
```

### 3. Translate to SQL

```r
orb <- orbital::orbital(wf_fit)

# Inspect the generated SQL (useful for review/debugging)
orbital::orbital_sql(orb)
```

### 4. Score in-database and write as a VIEW

```r
# Reference the full scoring table (could be billions of rows)
scoring_tbl <- tbl(con, in_schema("ML", "LOAN_APPLICATIONS"))

# Augment: adds prediction columns to the remote table reference
scored_tbl <- orbital::orbital_augment(orb, scoring_tbl)

# Materialise as a Snowflake VIEW — no data movement
DBI::dbExecute(con, "CREATE OR REPLACE SCHEMA ML_OUTPUTS")
DBI::dbExecute(con, glue::glue(
  "CREATE OR REPLACE VIEW ML_OUTPUTS.LOAN_PREDICTIONS AS\n{dbplyr::sql_render(scored_tbl)}"
))
```

The VIEW is now live in Snowflake. Every `SELECT` runs the preprocessing and
model inference in pure SQL against live data.

### 5. Materialise as a TABLE (scheduled batch scoring)

```r
# For scheduled jobs via Posit Connect or Snowflake Tasks
DBI::dbExecute(con, glue::glue(
  "CREATE OR REPLACE TABLE ML_OUTPUTS.LOAN_SCORES AS\n{dbplyr::sql_render(scored_tbl)}"
))
```

---

## Deploy VIEW + monitoring via Posit Connect

```r
# In a Quarto document or R script deployed to Connect:
library(vetiver)

v <- vetiver_model(wf_fit, "loan-default-classifier")

# Log model to Posit Connect's pin board
board <- pins::board_connect()
vetiver_pin_write(board, v)

# Schedule re-fitting and VIEW refresh as a Connect job
# The Quarto doc re-runs on a cron schedule, refits, and calls the
# orbital VIEW creation code above
```

---

## Python orbital (scikit-learn)

The same workflow applies for Python. Install: `pip install orbital-compat`

```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from orbital import orbital, orbital_sql

pipe = Pipeline([("scaler", StandardScaler()), ("clf", LogisticRegression())])
pipe.fit(X_train, y_train)

orb = orbital(pipe)
print(orbital_sql(orb))   # Snowflake-compatible SQL
```

---

## Supported model types (as of orbital 0.5.0)

| parsnip engine | Supported |
|---|---|
| `glm` (logistic/linear regression) | ✅ |
| `ranger` (random forest) | ✅ |
| `xgboost` | ✅ |
| `lightgbm` | ✅ |
| `keras` / deep learning | ❌ |
| `svm_rbf` | ❌ (complex kernel functions) |

Always run `orbital_requirements()` to check before deploying.

---

## Common mistakes

- **Not locking `renv`** before deploying the scoring VIEW — Snowflake runs
  the SQL, not R, but the R code that *generates* the SQL must be reproducible.
- **Using `collect()` before `orbital_augment()`** — defeats the purpose;
  keep scoring in-database.
- **Forgetting preprocessing steps** — `orbital` translates the full workflow
  including `step_normalize`, `step_dummy`, etc. You do not need to manually
  apply preprocessing before scoring.
- **Schema permissions** — the Snowflake role running the `CREATE VIEW`
  needs `CREATE ON SCHEMA` privilege on the target schema.
