# Deploying to Posit Connect from Workbench

Posit Connect is the publishing platform for Shiny apps, Quarto reports, R
Plumber APIs, and Pins. Inside the Posit Team Native App it shares the same
Snowflake security boundary as Workbench — enabling one-click deployment with
no network or auth reconfiguration.

---

## Deployment methods

### Posit Team Native App — deploy from inside Workbench

Inside the Native App, Connect runs at `https://connect`. This internal URL
only resolves from a Workbench session (Positron, RStudio, or Workbench
terminal) — NOT from CoCo Snowsight, CoCo CLI on a local machine, or any
process outside Snowpark Container Services.

To deploy from a Workbench terminal:
```bash
rsconnect deploy streamlit my-app/ --name my-app --server https://connect
```

Or use the **Publish button** (blue rocket icon) in Positron or RStudio —
it's pre-configured to point at `https://connect`.

### Method 1 — Push-button from Positron / RStudio (recommended)

1. Open the file to deploy (`app.R`, `report.qmd`, etc.) in the IDE.
2. Click the **Publish** button (blue rocket icon in the toolbar).
3. Select your Connect server (pre-configured in the Native App).
4. Choose content type, name, and access settings.
5. Click **Publish**. Connect installs packages via Posit Package Manager
   automatically.

### Method 2 — `rsconnect` package (scripted / CI)

```r
library(rsconnect)

# Configure the Connect server once (skip if pre-configured in Workbench)
rsconnect::addServer(
  url  = Sys.getenv("CONNECT_SERVER_URL"),   # e.g. "https://connect.example.com"
  name = "prod-connect"
)
rsconnect::connectApiUser(
  server  = "prod-connect",
  account = Sys.getenv("CONNECT_USER"),
  apiKey  = Sys.getenv("CONNECT_API_KEY")
)

# Deploy an app
rsconnect::deployApp(
  appDir  = ".",
  appName = "loan-dashboard",
  server  = "prod-connect",
  forceUpdate = TRUE
)

# Deploy a Quarto document
rsconnect::deployDoc(
  doc    = "report.qmd",
  server = "prod-connect"
)

# Deploy a scheduled R script
rsconnect::deployApp(
  appDir      = ".",
  appName     = "weekly-scoring-job",
  appPrimaryDoc = "score.R",
  contentCategory = "schedule"
)
```

### Method 3 — Connect API (advanced / programmatic)

```r
library(connectapi)

client <- connect(
  server  = Sys.getenv("CONNECT_SERVER_URL"),
  api_key = Sys.getenv("CONNECT_API_KEY")
)

# List deployed content
get_content(client)

# Update environment variables for a specific content item
content <- get_content(client, guid = "your-content-guid")
set_environment_new(content, MY_SECRET = Sys.getenv("MY_SECRET"))
```

---

## Snowflake OAuth passthrough in Posit Connect

By default, Connect deploys apps using the **publisher's** Snowflake role. To
enforce row-level security so each viewer sees only their own data, enable
**viewer OAuth passthrough**.

### How it works

Each viewer logs into Connect with their identity provider. Connect exchanges
that identity for a Snowflake OAuth token scoped to the viewer's Snowflake
role. The app's database connection runs under the viewer's role, not the
publisher's.

### Setup (admin)

In the Posit Team Native App, OAuth passthrough is configured at the platform
level. No app-level code changes are needed.

For external Connect deployments, the admin configures:
1. A Snowflake OAuth Security Integration (type: "partner").
2. The Connect server's Snowflake OAuth settings.
3. Content-level OAuth setting (per-app in Connect settings UI).

### App code — no changes required

The connection code is identical to the development version:

```r
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
```

Connect injects the viewer's token at runtime. The app never sees credentials.

### Testing viewer access in development

```r
# Temporarily impersonate a lower-privilege role to test RLS
DBI::dbExecute(con, "USE ROLE ANALYST_ROLE")
tbl(con, "SENSITIVE_TABLE") |> head(5) |> collect()
```

---

## Package management with Posit Package Manager

Posit Package Manager (PPM) is the CRAN mirror + vulnerability scanner inside
the Native App. Connect uses PPM automatically for package installation.

```r
# Lock the current environment before deployment
renv::init()        # first time
renv::snapshot()    # after adding packages

# Confirm the lockfile is committed to the deployment bundle
# rsconnect will include renv.lock automatically if present
```

```r
# Check for vulnerable packages
pak::pak_install("pak")
pak::pak_check()    # reports CVEs from PPM's vulnerability database
```

---

## Scheduling Quarto / R scripts on Connect

From the Connect UI: Settings → Schedule → set cron expression.

From code:

```r
library(connectapi)

client <- connect(server = Sys.getenv("CONNECT_SERVER_URL"),
                  api_key = Sys.getenv("CONNECT_API_KEY"))
content <- get_content(client, guid = "your-content-guid")

# Run on the first of every month at 06:00 UTC
set_schedule(content, schedule = "0 6 1 * *")
```

---

## Common deployment errors

| Error | Cause | Fix |
|---|---|---|
| `package 'XYZ' is not available` | Package not in PPM | Check `pak::pkg_status("XYZ")` |
| `Error: could not find function 'dbConnect'` | Missing from `renv.lock` | Run `renv::snapshot()` again |
| `Shiny app failed to start` | Port / env var not set | Set env vars in Connect UI → Vars |
| `Snowflake: insufficient privileges` | Wrong role for viewer | Check OAuth passthrough config |
| `Bundle too large` | Included data files | Add large files to `.rscignore` |
