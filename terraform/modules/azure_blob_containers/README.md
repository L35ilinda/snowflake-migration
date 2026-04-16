# azure_blob_containers

Manages blob containers within an existing Azure storage account.

## Usage

```hcl
module "azure_containers" {
  source = "../../modules/azure_blob_containers"

  resource_group_name  = "snflk_training_rg"
  storage_account_name = "fspsftpsource"

  containers = {
    "fsp-data-onboarding-queue" = { access_type = "private" }
    "fsp-another-container"     = {}  # defaults to private
  }
}
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `resource_group_name` | `string` | Resource group containing the storage account |
| `storage_account_name` | `string` | Existing storage account name |
| `containers` | `map(object)` | Map of container name -> `{ access_type }`. Defaults to `private` |

## Outputs

| Name | Description |
|------|-------------|
| `container_names` | Map of key -> container name |
| `container_ids` | Map of key -> Azure resource ID |
| `storage_account_name` | Storage account the containers belong to |

## Notes

- Does **not** create the storage account — it must already exist.
- Container names are validated against Azure naming rules (3-63 chars, lowercase alphanumeric + hyphens).
- To bring existing manually-created containers under management, use `terraform import`.