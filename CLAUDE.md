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
- Cortex (Analyst, Document AI) for the GenAI angle
- One Airflow DAG (skill demonstration, not core orchestration)
- **Multi-tenant patterns** (three "companies" with non-standardized data feeds)

## 2. Target architecture

```text
Sources (3 "company" SFTP feeds -> Azure containers, mock operational systems, external APIs)
   |
   v
Ingestion (Snowpipe per company for files; Fivetran/Airbyte for DB mocks; Iceberg for cold data)
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
| Virtualization layer (views, process-on-read) | Fivetran/Airbyte replication; Iceberg/External Tables for cold data |
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

### Snowflake
- **Edition:** Enterprise
- **Cloud / region:** Azure / East US (`AZURE_EASTUS`)
- **Account locator:** `BO46193`
- **Org-account identifier:** `VNCENFN-XF07416`
- **Default user:** `LSILINDA`
- **Auth method:** key-pair for programmatic clients (`SNOWFLAKE_JWT`); interactive Snowsight still uses browser login and MFA
- **Current role:** `ACCOUNTADMIN` (bootstrap only - switch to a dedicated dev role after RBAC exists)
- **Target database:** `ANALYTICS_DEV` (live, Terraform-managed)
- **Legacy sandbox database:** `FSP_DATA_INTEGRATION_DB` (keep isolated from project objects)
- **Default warehouse:** `COMPUTE_WH` (default only, to be replaced by workload-separated warehouses)

### Tooling
- **Git repo:** initialized, scaffold committed (no version tags yet)
- **dbt:** dbt Core (Core over Cloud for IaC control and lower cost)
- **Terraform:** installed locally (`1.14.8`)
- **Azure CLI:** installed locally and authenticated to the project subscription
- **IDE:** VS Code with Claude Code extension
- **Python runtime:** Anaconda (`C:\ProgramData\anaconda3`). Use this for pip, dbt, snowflake-connector, and all Python tooling.
- **OS / shell:** Windows 11 with PowerShell + Bash

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
- [x] `generate_schema_name` macro — writes to `STAGING`/`CORE`/`MARTS` directly (no prefix)
- [x] Tagged `v0.1.0-foundations`

### Pending (Replicate Sources phase)
- [ ] Onboard remaining 60 files from `fsp-data-onboarding-queue` (8 company groups + shared/reference tables)
- [ ] Snowpipe for Indigo Insurance and Horizon Assurance datasets
- [ ] Define quarantine table pattern for rejected rows
- [ ] CI/CD pipelines validated end to end
- [ ] Mock operational DB for Fivetran/Airbyte demonstration

### Snowflake current state
- **Databases:** `ANALYTICS_DEV` (project, Terraform-managed), `FSP_DATA_INTEGRATION_DB` (sandbox, ignore), system databases
- **Schemas in `ANALYTICS_DEV`:** `RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, `RAW_HORIZON_ASSURANCE`, `STAGING`, `CORE`, `MARTS`
- **Tables in `RAW_MAIN_BOOK`:** 6 landing tables (all-VARCHAR + `_LOADED_AT`), 100K rows each: `MAIN_BOOK_INS_COMMISSIONS`, `MAIN_BOOK_INV_COMMISSIONS`, `MAIN_BOOK_RISK_BENEFITS`, `MAIN_BOOK_RISK_BENEFITS_TRANSACTIONS`, `MAIN_BOOK_VALUATION_TRANSACTIONS`, `MAIN_BOOK_VALUATIONS`
- **Views in `STAGING`:** 6 dbt-managed staging views (`stg_main_book__*`) with type casting and PascalCase rename
- **Warehouses:** `COMPUTE_WH` (default, XS, 300s), `LOAD_WH` (XS, 60s), `TRANSFORM_WH` (XS, 60s), `BI_WH` (XS, 60s)
- **Resource monitors:** `RM_DEV_ACCOUNT` (10cr backstop), `RM_LOAD_WH` (5cr), `RM_TRANSFORM_WH` (3cr), `RM_BI_WH` (2cr)
- **Roles:** `FR_ENGINEER` (all RW), `FR_ANALYST` (staging/core/marts RO), 12 access roles (`AR_ANALYTICS_DEV_<SCHEMA>_RW/RO`), plus Snowflake defaults
- **Storage integrations:** `SI_AZURE_FSPSFTPSOURCE_DEV` (covers `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`)
- **Stages:** `STG_MAIN_BOOK`, `STG_INDIGO_INSURANCE`, `STG_HORIZON_ASSURANCE` (in respective RAW schemas)
- **Pipes:** `PIPE_MAIN_BOOK_INS_COMMISSIONS`, `PIPE_MAIN_BOOK_INV_COMMISSIONS`, `PIPE_MAIN_BOOK_RISK_BENEFITS`, `PIPE_MAIN_BOOK_RISK_BENEFITS_TRANSACTIONS`, `PIPE_MAIN_BOOK_VALUATION_TRANSACTIONS`, `PIPE_MAIN_BOOK_VALUATIONS`
- **File formats:** `FF_CSV_MAIN_BOOK`, `FF_CSV_INDIGO_INSURANCE`, `FF_CSV_HORIZON_ASSURANCE`
- **Terraform-managed state:** storage integration, database, 6 schemas, 3 stages, 3 file formats, 6 tables, 6 pipes, 14 roles, 3 warehouses, 4 resource monitors, 4 Azure containers

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
- **Quarantine pattern:** Snowpipe sends rejected rows to a per-company quarantine table; never fail the pipe
- **Filename parsing:** dbt macro to derive `company`, `dataset_type`, and `feed_subtype` (`inv` / `ins` / none) from filename in staging
- **Git:** trunk-based. PRs run `dbt build` against a dev database via GitHub Actions

### Code style
- SQL: lowercase keywords, leading commas, CTEs over subqueries, one column per line in `select`
- Terraform: modules for anything reused, explicit `for_each` over `count`, locked provider versions
- Python: `ruff` for linting and formatting, type hints where they help

## 6. Next milestone

**Replicate sources phase.** Expand ingest beyond Main Book to all companies and demonstrate DB replication.

```text
Onboarding queue files -> assign to companies -> Snowpipe -> RAW_<COMPANY> -> dbt staging
Mock operational DB -> Fivetran/Airbyte -> RAW_<SOURCE> -> dbt staging
```

Concrete steps for the next session:
1. Decide how to assign the 8 remaining company groups (baobab, fynbos, etc.) to the three tenants — or add more tenants.
2. Copy assigned files from `fsp-data-onboarding-queue` to their company containers.
3. Inspect headers, create landing tables + Snowpipes for Indigo Insurance and Horizon Assurance.
4. Build staging models for the two new companies.
5. Decide on shared/reference table placement (shared container? all RAW schemas?).
6. Define quarantine table pattern for rejected rows.
7. Set up mock operational DB and configure Fivetran or Airbyte replication.
8. Enable Snowpipe auto-ingest via Azure Event Grid (upgrade from manual refresh).
9. Set up GitHub Actions CI/CD: `dbt build` on PR against a dev database.
10. Tag `v0.2.0-replicate-sources` when complete.

Once Replicate Sources is green, the next milestone is **Model the warehouse** — rebuild DW logic in dbt with Star Schema in MARTS and one Data Vault domain in CORE.

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

- **Which CORE domain to model as Data Vault 2.0?** Probably transactions (most history complexity), but TBD.
- **Fivetran vs Airbyte vs roll-our-own** for replicating mock operational systems? Leaning Airbyte self-hosted for cost + learning.
- **Power BI vs Streamlit-only** for serving? Probably both - Streamlit for the AI-augmented app, Power BI for the traditional BI demo.
- **Cortex use case scope** - Analyst on the semantic layer is a given. Document AI on the file-server folder data is more impressive but more work. Decide once Foundations is done.
- **Airflow hosting** - local Docker for the demo DAG, or Azure Container Apps? Local is fine for portfolio purposes.
- **dbt Semantic Layer vs Snowflake Semantic Views vs Power BI semantic model** - defer until MARTS is built.
- **Cross-region (Azure SA-North storage -> Snowflake Azure East US)** - keep as-is for portfolio (good teaching moment) or move to West Europe / co-locate? Leaning keep + document.
- **Onboarding queue strategy** — 60 files remain in `fsp-data-onboarding-queue`. 8 company groups (baobab, fynbos, karoo, khoisan, protea, springbok, summit, ubuntu) need to be assigned to the three tenant companies or treated as additional tenants. Shared/reference tables (accounts, customers, etc.) need a home — likely a shared container or loaded into all three RAW schemas.
- **Encoding/format quirks to inject** - UTF-8 vs UTF-16 vs Latin-1? Mixed delimiters in some files? Plan once Foundations works.

## 9. Reference: phased roadmap

1. **Foundations** (COMPLETE — tagged `v0.1.0-foundations`)
   Snowflake account, RBAC, warehouses, Git, dbt skeleton, one source end to end.
2. **Replicate sources** <- currently here
   All files via Snowpipe (per company). Mock operational systems via Airbyte. External Tables for cold data.
3. **Model the warehouse**
   Rebuild DW logic in dbt. Star Schema in MARTS, one Data Vault domain in CORE.
4. **Serve**
   Power BI on MARTS. Streamlit app with Cortex Analyst. Snowsight ops dashboards.
5. **AI layer**
   Cortex Analyst on semantic layer. Document AI on file-server data.
6. **Govern and demonstrate**
   Masking policies, row access policies, resource monitors, cost dashboards. Airflow demo DAG.
7. **Decommission narrative**
   Document the "old vs new" comparison, cost analysis, and lessons learned as the portfolio writeup.
