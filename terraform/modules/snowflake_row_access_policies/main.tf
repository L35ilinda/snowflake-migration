terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Row access policies — mirrors snowflake_masking_policies in shape so the
# two read consistently in environments/dev/main.tf. See ADR-0020.
# ---------------------------------------------------------------------------

resource "snowflake_row_access_policy" "this" {
  for_each = var.policies

  name     = each.key
  database = var.database_name
  schema   = var.schema_name

  argument {
    name = split(" ", each.value.signature)[0]
    type = split(" ", each.value.signature)[1]
  }

  body    = each.value.body
  comment = each.value.comment != "" ? each.value.comment : "Row access policy (${var.environment})."
}