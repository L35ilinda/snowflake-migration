# Claude Code instructions

This is a personal Snowflake migration project, built to enterprise standards.
Read this entire file before suggesting changes or running commands.

## Operating rules for Claude Code

- **Plan before acting.** For any non-trivial change, show the plan first, get confirmation, then execute step by step.
- **Never run destructive SQL** (`DROP`, `TRUNCATE`, `DELETE` without `WHERE`) without explicit confirmation in the same session.
- **Never commit secrets.** Use `.env` (gitignored) and reference via env vars. If you see a credential in a file you're about to commit, stop.
- **Terraform changes:** always show `terraform plan` output before `apply`. Never `apply` without explicit user approval.
- **dbt changes:** run `dbt build --select <model>+` to test downstream impact before merging.
- **Prefer editing existing files** over creating new ones. Match the existing structure.
- **Match naming conventions** defined in section 5. Don't invent new ones.
- **Update this file** (sections 4 and 6) when state changes meaningfully.
- **Commit after every working step.** Small commits, descriptive messages.
- **If unsure, ask.** Don't guess at Azure resource names, Snowflake object names, or business logic.

---

## 1. Project goal

Migrate a legacy on-premise BI architecture to a modern, Snowflake-native stack on Azure.

**Legacy stack being replaced:** SQL Server data warehouse + SSIS + SSAS Tabular + SSRS + Power BI, fed by SFTP/IBM Connect:Direct/Ab Initio scheduled ETL and a SQL Server virtualization layer over operational systems.

This is a personal portfolio project but built to enterprise standards. It deliberately exercises the skills required for a Snowflake Solution Architect role:

- Snowflake Core (Snowpipe, clustering, micro-partitions, data sharing)
- dbt + Dynamic Tables for transformation
- Star Schema + Data Vault 2.0 modeling (one domain in each)
- Terraform IaC + GitHub Actions CI/CD
- Snowflake Horizon (RBAC, masking, row access policies)
- FinOps (resource monitors, warehouse sizing, auto-suspend tuning)
- Cortex (Analyst, Document AI) for the GenAI angle — Analyst currently blocked by account region, see ADR-0011
- One Airflow DAG (skill demonstration, not core orchestration)
- **Multi-tenant patterns** (three "companies" with non-standardized data feeds)

## 2. Target architecture

```text
Sources (3 "company" SFTP feeds -> Azure containers, Azure Postgres Flexible Server (mock ops, Flyway-managed), external APIs)
   |
   v
Ingestion (Snowpipe per company for files; Airbyte self-hosted for Postgres replication; Iceberg for cold data)
   |
   v
Snowflake schemas: RAW_<COMPANY_NAME> -> STAGING -> CORE -> MARTS  (dbt + Dynamic Tables)
   |
   v
AI/ML layer (Cortex Analyst, Document AI, Snowpark UDFs)
   |
   v
Serving (Streamlit in Snowflake, Snowsight, Power BI)

Cross-cutting (all layers): Terraform, GitHub Actions, Horizon RBAC/masking,
resource monitors, Airflow
```

### Component mapping (legacy -> target)

| Legacy | Target |
|---|---|
| SFTP + IBM Connect:Direct + Landing Zone | Azure Storage container per company + Snowflake external stages |
| Ab Initio (scheduled ETL) | Snowpipe (ingest) + dbt (transform) |
| SSIS | dbt models + Dynamic Tables |
| Virtualization layer (views, process-on-read) | Airbyte replication (Azure Postgres → Snowflake); Iceberg/External Tables for cold data |
| Data Warehouse (SQL Server) | Snowflake `CORE` + `MARTS` schemas |
| SSAS Tabular | Power BI semantic model (or Snowflake Semantic Views) |
| SSRS Report Server + subscriptions | Power BI Paginated Reports + subscriptions |
| Power BI Dashboards | Power BI on Snowflake + Streamlit + Snowsight |
| Excel reports for business users | Power BI subscriptions + Analyze in Excel |
| Email/manual fetch paths | Same Azure Storage drop pattern -> Snowpipe |

## 3. Environment

### Cloud
- **Cloud provider:** Azure
- **Subscription ID:** `60abe083-7f78-4a57-9f4f-ca0214215c77`
- **Tenant ID:** `bc5006a1-0712-4769-a24f-3cc61c360e7e`
- **Resource group:** `snflk_training_rg`
- **Storage region:** `southafricanorth`
- **Snowflake region:** `AZURE_EASTUS`
- **Cross-region setup:** Azure Storage is in South Africa North while Snowflake is in Azure East US. Egress costs and latency apply. Acceptable for portfolio scale, but call it out in the writeup.

### Azure Storage
- **Storage account:** `fspsftpsource`
- **Containers (Terraform-managed, descriptive naming):**
  - `fsp-main-book` — 6 CSVs (main_book_* files)
  - `fsp-indigo-insurance` — 6 CSVs (indigo_* files)
  - `fsp-horizon-assurance` — 6 CSVs (horizon_* files)
  - `fsp-data-onboarding-queue` — 60 files awaiting onboarding (other company groups + shared/reference tables)
  - `tfstate` — Terraform remote state (bootstrap-managed)
- **Path convention:** `fsp-<company-name>/<filename>.csv` (flat, no subdirectories)
- **Legacy containers (`fsp-company-01/02/03`):** deleted — replaced by descriptive names above
- **Auth to Snowflake:** shared storage integration `SI_AZURE_FSPSFTPSOURCE_DEV` is live and Azure-consented

### Azure Database for PostgreSQL (mock operational DB)
- **Service:** Azure Database for PostgreSQL — Flexible Server (managed PaaS, not a VM)
- **Purpose:** Simulates internal source systems (CRM, operational databases) that Airbyte replicates into Snowflake `RAW_OPS`
- **Status:** not yet provisioned — Terraform module TBD, schema design TBD
- **Planned Terraform module:** `terraform/modules/azure_postgres_flexible_server/`
- **Schema management:** Flyway (versioned SQL migrations), not dbt — dbt owns transformation, Flyway owns DDL/schema evolution
- **Estimated cost:** ~R80–200/day depending on compute tier (B1s burstable at lower end, GP_Standard_D2s at upper end); auto-shutdown during off-hours recommended
- **Region decision pending:** co-locate with Snowflake in East US (lower Airbyte replication latency) vs. South Africa North (closer to developer, but cross-region egress to Snowflake)

### Snowflake
- **Edition:** Enterprise
- **Cloud / region:** Azure / East US (`AZURE_EASTUS`)
- **Account locator:** `BO46193`
- **Org-account identifier:** `VNCENFN-XF07416`
- **Default user:** `LSILINDA`
- **Auth method:** key-pair for programmatic clients (`SNOWFLAKE_JWT`); interactive Snowsight still uses browser login and MFA
- **Roles on LSILINDA:** `ACCOUNTADMIN` (for Terraform and account-level ops), `FR_ENGINEER` (day-to-day dbt/SQL work), `FR_ANALYST` (for testing analyst-facing artefacts like masking policies)
- **Databases:** `ANALYTICS_DEV` (project, Terraform-managed, live), `ANALYTICS_CI` (CI builds, Terraform-managed)
- **Legacy sandbox database:** `FSP_DATA_INTEGRATION_DB` (keep isolated from project objects)
- **Workload warehouses:** `LOAD_WH` (Snowpipe — though pipes use Snowflake-managed compute), `TRANSFORM_WH` (dbt), `BI_WH` (Streamlit + ad-hoc). Default `COMPUTE_WH` retained but not used by the pipeline.

### Tooling
- **Git repo:** public at `https://github.com/L35ilinda/snowflake-migration`; tag `v0.1.0-foundations`; trunk-based with branch protection on `master`
- **dbt:** dbt Core (Core over Cloud for IaC control and lower cost); local CLI at `C:\Users\Lonwabo_Eric\AppData\Roaming\Python\Python312\Scripts\dbt.exe`
- **Terraform:** installed locally (`1.14.8`); remote state in `fspsftpsource/tfstate/environments/dev/terraform.tfstate`
- **Azure CLI:** installed locally and authenticated to the project subscription
- **GitHub Actions CI:** 3 workflows live — `dbt_ci.yml` (PR, slim + per-PR schemas against `ANALYTICS_CI`), `dbt_main.yml` (merge, deploy to `ANALYTICS_DEV` + publish prod manifest), `dbt_ci_teardown.yml` (PR close, drops `PR_<n>_*` schemas), `terraform.yml` (PR, `fmt -check` + `validate` no creds). See ADR-0009.
- **CI service user:** `CI_SVC` with dedicated RSA key pair; 6 GitHub repo secrets set (`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_PRIVATE_KEY` base64)
- **IDE:** VS Code with Claude Code extension
- **Python runtime:** Anaconda (`C:\ProgramData\anaconda3`). Use this for pip, dbt, snowflake-connector, and all Python tooling.
- **OS / shell:** Windows 11 with PowerShell + Bash
- **Flyway:** for Postgres schema management (versioned SQL migrations under `flyway/sql/`). Not yet installed — will be set up when mock ops schema design is finalized. Flyway manages Postgres DDL only; Snowflake DDL is owned by dbt (transformation objects) and Terraform (infrastructure objects).

## 4. Current state - what's been done

### Done
- [x] Azure subscription, resource group, storage account created
- [x] 70+ synthetic CSV files generated
- [x] Snowflake Enterprise account provisioned (Azure East US)
- [x] Project directory scaffolded (Terraform, dbt, Snowpipe, Streamlit, Airflow, GitHub Actions structure)
- [x] Terraform v1.14.8 installed locally; Azure CLI installed and authenticated
- [x] `.env` populated with Azure config plus Snowflake key-pair settings
- [x] README, ADR, and session-log structure created; ADR-0001 through ADR-0006 written
- [x] Terraform bootstrap applied; remote state backend live in `fspsftpsource/tfstate/`
- [x] Snowflake provider migrated to `snowflakedb/snowflake`; key-pair auth (`SNOWFLAKE_JWT`) configured
- [x] RSA key pair generated outside the repo; public key registered on `LSILINDA`
- [x] Shared storage integration `SI_AZURE_FSPSFTPSOURCE_DEV` applied, admin-consented, verified
- [x] `azure_blob_containers` module built — manages containers in existing storage account via `for_each`
- [x] Adopted descriptive container naming: `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`, `fsp-data-onboarding-queue`
- [x] Deleted legacy generic containers (`fsp-company-01/02/03`)
- [x] `snowflake_database_layers` module built and applied — `ANALYTICS_DEV` with 6 schemas live
- [x] `snowflake_company_ingest` module built and applied — uses descriptive `company_name` for Snowflake object naming
- [x] All stages and file formats live with descriptive names (`STG_MAIN_BOOK`, `FF_CSV_MAIN_BOOK`, etc.)
- [x] Files distributed: 6 CSVs each in `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`; 60 files in onboarding queue
- [x] Verified end-to-end: `LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_MAIN_BOOK;` returns 6 CSVs
- [x] `scripts/list_stage.py` added for programmatic stage verification

- [x] `snowflake_rbac` module built and applied — 12 access roles (RW+RO per schema), 2 functional roles (`FR_ENGINEER`, `FR_ANALYST`), `LSILINDA` granted `FR_ENGINEER` (retains `ACCOUNTADMIN`)
- [x] `snowflake_warehouses` module built and applied — `LOAD_WH`, `TRANSFORM_WH`, `BI_WH` (all XS, auto-suspend 60s, start suspended)
- [x] Resource monitors: per-warehouse (`RM_LOAD_WH` 5cr, `RM_TRANSFORM_WH` 3cr, `RM_BI_WH` 2cr) + account backstop (`RM_DEV_ACCOUNT` 10cr)
- [x] `snowflake_snowpipe` module built and applied — 6 all-VARCHAR landing tables + 6 Snowpipes for Main Book
- [x] All 6 Main Book pipes refreshed, 600K rows loaded across 6 tables in `RAW_MAIN_BOOK`
- [x] dbt-snowflake installed (Anaconda), `profiles.yml` with key-pair auth, `FR_ENGINEER` role, `TRANSFORM_WH`
- [x] `dbt debug` — all checks passed
- [x] 6 dbt staging models (views) in `ANALYTICS_DEV.STAGING` — type casting, PascalCase rename, source + model tests
- [x] `generate_schema_name` macro — writes to `STAGING`/`CORE`/`MARTS` directly; also supports optional `DBT_SCHEMA_PREFIX` env var for per-PR CI isolation
- [x] Tagged `v0.1.0-foundations`
- [x] Snowpipes for Indigo Insurance and Horizon Assurance — 12 more landing tables + 12 pipes, all loaded (1.8M rows total across `RAW_*`)
- [x] 12 additional dbt staging views (6 per company for Indigo + Horizon); 18 staging views total
- [x] Full CORE layer (Star Schema): `dim_advisor`, `dim_product`, `dim_fund`, `dim_date`, `dim_client`, `dim_policy`, `fct_commissions`, `fct_valuations`, `fct_transactions`, `fct_policies`. `dim_policy` materialised Type 1 but with Type 2-ready columns (`is_current`, `valid_from`, `valid_to`)
- [x] First MARTS models: `finance_advisor_commissions_monthly`, `portfolio_aum_monthly`, `risk_policy_inforce`
- [x] PII masking policies via `snowflake_masking_policies` module: `MP_MASK_STRING_PII` + `MP_MASK_DATE_PII`, attached to `dim_client` via dbt post-hook (gated on `target.database == 'ANALYTICS_DEV'`)
- [x] Snowpipe auto-ingest via Azure Event Grid (ADR-0010) — notification integration, storage queue, system topic + subscription, all 18 pipes now `AUTO_INGEST = TRUE`. Verified 41-second file-to-row latency end-to-end.
- [x] SFTP disabled on storage account (ADR-0007) for cost + security
- [x] GitHub Actions CI (ADR-0009) — dedicated `ANALYTICS_CI` database, `CI_SVC` service user, slim CI with `state:modified+ --defer`, per-PR schema isolation via `DBT_SCHEMA_PREFIX`, auto-teardown on PR close
- [x] Branch protection on `master` — `dbt CI` required, force-push + deletions blocked
- [x] Streamlit in Snowflake app `FSP_ANALYST` live with 4 tabs (Finance / Portfolio / Risk / SQL Playground); semantic model YAML on stage ready for Cortex Analyst
- [x] Cortex Analyst deferred by region (ADR-0011) — all scaffolding in place; `AZURE_EASTUS` not supported, would light up with a one-file swap if the region becomes supported
- [x] Consolidated replication guide written: [docs/log/issues-and-fixes.md](docs/log/issues-and-fixes.md)
- [x] `_LOADED_AT` NULL fixed (ADR-0010 known limitation closed) — pipes now use a transformed COPY (`SELECT $1, ..., $N, CURRENT_TIMESTAMP()`); 18 pipes replaced; existing 1.8M rows backfilled
- [x] Snowpipe quarantine module live (ADR-0012) — `RAW_QUARANTINE.PIPE_ERRORS` table + `TSK_CAPTURE_PIPE_ERRORS` task on `LOAD_WH` (every 5 min) using `VALIDATE_PIPE_LOAD()` over all 18 pipes
- [x] Mock operational DB scaffolded (ADR-0013) — Postgres 16 docker-compose + 13K-row seed in `mock_ops_db/`; Snowflake side live: `RAW_OPS` schema, `AIRBYTE_SVC` user (key-pair), `FR_AIRBYTE` role. Implementation deferred to v1.1.0 per ADR-0014 (Airbyte + Azure Postgres Flexible Server + Flyway). Snowflake scaffolding stays in place; Docker compose retained as reference for v1.1.0 Flyway schema design.
- [x] **Replicate Sources declared done at 3-tenant scope** (ADR-0014). Project scope locked to Main Book + Indigo Insurance + Horizon Assurance for the entire v0.x → v1.0.0 arc. Airbyte and the 8 queue tenants (baobab, fynbos, karoo, khoisan, protea, springbok, summit, ubuntu) move to v1.1.0 / manual practice.
- [x] **Type 2 `dim_policy` via dbt snapshot** (ADR-0015) — `snp_dim_policy` (check strategy on a curated attribute set) + `dim_policy_history` view exposing `valid_from` / `valid_to` / `is_current`. Existing `dim_policy.sql` (Type 1) untouched so facts continue joining to current state.
- [x] **Data Vault 2.0 on transactions** (ADR-0015) — 4 hubs (transaction, policy, client, fund) + 3 links (txn-policy, txn-client, txn-fund) + 2 satellites split by churn rate (`sat_transaction_details`, `sat_transaction_amounts`). All `incremental` insert-only with hashdiff guard on sats; coexists with the star schema. Source = `fct_transactions`. `dbt build` PASS=72 WARN=0 ERROR=0. Tagged `v0.2.0-model-the-warehouse` (PRs #9 + #11; PR #10 auto-closed by stacked-base deletion — see ADR-0016).
- [x] **Stacked-PR merge convention documented** (ADR-0016) — retarget downstream PR base to `master` *before* deleting the upstream branch. Cross-referenced in [issues-and-fixes.md](docs/log/issues-and-fixes.md) under "GitHub workflow."
- [x] **Power BI v0.3.0 scaffold** (ADR-0017 + 2026-04-22 addendum) — repo scaffold under [power_bi/](power_bi/): README + 3-step walkthrough (connect / semantic model / paginated report). DirectQuery for the semantic model, Import for the paginated report. **Publish to Power BI Service scoped out** — `.pbix` + `.rdl` + screenshots in repo are the portfolio deliverable. `PBI_SVC` Snowflake user destroyed; `LSILINDA` OAuth is the only Power BI connection identity. .pbix and .rdl pending GUI build.

### Done (Model the warehouse — `v0.2.0-model-the-warehouse` TAGGED 2026-04-22)
- [x] `dbt snapshot` for `dim_policy` + `dim_policy_history` view (ADR-0015)
- [x] Build Data Vault 2.0 on transactions (4 hubs + 3 links + 2 sats) (ADR-0015)
- [x] Tag `v0.2.0-model-the-warehouse` at merge commit `f5d9d40`

### Pending (Serve — v0.3.0)
- [x] ADR-0017 (Power BI on Snowflake — semantic model location, connection mode, auth) + 2026-04-22 addendum (publish skipped)
- [x] Snowflake side: nothing to provision — `LSILINDA` + `FR_ANALYST` + `BI_WH` already in place. `PBI_SVC` provisioned then destroyed when publish was scoped out.
- [x] Repo scaffold: [power_bi/](power_bi/) with README + 3 walkthroughs (connect / semantic model / paginated report)
- [ ] Build `fsp_marts.pbix` (Power BI Desktop, DirectQuery) — GUI work, follow walkthroughs
- [ ] Build `fsp_advisor_commissions.rdl` (Power BI Report Builder, Import) — GUI work
- [ ] Capture screenshots into `power_bi/screenshots/`
- [ ] Tag `v0.3.0-serve`

### Pending (Govern — v0.4.0)
- [ ] Row access policies for multi-tenant isolation on CORE/MARTS
- [ ] Tighter `FR_CI` role scoped down from `FR_ENGINEER`
- [ ] Snowflake Alert on `RAW_QUARANTINE.PIPE_ERRORS` row-count delta (closes ADR-0012 loop)
- [ ] Event Grid DLQ for delivery failures (closes ADR-0010 loop)
- [ ] Tag `v0.4.0-govern`

### Pending (Orchestrate + AI — v0.5.0)
- [ ] One Airflow DAG (skill demo — local Docker is fine)
- [ ] Cortex Document AI demo (Cortex Analyst still blocked by region — ADR-0011)
- [ ] Tag `v0.5.0-orchestrate-ai`

### Pending (Portfolio writeup — v1.0.0)
- [ ] Portfolio writeup (legacy vs new stack, cost analysis, lessons learned)
- [ ] Top-level README polish for the public repo
- [ ] Tag `v1.0.0`

### Parked (post-v1.0.0)
Per ADR-0014 — deferred to keep the v1.0 path focused on higher-impact work.
- [ ] **v1.1.0 Replicate operational DB:** Azure Postgres Flexible Server + Flyway V1 + Airbyte sync + dbt staging on `RAW_OPS`. Snowflake-side scaffolding (`RAW_OPS` schema, `AIRBYTE_SVC` user, `FR_AIRBYTE` role) is already provisioned and idle. ADRs 0013 + 0014 cover context.
- [ ] **8 queue tenants (baobab, fynbos, karoo, khoisan, protea, springbok, summit, ubuntu):** parked for **manual practice** — user wants to onboard these by hand (Snowpipe + dbt) as a learning exercise. Files stay in `fsp-data-onboarding-queue/Outbound/`. New pipe FQNs added by that practice must be appended to `module.quarantine.pipe_fully_qualified_names`.
- [ ] **15 shared/reference files:** placement decision (shared `RAW_SHARED` vs per-tenant duplication) deferred until manual practice surfaces a concrete need.

### Snowflake current state
- **Databases:** `ANALYTICS_DEV` (project, Terraform-managed), `ANALYTICS_CI` (GitHub Actions CI builds, Terraform-managed), `FSP_DATA_INTEGRATION_DB` (legacy sandbox, ignore), system databases
- **Schemas in `ANALYTICS_DEV`:** `RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, `RAW_HORIZON_ASSURANCE`, `RAW_QUARANTINE`, `RAW_OPS`, `STAGING`, `CORE`, `MARTS`, `SEMANTIC`
- **RAW tables:** 18 landing tables (all-VARCHAR, 100K rows each, 1.8M total) — 6 per tenant (`<company>_ins_commissions`, `<company>_inv_commissions`, `<company>_insurance`|`assurance`|`risk_benefits`, `<company>_ins_transactions`|`risk_benefits_transactions`, `<company>_transactions`|`valuation_transactions`, `<company>_valuations`)
- **STAGING views:** 18 dbt-managed (`stg_main_book__*`, `stg_indigo_insurance__*`, `stg_horizon_assurance__*`) — type casting + PascalCase rename
- **CORE tables (Star Schema):** 6 dims (`dim_advisor`, `dim_product`, `dim_fund`, `dim_date`, `dim_client` with PII masking, `dim_policy` Type 1 current state); 4 facts (`fct_commissions`, `fct_valuations`, `fct_transactions`, `fct_policies`); + `dim_policy_history` view (Type 2 over `snp_dim_policy` snapshot)
- **CORE tables (Data Vault 2.0 — transactions domain):** 4 hubs (`hub_transaction`, `hub_policy`, `hub_client`, `hub_fund`), 3 links (`lnk_transaction_policy`, `lnk_transaction_client`, `lnk_transaction_fund`), 2 satellites (`sat_transaction_details`, `sat_transaction_amounts`). All in `dbt/models/core/vault/`. Insert-only incremental; hashdiff-guarded sats. See ADR-0015.
- **Snapshot:** `snp_dim_policy` in CORE — `check` strategy on a curated attribute set. Targeted via `target_database = target.database` + DBT_SCHEMA_PREFIX-aware schema in `dbt_project.yml`.
- **MARTS tables:** 3 — `finance_advisor_commissions_monthly`, `portfolio_aum_monthly`, `risk_policy_inforce`
- **SEMANTIC schema:** internal stage `MODELS` (Cortex semantic model YAML + Streamlit source); Streamlit app `FSP_ANALYST`
- **Warehouses:** `COMPUTE_WH` (default, XS, 300s), `LOAD_WH` (XS, 60s), `TRANSFORM_WH` (XS, 60s), `BI_WH` (XS, 60s)
- **Resource monitors:** `RM_DEV_ACCOUNT` (10cr backstop), `RM_LOAD_WH` (5cr), `RM_TRANSFORM_WH` (3cr), `RM_BI_WH` (2cr)
- **Roles:** `FR_ENGINEER` (all RW incl. `RAW_QUARANTINE`, `RAW_OPS`), `FR_ANALYST` (staging/core/marts RO + `RAW_QUARANTINE` RO for data-quality visibility), `FR_AIRBYTE` (`RAW_OPS` RW only — Airbyte destination), 16 access roles (`AR_ANALYTICS_DEV_<SCHEMA>_RW/RO`), `CI_SVC` service user with `FR_ENGINEER`, `AIRBYTE_SVC` service user with `FR_AIRBYTE`. `ACCOUNTADMIN` holds `AR_ANALYTICS_DEV_MARTS_RO` so the Streamlit app (owner = ACCOUNTADMIN) can query MARTS. `SNOWFLAKE.CORTEX_USER` granted to FR_ENGINEER, FR_ANALYST, ACCOUNTADMIN.
- **Storage integration:** `SI_AZURE_FSPSFTPSOURCE_DEV` (covers `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`)
- **Notification integration:** `NI_AZURE_FSPSFTPSOURCE_DEV` wired to Event Grid → Storage Queue `snowpipe-events` for auto-ingest (ADR-0010)
- **Stages:** `STG_MAIN_BOOK`, `STG_INDIGO_INSURANCE`, `STG_HORIZON_ASSURANCE` (external, per-tenant); `SEMANTIC.MODELS` (internal)
- **Pipes:** 18 total (6 per tenant), all `AUTO_INGEST = TRUE` + notification integration. COPY is transformed (`SELECT $1, ..., $N, CURRENT_TIMESTAMP()`) so `_LOADED_AT` is populated on every load. `ON_ERROR = CONTINUE` rejects are captured by the quarantine task.
- **Quarantine:** `RAW_QUARANTINE.PIPE_ERRORS` (shared across all 18 pipes) populated by `TSK_CAPTURE_PIPE_ERRORS` (every 5 min on `LOAD_WH`) via `VALIDATE_PIPE_LOAD()`. See ADR-0012.
- **File formats:** `FF_CSV_MAIN_BOOK`, `FF_CSV_INDIGO_INSURANCE`, `FF_CSV_HORIZON_ASSURANCE`
- **Masking policies:** `MP_MASK_STRING_PII`, `MP_MASK_DATE_PII` in `CORE`; applied to `dim_client` via dbt post-hook when `target.database == 'ANALYTICS_DEV'`
- **Account parameters:** `ENABLE_CORTEX_ANALYST = TRUE` (set; blocked by region per ADR-0011)
- **Terraform-managed state:** storage integration, 2 databases, 9 schemas, 3 external stages + 1 internal stage, 3 file formats, 19 tables (18 landing + 1 quarantine), 18 pipes, 1 task, 19 roles, 3 warehouses, 4 resource monitors, 4 Azure containers, 1 Azure storage queue, 1 Event Grid system topic + subscription, 1 Snowflake notification integration, 2 masking policies, 1 Streamlit app, `CI_SVC` + `AIRBYTE_SVC` users

### Source data shape
- **Total files:** ~80 CSVs across all containers + onboarding queue
- **Onboarded (18 files):** `main_book_*` (6), `indigo_*` (6), `horizon_*` (6) — in respective company containers at root level
- **Awaiting onboarding (60 files):** in `fsp-data-onboarding-queue/Outbound/`
  - 8 company groups: baobab (6), fynbos (6), karoo (6), khoisan (6), protea (6), springbok (6), summit (6), ubuntu (6) = 48 files
  - Shared/reference tables (10): `_client_pool`, `accounts`, `advisor_company_codes`, `advisor_pool`, `branches`, `cards`, `customers`, `loans`, `product_pool`, `transactions`
  - Other (4): `data_dictionary`, `risk_benefits`, `risk_benefits_transactions`, `policy_valuations`, `policy_valuations_transactions`
  - Non-data (2): `MOCK_DATA.csv`, `README.md`
- **Naming pattern (intentionally non-standard, mimicking heterogeneous suppliers):**
  - `<companyname>_inv_<datasettype>.csv`
  - `<companyname>_ins_<datasettype>.csv`
  - `<companyname>_<datasettype>.csv`
- **Format:** CSV, comma-delimited, all have headers, files at container root (no subdirectories)
- **Quirks (intentional):** PII columns, empty cells/nulls, non-standardized naming across companies

## 5. Conventions and standards

### Naming
- **Snowflake databases:** UPPERCASE, environment-suffixed: `ANALYTICS_DEV`, `ANALYTICS_PROD`
- **Schemas:** UPPERCASE: `RAW_<COMPANY_NAME>`, `STAGING`, `CORE`, `MARTS`
- **Tables and columns:** `lower_snake_case`
- **Source tables in RAW:** prefixed with dataset type: `raw_main_book.commission`, `raw_indigo_insurance.insurance`
- **dbt staging models:** `stg_<company_name>__<dataset_type>.sql` (e.g. `stg_main_book__valuations.sql`)
- **dbt core models:** `dim_<entity>.sql`, `fct_<process>.sql`, `hub_/lnk_/sat_` for the Vault domain
- **dbt marts:** `<domain>_<purpose>.sql`
- **Warehouses:** `<PURPOSE>_WH` - `LOAD_WH`, `TRANSFORM_WH`, `BI_WH`, `ADHOC_WH`
- **Roles:** functional `FR_<n>` (for example `FR_ANALYST`, `FR_ENGINEER`), access `AR_<DB>_<SCHEMA>_<RW|RO>`
- **Terraform resources:** `snake_case` matching Snowflake object names
- **Azure containers:** `fsp-<company-name>` (descriptive, e.g. `fsp-main-book`, not `fsp-company-01`)
- **Stages:** `STG_<COMPANY_NAME>` (e.g. `STG_MAIN_BOOK`)
- **File formats:** `FF_CSV_<COMPANY_NAME>` (e.g. `FF_CSV_MAIN_BOOK`)
- **Pipes:** `PIPE_<COMPANY_NAME>_<DATASET_TYPE>`

### Architectural rules
- **Schemas as layers:** `RAW_<COMPANY_NAME>` (1:1 source per tenant, append-only) -> `STAGING` (typed, cleaned, renamed, conformed) -> `CORE` (conformed dims and facts) -> `MARTS` (domain-specific, BI-ready)
- **Tenant mapping (initial three):** Azure containers `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance` mapped 1:1 to `RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, `RAW_HORIZON_ASSURANCE`
- **Multi-tenant pattern:** isolate raw per company; conform in STAGING; merge into shared CORE
- **Modeling:** Star Schema is the default in MARTS. One CORE domain should be modeled as Data Vault 2.0 (TBD which)
- **dbt materializations:** staging = view, intermediate = ephemeral, core = table, marts = table or dynamic table where freshness matters
- **RBAC:** functional roles granted to access roles granted to users. Never grant directly to users.
- **Warehouses:** separate per workload. Auto-suspend <= 60s. Right-size by workload, not by user.
- **IaC first:** all Snowflake objects via Terraform. No click-ops in anything that matters.
- **Schema management separation of concerns:** Terraform owns infrastructure DDL (databases, schemas, roles, grants, integrations, warehouses, masking policies). dbt owns transformation DDL (models, views, tables created via `CREATE OR REPLACE`). Flyway owns Postgres operational schema DDL (migrations, seed data, schema evolution). These three tools do not overlap in ownership.
- **Quarantine pattern:** Snowpipe sends rejected rows to a per-company quarantine table; never fail the pipe
- **Filename parsing:** dbt macro to derive `company`, `dataset_type`, and `feed_subtype` (`inv` / `ins` / none) from filename in staging
- **Git:** trunk-based. PRs run `dbt build` against a dev database via GitHub Actions

### Code style
- SQL: lowercase keywords, leading commas, CTEs over subqueries, one column per line in `select`
- Terraform: modules for anything reused, explicit `for_each` over `count`, locked provider versions
- Python: `ruff` for linting and formatting, type hints where they help

## 6. Next milestone

**Model the warehouse — tag `v0.2.0`.** Replicate Sources is declared done at 3-tenant scope (ADR-0014). The remaining warehouse-modeling work is the next vertical.

```text
Existing CORE Star Schema (6 dims + 4 facts, 1.8M rows from 3 tenants)
   |
   v
+ dbt snapshot on dim_policy   (Type 1 -> true Type 2 with valid_from/valid_to)
+ Data Vault 2.0 on transactions  (hubs / links / sats alongside existing star)
```

Concrete steps for the next session:
1. Convert `dim_policy` from Type 1 to Type 2 via `dbt snapshot`. Existing `is_current` / `valid_from` / `valid_to` columns are already in the model — wiring them to a snapshot table is the missing piece.
2. Pick the Data Vault 2.0 domain. Default: **transactions** (most history complexity, cleanest fit for the Vault pattern). Confirm before building.
3. Build `hub_*`, `lnk_*`, `sat_*` models in CORE for the chosen domain. Materialize as tables. Run alongside the existing star schema — no replacement, both coexist for the portfolio narrative.
4. Add dbt tests for the Vault models (uniqueness on hub keys, referential integrity on links).
5. Tag `v0.2.0-model-the-warehouse`.

After v0.2.0:
- **v0.3.0 Serve** — Power BI semantic model on MARTS + paginated reports (SSAS/SSRS replacement story).
- **v0.4.0 Govern** — row access policies, tighter `FR_CI`, Snowflake Alert on quarantine, Event Grid DLQ.
- **v0.5.0 Orchestrate + AI** — Airflow DAG, Cortex Document AI demo.
- **v1.0.0 Portfolio writeup** — legacy vs new stack comparison, cost analysis, lessons learned.
- **v1.1.0 (post-1.0)** — Azure Postgres Flexible Server + Flyway + Airbyte sync into `RAW_OPS`. Plus user's manual practice onboarding the 8 parked queue tenants. See ADR-0014.

## 7. How to interact with me (the user)

- Be opinionated. If I'm about to do something suboptimal, say so directly.
- Default to Snowflake-native solutions over third-party tools.
- Show me the SQL/Terraform/YAML, don't just describe it.
- When there's a tradeoff, name it explicitly (cost, complexity, learning value, time-to-implement).
- Skip basic explanations unless I ask - assume working knowledge of SQL, Python, cloud concepts, dimensional modeling.
- For longer artifacts (DDL scripts, dbt models, Terraform modules), put them in files in the repo, not in chat.
- Reference the architecture in section 2 when proposing changes - call out which layer/component is affected.
- I'm in Johannesburg / South Africa timezone (SAST). Costs matter - flag anything that will burn credits or incur cross-region egress.
- I work in Windows 11 with both PowerShell and Bash available. Default to PowerShell for Azure/Windows-native commands; Bash for Unix-style tooling (dbt, terraform also fine in PowerShell).

## 8. Open questions / decisions pending

### Active (in v0.2 → v1.0 path)
- **Cortex Analyst region** — blocked on `AZURE_EASTUS` (ADR-0011). Revisit if Snowflake adds East US to the supported list, or if we decide to move the account to `AZURE_EASTUS2`.
- **Snowflake Semantic Views as v0.3.x stretch** — server-side semantic layer would be the cleaner SA story over Power-BI-only metrics (ADR-0017 §1 reversal triggers). Stretch goal; would land as ADR-0018.
- **Airflow hosting** — local Docker for the demo DAG, or Azure Container Apps? Local is fine for portfolio purposes (v0.5.0).
- **Cross-region (Azure SA-North storage → Snowflake Azure East US)** — keep as-is for portfolio (good teaching moment for egress cost discussion) vs move to West Europe / co-locate. Leaning keep + document.

### Deferred to v1.1.0 (post-1.0) — see ADR-0014
- **Postgres Flexible Server region** — East US (co-located with Snowflake) vs SA-North. Leaning East US.
- **Postgres Flexible Server compute tier** — recommend B1ms + auto-stop (~R30/day) over GP_Standard_D2s (~R200/day). Decide when v1.1.0 starts.
- **Mock ops schema design** — port from existing `mock_ops_db/seed/` Docker scaffold, or redesign for Flexible Server? Schema in `01_schema.sql` is realistic enough; recommend port-as-is to Flyway `V1__initial_schema.sql`.
- **Onboarding queue strategy (parked for manual practice)** — 8 company groups (baobab, fynbos, karoo, khoisan, protea, springbok, summit, ubuntu) and 15 shared/reference files. Tenant-vs-merge decision lives with the user's manual onboarding work, not the assistant's roadmap.
- **Encoding/format quirks to inject** — UTF-8 vs UTF-16 vs Latin-1? Mixed delimiters in some files? Tied to queue onboarding; deferred with it.

### Resolved (moved to ADRs)
- **Keep generic containers or rename** → ADR (container rename to descriptive names, pre-ADR)
- **Shared storage integration** → ADR-0003
- **Key-pair auth** → ADR-0005
- **Named RAW schemas** → ADR-0006
- **Disable SFTP** → ADR-0007
- **Keep STAGING layer** → ADR-0008
- **CI architecture (ANALYTICS_CI + CI_SVC)** → ADR-0009
- **Snowpipe auto-ingest architecture** → ADR-0010
- **Cortex Analyst deferral** → ADR-0011
- **Snowpipe quarantine pattern** → ADR-0012
- **Airbyte (self-hosted) for mock operational DB** → ADR-0013 (implementation deferred to v1.1.0 per ADR-0014)
- **Defer Airbyte+Postgres + queue tenants; lock v1.0 scope to 3 tenants** → ADR-0014
- **Data Vault 2.0 on transactions + Type 2 dim_policy via snapshot** → ADR-0015
- **Stacked-PR merge convention** → ADR-0016
- **Power BI on Snowflake — semantic model location, connection mode, auth** → ADR-0017
- **Mock ops hosting (Flexible Server vs VM vs Docker) and Flyway for Postgres DDL** → in-principle agreement reached but final ADRs deferred to v1.1.0 when Postgres work resumes.

## 9. Reference: phased roadmap

Scope-locked to 3 tenants for the entire v0.x → v1.0.0 arc. See ADR-0014.

1. **Foundations — `v0.1.0-foundations` (COMPLETE)**
   Snowflake account, RBAC, warehouses, Git, dbt skeleton, one source end to end.

2. **Replicate sources (3-tenant scope) — declared done at this scope (no separate tag)**
   Main Book + Indigo + Horizon live (18 tables, 1.8M rows), auto-ingest live (ADR-0010), CI live (ADR-0009), `_LOADED_AT` populated end-to-end, quarantine task live (ADR-0012), Streamlit + Cortex scaffold live (ADR-0011 deferral). Airbyte/Postgres replication and the 8 queue tenants are parked for v1.1.0 / manual practice (ADR-0014).

3. **Model the warehouse — `v0.2.0-model-the-warehouse` (TAGGED 2026-04-22)**
   Star Schema (6 dims + 4 facts + 3 MARTS), Type 2 `dim_policy_history` via dbt snapshot, and full Data Vault 2.0 transactions domain (4 hubs + 3 links + 2 sats with hashdiff guards) all live in CORE. ADR-0015. `dbt build` PASS=72 WARN=0 ERROR=0. Tag pushed at merge commit `f5d9d40`.

4. **Serve — `v0.3.0-serve` (in progress)**
   Streamlit in Snowflake live with domain dashboards. Power BI scaffold complete: ADR-0017 (with publish-skip addendum) + repo walkthroughs in [power_bi/](power_bi/). Publish to Power BI Service explicitly skipped — `.pbix` + `.rdl` + screenshots in repo are the deliverable. Outstanding: GUI build of `fsp_marts.pbix` (DirectQuery) + `fsp_advisor_commissions.rdl` (Import) + screenshots + tag.

5. **Govern — `v0.4.0-govern`**
   Masking policies on `dim_client` PII live; resource monitors live; quarantine task live. Outstanding: row access policies for multi-tenant isolation; tighter `FR_CI` role; Snowflake Alert on quarantine row-count delta; Event Grid DLQ.

6. **Orchestrate + AI — `v0.5.0-orchestrate-ai`**
   Cortex Analyst scaffolded but region-blocked. Outstanding: one Airflow demo DAG (local Docker is fine); Cortex Document AI demo.

7. **Portfolio writeup — `v1.0.0`**
   Legacy vs new stack comparison, cost analysis, lessons learned. Top-level README polish for the public repo.

8. **Replicate operational DB — `v1.1.0` (post-1.0)**
   Azure Postgres Flexible Server (Terraform-managed, B1ms + auto-stop) + Flyway V1 schema + Airbyte self-hosted sync into `RAW_OPS` + dbt staging models. Snowflake-side scaffolding already provisioned (`RAW_OPS`, `AIRBYTE_SVC`, `FR_AIRBYTE`). User's manual onboarding of the 8 parked queue tenants happens in this same window (separate practice exercise, not assistant work).
