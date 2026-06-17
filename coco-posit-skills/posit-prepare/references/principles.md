# Principles for Data Preparation

These apply to every object this skill creates, regardless of use case.

---

## Push compute to Snowflake

The whole point of preparing data as Snowflake objects is that R/Python
doesn't have to do the heavy lifting. Every join, filter, aggregation,
and transformation should happen in SQL. The analyst in the IDE should
receive a clean, analysis-ready object they can query directly.

If you catch yourself thinking "the user can filter this in R" — put
the filter in the view instead.

## Name for humans

Object names should tell the user what the data IS, not how it was built.

Good: `CUSTOMER_MONTHLY_REVENUE`, `LOAN_RISK_SCORES`, `PRODUCT_PERFORMANCE`
Bad: `V_JOIN_CUST_SALES_AGG_V2`, `TMP_FINAL_OUTPUT`, `MY_VIEW`

Use the pattern: `<what-it-describes>` or `<project>_<what-it-describes>`.

## Document everything

Every object this skill creates must have:
1. A table-level `COMMENT` explaining: what the data represents, which
   source tables it draws from, and when/why it was created.
2. Column-level `COMMENT ON COLUMN` for any derived or non-obvious column
   (calculated fields, flags, business logic).

This isn't optional — it's what makes the object useful to Posit Assistant
and to future users who didn't build it.

## Grant immediately

A view without grants is invisible. After creating any object:
1. Grant `SELECT` to the user's current role (at minimum).
2. If the user said the data is for their team, grant to the team role.
3. For shared/org-wide objects, consider `GRANT ON FUTURE` so new objects
   in the schema are automatically accessible.

Always show the user which grants were applied.

## Profile before building

Never create a curated view without first profiling the source tables.
The profile reveals issues that change the design:
- High null rates → need COALESCE or exclusion logic
- Duplicate keys → need deduplication (QUALIFY ROW_NUMBER)
- Stale data → user should know before building on it
- Skewed distributions → may need binning or log transforms

Present the profile as a readable summary, not raw query results. Flag
issues explicitly: "⚠️ 23% of rows have NULL annual_income."

## Don't over-engineer

Match the complexity of the solution to the complexity of the problem:

| User need | Right response | Wrong response |
|---|---|---|
| "I need to see sales by region" | Simple VIEW with GROUP BY | Dynamic table + masking policy + RLS |
| "My team needs hourly dashboards" | Dynamic table, 1hr lag | 1-minute lag (expensive, unnecessary) |
| "Just exploring this table" | Profile it, skip the view | Build a full curated layer |
| "Prepare this for production" | Dynamic table + governance + grants | Simple view with no comments |

Ask about the scope before building. A quick exploration doesn't need
the same treatment as a production data product.

## Show your work

After creating any object, display:
1. What was created (full object name)
2. Row count and column list
3. Grants applied
4. Refresh schedule (for dynamic tables)
5. Any governance policies attached

Then generate the handoff summary (see `references/handoff.md`).

## Anti-patterns to avoid

- **SELECT *** in views — list columns explicitly. The user's analysis
  shouldn't break when someone adds a column to the source table.
- **Cross-database joins without telling the user** — these work in
  Snowflake but the user should know the view depends on multiple databases.
- **Creating objects in INFORMATION_SCHEMA or PUBLIC** — always confirm
  the target schema.
- **Masking with CASE statements in the view** — use a proper masking
  policy instead. CASE-based masking is fragile and doesn't show up in
  governance reports.
- **Forgetting to handle NULLs** — if a join produces NULLs (LEFT JOIN),
  decide whether to COALESCE, filter, or leave them. Don't silently pass
  NULLs through without telling the user.
