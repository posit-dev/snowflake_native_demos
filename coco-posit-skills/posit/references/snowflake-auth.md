# Snowflake Authentication for Posit Workbench

## Decision tree

```
Are you inside the Posit Team Native App on Snowflake?
├── YES → Use Pattern A (fully managed, zero config)
└── NO  → Is Workbench configured with Snowflake OAuth integration?
           ├── YES → Use Pattern B (managed OAuth, external Workbench)
           └── NO  → Use Pattern C (explicit credentials — dev/test only)
```

---

## Pattern A — Posit Team Native App (recommended)

Inside the Native App, Workbench inherits Snowflake OAuth tokens automatically.
Users sign in once on the Workbench home page; all SDKs and drivers are
preconfigured. **No code needed to set up credentials.**

```r
# One line. No password, no token, no DSN configuration required.
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
```

The `snowflake` DSN is injected by the Native App runtime. The connection runs
under the user's own Snowflake role, inheriting full RBAC.

### Positron Assistant auto-configuration

When Positron IDE launches with Positron Assistant enabled inside the Native
App, Snowflake Cortex is automatically configured as the LLM backend using the
same managed credentials — no API keys required.

---

## Pattern B — External Workbench with managed Snowflake OAuth

When Workbench is deployed outside Snowflake but the admin has configured the
Snowflake OAuth integration:

```r
# Users sign in to their Snowflake account from the Workbench home page.
# After sign-in, the token is available to all sessions automatically.
con <- DBI::dbConnect(
  odbc::odbc(),
  driver    = "Snowflake",
  server    = Sys.getenv("SNOWFLAKE_ACCOUNT") ,   # e.g. "xy12345.snowflakecomputing.com"
  database  = "MY_DB",
  warehouse = "MY_WH",
  # No password or token — Workbench injects the OAuth token via the driver
  authenticator = "oauth"
)
```

Configure the Snowflake account URL via Workbench admin settings, not in user
code. Users never handle tokens directly.

---

## Pattern C — Explicit credentials (dev/test environments only)

Only use this outside of Workbench when testing locally or in CI pipelines
where managed credentials are unavailable.

```r
# Use environment variables. NEVER hardcode values.
con <- DBI::dbConnect(
  odbc::odbc(),
  driver    = "Snowflake",
  server    = Sys.getenv("SNOWFLAKE_ACCOUNT"),
  uid       = Sys.getenv("SNOWFLAKE_USER"),
  pwd       = Sys.getenv("SNOWFLAKE_PASSWORD"),
  database  = Sys.getenv("SNOWFLAKE_DATABASE"),
  warehouse = Sys.getenv("SNOWFLAKE_WAREHOUSE"),
  schema    = "PUBLIC"
)
```

Store secrets in `.Renviron` (local) or as environment variables in your CI
system. Never commit `.Renviron` to git.

---

## Key-pair authentication (service accounts / CI)

```r
con <- DBI::dbConnect(
  odbc::odbc(),
  driver        = "Snowflake",
  server        = Sys.getenv("SNOWFLAKE_ACCOUNT"),
  uid           = Sys.getenv("SNOWFLAKE_USER"),
  authenticator = "snowflake_jwt",
  priv_key_file = Sys.getenv("SNOWFLAKE_PRIVATE_KEY_PATH"),
  database      = Sys.getenv("SNOWFLAKE_DATABASE"),
  warehouse     = Sys.getenv("SNOWFLAKE_WAREHOUSE")
)
```

---

## Snowflake R SDK (alternative to ODBC)

The `{snowflakedb}` package uses the Snowflake Connector for Python under the
hood via `{reticulate}` and supports SSO / externalbrowser flows.

```r
library(snowflakedb)
# For Native App or OAuth sessions, credentials are sourced from the environment
con <- dbConnect(SnowflakeConnection(), account = Sys.getenv("SNOWFLAKE_ACCOUNT"))
```

---

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `[Snowflake][ODBC] (0) Unable to connect` | DSN not configured | Confirm `snowflake` DSN exists with `odbcListDrivers()` |
| `JWT token has expired` | OAuth token stale | Re-sign into Workbench home page |
| `Insufficient privileges` | Wrong Snowflake role active | Use `dbExecute(con, "USE ROLE MY_ROLE")` or set default role in Workbench |
| `odbc not found` | Missing ODBC driver | Install Posit Professional Drivers: `posit.co/download/professional-drivers` |
