terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Azure side: storage queue + Event Grid subscription
# ---------------------------------------------------------------------------

data "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.storage_account_resource_group
}

resource "azurerm_storage_queue" "snowpipe_events" {
  name                 = var.queue_name
  storage_account_name = data.azurerm_storage_account.this.name
}

# Event Grid System Topic for blob events. Azure does NOT auto-create these
# on storage accounts — we create one explicitly, scoped to the storage
# account's resource ID. One system topic per storage account is the
# recommended pattern.
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "${var.storage_account_name}-system-topic"
  resource_group_name    = var.storage_account_resource_group
  location               = data.azurerm_storage_account.this.location
  source_arm_resource_id = data.azurerm_storage_account.this.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
}

resource "azurerm_eventgrid_system_topic_event_subscription" "blob_created" {
  # Azure subscription names must be letters/digits/hyphens only.
  name                = "${replace(lower(var.name), "_", "-")}-blob-created"
  system_topic        = azurerm_eventgrid_system_topic.storage.name
  resource_group_name = var.storage_account_resource_group

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = var.subject_prefix
    subject_ends_with   = var.subject_suffix
  }

  storage_queue_endpoint {
    storage_account_id = data.azurerm_storage_account.this.id
    queue_name         = azurerm_storage_queue.snowpipe_events.name
  }
}

# ---------------------------------------------------------------------------
# Snowflake side: notification integration pointing at the queue
# ---------------------------------------------------------------------------

resource "snowflake_notification_integration" "this" {
  name    = var.name
  enabled = true
  type    = "QUEUE"

  notification_provider           = "AZURE_STORAGE_QUEUE"
  azure_storage_queue_primary_uri = "${data.azurerm_storage_account.this.primary_queue_endpoint}${azurerm_storage_queue.snowpipe_events.name}"
  azure_tenant_id                 = var.azure_tenant_id

  comment = "Shared notification integration for Snowpipe auto-ingest across all company containers (${var.environment})."

  depends_on = [azurerm_storage_queue.snowpipe_events]
}
