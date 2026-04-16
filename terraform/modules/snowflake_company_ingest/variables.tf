variable "company_key" {
  type        = string
  description = "Short identifier for the company (e.g. \"01\"). Used as the for_each key, not in Snowflake object names."
}

variable "company_name" {
  type        = string
  description = "Descriptive uppercase company name used in Snowflake object names (e.g. MAIN_BOOK, INDIGO_INSURANCE)."
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
  description = "Azure blob container name for this company's files."
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments only."
}