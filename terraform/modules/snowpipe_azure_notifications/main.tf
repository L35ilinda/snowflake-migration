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

  # Explicit retry envelope — Azure defaults to 30 attempts / 24h. We pin
  # both so the DLQ behaviour is reproducible regardless of platform default
  # drift. Closes the ADR-0010 known-limitation "no DLQ for delivery failures."
  retry_policy {
    max_delivery_attempts = var.dlq_max_delivery_attempts
    event_time_to_live    = floor(var.dlq_event_time_to_live_seconds / 60)
  }

  subject_filter {
    subject_begins_with = var.subject_prefix
    subject_ends_with   = var.subject_suffix
  }

  storage_queue_endpoint {
    storage_account_id = data.azurerm_storage_account.this.id
    queue_name         = azurerm_storage_queue.snowpipe_events.name
  }

  # DLQ: when an event fails max_delivery_attempts, Event Grid writes a
  # JSON blob describing the failure into the configured container.
  # Skipped entirely when dlq_storage_container_name is empty so the
  # subscription stays valid before DLQ is wired up.
  #
  # Intentionally no `dead_letter_identity` block — Event Grid uses its
  # built-in service auth to write to the storage account (the same path
  # it uses for the storage_queue_endpoint). Adding a SystemAssigned
  # identity here is possible but requires a pre-provisioned RBAC role
  # assignment (Storage Blob Data Contributor on the DLQ container) and
  # has been observed to return intermittent "Internal error" responses
  # from the Event Grid control plane in southafricanorth. The simpler
  # default path is sufficient for a DLQ on a private storage account.
  dynamic "storage_blob_dead_letter_destination" {
    for_each = var.dlq_storage_container_name == "" ? [] : [1]
    content {
      storage_account_id          = data.azurerm_storage_account.this.id
      storage_blob_container_name = var.dlq_storage_container_name
    }
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
