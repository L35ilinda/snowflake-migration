terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

locals {
  # Layered schemas per CLAUDE.md §5:
  # RAW_<COMPANY_NAME> (per tenant) -> STAGING -> CORE -> MARTS
  raw_schema_names = {
    for cid, schema_suffix in var.raw_companies :
    cid => "RAW_${schema_suffix}"
  }

  shared_schemas = {
    STAGING = "Typed, cleaned, conformed rows from all RAW sources."
    CORE    = "Conformed dimensions and facts (Star Schema + one Data Vault domain)."
    MARTS   = "Domain-specific, BI-ready tables."
  }
}

resource "snowflake_database" "this" {
  name    = var.database_name
  comment = "Primary analytics database (${var.environment}). Managed by Terraform."
}

resource "snowflake_schema" "raw" {
  for_each = local.raw_schema_names

  database = snowflake_database.this.name
  name     = each.value
  comment  = "Raw append-only landing zone for company ${each.key} (${var.environment})."
}

resource "snowflake_schema" "shared" {
  for_each = local.shared_schemas

  database = snowflake_database.this.name
  name     = each.key
  comment  = "${each.value} (${var.environment})"
}
