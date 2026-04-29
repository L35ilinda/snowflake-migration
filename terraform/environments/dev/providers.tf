terraform {
  required_version = ">= 1.6.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
}

# Snowflake provider v1.x — key-pair auth (SNOWFLAKE_JWT). See ADR-0005.
# The private key is read from disk at plan time via file(); nothing secret
# is persisted in state, tfvars, or environment config.
provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(var.snowflake_private_key_path)
  role              = var.snowflake_role

  # In provider v1.x, several resources are gated behind explicit opt-in
  # while their API stabilizes. Add more here as modules need them.
  preview_features_enabled = [
    "snowflake_storage_integration_resource",
    "snowflake_stage_resource",
    "snowflake_file_format_resource",
    "snowflake_pipe_resource",
    "snowflake_table_resource",
    "snowflake_notification_integration_resource",
    "snowflake_email_notification_integration_resource",
    "snowflake_alert_resource",
  ]
}
