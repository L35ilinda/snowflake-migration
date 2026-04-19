# Issues and fixes — replication guide

Every non-trivial blocker hit during this project, with root cause and fix. If you are rebuilding this project (or a similar Snowflake+Azure+dbt stack) from zero, read this first — these are the traps that cost time the first time.

Cross-references:
- Architecture/context: [CLAUDE.md](../../CLAUDE.md) and [ADRs](../adr/)
- Chronology: the daily logs [2026-04-15](2026-04-15.md), [2026-04-16](2026-04-16.md), [2026-04-19](2026-04-19.md)
- This document is the **de-duplicated** catalogue; daily logs keep the narrative order.

---

## Recommended replication order

Bootstrap order matters — later steps depend on earlier ones working. Deviating causes cascading pain.

1. Azure tenant/subscription + pre-existing storage account (out of scope here).
2. Terraform backend: `terraform/bootstrap/` → creates `tfstate` container; one-time local-state apply. Grant the applying user `Storage Blob Data Contributor` on the storage account **before** running.
3. Snowflake provider migration to `snowflakedb/snowflake` and key-pair auth (see §"Snowflake provider & auth").
4. First Snowflake apply: storage integration → Azure admin consent → grant `Storage Blob Data Reader` on storage account to the Snowflake enterprise app.
5. Database + schema layers, then per-company external stages and file formats.
6. Azure containers (via `azure_blob_containers` module) **and** an explicit `depends_on` from the ingest module, or stages will fail at create time with a container-not-found race.
7. RBAC module (access + functional roles), then warehouses + resource monitors.
8. **Grant `CREATE SCHEMA` on the database to RW access roles** and **`APPLY` on masking policies to FR_ENGINEER** _before_ the first dbt run — both are easy to miss and cause late failures.
9. dbt init → `dbt debug` → first `dbt build` (staging → core → marts).
10. Snowpipe Azure auto-ingest two-step bootstrap (see §"Snowpipe auto-ingest bootstrap").
11. GitHub Actions CI: `ANALYTICS_CI` database + `CI_SVC` user + 6 GitHub secrets + branch protection. Repo must be public **or** GitHub Pro for branch protection.
12. Streamlit + Cortex Analyst scaffold. Cortex Analyst only lights up in supported regions (see §"Cortex Analyst regional block").

---

## Category index

- [Snowflake provider & auth](#snowflake-provider--auth)
- [Snowflake provider quirks (v1.x)](#snowflake-provider-quirks-v1x)
- [Preview feature gating](#preview-feature-gating)
- [Cross-provider race conditions](#cross-provider-race-conditions)
- [Azure CLI quirks](#azure-cli-quirks)
- [Snowpipe bootstrap](#snowpipe-bootstrap)
- [Snowpipe COPY INTO quirks](#snowpipe-copy-into-quirks)
- [RBAC and permissions](#rbac-and-permissions)
- [dbt setup and behaviour](#dbt-setup-and-behaviour)
- [Data quality patterns](#data-quality-patterns)
- [GitHub Actions CI](#github-actions-ci)
- [Streamlit in Snowflake](#streamlit-in-snowflake)
- [Cortex Analyst regional block](#cortex-analyst-regional-block)

---

## Snowflake provider & auth

### Deprecated `Snowflake-Labs/snowflake` provider
- **Symptom:** Using `Snowflake-Labs/snowflake` source. Features lag, newer docs reference different resources.
- **Fix:** Migrate to `snowflakedb/snowflake ~> 1.0` (the official SDN provider).
- **Replication tip:** Start on `snowflakedb/snowflake` from day zero.

### `authenticator = "ExternalBrowser"` fails
- **Symptom:** Provider attempts to open a browser for SSO, fails in Terraform context with a SAML-federation error.
- **Root cause:** Snowflake account has SAML/SSO but no compatible federation for CLI-initiated browser auth.
- **Fix:** Switch to `authenticator = "SNOWFLAKE_JWT"` + key-pair. ADR-0005.
- **Replication tip:** Generate the RSA key pair *outside* the repo (e.g. `~/.snowflake/keys/`). Use PKCS#8 PEM format. Register the public key on the user with `ALTER USER X SET RSA_PUBLIC_KEY = '...';`.

### `openssl` not on PATH (Windows)
- **Symptom:** Key-generation commands from Snowflake docs assume openssl is available; Windows often doesn't have it.
- **Fix:** Generate keys with Python `cryptography` library (shipped with Anaconda). See `scripts/` in this repo for the snippet used.

---

## Snowflake provider quirks (v1.x)

### `snowflake_stage.directory` force-replacement drift
- **Symptom:** Apply plan wants to replace existing stages. Diff shows `directory` attribute changing between null and `"ENABLE = true"`.
- **Root cause:** Snowflake server-side defaults `directory` to `ENABLE = true`. The provider treats it as `ForceNew`.
- **Fix:** Pin it explicitly in the module: `directory = "ENABLE = true"`.
- **Replication tip:** Do this on every `snowflake_stage` resource from the start — rebuilds are harmless, but prevention is free.

### `snowflake_grant_database_role` "inconsistent result after apply"
- **Symptom:** `Error: Provider produced inconsistent result after apply ... Root object was present, but now absent`. Grant *does* land server-side, but Terraform state read-back fails.
- **Fix:** Use `snowflake_execute` with explicit `GRANT DATABASE ROLE ... TO ROLE ...` / `REVOKE` / `SHOW GRANTS TO ROLE ...` as the create/destroy/read triplet.

### Notification-integration resource doesn't expose consent URL
- **Symptom:** After `terraform apply` of a `snowflake_notification_integration` (Azure), there's no `azure_consent_url` or `azure_multi_tenant_app_name` attribute, unlike for `snowflake_storage_integration`.
- **Fix:** After apply, run `DESC NOTIFICATION INTEGRATION <name>` and grep the `AZURE_CONSENT_URL` / `AZURE_MULTI_TENANT_APP_NAME` rows manually.

### `EXECUTE_AS` not settable on `snowflake_streamlit`
- **Symptom:** `ALTER STREAMLIT ... SET EXECUTE_AS = 'CALLER'` returns `invalid property 'EXECUTE_AS'`.
- **Root cause:** Not yet supported by Snowflake for Streamlit objects.
- **Fix:** Ensure the owner role has the privileges the app needs (see §"Streamlit in Snowflake").

---

## Preview feature gating

Several Snowflake provider v1.x resources are gated by `preview_features_enabled` in the provider config. Turning them on is a one-line fix, but the error message is opaque until you know to look.

Resources we needed to enable, in order:
- `snowflake_storage_integration_resource`
- `snowflake_stage_resource`
- `snowflake_file_format_resource`
- `snowflake_pipe_resource`
- `snowflake_table_resource`
- `snowflake_notification_integration_resource`

**Not** a preview resource (do **not** add — will reject): `snowflake_streamlit_resource` is GA.

---

## Cross-provider race conditions

### Snowflake stage created before Azure container
- **Symptom:** `terraform apply` fails: `Pipe Notifications bind failure: could not locate queue` or `The specified container does not exist`. Azure container and Snowflake stage creation are parallelised by Terraform.
- **Fix:** Add `depends_on = [module.azure_containers]` on the `company_ingest` module.

### Snowpipe created before landing table
- **Symptom:** `Pipe creation failed ... table does not exist`.
- **Fix:** `depends_on = [snowflake_table.landing]` on the `snowflake_pipe` resource inside `snowflake_snowpipe` module.

### Snowpipe created before queue RBAC
- **Symptom:** First apply after adding the notification integration fails with `Pipe Notifications bind failure: Internal error, could not locate queue for integration`. Azure admin consent and queue RBAC must be in place before Snowflake can validate the queue.
- **Fix:** Two-step bootstrap (documented in §"Snowpipe auto-ingest bootstrap").

---

## Azure CLI quirks

### `az storage blob copy start --auth-mode login` returns `InvalidUri`
- **Symptom:** Single-blob cross-container copies fail with a misleading URI error when using Entra-ID auth.
- **Fix:** Use `az storage copy` (the newer `azcopy`-backed command) for any non-trivial copy. It handles auth correctly.

### `az storage blob copy start` doesn't support same-container renames
- **Symptom:** "Copy blob from `Outbound/X.csv` to `X.csv` in the same container" fails.
- **Fix:** Download locally, re-upload to target path, delete originals. We used this to flatten `Outbound/` prefixes out of the company containers.

### `az role assignment create` returns `MissingSubscription` persistently
- **Symptom:** Despite correctly authenticated `az account show`, role-assignment creation at a storage-account scope fails repeatedly.
- **Root cause:** CLI wraps ARM in a way that this specific scope returns a misleading error.
- **Fix:** Call the REST API directly with `az rest --method put --url 'https://management.azure.com<scope>/providers/Microsoft.Authorization/roleAssignments/<uuid>?api-version=2022-04-01' --body ...`. Works where CLI fails. Used for granting `Storage Queue Data Contributor` to Snowflake's multi-tenant app.

### Role assignment for `Storage Queue Data Contributor` can't scope to queue
- **Symptom:** `Microsoft.Storage/storageAccounts/<sa>/queueServices/default/queues/<queue>` as a scope returns `MissingSubscription`.
- **Fix:** Scope at the storage-account level. If there are multiple queues you only want one consumer to see, use data-plane ACLs instead of RBAC.

### Azure admin consent can be automated
- **Symptom:** Every Snowflake storage/notification integration asks for browser admin consent on an `AZURE_CONSENT_URL`.
- **Fix:** Run `az ad sp create --id <client_id_from_consent_url>` using an Azure admin account. Same effect as clicking through the consent page.

### Azure Event Grid System Topic must be created explicitly
- **Symptom:** `data "azurerm_eventgrid_system_topic"` lookup fails with "not found".
- **Root cause:** Storage accounts do *not* auto-provision a system topic. Our initial assumption was wrong.
- **Fix:** Create one via Terraform: `azurerm_eventgrid_system_topic` with `source_arm_resource_id = <storage_account_id>` and `topic_type = "Microsoft.Storage.StorageAccounts"`.

### Azure Event Grid subscription names reject underscores
- **Symptom:** Apply fails: `EventGrid subscription name must be 3-64 characters long, contain only letters, numbers and hyphens.`
- **Fix:** When deriving names from Snowflake identifiers (which use underscores), transform with `replace(lower(var.name), "_", "-")`.

---

## Snowpipe bootstrap

### Two-step apply is unavoidable
- **Sequence that works:**
  1. `terraform apply` creates the storage queue, Event Grid system topic, event subscription, Snowflake notification integration. Pipe creation in the same apply *will* fail.
  2. Retrieve consent URL + app name: `DESC NOTIFICATION INTEGRATION NI_AZURE_FSPSFTPSOURCE_DEV`.
  3. `az ad sp create --id <client-id>` (consent).
  4. `az rest --method put ...` to grant `Storage Queue Data Contributor` on the storage account to the Snowflake SP.
  5. `terraform apply` again — pipes now create with `AUTO_INGEST = TRUE`.
- **Why it can't be one step:** Snowflake validates queue reachability at pipe-create time; that needs the RBAC which needs the consent which needs the notification integration to exist first. Cyclic.

### Verifying auto-ingest works
- Upload a test CSV to a monitored container.
- Wait ~30-60s.
- `SYSTEM$PIPE_STATUS('<db>.<schema>.<pipe>')` should show `executionState: RUNNING` and updating timestamps.
- Confirm row count increases in the landing table.
- Measured latency in practice: **~41 seconds** file-upload-to-row-visible.

---

## Snowpipe COPY INTO quirks

### `METADATA$FILENAME` / `METADATA$FILE_ROW_NUMBER` not valid as column defaults
- **Symptom:** `snowflake_table` with a column default of `METADATA$FILENAME` fails on create.
- **Root cause:** These pseudo-columns are only valid inside a `COPY INTO` statement.
- **Fix:** Either drop them from the landing table OR select them explicitly in the pipe's `COPY INTO` SELECT clause. We dropped them.

### `CURRENT_TIMESTAMP()` default on `_LOADED_AT` does NOT fire on `COPY INTO`
- **Symptom:** Landing-table column `_LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()` stays NULL after Snowpipe loads rows.
- **Root cause:** Column defaults fire on explicit `INSERT`, not on `COPY INTO`.
- **Current state:** Documented as a known limitation in ADR-0010. Proper fix is to explicitly select `CURRENT_TIMESTAMP()` as a value in the pipe's COPY statement, or drop `_LOADED_AT` from landing tables entirely.

### `MATCH_BY_COLUMN_NAME` conflicts with `SKIP_HEADER`
- **Symptom:** Pipe `COPY INTO` with both `MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE` and a file format using `SKIP_HEADER = 1` fails.
- **Root cause:** `MATCH_BY_COLUMN_NAME` requires `PARSE_HEADER = TRUE`, which conflicts with `SKIP_HEADER`.
- **Fix:** Use positional loading (order columns in the landing table to match the CSV).

### File-pattern regex for `risk_benefits` vs `risk_benefits_transactions`
- **Symptom:** A pattern like `.*risk_benefits[^_].*[.]csv` intended to exclude `_transactions` fails to match `risk_benefits.csv` (no char after `risk_benefits`).
- **Fix:** Use an exact tail anchor — e.g. `.*risk_benefits[.]csv` — or two separate patterns.

---

## RBAC and permissions

### dbt fails with "Insufficient privileges to operate on database ANALYTICS_DEV"
- **Symptom:** `dbt build` under `FR_ENGINEER` fails to even touch the database.
- **Root cause:** dbt runs `CREATE SCHEMA IF NOT EXISTS` before creating models. `FR_ENGINEER` had USAGE on database (via access roles) but not `CREATE SCHEMA`.
- **Fix:** Grant `CREATE SCHEMA` on the database to every RW access role (added to `snowflake_rbac` module).

### dbt masking-policy post-hook fails: "policy does not exist or not authorized"
- **Symptom:** `dim_client` post-hook attaching masking policies fails under `FR_ENGINEER`. Works under `ACCOUNTADMIN`.
- **Root cause:** `FR_ENGINEER` owns the tables but wasn't granted `APPLY` on the masking policies.
- **Fix:** `snowflake_grant_privileges_to_account_role` granting `APPLY` on each masking policy to `FR_ENGINEER`.

### Masking policy scoped to one env breaks dbt build in another
- **Symptom:** CI build against `ANALYTICS_CI` fails because `dim_client` post-hook references `ANALYTICS_DEV.CORE.MP_MASK_STRING_PII`.
- **Fix:** Gate the post-hook on target: `{% set apply_masking = target.database == 'ANALYTICS_DEV' %}`. CI skips the masking step; masking remains a property of real environments.

### `ACCOUNTADMIN` can SELECT but Cortex/Streamlit validator reports "not authorized"
- **Symptom:** From a Python connector with `role=ACCOUNTADMIN`, `SELECT * FROM MARTS.X` works. From Streamlit (owned by ACCOUNTADMIN), the same query fails with insufficient-privileges.
- **Root cause:** Python sessions have `USE SECONDARY ROLES ALL` active by default, pulling in your user's other roles. Streamlit apps in Snowflake run under the *primary* owner role only. ACCOUNTADMIN doesn't inherit MARTS access from its role chain — it has DB ownership but not direct SELECT.
- **Fix:** Grant the relevant access role directly to ACCOUNTADMIN: `GRANT ROLE AR_ANALYTICS_DEV_MARTS_RO TO ROLE ACCOUNTADMIN`. Codify this in Terraform — don't rely on what Python sessions can do.

---

## dbt setup and behaviour

### `pip install dbt-snowflake` lands outside the Anaconda path on Windows
- **Symptom:** `dbt` command not found after install. `Scripts/` directory may be under `%APPDATA%\Python\Python312\Scripts\` rather than Anaconda's.
- **Fix:** Always invoke via the full path you find with `pip show dbt-core | grep Location`. On this machine: `C:\Users\<user>\AppData\Roaming\Python\Python312\Scripts\dbt.exe`.
- **Replication tip:** Pin paths in scripts and CI to avoid ambiguity. Reserve Anaconda for Python scripts and let the user-site `dbt.exe` handle dbt.

### `generate_schema_name` produces `STAGING_staging` by default
- **Symptom:** dbt writes into `ANALYTICS_DEV.STAGING_STAGING` (concatenation of profile schema + model's `+schema`).
- **Fix:** Override `generate_schema_name` macro to use only the custom schema name (uppercased). The override also supports an env-var-driven prefix for CI per-PR isolation.

### Deprecation warnings for `tests:` vs `data_tests:`
- **Symptom:** `PropertyMovedToConfigDeprecation` warnings flood the build log.
- **Fix:** Use `data_tests:` (plural, new key) and wrap severity under `config:`. See example in `dbt/models/staging/main_book/_main_book__models.yml`.

### `~` regex operator fails in Snowflake
- **Symptom:** Postgres-style `column ~ 'regex'` throws `unexpected '~'`.
- **Fix:** Use `REGEXP_LIKE(column, 'regex')` — Snowflake's syntax.

---

## Data quality patterns

### Surrogate-key collisions from nullable natural-key columns
- **Symptom:** `fct_valuations` uniqueness test failed with ~7,200 duplicate SKs. Source has ~8–16% nulls in grain columns (`policy_number`, `valuation_date`).
- **Fix:** Add a `ROW_NUMBER()` disambiguator partitioned on the grain, plus a `has_complete_grain` boolean flag so downstream can filter if desired. Pattern reused in `fct_transactions`.

### Source `not_null` tests fail on intentional synthetic nulls
- **Symptom:** Early dbt builds showed ~8% null violations on staging `not_null` tests.
- **Fix:** Lower severity to `warn` for source tests where business-value missingness is expected. Keep `error` severity for surrogate-key uniqueness and for columns where null means broken pipeline.

### Duplicate schema prefix in RBAC module composition
- **Symptom:** Access roles generated as `AR_ANALYTICS_DEV_RAW_RAW_MAIN_BOOK_RO` (double `RAW_`).
- **Root cause:** Schema names already include `RAW_` prefix; composition lower-cased and prefixed again.
- **Fix:** Use `lower(name)` directly (no extra prefix) when building the schema key map into the RBAC module.

---

## GitHub Actions CI

### `actions/setup-python@v5` with `cache: pip` needs a requirements file
- **Symptom:** Workflow fails: `No file in <path> matched to [**/requirements.txt or **/pyproject.toml]`.
- **Fix:** Add a `dbt/requirements.txt` (pins dbt version) and set `cache-dependency-path: dbt/requirements.txt`.

### Default `GITHUB_TOKEN` can't read another workflow's artifacts
- **Symptom:** `dawidd6/action-download-artifact` fails with `Resource not accessible by integration` when trying to read `dbt_main.yml`'s prod-manifest from a PR workflow.
- **Fix:** Add `permissions: { actions: read, contents: read }` at the job/workflow level.

### Downloaded artifact at wrong path for working-directory steps
- **Symptom:** Artifact downloads to `<repo-root>/prod_manifest/` but subsequent steps use `working-directory: dbt`, so they look in `dbt/prod_manifest/`.
- **Fix:** Set the action's `path: dbt/prod_manifest/` explicitly.

### Branch protection requires repository to be public OR GitHub Pro
- **Symptom:** `gh api ... /branches/master/protection` returns 403: "Upgrade to GitHub Pro or make this repository public to enable this feature".
- **Fix (portfolio):** Make the repo public. Do a history sweep for secrets first:
  ```
  git log --all -p | grep -iE "BEGIN.*PRIVATE KEY|BEGIN RSA PRIVATE"
  git log --all -p | grep -iE "password *= *[\"'][^\"']{4,}"
  ```

### Path-filtered required checks block merges
- **Symptom:** PR touches only `terraform/**` or `docs/**`. Required `dbt CI` check never fires; branch protection reports "missing required check"; merge blocked.
- **Fix:** Drop the `paths:` filter from the workflow that's listed as a required check. It costs a short run per PR; branch protection works as intended.

### Stale scaffolded workflows
- **Symptom:** Pre-existing `dbt.yml` and `terraform.yml` from project scaffolding had wrong auth (passwords) and broken configs, silently failing on PRs.
- **Fix:** Delete `dbt.yml` (our `dbt_ci.yml` replaces it). Convert `terraform.yml` to `terraform fmt -check -recursive` + `terraform validate` under `init -backend=false` (no credentials needed).

### `terraform fmt -check` exit 3 on CI
- **Symptom:** Exit code 3 means formatting issues exist.
- **Fix:** Run `terraform fmt -recursive terraform/` locally before pushing; CI will pass.

### `resource_monitor start_timestamp` rejected as "already passed"
- **Symptom:** Apply fails with `The specified Start time has already passed` — Snowflake account clock is on the account's region timezone (e.g. US east), which may be hours ahead of where you submit from.
- **Fix:** Use a date clearly in the future. `start_timestamp = "2026-05-01 00:00"` worked; anything "today" at a local time that's UTC-ahead may fail.

### Resource monitor `frequency` requires `start_timestamp`
- **Symptom:** `"frequency": all of `frequency,start_timestamp` must be specified`.
- **Fix:** Always pair the two in the module variable.

---

## Streamlit in Snowflake

### Streamlit owner role needs data access directly
- **Symptom:** `SnowparkSQLException: Insufficient privileges to operate on table ...` when clicking through the app.
- **Root cause:** Streamlit apps run as the *owner* role, not the caller. Owner here is `ACCOUNTADMIN`, which doesn't have direct SELECT on MARTS tables.
- **Fix:** Grant the relevant access role to `ACCOUNTADMIN`:
  ```
  GRANT ROLE AR_ANALYTICS_DEV_MARTS_RO TO ROLE ACCOUNTADMIN
  ```
  Codify in Terraform via `snowflake_execute`. Reverting this during debugging was a mistake that re-broke the app.

### No `ALTER STREAMLIT ... SET EXECUTE_AS = 'CALLER'`
- **Symptom:** `invalid property 'EXECUTE_AS'` when trying to switch the app to caller's rights.
- **Root cause:** Snowflake hasn't released this for Streamlit objects yet.
- **Fix:** Live with owner-rights behaviour. Grant the owner the access roles it needs (see above).

### Uploading files to the stage
- **Pattern:** `scripts/upload_streamlit_app.py` uses `PUT file://... @DB.SCHEMA.STAGE OVERWRITE=TRUE AUTO_COMPRESS=FALSE`. `AUTO_COMPRESS=FALSE` is important — gzipped YAML or Python isn't readable by Cortex or by the Streamlit runtime.
- **Note:** Terraform creates the stage but Snowflake provider does not upload files. Out-of-band PUT is expected.

### Streamlit app expects environment.yml in app directory
- Python dependencies beyond the defaults go in `streamlit/app/environment.yml` with `channels: [snowflake]`. Anything outside the Snowflake channel is not permitted by the managed runtime.

---

## Cortex Analyst regional block

### "Cortex Analyst is not enabled"
- **Symptom:** First Cortex Analyst API call returns 400: `Cortex Analyst is not enabled`.
- **Fix:** `ALTER ACCOUNT SET ENABLE_CORTEX_ANALYST = TRUE` (ACCOUNTADMIN-only). Codified in Terraform via `snowflake_execute`.

### "Tables do not exist or are not authorized"
- **Symptom:** After enabling, Cortex Analyst returns 404: `The following tables in the semantic model do not exist or are not authorized`.
- **Root cause:** The caller role (app owner = ACCOUNTADMIN) must have direct SELECT on every table referenced in the semantic model, and `SNOWFLAKE.CORTEX_USER` database role.
- **Fix:** Grant `SNOWFLAKE.CORTEX_USER` to ACCOUNTADMIN (already granted to FR_ENGINEER/FR_ANALYST) **and** grant the MARTS access role to ACCOUNTADMIN so the validator's strict grant check finds SELECT.

### Error 503 / error_code 392704 after that → region unsupported
- **Symptom:** `SNOWFLAKE.CORTEX.COMPLETE` also fails with a 500 external-function error. Account is in `AZURE_EASTUS`.
- **Root cause:** Cortex Analyst is not available in `AZURE_EASTUS`. It is available in `AZURE_EASTUS2` (distinct region) and several AWS/GCP regions. **Cortex Analyst does not support cross-region inference** (unlike LLM functions, which do).
- **Fix:** Documented the block in ADR-0011. Pivoted to a Streamlit-only version of the app with a SQL playground and pre-built domain tabs. Kept all Cortex scaffolding (semantic model YAML, grants, account flag) for the day the region supports it — re-enabling is a one-file swap in `streamlit_app.py`.

---

## Cleanup hygiene

### `tfplan*.binary` files
- Always add `tfplan*` and `*.tfplan` to `.gitignore`. Plan artefacts can contain secrets in plaintext.

### Legacy schemas left behind during migration
- `ANALYTICS_CI` accumulated `STAGING`/`CORE`/`MARTS` schemas from a pre-`PR_<n>_*` prefixing PR. Teardown workflow only matches `PR_<n>_*`. Drop manually:
  ```
  DROP SCHEMA IF EXISTS ANALYTICS_CI.<X> CASCADE;
  ```

### Manual Azure containers left after adopting IaC
- `fsp-company-01/02/03` containers were created manually before Terraform owned container management. Deleted via `az storage container delete` once they were empty. `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`, and `fsp-data-onboarding-queue` are Terraform-managed going forward.

---

## Things we kept as known limitations (not fixed)

- `_LOADED_AT` NULL on COPY INTO (ADR-0010).
- No dead-letter queue for Event Grid delivery failures.
- No Snowflake alerting on pipe errors; `SYSTEM$PIPE_STATUS` polled manually.
- Shared CI schemas in `ANALYTICS_CI` (not per-PR). Fine at team size ≤ 5.
- Semantic model kept in sync with marts manually.
- Cortex Analyst availability in `AZURE_EASTUS`.
