terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

resource "snowflake_storage_integration" "this" {
  name    = var.name
  type    = "EXTERNAL_STAGE"
  enabled = true

  storage_provider = "AZURE"
  azure_tenant_id  = var.azure_tenant_id

  storage_allowed_locations = [
    for container in var.allowed_containers :
    "azure://${var.storage_account_name}.blob.core.windows.net/${container}/"
  ]

  comment = "Shared storage integration for multi-tenant FSP ingestion (${var.environment})."
}
