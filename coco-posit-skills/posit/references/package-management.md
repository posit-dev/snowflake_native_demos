# Package Management on Posit Connect + Snowflake

Two concerns, both matter for reproducible apps:

1. **Install source** — WHERE packages come from. In the Native App this is
   **Posit Package Manager (PPM)**: a curated, vulnerability-scanned CRAN +
   PyPI mirror inside the customer's perimeter. Connect is pre-configured to
   install from it; the app doesn't choose the source, Connect does.
2. **Version pinning** — WHICH exact versions get installed. This is the
   lockfile the app ships: `renv.lock` (R) or pinned `requirements.txt` /
   `uv.lock` (Python). Pinning is what makes a redeploy reproduce the same
   environment.

You want both: Connect installs FROM PPM, pinned BY the lockfile.

## Python

### requirements.txt (minimum)
Always ship one. Pin floors so Connect can resolve against its Python:
```
snowflake-connector-python>=3.12.0
posit-sdk
pandas>=2.0.0
streamlit>=1.36.0      # or shiny / dash / fastapi
```

### uv (preferred for reproducibility)
uv is the fast Python resolver/installer. Use it to produce a fully pinned
lockfile during development:
```bash
uv pip compile requirements.in -o requirements.txt   # fully pinned output
# or, project style:
uv lock                                               # produces uv.lock
```
Ship the pinned `requirements.txt` in the bundle. Connect installs those
exact versions from PPM. (Connect's manifest uses pip + requirements.txt;
uv is the tool that pins it.)

### How Connect resolves it
The deploy manifest names `requirements.txt`; Connect runs pip against its
configured PyPI source (PPM). No source URLs belong in the app — keep it
clean and let Connect supply PPM.

## R

### renv (required before deploying)
renv captures exact package versions in `renv.lock`. Always snapshot before
deploying:
```r
renv::init()        # first time in the project
renv::snapshot()    # after adding/updating packages — writes renv.lock
```
Ship `renv.lock` in the bundle. Connect restores those exact versions from
PPM. The deploy watcher reads the R version out of renv.lock and pins it in
the manifest automatically.

### How Connect resolves it
Connect sees `renv.lock`, restores the locked versions from PPM. If no
lockfile is present, Connect falls back to latest-from-PPM — works, but not
reproducible. Always lock.

## What $posit should generate

- **Python app** → always emit a `requirements.txt` with posit-sdk +
  snowflake-connector-python + framework + any AI/viz packages. If the user
  has uv, suggest `uv pip compile` to pin it fully.
- **R app** → emit/refresh `renv.lock` via `renv::snapshot()` before delivery
  or deploy. Never deploy an R app without a lockfile.
- **Either** → never hardcode a package source URL in the app. Connect +
  PPM supply the source. The app ships only the lockfile.

## PPM as the install source (customer note)

In a customer's Native App, PPM is typically pre-wired as Connect's repo, so
this is automatic. If a customer runs their own external PPM, the Connect
admin points Connect's R/Python repos at that PPM URL once — it's a Connect
server setting, not something the app or $posit configures per deploy.
