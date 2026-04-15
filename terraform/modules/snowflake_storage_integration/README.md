# Module: `snowflake_storage_integration`

Creates a single Snowflake storage integration pointing at one or more Azure blob containers in the same storage account. It is intentionally shared across companies - see [ADR-0003](../../../docs/adr/0003-shared-storage-integration.md).

## Inputs

| name | type | description |
|---|---|---|
| `name` | string | Snowflake object name. |
| `azure_tenant_id` | string | Azure AD tenant that owns the storage account. |
| `storage_account_name` | string | Name of the storage account. |
| `allowed_containers` | list(string) | Container names to include in `STORAGE_ALLOWED_LOCATIONS`. |
| `environment` | string | Written to the object comment only. |

## Outputs

| name | description |
|---|---|
| `name` | Integration name. |
| `azure_consent_url` | Open once in a browser after first apply. Grants admin consent to the Snowflake service principal. |
| `azure_multi_tenant_app_name` | The service principal that needs **Storage Blob Data Reader** on the storage account. |

## Post-apply steps

1. Run `terraform output storage_integration_azure_consent_url`, open the URL, and grant consent.
2. In Azure portal, go to the storage account IAM page and add **Storage Blob Data Reader** to the principal named in `storage_integration_azure_multi_tenant_app_name`.
3. In Snowflake, run `DESC STORAGE INTEGRATION <name>;` and verify `STORAGE_ALLOWED_LOCATIONS` lists all three containers.
4. The integration is now usable by the per-company ingest module in this repo: `snowflake_company_ingest`.
