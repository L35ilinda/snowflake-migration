terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

resource "snowflake_masking_policy" "this" {
  for_each = var.policies

  name     = each.key
  database = var.database_name
  schema   = var.schema_name

  argument {
    name = split(" ", each.value.signature)[0]
    type = split(" ", each.value.signature)[1]
  }

  return_data_type = each.value.return_type
  body             = each.value.body
  comment          = each.value.comment != "" ? each.value.comment : "Masking policy (${var.environment})."
}
