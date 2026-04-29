# ADR-0019: Tighter `FR_CI` role — least-privilege CI_SVC

- **Status:** accepted
- **Date:** 2026-04-24
- **Deciders:** Eric Silinda
- **Builds on:** [ADR-0009](0009-ci-architecture.md) (CI architecture)

## Context

`CI_SVC` was bootstrapped on `FR_ENGINEER` (ADR-0009) — the same functional
role developers use. That was deliberate at the time: keep CI architecture
PR small, ship the green-build signal first, tighten later. ADR-0009 itself
flagged this as a follow-up under §6.

`FR_ENGINEER` grants more than CI needs:

| Privilege | FR_ENGINEER has it | CI needs it? |
|---|---|---|
| RW on `ANALYTICS_DEV.RAW_*` | yes | **no** — CI reads source from `ANALYTICS_DEV` |
| RW on `ANALYTICS_DEV.STAGING/CORE/MARTS` | yes | **no** — CI builds those in `ANALYTICS_CI` |
| RW on `ANALYTICS_DEV.RAW_QUARANTINE/RAW_OPS` | yes | **no** — never touched by CI |
| RW on `ANALYTICS_CI.*` | yes (via direct grants) | **yes** |
| `APPLY` on masking policies | yes | **no** — post-hook is `target.database` gated, no-ops in CI |
| `USAGE` on `BI_WH` | yes | **no** — CI runs on `TRANSFORM_WH` only |
| `USAGE` on `LOAD_WH` | yes | **no** — Snowpipe is not a CI concern |
| `USAGE` on `TRANSFORM_WH` | yes | **yes** |

Every "no" is a blast-radius leak. If `CI_SVC` credentials are compromised
or a PR contains a malicious dbt model, the role can write to dev objects,
strip masking policies, or burn `BI_WH` credits. None of that is
necessary for CI's job: read from dev, write to CI database, run tests.

## Decisions

### 1. Create dedicated `FR_CI` functional role

Net change vs `FR_ENGINEER`:

- **Read-only on `ANALYTICS_DEV.*`** — granted via all `*_ro` access roles
  produced by the `snowflake_rbac` module (`raw_main_book_ro`,
  `raw_indigo_insurance_ro`, `raw_horizon_assurance_ro`, `staging_ro`,
  `core_ro`, `marts_ro`, `raw_quarantine_ro`, `raw_ops_ro`). Eight RO
  access roles, each carrying USAGE + SELECT on its schema.
- **Read-write on `ANALYTICS_CI.*`** — direct grants on the `ANALYTICS_CI`
  database object: `USAGE` + `CREATE SCHEMA`. dbt creates per-PR schemas at
  runtime (`PR_<n>_STAGING`, etc.) and `CI_SVC` becomes the owner of every
  schema it creates, so no further grants are needed inside the database.
- **Usage on `TRANSFORM_WH`** — dbt's only compute target in CI.
- **No `APPLY` on masking policies.** The masking-policy post-hook is
  gated `when target.database == 'ANALYTICS_DEV'`, so it doesn't fire in
  CI runs (`target.database = 'ANALYTICS_CI'`). FR_CI without APPLY is
  safe.
- **No `BI_WH` access.** CI doesn't run BI workloads.
- **No `LOAD_WH` access.** Snowpipe is unrelated to CI.

### 2. Switch `CI_SVC` from `FR_ENGINEER` to `FR_CI`

Three Terraform-resource changes on `CI_SVC`:

1. `default_role` flips from `FR_ENGINEER` to `FR_CI` (in-place update).
2. New `snowflake_grant_account_role.ci_svc_fr_ci` granting `FR_CI` to `CI_SVC`.
3. Destroy `snowflake_grant_account_role.ci_svc_fr_engineer`.

Terraform's resource graph will create `FR_CI` (and its grants) before
modifying `CI_SVC.default_role`, since the user resource references the
role. The race window between "FR_CI granted" and "FR_ENGINEER revoked" is
milliseconds and only matters if a CI run happens to start in that window
— acceptable risk for a personal portfolio project.

### 3. Remove `FR_ENGINEER`'s direct grants on `ANALYTICS_CI`

The two existing `snowflake_grant_privileges_to_account_role` resources
(`fr_engineer_ci_database_usage`, `fr_engineer_ci_database_create_schema`)
are replaced by `fr_ci_database_usage` and `fr_ci_database_create_schema`
on the same database object but for the new role.

Why: least-privilege. `LSILINDA` (the only user on `FR_ENGINEER`) doesn't
run dbt against `ANALYTICS_CI` directly — that's what the GitHub Actions
workflow is for. After PR-B, `SHOW GRANTS ON DATABASE ANALYTICS_CI` will
show no `FR_ENGINEER` row, which is the correct end state.

## Consequences

### Verification

PR-B's own GitHub Actions CI run is the live test:

- The PR opens with the FR_CI config staged but `terraform apply` not yet
  done. Local apply happens before push.
- Once applied, `CI_SVC` is using `FR_CI` for the rest of this PR's CI
  evaluation.
- If `dbt_ci.yml` returns green on this PR, `FR_CI` works end-to-end:
  it can read source from `ANALYTICS_DEV`, write models to
  `ANALYTICS_CI.PR_<n>_*`, run tests, and exit cleanly.
- If it fails, the failure points us at exactly what privilege is missing.
  Most likely candidates: missing future-grant on a newly-added schema,
  missing warehouse usage, or a hidden post-hook that needs APPLY.

Spot checks after apply:

```sql
SHOW GRANTS TO ROLE FR_CI;
-- Should show: USAGE on ANALYTICS_CI database, CREATE SCHEMA on ANALYTICS_CI,
--              USAGE on TRANSFORM_WH, plus all 8 *_ro access roles.

SHOW GRANTS TO USER CI_SVC;
-- Should show FR_CI (granted), no FR_ENGINEER.

SHOW GRANTS ON DATABASE ANALYTICS_CI;
-- Should show FR_CI (USAGE + CREATE SCHEMA), no FR_ENGINEER row.
```

### Blast-radius reduction

If `CI_SVC` is compromised post-PR-B:

- **Cannot** write to `ANALYTICS_DEV.*` (RO only).
- **Cannot** strip masking policies (no APPLY).
- **Cannot** burn `BI_WH` or `LOAD_WH` credits.
- **Can** read `ANALYTICS_DEV` data (acceptable — it's mock test data).
- **Can** create / fill / drop schemas in `ANALYTICS_CI` (acceptable —
  CI database is for CI, isolated from dev).

### Cost impact

Zero. Same RBAC pattern, just a different role. Resource count goes up
by ~10 grant edges; resource monitor coverage unchanged.

### Known limitation: orphan `ANALYTICS_CI.PR_<n>_*` schemas

CI schemas created before PR-B are owned by `FR_ENGINEER` (via `CI_SVC`
acting on `FR_ENGINEER` at the time of creation). After the role swap,
`CI_SVC` running as `FR_CI` cannot see them — `FR_CI` has no grants
inherited from `FR_ENGINEER`.

These orphans are zero-cost (empty schemas hold no storage), the
`dbt_ci_teardown.yml` workflow already drops `PR_<n>_*` schemas on PR
close, and any orphan from a closed PR can be manually removed via
`ACCOUNTADMIN`:

```sql
SHOW SCHEMAS IN DATABASE ANALYTICS_CI;
-- Identify any PR_<n>_* schemas owned by FR_ENGINEER that aren't tied to
-- a still-open PR. Drop them with ACCOUNTADMIN.
DROP SCHEMA ANALYTICS_CI.PR_<n>_STAGING;  -- etc.
```

Decided to accept rather than orchestrate a chown-on-apply workflow:
the cleanup is one-time, low-risk, and runs under operator supervision.

## Alternatives considered

| Option | Verdict |
|---|---|
| **Keep `CI_SVC` on `FR_ENGINEER`; add a new `FR_CI` for future use** | Rejected — defeats the purpose. Least-privilege only matters when applied. |
| **Make `FR_CI` inherit from `FR_ENGINEER`** | Rejected — Snowflake role hierarchies are aggregating, not subtractive. Inheriting `FR_ENGINEER` then "removing" privileges isn't a thing. Build `FR_CI` standalone. |
| **Two-phase: add `FR_CI` first, swap `CI_SVC` in a follow-up PR** | Rejected — adds a stale PR window where `FR_CI` exists but is unused. The Terraform graph already orders create-before-destroy for the user role grant. |
| **Auto-clean orphan CI schemas in this PR** | Rejected — out of scope. The teardown workflow handles new PRs; old orphans are a one-time housekeeping task, not a recurring concern. |

## References

- ADR-0009: GitHub Actions CI architecture (parent decision)
- `terraform/environments/dev/main.tf` — FR_CI definition + CI_SVC swap
- `.github/workflows/dbt_ci.yml` — the CI workflow that uses CI_SVC