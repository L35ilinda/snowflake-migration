variable "database_name" {
  type        = string
  description = "Database name. Must be UPPERCASE per CLAUDE.md §5."
  validation {
    condition     = var.database_name == upper(var.database_name)
    error_message = "database_name must be UPPERCASE."
  }
}

variable "environment" {
  type        = string
  description = "Environment name, written to comments only."
}

variable "raw_companies" {
  type        = map(string)
  description = "Map of zero-padded company identifiers to uppercase schema suffixes, e.g. { \"01\" = \"MAIN_BOOK\" }."

  validation {
    condition = alltrue([
      for company_id in keys(var.raw_companies) :
      can(regex("^[0-9]{2}$", company_id))
    ])
    error_message = "raw_companies keys must be two-digit zero-padded strings, e.g. \"01\"."
  }

  validation {
    condition = alltrue([
      for schema_suffix in values(var.raw_companies) :
      can(regex("^[A-Z0-9_]+$", schema_suffix))
    ])
    error_message = "raw_companies values must use Snowflake-safe uppercase identifiers, e.g. MAIN_BOOK."
  }
}
