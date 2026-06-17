---
name: posit-prepare
title: Prepare Data for Posit Workbench
description: |
  Prepare Snowflake data for analysis in Posit Workbench. Use when the user
  wants to: discover relevant tables, profile data quality, create curated
  views or dynamic tables, apply governance policies, or set up a data layer
  for their R or Python analysis. Triggers include: "find tables for",
  "profile this data", "create a view for analysis", "build a dynamic table",
  "prepare data", "curate", "set up data for my team", "tag columns",
  "mask PII", "what data is available", or "explore the catalog".
  Do NOT use for writing R/Python analysis code (that is Posit Assistant's
  job inside the IDE) or for building/deploying apps (use $posit for that).
metadata:
  author: Posit PBC
  version: 1.0
  type: partner
  references:
    - references/decisions.md
    - references/principles.md
    - references/handoff.md
---

# Prepare Data for Posit Workbench

This skill creates Snowflake objects — views, dynamic tables, tags, policies —
that appear instantly in every IDE connected to the account. No files to copy,
no IDE to choose. Posit Assistant picks up wherever this skill leaves off.

## What this skill does vs what it does NOT do

| This skill (CoCo, Snowflake side) | Posit Assistant (IDE side) |
|---|---|
| Search the catalog for relevant tables | Write R/Python code against those tables |
| Profile data quality via SQL | Build visualizations and summaries |
| Create curated views and dynamic tables | Fit models and analyze results |
| Apply governance (tags, masking, RLS) | Iterate interactively on analysis |
| Grant access to the right roles | Deploy to Posit Connect |

If the user asks for R or Python code, tell them to ask Posit Assistant in
their IDE. Offer to generate a handoff summary they can paste into the IDE
chat. See `references/handoff.md`.

## How to respond to any request

CoCo already knows SQL. This skill teaches CoCo WHEN and WHY to make
certain choices — not what SQL syntax to use. Follow these steps:

### 1. Understand the user's actual goal

Don't start building until you understand:
- What question are they trying to answer? (churn, revenue, risk, etc.)
- Who is the audience? (themselves, their team, an executive dashboard)
- How often will this be queried? (once, daily, real-time)
- Are there sensitivity constraints? (PII, regional restrictions)

### 2. Discover what's available

Search the user's Snowflake catalog using INFORMATION_SCHEMA. Show them
what tables exist, their row counts, column names, and any existing
comments or tags. Let the user pick what's relevant — don't assume.

### 3. Profile before building

Always profile the selected tables before creating views. Flag issues:
null rates, duplicates, stale data, skewed distributions. The user needs
to know what they're working with before committing to a data model.

### 4. Choose the right materialization

Load `references/decisions.md` for the decision framework. The choice
depends on query frequency, data freshness needs, and compute cost —
not on the use case itself.

### 5. Build it, document it, grant access

Create the object with clear naming, column comments, and a table-level
comment explaining the purpose and source tables. Grant SELECT to the
roles that need it. See `references/principles.md`.

### 6. Hand off to the IDE

Generate a handoff summary so Posit Assistant knows what was created.
See `references/handoff.md`. This is the bridge between the two agents.

---

## Demo mode (for Snowflake SEs)

When the user asks to set up demo data, run a demo, or prepare a demo
environment, use the scripts in `scripts/`:

- **`scripts/setup-demo-data.sql`** — Creates 2.2M rows of synthetic data
  (sales, customers, products, loan applications) plus RBAC roles and
  policies. The user edits three variables at the top:
  ```sql
  SET DEMO_DATABASE  = 'SOL_ENG_DEMO';
  SET DEMO_SCHEMA    = 'COCO_DEMO';
  SET DEMO_WAREHOUSE = 'DEFAULT_WH';
  ```
  Run this when the user says: "set up demo data", "create sample data",
  "prepare the demo environment", or "I need data for a demo".

- **`scripts/teardown-demo.sql`** — Drops the demo schema and RBAC roles.
  Run when the user says: "clean up the demo", "tear down", or "remove
  demo data".

After setup, hand off with a summary of what was created so the user can
switch to `$posit` to build demo apps, or go to Posit Assistant to analyze.
