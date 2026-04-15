# Terraform

Modular Terraform for the Snowflake migration project. See [ADR-0001](../docs/adr/0001-modular-terraform-layout.md) for the layout rationale and [ADR-0002](../docs/adr/0002-azure-remote-state-backend.md) for the remote-state decision.

## Layout

```
terraform/
  bootstrap/                      # one-time: creates the tfstate container (LOCAL state)
  environments/
    dev/                          # dev environment root — apply from here
  modules/
    snowflake_storage_integration/
    snowflake_rbac/               # scaffolded, empty
    snowflake_warehouses/         # scaffolded, empty
```

You never run `terraform apply` from `terraform/` root. You run it from an environment root (`environments/dev/`) or from `bootstrap/`.

## First-run order (Foundations phase)

### 1. Bootstrap the remote state backend (one time only)

```bash
cd terraform/bootstrap
az login --tenant bc5006a1-0712-4769-a24f-3cc61c360e7e
terraform init
terraform plan
terraform apply
```

This creates a `tfstate` container inside the existing `fspsftpsource` storage account. State for the bootstrap itself stays local (chicken-and-egg — it can't store its own state in a container it's about to create). Commit-safe: `*.tfstate` is gitignored.

### 2. Initialize and plan the dev environment

```bash
cd ../environments/dev
terraform init          # downloads providers, connects to azurerm backend
terraform plan
```

First `plan` for the storage integration will succeed, but the resulting Azure enterprise-app needs **manual admin consent** before Snowflake can actually read the containers. After `apply`:

```bash
terraform apply
terraform output storage_integration_azure_consent_url
```

Open the URL, grant consent in the Azure portal. Then in a Snowflake worksheet, `DESC STORAGE INTEGRATION <name>;` to copy the `AZURE_MULTI_TENANT_APP_NAME` — grant it **Storage Blob Data Reader** on the storage account (or per-container, stricter).

### 3. Verify

From Snowflake, once stages are created (next module):

```sql
LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND;
```

## Provider versions

- `hashicorp/azurerm ~> 4.0`
- `Snowflake-Labs/snowflake ~> 1.0` (⚠️ v1.x had breaking changes vs 0.9x — verify resource/field names against current docs before any `apply`; this scaffold uses common names but the provider evolves quickly)

## Secrets

- No secrets live in `.tf` or `.tfvars` files. Azure IDs and Snowflake account IDs are non-secret config.
- Snowflake auth uses SSO via the provider's external-browser flow — no password in state.
- `.env` at the repo root holds the same values as `terraform.tfvars` for use by other tooling (dbt, scripts). Keep them in sync.
