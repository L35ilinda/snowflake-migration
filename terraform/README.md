# Terraform

Modular Terraform for the Snowflake migration project. See [ADR-0001](../docs/adr/0001-modular-terraform-layout.md) for the layout rationale and [ADR-0002](../docs/adr/0002-azure-remote-state-backend.md) for the remote-state decision.

## Layout

```text
terraform/
  bootstrap/                      # one-time: creates the tfstate container (LOCAL state)
  environments/
    dev/                          # dev environment root - apply from here
  modules/
    snowflake_company_ingest/
    snowflake_database_layers/
    snowflake_storage_integration/
    snowflake_rbac/               # scaffolded, empty
    snowflake_warehouses/         # scaffolded, empty
```

You never run `terraform apply` from `terraform/` root. Run it from an environment root (`environments/dev/`) or from `bootstrap/`.

## Current status

- Remote-state bootstrap is already applied.
- The shared storage integration is already applied and Azure-side consent/RBAC is complete.
- The current dev plan will create the database layer plus three per-company ingest surfaces.

## Foundations flow

### 1. Bootstrap the remote state backend (one time only)

```bash
cd terraform/bootstrap
az login --tenant bc5006a1-0712-4769-a24f-3cc61c360e7e
terraform init
terraform plan
terraform apply
```

This creates a `tfstate` container inside the existing `fspsftpsource` storage account. State for the bootstrap itself stays local because it cannot store its own state in a container it is about to create.

### 2. Initialize and apply the storage integration

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
terraform output storage_integration_azure_consent_url
```

After the first storage-integration apply:

1. Open the consent URL and grant Azure admin consent.
2. Grant **Storage Blob Data Reader** to the principal named in `storage_integration_azure_multi_tenant_app_name`.
3. Verify with `DESC STORAGE INTEGRATION <name>;`.

### 3. Current next apply: database layers plus company ingest

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

Current clean plan: `13 to add, 0 to change, 0 to destroy`.

That apply will create:

- `ANALYTICS_DEV`
- `RAW_MAIN_BOOK`, `RAW_INDIGO_INSURANCE`, `RAW_HORIZON_ASSURANCE`
- `STAGING`, `CORE`, `MARTS`
- `FF_CSV_COMPANY_01`, `FF_CSV_COMPANY_02`, `FF_CSV_COMPANY_03`
- `STG_COMPANY_01_OUTBOUND`, `STG_COMPANY_02_OUTBOUND`, `STG_COMPANY_03_OUTBOUND`

### 4. Verify

```sql
LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND/Outbound;
```

## Provider versions

- `hashicorp/azurerm ~> 4.0`
- `snowflakedb/snowflake ~> 1.0`

## Secrets

- No secrets live in `.tf` or `.tfvars` files. Azure IDs and Snowflake account IDs are non-secret config.
- Snowflake auth uses key-pair auth (`SNOWFLAKE_JWT`) via `private_key = file(var.snowflake_private_key_path)`.
- The private key stays outside the repo. `terraform/.gitignore` defensively ignores `*.p8`, `*.pem`, and `*.key`.
- `.env` at the repo root holds the same values as `terraform.tfvars` for other tooling (dbt, scripts). Keep them in sync.
