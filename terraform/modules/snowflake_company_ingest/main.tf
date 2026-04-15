terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

locals {
  file_format_name = "FF_CSV_COMPANY_${var.company_id}"
  stage_name       = "STG_COMPANY_${var.company_id}_OUTBOUND"
  stage_url        = "azure://${var.storage_account_name}.blob.core.windows.net/${var.container_name}/"
}

resource "snowflake_file_format" "csv" {
  name        = local.file_format_name
  database    = var.database_name
  schema      = var.raw_schema_name
  format_type = "CSV"

  field_delimiter              = ","
  skip_header                  = 1
  field_optionally_enclosed_by = "\""
  null_if                      = ["", "NULL", "null", "\\N"]
  trim_space                   = true
  empty_field_as_null          = true

  # Be forgiving on ingest. Quarantine is enforced at the pipe/copy layer,
  # not by failing on schema quirks here.
  error_on_column_count_mismatch = false
  replace_invalid_characters     = true

  comment = "CSV file format for company ${var.company_id} outbound feed (${var.environment})."
}

resource "snowflake_stage" "outbound" {
  name                = local.stage_name
  database            = var.database_name
  schema              = var.raw_schema_name
  url                 = local.stage_url
  storage_integration = var.storage_integration_name
  file_format         = "FORMAT_NAME = ${var.database_name}.${var.raw_schema_name}.${snowflake_file_format.csv.name}"

  comment = "External stage on ${var.container_name} for company ${var.company_id} (${var.environment})."
}
