# ADR-0009: GitHub Actions CI — dedicated ANALYTICS_CI database and CI_SVC service user

- **Status:** accepted
- **Date:** 2026-04-19
- **Deciders:** Eric Silinda

## Context

With CORE and MARTS now built, the project needs CI: every PR to master should run `dbt build` against Snowflake to catch compile errors, materialization failures, and test failures before merge. GitHub Actions is the hosting target (already in the stack per CLAUDE.md §2).

Four design axes to decide:

1. **What to run in CI** — `dbt parse`/`compile` vs `dbt build` vs `dbt build --state modified+`
2. **Isolation** — where should CI's artifacts live relative to dev
3. **Service identity** — reuse `LSILINDA` credentials or dedicate a service user
4. **Compute** — reuse `TRANSFORM_WH` or dedicate a warehouse

## Decisions

### 1. Run full `dbt build` on every PR

Runs models + tests in dependency order against live Snowflake. `parse`/`compile` is too weak (doesn't catch materialization or runtime errors). State-based partial builds are worth adding later for speed but full builds are the correct starting point.

### 2. Dedicated `ANALYTICS_CI` database with shared `STAGING`/`CORE`/`MARTS` schemas

Not per-PR schemas, not shared `CI_*` schemas inside `ANALYTICS_DEV`. Options considered:

| Option | Approach | Verdict |
|---|---|---|
| A | Write to `CI_STAGING`/`CI_CORE`/`CI_MARTS` in `ANALYTICS_DEV` | Rejected — no env separation; one bad CI run can corrupt dev artifacts a developer is querying |
| B | PR-unique schemas in `ANALYTICS_DEV` (`PR_123_STAGING`) | Rejected for now — requires cleanup job, schema proliferation, overkill for team of 1-5 |
| C | Dedicated `ANALYTICS_CI` database with fixed schemas | **Chosen** — real env separation with minimal complexity |
| D | Option C plus per-PR schemas inside `ANALYTICS_CI` | Future: adopt when team grows past ~5 or concurrent PR volume warrants it |

**Why C:**
- Blast radius containment — CI cannot touch dev objects
- Independent cost tracking — dedicated resource monitor shows CI spend distinct from dev analyst activity
- Easier RBAC — `CI_SVC` only gets grants on `ANALYTICS_CI`
- Easy wipe/rebuild — `DROP DATABASE ANALYTICS_CI CASCADE` has zero collateral damage
- Modelled pattern — matches real enterprise environment separation

**Shared rather than per-PR schemas** is acceptable because:
- Team size is 1 today; grows to 3-5 is plausible
- Concurrent-PR collision window is only the 5 min of CI runtime per PR
- Adopting per-PR later is a small change (one macro) with no structural impact

**Source data access:** rather than duplicate 1.8M RAW rows into `ANALYTICS_CI`, grant the CI role SELECT on `ANALYTICS_DEV.RAW_*`. CI reads source, writes transforms. Keeps storage single-sourced.

### 3. Dedicated `CI_SVC` user with key-pair auth

Create a dedicated Snowflake service user rather than reuse `LSILINDA`.

Trade-off considered:

| Option | Pros | Cons |
|---|---|---|
| A | Reuse `LSILINDA` key and role | Simpler — one identity |
| B | Dedicated `CI_SVC` user with its own key | Proper service-account separation; rotatable independent of human user |

**Chose B** because:
- Audit log shows CI activity distinctly from human activity
- Can disable CI_SVC without affecting developer access
- Can rotate CI keys without rotating developer keys
- Shows separation-of-identity discipline in the portfolio writeup
- Marginal extra cost is 15 min of Terraform

CI_SVC is granted `FR_ENGINEER` (same as developer). A tighter `FR_CI` role with only DEV.RAW_* SELECT + CI write access would be better, but adds module complexity for limited marginal benefit today. Tighten later if needed.

### 4. Reuse `TRANSFORM_WH`, tied to existing `RM_TRANSFORM_WH` monitor

CI workload is identical in shape to dbt runs (compile + COPY INTO + tests). Existing `TRANSFORM_WH` (XS, auto-suspend 60s) is sized correctly. Existing `RM_TRANSFORM_WH` (3 credits/month) caps CI spend automatically. A dedicated `CI_WH` would add complexity with no real benefit at this scale.

## Consequences

- `ANALYTICS_CI` is created via Terraform using the existing `snowflake_database_layers` module (no new modules needed).
- `CI_SVC` user added to `snowflake_rbac` module via `user_grants`. Private key registered on the user (generated outside the repo, same pattern as `LSILINDA`).
- Cross-database SELECT grants: `FR_ENGINEER` gains SELECT on `ANALYTICS_DEV.RAW_*` future tables (extends the existing RW grant set).
- dbt `profiles.yml.example` gains a `ci` target pointing at `ANALYTICS_CI`.
- `.github/workflows/dbt_ci.yml` runs on PR: installs dbt, writes profiles.yml from secrets, runs `dbt deps` + `dbt build`.
- Six GitHub secrets required: account, user, private key (base64-encoded), role, warehouse, database.
- README documents the secret setup + CI_SVC key generation steps.

## Known limitations to revisit

- **Concurrent-PR collision in CI.** Mitigation today: rare at team size 1-5. Future fix: per-PR schema suffix via `generate_schema_name`.
- **No teardown/cleanup job.** Each CI run overwrites via dbt's `CREATE OR REPLACE`. Fine until schemas get crufty.
- **`FR_ENGINEER` for CI is broader than needed.** Future tightening to a dedicated `FR_CI` role with write access only to CI_STAGING/CORE/MARTS and read access to DEV.RAW_*.
- **No deploy-to-dev workflow yet.** When a PR merges to master, nothing auto-deploys to `ANALYTICS_DEV`. Adding `dbt_main.yml` is straightforward follow-up.
