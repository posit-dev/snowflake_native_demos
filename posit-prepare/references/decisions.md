# Decision Framework

CoCo already knows SQL syntax. This file teaches WHEN and WHY to make
specific choices. Apply these decision trees to any use case.

---

## Materialization: view vs dynamic table vs table

```
Is the underlying query expensive (joins 3+ tables, aggregates millions of rows)?
├── NO  → CREATE VIEW (no storage cost, always current)
└── YES → Will the result be queried more than once per refresh cycle?
          ├── NO  → CREATE TABLE AS SELECT (one-time snapshot)
          └── YES → How fresh does the data need to be?
                    ├── Real-time (< 1 min)    → CREATE DYNAMIC TABLE, TARGET_LAG = '1 minute'
                    ├── Near-real-time (< 1 hr) → CREATE DYNAMIC TABLE, TARGET_LAG = '1 hour'
                    ├── Daily                    → CREATE DYNAMIC TABLE, TARGET_LAG = '24 hours'
                    └── On-demand only           → CREATE TABLE + Snowflake TASK on schedule
```

**Default to VIEW unless the user describes a clear performance problem or
refresh requirement.** Views cost nothing and are always current.

## Secure view vs standard view

```
Does the view contain sensitive data OR will viewers with different roles query it?
├── NO  → Standard VIEW
└── YES → Does the SQL definition itself reveal sensitive logic?
          ├── NO  → Standard VIEW + masking policies on sensitive columns
          └── YES → SECURE VIEW (hides SQL from viewers)
```

**Default to standard views.** Secure views disable some query optimizations.
Use them only when the SQL logic itself is sensitive — not just the data.

## Governance: when to apply policies

```
Does the data contain PII (names, emails, SSNs, addresses, phone numbers)?
├── YES → Apply masking policy. Reveal to privileged roles only.
└── NO  → Skip masking.

Should different users see different rows (regional teams, org hierarchy)?
├── YES → Apply row access policy based on CURRENT_ROLE() or CURRENT_USER().
└── NO  → Skip RLS.

Should columns be discoverable in the catalog with semantic meaning?
├── YES → Apply object tags (SNOWFLAKE.CORE.PRIVACY_CATEGORY, custom tags).
└── NO  → Add COMMENT ON COLUMN instead (lighter weight).
```

**Don't over-govern.** If the user just needs a quick view for their own
analysis, comments and grants are enough. Save policies for team-wide or
org-wide shared objects.

## Schema placement

```
Is this for one person's analysis?
├── YES → Create in the user's working schema (sandbox, personal schema)
└── NO  → Is it for a specific project or team?
          ├── YES → Create in a project/team schema (e.g., CHURN_ANALYSIS, DATA_SCIENCE)
          └── NO  → Create in a shared analytics schema (e.g., ANALYTICS, CURATED)
```

**Always confirm the target schema with the user before running DDL.**
