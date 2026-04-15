variable "company_id" {
  type        = string
  description = "Zero-padded company identifier (e.g. \"01\")."
  validation {
    condition     = can(regex("^[0-9]{2}$", var.company_id))
    error_message = "company_id must be a two-digit zero-padded string, e.g. \"01\"."
  }
}

variable "database_name" {
  type        = string
  description = "Database holding the named RAW schema."
}

variable "raw_schema_name" {
  type        = string
  description = "RAW schema name, e.g. RAW_MAIN_BOOK."
}

variable "storage_integration_name" {
  type        = string
  description = "Snowflake storage integration granting access to the Azure container."
}

variable "storage_account_name" {
  type        = string
  description = "Azure storage account name."
}

variable "container_name" {
  type        = string
  description = "Azure blob container name for this company's outbound files."
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments only."
}
