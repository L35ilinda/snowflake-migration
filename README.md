# Snowflake Migration (Portfolio)

Migrating a legacy SQL Server + SSIS + SSAS + SSRS + Power BI BI stack to a Snowflake-native architecture on Azure. Built to enterprise standards as a Snowflake Solution Architect portfolio project.

See [CLAUDE.md](CLAUDE.md) for the full architecture, conventions, and phased roadmap.

## Repo layout

```text
terraform/   # IaC for Snowflake and Azure objects
dbt/         # dbt Core project (staging -> core -> marts)
snowpipe/    # Snowpipe definitions and quarantine patterns
airflow/     # Demo DAG (skill demo, not core orchestration)
streamlit/   # Streamlit-in-Snowflake apps (Cortex Analyst)
notebooks/   # Ad-hoc analysis and design scratchpads
data/        # Source-data inventory and sample metadata (no raw data)
```

## Prerequisites

- **Terraform** >= 1.14 - `winget install HashiCorp.Terraform`
- **Python** 3.11+ with `dbt-core` and `dbt-snowflake`
- **Azure CLI** - authenticated to subscription `60abe083-7f78-4a57-9f4f-ca0214215c77`
- **Snowflake account** - Enterprise edition in `AZURE_EASTUS`, with an RSA public key registered on the user for programmatic auth
- **PowerShell 7** or Bash (Git Bash / WSL)

## Environment setup

Copy the block below into a new file named `.env` at the repo root (`snowflake-migration/.env`). It is gitignored.

```bash
# ---- Snowflake ----
SNOWFLAKE_ACCOUNT=VNCENFN-XF07416
SNOWFLAKE_USER=LSILINDA
SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
SNOWFLAKE_PRIVATE_KEY_PATH=C:/Users/Lonwabo_Eric/.snowflake/keys/lsilinda_rsa_key.p8
SNOWFLAKE_ROLE=ACCOUNTADMIN
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_DATABASE=ANALYTICS_DEV
SNOWFLAKE_REGION=AZURE_EASTUS

# ---- Azure ----
AZURE_SUBSCRIPTION_ID=60abe083-7f78-4a57-9f4f-ca0214215c77
AZURE_TENANT_ID=bc5006a1-0712-4769-a24f-3cc61c360e7e
AZURE_RESOURCE_GROUP=snflk_training_rg
AZURE_STORAGE_ACCOUNT=fspsftpsource
AZURE_STORAGE_REGION=southafricanorth
AZURE_CONTAINER_MAIN_BOOK=fsp-main-book
AZURE_CONTAINER_INDIGO_INSURANCE=fsp-indigo-insurance
AZURE_CONTAINER_HORIZON_ASSURANCE=fsp-horizon-assurance
```

### Secrets policy

- `.env` is gitignored. Never commit it.
- No Snowflake password is stored. Programmatic auth uses key-pair auth (`SNOWFLAKE_JWT`).
- The private key lives outside the repo at `C:/Users/Lonwabo_Eric/.snowflake/keys/`.
- Azure subscription and tenant IDs are not secrets, but they are pinned here for reproducibility.
- Any service principal credentials added later go in `.env` only and are referenced via environment variables in Terraform.

## Current status

**Foundations complete** — tagged `v0.1.0-foundations`. Full end-to-end pipeline live:

- `ANALYTICS_DEV` database with 6 schemas, RBAC (12 access roles, 2 functional roles), 3 workload-separated warehouses with per-warehouse resource monitors
- 6 Snowpipes loading Main Book data (600K rows) into `RAW_MAIN_BOOK`
- 6 dbt staging views in `STAGING` with type casting, tests, and source definitions
- Storage integration, external stages, and file formats for all 3 companies

## Current phase

**Replicate sources** — see [CLAUDE.md](CLAUDE.md) for the live checklist of what is done and what is next.

## GitHub Actions CI

Every PR to `master` runs `dbt build` against a dedicated `ANALYTICS_CI` database via `.github/workflows/dbt_ci.yml`. Architecture and rationale: [ADR-0009](docs/adr/0009-ci-architecture.md).

### Required GitHub repository secrets

Configure these at **Settings → Secrets and variables → Actions**:

| Secret | Value | Notes |
|--------|-------|-------|
| `SNOWFLAKE_ACCOUNT` | `VNCENFN-XF07416` | Org-account identifier |
| `SNOWFLAKE_USER` | `CI_SVC` | Dedicated service user |
| `SNOWFLAKE_ROLE` | `FR_ENGINEER` | Functional role |
| `SNOWFLAKE_WAREHOUSE` | `TRANSFORM_WH` | Bound to `RM_TRANSFORM_WH` monitor |
| `SNOWFLAKE_DATABASE` | `ANALYTICS_CI` | CI build target (separate from dev) |
| `SNOWFLAKE_PRIVATE_KEY` | *base64-encoded PEM* | See generation steps below |

### Generating the CI_SVC private key secret

The `CI_SVC` Snowflake user is provisioned by Terraform with the public key from `~/.snowflake/keys/ci_svc_rsa_key.pub`. To let GitHub Actions authenticate as `CI_SVC`, encode the matching private key:

**PowerShell:**
```powershell
$privateKeyPath = "$env:USERPROFILE\.snowflake\keys\ci_svc_rsa_key.p8"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($privateKeyPath)) | Set-Clipboard
```

Paste the clipboard contents as the `SNOWFLAKE_PRIVATE_KEY` secret. GitHub Actions base64-decodes it back into a PEM file at runtime.

**Bash (Git Bash / WSL):**
```bash
base64 -w0 < ~/.snowflake/keys/ci_svc_rsa_key.p8
```
