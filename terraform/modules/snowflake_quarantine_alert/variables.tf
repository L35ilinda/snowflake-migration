variable "database_name" {
  type        = string
  description = "Database containing the quarantine schema."
}

variable "schema_name" {
  type        = string
  description = "Schema where the alert lives. Typically same as the quarantine table's schema."
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse the alert runs on. Use the same warehouse as the capture task (LOAD_WH)."
}

variable "quarantine_table_fully_qualified_name" {
  type        = string
  description = "Fully qualified quarantine table name (DB.SCHEMA.TABLE) to poll for new rows."
}

variable "email_integration_name" {
  type        = string
  description = "Name of the snowflake_email_notification_integration to create (e.g. NI_EMAIL_OPS)."
  validation {
    condition     = can(regex("^[A-Z0-9_]+$", var.email_integration_name))
    error_message = "email_integration_name must be UPPERCASE Snowflake-safe identifier."
  }
}

variable "alert_name" {
  type        = string
  description = "Name of the snowflake_alert to create."
  default     = "ALR_QUARANTINE_NEW_ERRORS"
}

variable "recipient_emails" {
  type        = list(string)
  description = "Email addresses to notify. MUST match the EMAIL property set on a Snowflake user in this account (Snowflake only sends to verified addresses)."
  validation {
    condition     = length(var.recipient_emails) > 0
    error_message = "At least one recipient email must be supplied."
  }
}

variable "schedule_minutes" {
  type        = number
  description = "How often (minutes) the alert evaluates its condition."
  default     = 5
}

variable "lookback_minutes" {
  type        = number
  description = "How far back (minutes) to scan for new quarantine rows. Match schedule_minutes so every window is evaluated exactly once."
  default     = 5
}

variable "environment" {
  type        = string
  description = "Environment name (used in comments)."
}