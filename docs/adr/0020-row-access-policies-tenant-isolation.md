# ADR-0020: Row access policies for multi-tenant isolation on CORE / MARTS

- **Status:** accepted
- **Date:** 2026-04-24
- **Deciders:** Eric Silinda
- **Builds on:** [ADR-0006](0006-named-raw-schemas.md) (per-tenant RAW), [ADR-0019](0019-fr-ci-tighter-role.md) (FR_CI design)

## Context

The project models three tenants (Main Book, Indigo Insurance, Horizon
Assurance) into shared `CORE` and `MARTS` schemas. The conformed star
schema and Vault models all carry a `company` column denoting which tenant
each row belongs to.

Current state: any role with `SELECT` on a CORE/MARTS table sees every
tenant's rows. This is fine for engineering (`FR_ENGINEER`) and for the
shared `FR_ANALYST` role used during model development. It is **wrong**
for the Solution Architect story this project deliberately exercises:
multi-tenant SaaS data platforms isolate tenants in the data layer, not
just in application code.

The natural Snowflake-native primitive is a row access policy (RAP):
a function returning `BOOLEAN` keyed off `current_role()` and the row's
`company` value, attached to each table's `company` column.

## Decisions

### 1. Single shared policy, role-keyed

One policy `RAP_TENANT_ISOLATION(company VARCHAR) RETURNS BOOLEAN` lives
in `ANALYTICS_DEV.CORE`. Body:

```sql
case
  when current_role() in ('ACCOUNTADMIN', 'FR_ENGINEER', 'FR_CI', 'FR_ANALYST') then true
  when current_role() = 'FR_ANALYST_MAIN_BOOK'         and company = 'MAIN_BOOK'         then true
  when current_role() = 'FR_ANALYST_INDIGO_INSURANCE'  and company = 'INDIGO_INSURANCE'  then true
  when current_role() = 'FR_ANALYST_HORIZON_ASSURANCE' and company = 'HORIZON_ASSURANCE' then true
  else false
end
```

Role-bypass list rationale:

| Role | Sees | Why |
|---|---|---|
| `ACCOUNTADMIN` | all | platform admin |
| `FR_ENGINEER` | all | data-engineering ops; builds and audits everything |
| `FR_CI` | all | CI tests count cross-tenant; full visibility lets tests assert real totals |
| `FR_ANALYST` | all | preserves current behaviour for the shared analyst role |
| `FR_ANALYST_<TENANT>` | one tenant | the new isolation contract |
| anything else | none | defensive default; e.g. `FR_AIRBYTE` shouldn't query CORE/MARTS |

A single policy is simpler than per-tenant policies: one object to manage,
one place to add a tenant. Trade-off: a `case` statement linear in the
number of tenants. For 3-10 tenants that's fine; at hundreds it would be
worth a lookup table approach.

### 2. Three new tenant-scoped functional roles

`FR_ANALYST_MAIN_BOOK`, `FR_ANALYST_INDIGO_INSURANCE`,
`FR_ANALYST_HORIZON_ASSURANCE`. Each gets the same access roles as
`FR_ANALYST` (`staging_ro`, `core_ro`, `marts_ro`, `raw_quarantine_ro`)
plus `BI_WH` USAGE — the RAP filters at the row level, so granting the
same SELECTs is correct.

All three are granted to `LSILINDA` for live testing. No new service
users — production-style mapping (one human user per tenant) is post-v1.0
work.

### 3. Attach via dbt post-hook, gated on `target.database`

Mirrors the masking-policy pattern from ADR-0009. The post-hook only
runs when `target.database == 'ANALYTICS_DEV'`, so:

- **dev:** policy attached, isolation enforced.
- **CI (`ANALYTICS_CI`):** post-hook no-ops; CI tests run against
  unfiltered data, so test counts match expected row totals across all
  three tenants.

A new dbt macro `attach_rap_tenant_isolation()` encapsulates the
two-statement attach (drop-all + add):

```sql
ALTER TABLE {{ this }} DROP ALL ROW ACCESS POLICIES;
ALTER TABLE {{ this }} ADD ROW ACCESS POLICY ANALYTICS_DEV.CORE.RAP_TENANT_ISOLATION ON (company);
```

`DROP ALL` is required because Snowflake errors if you `ADD` while a
policy is already attached. `DROP ALL` is idempotent; it survives policy
renames and detaches any orphan attachment from earlier experiments.

The post-hook is added to **13 models** with a `company` column:

- 5 conformed dims: `dim_advisor`, `dim_client`, `dim_fund`,
  `dim_policy`, `dim_product`
- 1 SCD2 view: `dim_policy_history`
- 4 facts: `fct_commissions`, `fct_policies`, `fct_transactions`,
  `fct_valuations`
- 3 marts: `finance_advisor_commissions_monthly`,
  `portfolio_aum_monthly`, `risk_policy_inforce`

`dim_date` is excluded (no `company`). Vault hubs/links/sats are
excluded by scope: the Vault is a separate transactions domain owned
by data engineering, not by tenant analysts.

### 4. APPLY grant on RAP → FR_ENGINEER

Mirrors how the masking-policy `APPLY` is granted today (in
`environments/dev/main.tf`). Both `LSILINDA` and `CI_SVC` run dbt as
`FR_ENGINEER` against `ANALYTICS_DEV`; `FR_CI` (CI's role against
`ANALYTICS_CI`) doesn't need APPLY because the post-hook is gated.

## Consequences

### Verification

A `scripts/verify_tenant_isolation.py` opens a fresh Snowflake session
per role, runs `SELECT count(*)` over a sample of protected tables, and
asserts:

- `FR_ANALYST_MAIN_BOOK` sees only `MAIN_BOOK` rows on every protected
  table.
- Same for the other two tenant roles.
- `FR_ANALYST` sees all rows (current behaviour preserved).
- `FR_ENGINEER` sees all rows.

Run after `terraform apply` + `dbt build`. The script is the canonical
acceptance test for ADR-0020.

### Cost

RAP adds a CTE-style filter to every SELECT against a protected table.
For our scale (~100K rows per fact, 3 tenants) the overhead is well
under 50ms per query. Unmeasurable against `BI_WH` cap.

### CI behaviour

`target.database == 'ANALYTICS_DEV'` gating means CI's `dbt build`
against `ANALYTICS_CI` does not attach the policy. CI tests therefore
see all three tenants' data and pass the same tests they would without
RAP. Switching CI to also attach RAP would require granting `FR_CI`
APPLY on the policy and would change test row counts — out of scope.

### Known limitations

- **Per-row entitlement (analyst-sees-only-their-advisor's-data) is
  out of scope.** This policy isolates by *tenant*, not by advisor or
  client. Per-row entitlement would be a separate policy on a separate
  column.
- **Vault models are not RAP-isolated.** Tenant analysts cannot reach
  them via current grants, so the gap is notional. If the Vault is ever
  exposed to tenant analysts, it needs its own policy attachment.
- **Streamlit app runs as ACCOUNTADMIN owner** (see ADR-0017 / ADR-0018).
  ACCOUNTADMIN bypasses RAP, so the Streamlit app continues to see all
  tenants. Per-tenant Streamlit requires a more complex executor pattern
  (`EXECUTE AS CALLER`) which Snowflake does not yet support for
  Streamlit objects (see issues-and-fixes.md). Documented in CLAUDE.md.

## Alternatives considered

| Option | Verdict |
|---|---|
| **Per-tenant masking policies** instead of RAP | Rejected — masking redacts column values; isolation requires hiding rows entirely. |
| **Per-tenant copy of CORE/MARTS** (`CORE_MAIN_BOOK`, ...) | Rejected — 3x storage and DDL drift; defeats the conformed model. |
| **Application-layer filtering in Streamlit/Power BI** | Rejected — the SA story is "isolation in the platform," not "trust the BI tool." Defense-in-depth: enforce in Snowflake too. |
| **Per-tenant policies, one per role** | Rejected — N policies and N attachments per table; harder to reason about. |
| **Lookup-table policy body** keyed off a `role_tenant_map` table | Rejected for now — overkill at 3 tenants; revisit at ~10+ tenants. |

## References

- [ADR-0006](0006-named-raw-schemas.md): per-tenant RAW schemas
- [ADR-0009](0009-ci-architecture.md): CI architecture (target.database gating precedent)
- [ADR-0019](0019-fr-ci-tighter-role.md): FR_CI bypasses RAP (rationale in §1 above)
- `terraform/modules/snowflake_row_access_policies/` — module
- `dbt/macros/attach_rap_tenant_isolation.sql` — attach helper
- `scripts/verify_tenant_isolation.py` — acceptance test