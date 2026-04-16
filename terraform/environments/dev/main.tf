locals {
  companies = {
    "01" = {
      company_name = "MAIN_BOOK"
      container_name = var.azure_storage_container_main_book
    }
    "02" = {
      company_name = "INDIGO_INSURANCE"
      container_name = var.azure_storage_container_indigo_insurance
    }
    "03" = {
      company_name = "HORIZON_ASSURANCE"
      container_name = var.azure_storage_container_horizon_assurance
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
  raw_companies = { for company_id, company in local.companies : company_id => company.company_name }
}

# ---- Per-company ingest surface ----
module "company_ingest" {
  for_each = local.companies

  source = "../../modules/snowflake_company_ingest"

  # Stages validate container existence at create time. Ensure Azure
  # containers are created before Snowflake stages to avoid race conditions.
  depends_on = [module.azure_containers]

  company_key              = each.key
  company_name             = each.value.company_name
  database_name            = module.database_layers.database_name
  raw_schema_name          = module.database_layers.raw_schema_names[each.key]
  storage_integration_name = module.storage_integration.name
  storage_account_name     = var.azure_storage_account_name
  container_name           = each.value.container_name
  environment              = var.environment
}

# ---- Azure blob containers ----
# Manages containers in the existing storage account. Company containers use
# descriptive names (fsp-main-book, not fsp-company-01). Legacy generic
# containers (fsp-company-01/02/03) are not Terraform-managed and can be
# deleted once fully migrated.
module "azure_containers" {
  source = "../../modules/azure_blob_containers"

  resource_group_name  = var.azure_resource_group_name
  storage_account_name = var.azure_storage_account_name

  containers = {
    "fsp-data-onboarding-queue" = { access_type = "private" }
    "fsp-main-book"             = { access_type = "private" }
    "fsp-indigo-insurance"      = { access_type = "private" }
    "fsp-horizon-assurance"     = { access_type = "private" }
  }
}
