locals {
  companies = {
    "01" = {
      raw_schema_suffix = "MAIN_BOOK"
      container_name    = var.azure_storage_container_company_01
    }
    "02" = {
      raw_schema_suffix = "INDIGO_INSURANCE"
      container_name    = var.azure_storage_container_company_02
    }
    "03" = {
      raw_schema_suffix = "HORIZON_ASSURANCE"
      container_name    = var.azure_storage_container_company_03
    }
  }
}

# ---- Storage integration ----
# Single integration covering all three containers. See ADR-0003.
module "storage_integration" {
  source = "../../modules/snowflake_storage_integration"

  name                 = upper("si_azure_fspsftpsource_${var.environment}")
  azure_tenant_id      = var.azure_tenant_id
  storage_account_name = var.azure_storage_account_name
  allowed_containers   = [for company in values(local.companies) : company.container_name]
  environment          = var.environment
}

# ---- Database + layered schemas ----
# Keep the Azure container numbering explicit, but name RAW schemas after the
# tenant so the Snowflake layer reads like a real multi-company platform.
module "database_layers" {
  source = "../../modules/snowflake_database_layers"

  database_name = "ANALYTICS_DEV"
  environment   = var.environment
  raw_companies = { for company_id, company in local.companies : company_id => company.raw_schema_suffix }
}

# ---- Per-company ingest surface ----
module "company_ingest" {
  for_each = local.companies

  source = "../../modules/snowflake_company_ingest"

  company_id               = each.key
  database_name            = module.database_layers.database_name
  raw_schema_name          = module.database_layers.raw_schema_names[each.key]
  storage_integration_name = module.storage_integration.name
  storage_account_name     = var.azure_storage_account_name
  container_name           = each.value.container_name
  environment              = var.environment
}

# ---- Azure blob containers ----
# Manages containers in the existing storage account. Only add containers
# here that are Terraform-managed; the three company containers were created
# manually and can be imported later if desired.
module "azure_containers" {
  source = "../../modules/azure_blob_containers"

  resource_group_name  = var.azure_resource_group_name
  storage_account_name = var.azure_storage_account_name

  containers = {
    "fsp-data-onboarding-queue" = { access_type = "private" }
  }
}
