terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Access roles: one RW + one RO per schema
# Key convention: "<schema_key>_rw" and "<schema_key>_ro"
# Name convention: AR_<DATABASE>_<SCHEMA>_RW / AR_<DATABASE>_<SCHEMA>_RO
# ---------------------------------------------------------------------------

locals {
  # Build a flat map of access roles from the schema map.
  # Example: { "staging_rw" = { schema = "STAGING", privilege = "RW" }, ... }
  access_roles = merge([
    for key, schema in var.schemas : {
      "${key}_rw" = {
        name      = "AR_${var.database_name}_${schema}_RW"
        schema    = schema
        privilege = "RW"
      }
      "${key}_ro" = {
        name      = "AR_${var.database_name}_${schema}_RO"
        schema    = schema
        privilege = "RO"
      }
    }
  ]...)

  # Flatten user_grants into a set of { user, role } pairs for for_each.
  user_role_grants = { for pair in flatten([
    for user, roles in var.user_grants : [
      for role in roles : { user = user, role = role }
    ]
  ]) : "${pair.user}_${pair.role}" => pair }
}

# --- Access roles ---

resource "snowflake_account_role" "access" {
  for_each = local.access_roles

  name    = each.value.name
  comment = "${each.value.privilege} access on ${var.database_name}.${each.value.schema} (${var.environment})."
}

# Grant USAGE on the database to every access role.
resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each = local.access_roles

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# Grant USAGE on the schema to every access role.
resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  for_each = local.access_roles

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${var.database_name}\".\"${each.value.schema}\""
  }
}

# RO roles: SELECT on all tables and views (current + future).
resource "snowflake_grant_privileges_to_account_role" "schema_select" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RO" }

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"${each.value.schema}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_select_views" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RO" }

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"${each.value.schema}\""
    }
  }
}

# RW roles: ALL PRIVILEGES on all tables and views (current + future).
resource "snowflake_grant_privileges_to_account_role" "schema_all_tables" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RW" }

  account_role_name = snowflake_account_role.access[each.key].name
  all_privileges    = true

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"${each.value.schema}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_all_views" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RW" }

  account_role_name = snowflake_account_role.access[each.key].name
  all_privileges    = true

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"${each.value.schema}\""
    }
  }
}

# RW roles: CREATE TABLE + CREATE VIEW on schema.
resource "snowflake_grant_privileges_to_account_role" "schema_create" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RW" }

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${var.database_name}\".\"${each.value.schema}\""
  }
}

# RW roles: CREATE SCHEMA on database (dbt runs CREATE SCHEMA IF NOT EXISTS).
resource "snowflake_grant_privileges_to_account_role" "database_create_schema" {
  for_each = { for k, v in local.access_roles : k => v if v.privilege == "RW" }

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# --- Functional roles ---

resource "snowflake_account_role" "functional" {
  for_each = var.functional_roles

  name    = each.key
  comment = each.value.comment != "" ? each.value.comment : "Functional role (${var.environment})."
}

# Grant access roles to functional roles.
resource "snowflake_grant_account_role" "access_to_functional" {
  for_each = { for pair in flatten([
    for fr_name, fr in var.functional_roles : [
      for ar_key in fr.access_role_grants : {
        key     = "${fr_name}_${ar_key}"
        fr_name = fr_name
        ar_key  = ar_key
      }
    ]
  ]) : pair.key => pair }

  role_name        = snowflake_account_role.access[each.value.ar_key].name
  parent_role_name = snowflake_account_role.functional[each.value.fr_name].name
}

# --- User grants ---

resource "snowflake_grant_account_role" "functional_to_user" {
  for_each = local.user_role_grants

  role_name = snowflake_account_role.functional[each.value.role].name
  user_name = each.value.user
}
