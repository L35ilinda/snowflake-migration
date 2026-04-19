terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# SEMANTIC schema — separates analytics metadata from data schemas.
# ---------------------------------------------------------------------------

resource "snowflake_schema" "semantic" {
  database = var.database_name
  name     = var.semantic_schema_name
  comment  = "Cortex semantic models, Streamlit code, and other analytics metadata (${var.environment})."
}

# ---------------------------------------------------------------------------
# Internal stage holding the semantic model YAML and Streamlit source.
# Not an external stage — these are small text files we own, not data.
# ---------------------------------------------------------------------------

resource "snowflake_stage" "models" {
  name     = var.stage_name
  database = var.database_name
  schema   = snowflake_schema.semantic.name

  directory = "ENABLE = true"

  comment = "Holds Cortex semantic model YAML + Streamlit app files (${var.environment})."
}

# ---------------------------------------------------------------------------
# Streamlit app. Files must be uploaded to the stage before the app will run
# (see scripts/upload_streamlit_app.py). Creating the resource without files
# present is fine — Snowflake only validates on run.
# ---------------------------------------------------------------------------

resource "snowflake_streamlit" "this" {
  name     = var.streamlit_name
  database = var.database_name
  schema   = snowflake_schema.semantic.name
  title    = var.streamlit_title

  stage     = "\"${var.database_name}\".\"${snowflake_schema.semantic.name}\".\"${snowflake_stage.models.name}\""
  main_file = var.main_file

  query_warehouse = var.query_warehouse

  comment = "FSP Analyst: NL → SQL over MARTS via Cortex Analyst (${var.environment})."
}

# ---------------------------------------------------------------------------
# Account-level feature flag: Cortex Analyst must be explicitly enabled
# before the API returns anything other than "not enabled". Required once
# per account; idempotent.
# ---------------------------------------------------------------------------

resource "snowflake_execute" "enable_cortex_analyst" {
  execute = "ALTER ACCOUNT SET ENABLE_CORTEX_ANALYST = TRUE"
  revert  = "ALTER ACCOUNT UNSET ENABLE_CORTEX_ANALYST"
  query   = "SHOW PARAMETERS LIKE 'ENABLE_CORTEX_ANALYST' IN ACCOUNT"
}

# ---------------------------------------------------------------------------
# Grants
# ---------------------------------------------------------------------------

# Cortex Analyst usage — SNOWFLAKE.CORTEX_USER is a built-in database role.
# snowflake_grant_database_role has a provider bug in v1.x where state
# refresh returns a null root after apply, even though the grant lands
# server-side. Falling back to raw SQL via snowflake_execute keeps the
# infra declarative without the state-round-trip issue.
resource "snowflake_execute" "cortex_user" {
  for_each = toset(var.cortex_user_roles)

  execute = "GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE \"${each.value}\""
  revert  = "REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE \"${each.value}\""
  query   = "SHOW GRANTS TO ROLE \"${each.value}\""
}

# Roles listed in grant_usage_to need:
#  - USAGE on the SEMANTIC schema (to see the stage and the app)
#  - READ on the stage (to let Cortex read the semantic model)
#  - USAGE on the Streamlit app (to open it in Snowsight)

resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  for_each = toset(var.grant_usage_to)

  account_role_name = each.value
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${var.database_name}\".\"${snowflake_schema.semantic.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "stage_read" {
  for_each = toset(var.grant_usage_to)

  account_role_name = each.value
  privileges        = ["READ"]

  on_schema_object {
    object_type = "STAGE"
    object_name = "\"${var.database_name}\".\"${snowflake_schema.semantic.name}\".\"${snowflake_stage.models.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "streamlit_usage" {
  for_each = toset(var.grant_usage_to)

  account_role_name = each.value
  privileges        = ["USAGE"]

  on_schema_object {
    object_type = "STREAMLIT"
    object_name = "\"${var.database_name}\".\"${snowflake_schema.semantic.name}\".\"${snowflake_streamlit.this.name}\""
  }
}
