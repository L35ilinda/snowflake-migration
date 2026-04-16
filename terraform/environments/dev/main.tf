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

# ---- RBAC ----
# Access roles per schema (RW + RO), functional roles aggregate them,
# users get functional roles only. See CLAUDE.md §5.
module "rbac" {
  source = "../../modules/snowflake_rbac"

  database_name = module.database_layers.database_name
  environment   = var.environment

  schemas = merge(
    { for cid, name in module.database_layers.raw_schema_names : lower(name) => name },
    {
      staging = module.database_layers.staging_schema_name
      core    = module.database_layers.core_schema_name
      marts   = module.database_layers.marts_schema_name
    }
  )

  functional_roles = {
    FR_ENGINEER = {
      comment = "Full read-write access for data engineers."
      access_role_grants = concat(
        [for cid, name in module.database_layers.raw_schema_names : "${lower(name)}_rw"],
        ["staging_rw", "core_rw", "marts_rw"]
      )
    }
    FR_ANALYST = {
      comment            = "Read-only access for analysts."
      access_role_grants = ["staging_ro", "core_ro", "marts_ro"]
    }
  }

  user_grants = {
    LSILINDA = ["FR_ENGINEER"]
  }
}

# ---- Warehouses + resource monitors ----
# Workload-separated warehouses per CLAUDE.md §5. All start suspended.
module "warehouses" {
  source = "../../modules/snowflake_warehouses"

  environment = var.environment

  warehouses = {
    LOAD_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      comment        = "Snowpipe and COPY INTO workloads."
      grant_usage_to = [module.rbac.functional_role_names["FR_ENGINEER"]]
    }
    TRANSFORM_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      comment        = "dbt transformations."
      grant_usage_to = [module.rbac.functional_role_names["FR_ENGINEER"]]
    }
    BI_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      comment        = "BI and ad-hoc queries."
      grant_usage_to = [
        module.rbac.functional_role_names["FR_ENGINEER"],
        module.rbac.functional_role_names["FR_ANALYST"],
      ]
    }
  }

  resource_monitors = {
    # Account-level backstop — caps total account spend regardless of warehouse.
    RM_DEV_ACCOUNT = {
      credit_quota              = 10
      frequency                 = "MONTHLY"
      start_timestamp           = "2026-05-01 00:00"
      notify_triggers           = [75, 90, 100]
      suspend_trigger           = 100
      suspend_immediate_trigger = 110
    }
    # Per-warehouse monitors — finer cost control per workload.
    RM_LOAD_WH = {
      credit_quota              = 5
      frequency                 = "MONTHLY"
      start_timestamp           = "2026-05-01 00:00"
      notify_triggers           = [75, 90, 100]
      suspend_trigger           = 100
      suspend_immediate_trigger = 110
      warehouses                = ["LOAD_WH"]
    }
    RM_TRANSFORM_WH = {
      credit_quota              = 3
      frequency                 = "MONTHLY"
      start_timestamp           = "2026-05-01 00:00"
      notify_triggers           = [75, 90, 100]
      suspend_trigger           = 100
      suspend_immediate_trigger = 110
      warehouses                = ["TRANSFORM_WH"]
    }
    RM_BI_WH = {
      credit_quota              = 2
      frequency                 = "MONTHLY"
      start_timestamp           = "2026-05-01 00:00"
      notify_triggers           = [75, 90, 100]
      suspend_trigger           = 100
      suspend_immediate_trigger = 110
      warehouses                = ["BI_WH"]
    }
  }
}
