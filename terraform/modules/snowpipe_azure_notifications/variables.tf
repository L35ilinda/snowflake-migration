variable "name" {
  type        = string
  description = "Base name for resources (uppercase for Snowflake integration, becomes a suffix for Azure queue/subscription)."
  validation {
    condition     = can(regex("^[A-Z0-9_]+$", var.name))
    error_message = "name must be UPPERCASE Snowflake-safe identifier (e.g. NI_AZURE_FSPSFTPSOURCE_DEV)."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Azure storage account hosting the containers to watch. Must already exist."
}

variable "storage_account_resource_group" {
  type        = string
  description = "Resource group of the storage account."
}

variable "queue_name" {
  type        = string
  description = "Name of the Azure Storage Queue receiving blob-created events."
  default     = "snowpipe-events"
}

variable "subject_prefix" {
  type        = string
  description = "Event Grid subject filter prefix. Only blob events under this path fire notifications. Typical: /blobServices/default/containers/<prefix>"
  default     = "/blobServices/default/containers/"
}

variable "subject_suffix" {
  type        = string
  description = "Event Grid subject filter suffix. Use .csv to limit to CSV files."
  default     = ".csv"
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure tenant ID (for Snowflake notification integration)."
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments."
}

# ---------------------------------------------------------------------------
# Dead-letter queue for Event Grid delivery failures.
# When set, failed deliveries after max_delivery_attempts land as blobs in
# the configured container. Closes the ADR-0010 known-limitation "no DLQ
# for delivery failures."
# ---------------------------------------------------------------------------

variable "dlq_storage_container_name" {
  type        = string
  description = "Azure Blob container (in the same storage account) where Event Grid writes failed-delivery blobs. Empty string disables DLQ wiring."
  default     = ""
}

variable "dlq_max_delivery_attempts" {
  type        = number
  description = "Number of delivery attempts before Event Grid dead-letters the event. Azure default is 30; we set it explicitly for auditability."
  default     = 30
}

variable "dlq_event_time_to_live_seconds" {
  type        = number
  description = "Seconds Event Grid will retry delivery before dead-lettering. Azure max is 1440 minutes (86400s)."
  default     = 86400
}
