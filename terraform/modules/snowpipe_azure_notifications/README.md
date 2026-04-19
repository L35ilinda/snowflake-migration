# snowpipe_azure_notifications

Wires Azure Event Grid → Storage Queue → Snowflake Notification Integration so Snowpipe can auto-ingest files as they land in blob containers.

## Architecture

```
File lands → Event Grid System Topic fires → Event Subscription routes
(filtered by prefix/suffix) → Storage Queue → Snowflake Notification
Integration → Snowpipe (AUTO_INGEST=TRUE) → COPY INTO RAW table
```

Latency: ~30-60 seconds from file arrival to row visibility.

## What this module creates

- **Azure Storage Queue** (`snowpipe-events` by default) — receives events
- **Azure Event Grid System Topic Event Subscription** — filters `Microsoft.Storage.BlobCreated` events matching `subject_prefix*subject_suffix` and routes them to the queue
- **Snowflake Notification Integration** (`QUEUE` type, `AZURE_STORAGE_QUEUE` provider) — the Snowflake object pipes reference

## What this module does NOT create

- **Event Grid System Topic** — auto-provisioned on every storage account; looked up via data source.
- **Azure admin consent** — one-time manual step after first apply (open `azure_consent_url`).
- **RBAC grant** — grant `Storage Queue Data Contributor` on the queue to Snowflake's enterprise app (`azure_multi_tenant_app_name`). Do this manually or with a `azurerm_role_assignment`.
- **Pipe modifications** — pipes need `AUTO_INGEST = true` + reference to this integration. Handled in `snowflake_snowpipe` module.

## Usage

```hcl
module "snowpipe_notifications" {
  source = "../../modules/snowpipe_azure_notifications"

  name                           = "NI_AZURE_FSPSFTPSOURCE_DEV"
  storage_account_name           = "fspsftpsource"
  storage_account_resource_group = "snflk_training_rg"
  azure_tenant_id                = var.azure_tenant_id
  subject_prefix                 = "/blobServices/default/containers/fsp-"
  subject_suffix                 = ".csv"
  environment                    = "dev"
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — | Snowflake notification integration name (UPPERCASE) |
| `storage_account_name` | `string` | — | Existing storage account |
| `storage_account_resource_group` | `string` | — | RG of the storage account |
| `queue_name` | `string` | `snowpipe-events` | Storage queue name |
| `subject_prefix` | `string` | `/blobServices/default/containers/` | Event Grid filter prefix |
| `subject_suffix` | `string` | `.csv` | Event Grid filter suffix |
| `azure_tenant_id` | `string` | — | Azure tenant for the notification integration |
| `environment` | `string` | — | Environment name for comments |

## Outputs

| Name | Description |
|---|---|
| `name` | Notification integration name (pass to pipes) |
| `queue_uri` | Full queue URI |
| `azure_consent_url` | One-time consent URL — open after first apply |
| `azure_multi_tenant_app_name` | Snowflake enterprise app to grant queue RBAC |
| `queue_resource_id` | Queue Azure resource ID (for RBAC scoping) |

## First-apply bootstrap

1. `terraform apply` — creates queue, subscription, notification integration.
2. Open `azure_consent_url` output — grant admin consent for Snowflake's enterprise app.
3. Run:
   ```powershell
   az role assignment create \
     --role "Storage Queue Data Contributor" \
     --assignee-object-id "$(az ad sp list --display-name '<azure_multi_tenant_app_name>' --query '[0].id' -o tsv)" \
     --scope "<queue_resource_id output>"
   ```
4. `terraform apply` again (if the consent was required for state refresh).
5. Update pipes to `auto_ingest = true`.
