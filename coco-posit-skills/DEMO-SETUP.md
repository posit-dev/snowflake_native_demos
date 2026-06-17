# Demo Setup — Posit CoCo Skills

Audience: internal Posit + Snowflake co-sell. Goal: show the full
one-prompt-to-deployed-app pipeline and the three-agent "better together"
story. ~20 min end to end.

---

## GitHub: what you need

You need **one repo, two purposes**. Use the existing
`posit-dev/snowflake_native_demos` — no new repo required.

| Purpose | Path | Who reads it |
|---|---|---|
| The skills (install source) | `coco-posit-skills/posit/` and `coco-posit-skills/posit-prepare/` | CoCo, when you run "Install the skill at <url>" |
| A target repo for the git-iterate demo (optional) | any repo/branch you can push to | the git-delivery path in Mode 1 |

For THIS demo you only strictly need the first one. The git-iterate path is
optional polish (show it only if you want to demo the Posit Assistant loop).

### One-time GitHub prep

1. Make sure the latest `coco-posit-skills/` is pushed to
   `posit-dev/snowflake_native_demos` (skills + scripts + watcher).
2. Confirm the two install URLs resolve in a browser:
   - https://github.com/posit-dev/snowflake_native_demos/tree/main/coco-posit-skills/posit
   - https://github.com/posit-dev/snowflake_native_demos/tree/main/coco-posit-skills/posit-prepare
3. (Optional, for the iterate demo) Have a repo/branch you can push to, with
   git auth configured on the machine running CoCo.

---

## Pre-flight checklist (do this BEFORE the demo, not live)

Run through this the day before. Each line is a thing that has bitten us.

- [ ] Demo data exists: `SOL_ENG_DEMO.COCO_DEMO` has the 5 tables/views
      (re-run `posit-prepare/scripts/setup-demo-data.sql` if unsure)
- [ ] Bridge installed: `SOL_ENG_DEMO.POSIT_BRIDGE` has
      `POSIT_DEPLOY_REQUESTS` (with the `files` column) and
      `POSIT_REQUEST_DEPLOY`
- [ ] Old EAI-dependent procs are DROPPED (POSIT_DEPLOY / POSIT_PUSH) so
      CoCo can't pick them and fail
- [ ] Watcher is deployed on Connect, scheduled (~1 min), and its Vars +
      OAuth integration are set — confirm a test request goes COMPLETE
- [ ] Skills installed in CoCo and re-synced to the latest version
      (`/skill list` shows posit and posit-prepare)
- [ ] You ran ONE full deploy today and have the live URL handy as a backup
- [ ] Browser tabs open: Snowsight (with CoCo), Connect content listing,
      and the last successful app

---

## The demo script (~20 min)

### Act 1 — The data layer ($posit-prepare) — 4 min

In CoCo:
```
$posit-prepare profile the LOAN_APPLICATIONS table in SOL_ENG_DEMO.COCO_DEMO
```
Then:
```
$posit-prepare create a curated view joining SALES_FACT to CUSTOMER_DIM with
monthly revenue by segment and a churn flag, in SOL_ENG_DEMO.COCO_DEMO
```
Talking point: "CoCo just did Snowflake-side data engineering — profiling,
a governed view — and it shows up in every IDE's connections pane. This is
the data scientist's prep work, done in natural language."

### Act 2 — Build and deploy in one prompt ($posit) — 6 min

```
$posit create and deploy a streamlit app showing loan default risk from
SOL_ENG_DEMO.COCO_DEMO.LOAN_PREDICTIONS with a risk threshold slider and
charts by credit score band
```
Watch it: generate → queue via POSIT_REQUEST_DEPLOY → poll → live URL.
Open the URL. Talking point: "One prompt. CoCo generated a Posit Connect
app — not Streamlit-in-Snowflake — wired the Snowflake connection through
the OAuth integration, and deployed it. No IDE, no copy-paste."

### Act 3 — The "ask questions about your data" app — 4 min

```
$posit build a shiny app using SOL_ENG_DEMO.COCO_DEMO data that lets users
ask questions about loan applications in natural language, and deploy it
```
Talking point: "It reached for querychat + ellmer automatically — Posit's
open-source NL-to-SQL — backed by Snowflake Cortex. No API key, nothing
leaves Snowflake."

### Act 4 — Better together (the moat) — 4 min

Don't deploy this one — show the iterate path:
```
$posit build a shiny app for sales by region from SOL_ENG_DEMO.COCO_DEMO,
I want to iterate on it in Positron first
```
CoCo delivers the code to git / Workbench. Open it in Positron, show Posit
Assistant (Cortex-backed) refining it, then the Publish button.
Talking point: "Three agents, one Snowflake identity, Cortex throughout.
CoCo shapes the data and scaffolds. Posit Assistant iterates in the IDE.
Connect publishes with scheduling and RBAC. Snowflake App Runtime can't
match this — they have neither the IDE agent nor the publishing platform."

### Act 5 — RBAC closer (optional, 2 min)

Open the RBAC Streamlit app as two different Snowflake roles. Same URL, same
code, different data. "Zero filtering logic in the app. Snowflake's policies,
inherited through Connect's viewer OAuth."

---

## If something breaks live

- App deployed but shows an error page → connection pattern issue; you have
  the pre-deployed backup URL from the checklist. Pivot to that.
- Request stuck PENDING → watcher schedule; show the queued row in the table
  and the watcher log, explain the ~1 min cadence, move on. Don't wait live.
- Skill not triggering → confirm `/skill list`; worst case paste the prompt
  results you captured in the dry run.

Always have the dry-run screenshots/URLs ready. The pipeline works, but a
live cloud demo deserves a backup.
