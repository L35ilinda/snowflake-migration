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
- **Multi-tenant patterns** (three "companies" with non-standardised data feeds)

## 2. Target architecture

```
Sources (3 "company" SFTP feeds → Azure containers, mock operational systems, external APIs)
   ↓
Ingestion (Snowpipe per company for files; Fivetran/Airbyte for DB mocks; Iceberg for cold data)
   ↓
Snowflake schemas: RAW_<COMPANY_NAME> → STAGING → CORE → MARTS  (dbt + Dynamic Tables)
   ↓
AI/ML layer (Cortex Analyst, Document AI, Snowpark UDFs)
   ↓
Serving (Streamlit in Snowflake, Snowsight, Power BI)

Cross-cutting (all layers): Terraform, GitHub Actions, Horizon RBAC/masking,
                            resource monitors, Airflow
```

### Component mapping (legacy → target)

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
| Email/manual fetch paths | Same Azure Storage drop pattern → Snowpipe |

## 3. Environment

### Cloud
- **Cloud provider:** Azure
- **Subscription ID:** `60abe083-7f78-4a57-9f4f-ca0214215c77`
- **Tenant ID:** `bc5006a1-0712-4769-a24f-3cc61c360e7e`
- **Resource group:** `snflk_training_rg`
- **Storage region:** `southafricanorth`
- **Snowflake region:** `AZURE_EASTUS`
- ⚠️ **Cross-region setup** — egress costs and latency apply. Acceptable for portfolio scale; document as known tradeoff in writeup.

### Azure Storage
- **Storage account:** `fspsftpsource`
- **Containers (multi-tenant):**
  - `fsp-company-01` — currently holds all 70 files in `Outbound/`
  - `fsp-company-02` — to be populated
  - `fsp-company-03` — to be populated
- **Path convention (target):** `fsp-company-NN/Outbound/<filename>.csv`
- **Auth to Snowflake:** storage integration (to be created via Terraform)

### Snowflake
- **Edition:** Enterprise
- **Cloud / region:** Azure / East US (`AZURE_EASTUS`)
- **Account locator:** `BO46193`
- **Org-account identifier:** `VNCENFN-XF07416`
- **Default user:** `LSILINDA`
- **Auth method:** SSO (`externalbrowser`)
- **Current role:** `ACCOUNTADMIN` (used for setup only — switch to dedicated dev role ASAP)
- **Default database:** `FSP_DATA_INTEGRATION_DB` (existing, to be repurposed or replaced)
- **Default warehouse:** `COMPUTE_WH` (default — to be replaced by workload-separated warehouses)

### Tooling
- **Git repo:** initialized, scaffold committed (no version tags yet)
- **dbt:** dbt Core (Core over Cloud for IaC control and lower cost)
- **Terraform:** **NOT YET INSTALLED** — install before starting Foundations
- **IDE:** VS Code with Claude Code extension
- **OS / shell:** Windows 11 with PowerShell + Bash (Git Bash or WSL — confirm which)

## 4. Current state — what's been done

### Done
- [x] Azure subscription, resource group, storage account, three containers created
- [x] 70 synthetic CSV files generated and uploaded to `fsp-company-01/Outbound/`
- [x] Snowflake Enterprise account provisioned (Azure East US)
- [x] One mock learning table loaded (`MOCK_DATA` in `FSP_DATA_INTEGRATION_DB.PUBLIC`) — **ignore, not part of project**
- [x] Project directory scaffolded (Terraform, dbt, Snowpipe, Streamlit, Airflow, GitHub Actions structure)
- [x] Git repo initialized with `.gitignore`, `.env.example`, scaffold committed

### Pending
- [ ] Install Terraform locally
- [ ] Populate `.env` with real Snowflake and Azure credentials
- [ ] Split the 70 files across the three containers (e.g. ~25/25/20)
- [ ] Build Terraform module: storage integration + external stages (one per company) + file formats (potentially one per company for encoding differences)
- [ ] Build Terraform module: RBAC scaffolding (functional + access roles, never grant to users directly)
- [ ] Build Terraform module: workload-separated warehouses (`LOAD_WH`, `TRANSFORM_WH`, `BI_WH`) with auto-suspend ≤ 60s
- [ ] Build Terraform module: resource monitors (account-level and warehouse-level)
- [ ] Build Terraform module: layered databases/schemas (`RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, `RAW_HORIZON_ASSURANCE`, `STAGING`, `CORE`, `MARTS`)
- [ ] Configure Snowpipe for one company's files end-to-end
- [ ] Define quarantine table pattern for rejected rows
- [ ] Initialize dbt project, `dbt debug` green
- [ ] First staging model built and tested against a RAW table
- [ ] CI/CD pipelines validated end-to-end

### Snowflake current state
- **Databases:** `FSP_DATA_INTEGRATION_DB` (working), `SNOWFLAKE`, `SNOWFLAKE_LEARNING_DB`, `SNOWFLAKE_SAMPLE_DATA`, `USER$LSILINDA` (sandbox)
- **Schemas in working DB:** `PUBLIC`, `INFORMATION_SCHEMA`
- **Tables:** `FSP_DATA_INTEGRATION_DB.PUBLIC.MOCK_DATA` (1000 rows, ignore — learning artifact)
- **Warehouses:** `COMPUTE_WH` (default, X-Small, auto-suspend 300s), `SYSTEM$STREAMLIT_NOTEBOOK_WH` (system, leave alone)
- **Roles:** defaults only (`ACCOUNTADMIN`, `SYSADMIN`, `SECURITYADMIN`, `USERADMIN`, `ORGADMIN`, `PUBLIC`) — no custom roles yet
- **Storage integrations:** none
- **Stages:** none
- **Pipes:** none
- **File formats:** none

### Source data shape (the 70 files)
- **Count:** 70 CSV files
- **Total rows:** ~10–20 million across all files
- **Current location:** `fspsftpsource/fsp-company-01/Outbound/` (all 70, to be split)
- **Naming pattern (intentionally non-standard, mimicking heterogeneous suppliers):**
  - `<companyname>_inv_<datasettype>.csv`
  - `<companyname>_ins_<datasettype>.csv`
  - `<companyname>_<datasettype>.csv`
- **Dataset types:** `commission`, `transaction`, `insurance`, `valuations`, `market_values`, etc. — non-exhaustive, no enforced standard
- **Format:** CSV, comma-delimited, all have headers
- **Quirks (intentional):**
  - PII columns present (will need masking policies)
  - Empty cells / nulls
  - Plan to introduce **mixed encodings** and **mixed data formats** later for added realism
  - No standardised naming across companies

## 5. Conventions and standards

### Naming
- **Snowflake databases:** UPPERCASE, environment-suffixed: `ANALYTICS_DEV`, `ANALYTICS_PROD`
- **Schemas:** UPPERCASE: `RAW_<COMPANY_NAME>`, `STAGING`, `CORE`, `MARTS`
- **Tables and columns:** `lower_snake_case`
- **Source tables in RAW:** prefixed with dataset type: `raw_main_book.commission`, `raw_indigo_insurance.insurance`
- **dbt staging models:** `stg_company_NN__<dataset_type>.sql`
- **dbt core models:** `dim_<entity>.sql`, `fct_<process>.sql`, `hub_/lnk_/sat_` for the Vault domain
- **dbt marts:** `<domain>_<purpose>.sql`
- **Warehouses:** `<PURPOSE>_WH` — `LOAD_WH`, `TRANSFORM_WH`, `BI_WH`, `ADHOC_WH`
- **Roles:** functional `FR_<n>` (e.g. `FR_ANALYST`, `FR_ENGINEER`), access `AR_<DB>_<SCHEMA>_<RW|RO>`
- **Terraform resources:** `snake_case` matching Snowflake object names
- **Stages:** `stg_company_NN_outbound`
- **File formats:** `ff_csv_company_NN` (allowing per-company variation)
- **Pipes:** `pipe_company_NN_<dataset_type>`

### Architectural rules
- **Schemas as layers:** `RAW_<COMPANY_NAME>` (1:1 source per tenant, append-only) → `STAGING` (typed, cleaned, renamed, conformed) → `CORE` (conformed dims and facts) → `MARTS` (domain-specific, BI-ready)
- **Tenant mapping (initial three):** Azure containers stay `fsp-company-01/02/03`, mapped in Terraform to `RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, and `RAW_HORIZON_ASSURANCE`.
- **Multi-tenant pattern:** isolate raw per company; conform in STAGING; merge into shared CORE.
- **Modeling:** Star Schema is the default in MARTS. **One CORE domain modeled as Data Vault 2.0** (TBD which — likely transactions, see open questions).
- **dbt materializations:** staging = view, intermediate = ephemeral, core = table, marts = table or dynamic table where freshness matters.
- **RBAC:** functional roles granted to access roles granted to users. **Never grant directly to users.**
- **Warehouses:** separate per workload. Auto-suspend ≤ 60s. Right-size by workload, not by user.
- **IaC first:** all Snowflake objects via Terraform. No click-ops in anything that matters.
- **Quarantine pattern:** Snowpipe sends rejected rows to a per-company quarantine table; never fail the pipe.
- **Filename parsing:** dbt macro to derive `company`, `dataset_type`, and `feed_subtype` (`inv`/`ins`/none) from filename in staging.
- **Git:** trunk-based. PRs run `dbt build` against a dev database via GitHub Actions.

### Code style
- SQL: lowercase keywords, leading commas, CTEs over subqueries, one column per line in SELECT
- Terraform: modules for anything reused, explicit `for_each` over `count`, locked provider versions
- Python: `ruff` for linting/formatting, type hints where they help

## 6. Next milestone

**Foundations phase.** Get one source loaded end-to-end via the proper pipeline:

```
Azure Storage (fsp-company-01) → Storage Integration → External Stage → Snowpipe → RAW_MAIN_BOOK → dbt staging model
```

Concrete steps for the next session:
1. Install Terraform on Windows (PowerShell preferred for Azure/Snowflake provider work)
2. Populate `.env` with real Snowflake and Azure credentials
3. Decide whether to keep `FSP_DATA_INTEGRATION_DB` or create `ANALYTICS_DEV` (lean toward fresh DB for clean naming)
4. Build Terraform module: storage integration for `fspsftpsource`
5. Build Terraform module: external stage `stg_company_01_outbound` + file format `ff_csv_company_01`
6. Apply, verify Snowflake can `LIST @stg_company_01_outbound`
7. Build Terraform module: minimal RBAC (a `FR_ENGINEER` functional role + access roles for the new DB)
8. Build Terraform module: `LOAD_WH` (X-Small, auto-suspend 60s) and resource monitor
9. Initialize dbt project, connect via env vars (SSO via externalbrowser), `dbt debug` green
10. Configure Snowpipe for one file pattern from company 01
11. Drop a test file in `fsp-company-01/Outbound/`, verify it lands in RAW
12. Build first staging model in dbt, verify it runs against the RAW table
13. Tag this state as `v0.1.0-foundations`
14. Commit each step with a clear message

Once Foundations is green, next milestone is **Replicate sources** — Snowpipe for the remaining files (after splitting across companies) plus a mock operational DB for Fivetran/Airbyte demonstration.

## 7. How to interact with me (the user)

- Be opinionated. If I'm about to do something suboptimal, say so directly.
- Default to Snowflake-native solutions over third-party tools.
- Show me the SQL/Terraform/YAML, don't just describe it.
- When there's a tradeoff, name it explicitly (cost, complexity, learning value, time-to-implement).
- Skip basic explanations unless I ask — assume working knowledge of SQL, Python, cloud concepts, dimensional modeling.
- For longer artifacts (DDL scripts, dbt models, Terraform modules), put them in files in the repo, not in chat.
- Reference the architecture in section 2 when proposing changes — call out which layer/component is affected.
- I'm in Johannesburg / South Africa timezone (SAST). Costs matter — flag anything that will burn credits or incur cross-region egress.
- I work in Windows 11 with both PowerShell and Bash available. Default to PowerShell for Azure/Windows-native commands; Bash for Unix-style tooling (dbt, terraform also fine in PS).

## 8. Open questions / decisions pending

- **Keep `FSP_DATA_INTEGRATION_DB` or create fresh `ANALYTICS_DEV`?** Lean toward fresh DB for clean conventions; keep the existing one as a "playground" alongside.
- **Which CORE domain to model as Data Vault 2.0?** Probably transactions (most history complexity), but TBD.
- **Fivetran vs Airbyte vs roll-our-own** for replicating mock operational systems? Leaning Airbyte self-hosted for cost + learning.
- **Power BI vs Streamlit-only** for serving? Probably both — Streamlit for the AI-augmented app, Power BI for the traditional BI demo.
- **Cortex use case scope** — Analyst on the semantic layer is a given. Document AI on the file-server folder data is more impressive but more work. Decide once Foundations is done.
- **Airflow hosting** — local Docker for the demo DAG, or Azure Container Apps? Local is fine for portfolio purposes.
- **dbt Semantic Layer vs Snowflake Semantic Views vs Power BI semantic model** — defer until MARTS is built.
- **Cross-region (Azure SA-North storage ↔ Snowflake Azure East US)** — keep as-is for portfolio (good teaching moment) or move to West Europe / co-locate? Leaning keep + document.
- **File-splitting strategy across the three companies** — random, by dataset type, or by deliberate "company specialty"? Deliberate split makes for a better story (e.g. Main Book = financial, Indigo Insurance = insurance, Horizon Assurance = valuations).
- **Encoding/format quirks to inject** — UTF-8 vs UTF-16 vs Latin-1? Mixed delimiters in some files? Plan once Foundations works.

## 9. Reference: phased roadmap

1. **Foundations** ← currently here
   Snowflake account, RBAC, warehouses, Git, dbt skeleton, one source end-to-end.
2. **Replicate sources**
   All 70 files via Snowpipe (per company). Mock operational systems via Airbyte. External Tables for cold data.
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
