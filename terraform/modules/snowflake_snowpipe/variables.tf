variable "database_name" {
  type        = string
  description = "Database containing the RAW schema."
}

variable "raw_schema_name" {
  type        = string
  description = "RAW schema where landing tables and pipes are created."
}

variable "stage_name" {
  type        = string
  description = "External stage name (already created by company_ingest module)."
}

variable "file_format_name" {
  type        = string
  description = "File format name (already created by company_ingest module)."
}

variable "datasets" {
  type = map(object({
    columns      = list(string)
    file_pattern = string
  }))
  description = "Map of dataset name -> { columns (all loaded as VARCHAR), file_pattern (regex matching the filename) }."
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments only."
}
