locals {
  companies = {
    "01" = {
      company_name   = "MAIN_BOOK"
      container_name = var.azure_storage_container_main_book
    }
    "02" = {
      company_name   = "INDIGO_INSURANCE"
      container_name = var.azure_storage_container_indigo_insurance
    }
    "03" = {
      company_name   = "HORIZON_ASSURANCE"
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
    # DLQ target for Event Grid delivery failures. Referenced by
    # snowpipe_notifications. See ADR-0010 follow-up.
    "snowpipe-dlq" = { access_type = "private" }
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
      staging        = module.database_layers.staging_schema_name
      core           = module.database_layers.core_schema_name
      marts          = module.database_layers.marts_schema_name
      raw_quarantine = snowflake_schema.raw_quarantine.name
      raw_ops        = snowflake_schema.raw_ops.name
    }
  )

  functional_roles = {
    FR_ENGINEER = {
      comment = "Full read-write access for data engineers."
      access_role_grants = concat(
        [for cid, name in module.database_layers.raw_schema_names : "${lower(name)}_rw"],
        ["staging_rw", "core_rw", "marts_rw", "raw_quarantine_rw", "raw_ops_rw"]
      )
    }
    FR_ANALYST = {
      comment = "Read-only access for analysts."
      # Analysts see quarantine errors (data-quality visibility) but not raw
      # per-tenant landing tables (tenant data is conformed in STAGING first).
      access_role_grants = ["staging_ro", "core_ro", "marts_ro", "raw_quarantine_ro"]
    }
    FR_AIRBYTE = {
      comment            = "Self-hosted Airbyte destination role. Writes replicated operational tables into RAW_OPS. See ADR-0013."
      access_role_grants = ["raw_ops_rw"]
    }
  }

  user_grants = {
    # LSILINDA holds both functional roles so we can test analyst-facing
    # artefacts (e.g. dim_client masking policies) without a second user.
    # Service users (CI_SVC, AIRBYTE_SVC) are granted outside this module
    # because they are created alongside dev/main.tf, not inside snowflake_rbac.
    LSILINDA = ["FR_ENGINEER", "FR_ANALYST"]
  }

  depends_on = [snowflake_schema.raw_quarantine, snowflake_schema.raw_ops]
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
      size         = "XSMALL"
      auto_suspend = 60
      comment      = "BI and ad-hoc queries."
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

# ---- Snowpipe auto-ingest (Event Grid → Storage Queue → Snowflake) ----
# Shared notification integration used by every pipe across all companies.
# See ADR-0010.
module "snowpipe_notifications" {
  source = "../../modules/snowpipe_azure_notifications"

  name                           = upper("ni_azure_fspsftpsource_${var.environment}")
  storage_account_name           = var.azure_storage_account_name
  storage_account_resource_group = var.azure_resource_group_name
  azure_tenant_id                = var.azure_tenant_id

  # Only CSVs from our fsp-* containers should trigger Snowpipe.
  subject_prefix = "/blobServices/default/containers/fsp-"
  subject_suffix = ".csv"

  # DLQ: failed Event Grid deliveries write JSON blobs into snowpipe-dlq
  # after max_delivery_attempts. Referencing the module output (not a string
  # literal) gives Terraform an explicit dependency on the container create
  # without triggering a re-read of the storage-account data source — a
  # module-level depends_on would propagate `known after apply` through the
  # data source and force-replace the system topic + notification integration.
  # Closes ADR-0010 known-limitation "no DLQ for delivery failures."
  dlq_storage_container_name = module.azure_containers.container_names["snowpipe-dlq"]

  environment = var.environment
}

# ---- Snowpipe: Main Book ----
# Landing tables (all-VARCHAR) + pipes for each Main Book dataset.
# Pipes use ON_ERROR=CONTINUE and MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE.
module "main_book_pipes" {
  source = "../../modules/snowflake_snowpipe"

  database_name                 = module.database_layers.database_name
  raw_schema_name               = module.database_layers.raw_schema_names["01"]
  stage_name                    = module.company_ingest["01"].stage_name
  file_format_name              = module.company_ingest["01"].file_format_name
  notification_integration_name = module.snowpipe_notifications.name
  environment                   = var.environment

  datasets = {
    main_book_ins_commissions = {
      file_pattern = ".*main_book_ins_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    main_book_inv_commissions = {
      file_pattern = ".*main_book_inv_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    main_book_risk_benefits = {
      file_pattern = ".*main_book_risk_benefits\\\\.csv"
      columns = [
        "policynumber", "inceptiondate", "policystatus", "memberid",
        "agenext", "smokerstatus", "incomebrackets", "life_sumassured",
        "life_premium", "disability_type", "disability_sumassured",
        "disability_premium", "chronic_level", "chronic_waitingperiod",
        "chronic_premium", "accident_benefit", "accident_premium",
        "total_monthlypremium", "commission_rate", "advisor_identifier",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    main_book_risk_benefits_transactions = {
      file_pattern = ".*main_book_risk_benefits_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "member_id", "transaction_type",
        "transaction_date", "amount", "status", "reference_number",
        "narrative", "claim_type", "claim_reason", "benefit_affected",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    main_book_valuation_transactions = {
      file_pattern = ".*main_book_valuation_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "client_id_number", "fund_code",
        "transaction_type", "transaction_date", "amount", "units",
        "price_per_unit", "status", "reference_number", "source_fund",
        "narrative", "client_title", "client_first_name", "client_surname",
        "client_initials"
      ]
    }

    main_book_valuations = {
      file_pattern = ".*main_book_valuations.*[.]csv"
      columns = [
        "advisor_identifier", "client_title", "client_first_name",
        "client_surname", "client_initials", "client_id_number",
        "policy_number", "product_name", "product_code", "fund_name",
        "fund_code", "jse_code", "valuation_date", "currency",
        "market_value_amount", "units", "anniversary_month",
        "monthly_income_amount", "monthly_income_pct", "income_frequency"
      ]
    }
  }
}

# ---- Snowpipe: Indigo Insurance ----
module "indigo_insurance_pipes" {
  source = "../../modules/snowflake_snowpipe"

  database_name                 = module.database_layers.database_name
  raw_schema_name               = module.database_layers.raw_schema_names["02"]
  stage_name                    = module.company_ingest["02"].stage_name
  file_format_name              = module.company_ingest["02"].file_format_name
  notification_integration_name = module.snowpipe_notifications.name
  environment                   = var.environment

  datasets = {
    indigo_ins_commissions = {
      file_pattern = ".*indigo_ins_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    indigo_inv_commissions = {
      file_pattern = ".*indigo_inv_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    # Note: indigo has `ProductName` column that Main Book does not.
    indigo_insurance = {
      file_pattern = ".*indigo_insurance.*[.]csv"
      columns = [
        "policynumber", "inceptiondate", "policystatus", "memberid",
        "agenext", "smokerstatus", "incomebrackets", "productname",
        "life_sumassured", "life_premium", "disability_type",
        "disability_sumassured", "disability_premium", "chronic_level",
        "chronic_waitingperiod", "chronic_premium", "accident_benefit",
        "accident_premium", "total_monthlypremium", "commission_rate",
        "advisor_identifier", "client_title", "client_first_name",
        "client_surname", "client_initials"
      ]
    }

    indigo_ins_transactions = {
      file_pattern = ".*indigo_ins_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "member_id", "transaction_type",
        "transaction_date", "amount", "status", "reference_number",
        "narrative", "claim_type", "claim_reason", "benefit_affected",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    indigo_transactions = {
      file_pattern = ".*indigo_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "client_id_number", "fund_code",
        "transaction_type", "transaction_date", "amount", "units",
        "price_per_unit", "status", "reference_number", "source_fund",
        "narrative", "client_title", "client_first_name", "client_surname",
        "client_initials"
      ]
    }

    indigo_valuations = {
      file_pattern = ".*indigo_valuations.*[.]csv"
      columns = [
        "advisor_identifier", "client_title", "client_first_name",
        "client_surname", "client_initials", "client_id_number",
        "policy_number", "product_name", "product_code", "fund_name",
        "fund_code", "jse_code", "valuation_date", "currency",
        "market_value_amount", "units", "anniversary_month",
        "monthly_income_amount", "monthly_income_pct", "income_frequency"
      ]
    }
  }
}

# ---- Snowpipe: Horizon Assurance ----
module "horizon_assurance_pipes" {
  source = "../../modules/snowflake_snowpipe"

  database_name                 = module.database_layers.database_name
  raw_schema_name               = module.database_layers.raw_schema_names["03"]
  stage_name                    = module.company_ingest["03"].stage_name
  file_format_name              = module.company_ingest["03"].file_format_name
  notification_integration_name = module.snowpipe_notifications.name
  environment                   = var.environment

  datasets = {
    horizon_ins_commissions = {
      file_pattern = ".*horizon_ins_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    horizon_inv_commissions = {
      file_pattern = ".*horizon_inv_commissions.*[.]csv"
      columns = [
        "commission_id", "policy_number", "advisor_identifier", "business_line",
        "commission_type", "transaction_date", "gross_amount", "vat_amount",
        "net_amount", "product_code", "commission_rate", "clawback_reason",
        "payment_reference", "payment_date", "brokerage_split", "status",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    horizon_assurance = {
      file_pattern = ".*horizon_assurance.*[.]csv"
      columns = [
        "policynumber", "inceptiondate", "policystatus", "memberid",
        "agenext", "smokerstatus", "incomebrackets", "productname",
        "life_sumassured", "life_premium", "disability_type",
        "disability_sumassured", "disability_premium", "chronic_level",
        "chronic_waitingperiod", "chronic_premium", "accident_benefit",
        "accident_premium", "total_monthlypremium", "commission_rate",
        "advisor_identifier", "client_title", "client_first_name",
        "client_surname", "client_initials"
      ]
    }

    horizon_ins_transactions = {
      file_pattern = ".*horizon_ins_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "member_id", "transaction_type",
        "transaction_date", "amount", "status", "reference_number",
        "narrative", "claim_type", "claim_reason", "benefit_affected",
        "client_title", "client_first_name", "client_surname", "client_initials"
      ]
    }

    horizon_transactions = {
      file_pattern = ".*horizon_transactions.*[.]csv"
      columns = [
        "transaction_id", "policy_number", "client_id_number", "fund_code",
        "transaction_type", "transaction_date", "amount", "units",
        "price_per_unit", "status", "reference_number", "source_fund",
        "narrative", "client_title", "client_first_name", "client_surname",
        "client_initials"
      ]
    }

    horizon_valuations = {
      file_pattern = ".*horizon_valuations.*[.]csv"
      columns = [
        "advisor_identifier", "client_title", "client_first_name",
        "client_surname", "client_initials", "client_id_number",
        "policy_number", "product_name", "product_code", "fund_name",
        "fund_code", "jse_code", "valuation_date", "currency",
        "market_value_amount", "units", "anniversary_month",
        "monthly_income_amount", "monthly_income_pct", "income_frequency"
      ]
    }
  }
}

# ---- Masking policies ----
# Dynamic masking for PII in dim_client. Privileged roles (FR_ENGINEER,
# ACCOUNTADMIN) see clear values; other roles see masked output.
module "masking_policies" {
  source = "../../modules/snowflake_masking_policies"

  database_name = module.database_layers.database_name
  schema_name   = module.database_layers.core_schema_name
  environment   = var.environment

  policies = {
    MP_MASK_STRING_PII = {
      signature   = "val VARCHAR"
      return_type = "VARCHAR"
      body        = <<-SQL
        case
          when current_role() in ('FR_ENGINEER', 'ACCOUNTADMIN') then val
          else '***MASKED***'
        end
      SQL
      comment     = "Redact string PII (names, IDs) for non-privileged roles."
    }

    MP_MASK_DATE_PII = {
      signature   = "val DATE"
      return_type = "DATE"
      body        = <<-SQL
        case
          when current_role() in ('FR_ENGINEER', 'ACCOUNTADMIN') then val
          else date_trunc('year', val)
        end
      SQL
      comment     = "Truncate date PII (birth_date) to year for non-privileged roles."
    }
  }

  depends_on = [module.database_layers]
}

# Grant APPLY on each masking policy to FR_ENGINEER so dbt (running as
# FR_ENGINEER from either LSILINDA or CI_SVC) can attach the policies via
# post-hook. Without this, `ALTER TABLE ... SET MASKING POLICY ...` fails
# with "policy does not exist or not authorized".
resource "snowflake_grant_privileges_to_account_role" "apply_masking_policies" {
  for_each = module.masking_policies.policy_fully_qualified_names

  account_role_name = module.rbac.functional_role_names["FR_ENGINEER"]
  privileges        = ["APPLY"]

  on_schema_object {
    object_type = "MASKING POLICY"
    object_name = each.value
  }
}

# ---- ANALYTICS_CI database (for GitHub Actions dbt builds) ----
# Dedicated database so CI cannot corrupt dev artifacts. See ADR-0009.
# Only the database is created here — dbt creates STAGING/CORE/MARTS
# schemas at runtime under CI_SVC ownership.
resource "snowflake_database" "analytics_ci" {
  name    = "ANALYTICS_CI"
  comment = "CI build target for dbt runs from GitHub Actions. See ADR-0009."
}

# Grant USAGE + CREATE SCHEMA on ANALYTICS_CI to FR_ENGINEER so dbt (running
# as CI_SVC → FR_ENGINEER) can create and populate schemas.
resource "snowflake_grant_privileges_to_account_role" "fr_engineer_ci_database_usage" {
  account_role_name = module.rbac.functional_role_names["FR_ENGINEER"]
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics_ci.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "fr_engineer_ci_database_create_schema" {
  account_role_name = module.rbac.functional_role_names["FR_ENGINEER"]
  privileges        = ["CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics_ci.name
  }
}

# ---- CI_SVC service user ----
# Dedicated service user for GitHub Actions. Uses its own key pair for
# rotation/audit separation from developer users. See ADR-0009.
resource "snowflake_user" "ci_svc" {
  name         = "CI_SVC"
  login_name   = "CI_SVC"
  display_name = "CI service account (GitHub Actions)"
  comment      = "Runs dbt build on PRs. Target: ANALYTICS_CI. See ADR-0009."
  disabled     = "false"

  default_role      = module.rbac.functional_role_names["FR_ENGINEER"]
  default_warehouse = module.warehouses.warehouse_names["TRANSFORM_WH"]

  rsa_public_key = file(var.ci_svc_public_key_path)
}

resource "snowflake_grant_account_role" "ci_svc_fr_engineer" {
  role_name = module.rbac.functional_role_names["FR_ENGINEER"]
  user_name = snowflake_user.ci_svc.name
}

# ---- Streamlit + Cortex Analyst over MARTS ----
# FR_ANALYST users get an NL Q&A app over the three marts via Cortex.
# Files on the stage (semantic model YAML + Streamlit source) are uploaded
# out-of-band via scripts/upload_streamlit_app.py after apply.
module "streamlit_analyst" {
  source = "../../modules/snowflake_streamlit_analyst"

  database_name = module.database_layers.database_name
  environment   = var.environment

  grant_usage_to = [
    module.rbac.functional_role_names["FR_ENGINEER"],
    module.rbac.functional_role_names["FR_ANALYST"],
  ]
  cortex_user_roles = [
    module.rbac.functional_role_names["FR_ENGINEER"],
    module.rbac.functional_role_names["FR_ANALYST"],
    # Streamlit apps run as their owner's role. This app is owned by
    # ACCOUNTADMIN (the role used to apply Terraform), so ACCOUNTADMIN
    # itself needs CORTEX_USER to call the Cortex Analyst API from
    # inside the app.
    "ACCOUNTADMIN",
  ]

  depends_on = [module.database_layers, module.warehouses]
}

# Streamlit apps in Snowflake run as their owner role. This app is owned by
# ACCOUNTADMIN (whoever ran `terraform apply`), and Snowflake does not
# currently support ALTER STREAMLIT ... SET EXECUTE_AS = 'CALLER'. So for
# ACCOUNTADMIN to actually execute the embedded SQL against MARTS, it needs
# the read access role directly — inherited access via DB ownership or
# secondary roles isn't sufficient for the Streamlit runtime context.
resource "snowflake_execute" "accountadmin_marts_ro" {
  execute = "GRANT ROLE ${module.rbac.access_role_names["marts_ro"]} TO ROLE ACCOUNTADMIN"
  revert  = "REVOKE ROLE ${module.rbac.access_role_names["marts_ro"]} FROM ROLE ACCOUNTADMIN"
  query   = "SHOW GRANTS OF ROLE ${module.rbac.access_role_names["marts_ro"]}"

  depends_on = [module.rbac]
}

# ---- Cross-tenant schemas (RAW_QUARANTINE, RAW_OPS) ----
# These do not belong in the database_layers module because they cross
# tenant boundaries (quarantine spans all pipes; ops is replicated from
# the mock operational DB, not a tenant SFTP feed).
resource "snowflake_schema" "raw_quarantine" {
  database = module.database_layers.database_name
  name     = "RAW_QUARANTINE"
  comment  = "Snowpipe rejected-row capture across all tenants. See ADR-0012."
}

resource "snowflake_schema" "raw_ops" {
  database = module.database_layers.database_name
  name     = "RAW_OPS"
  comment  = "Landing zone for tables replicated from the mock operational DB via Airbyte. See ADR-0013."
}

# ---- Snowpipe quarantine ----
# One shared table + one task that captures rejected rows across every pipe
# in the project via VALIDATE_PIPE_LOAD. See ADR-0012.
module "quarantine" {
  source = "../../modules/snowflake_quarantine"

  database_name  = module.database_layers.database_name
  schema_name    = snowflake_schema.raw_quarantine.name
  warehouse_name = module.warehouses.warehouse_names["LOAD_WH"]
  environment    = var.environment

  # Every pipe in the project. Append here when new pipes are added.
  pipe_fully_qualified_names = concat(
    [for k, name in module.main_book_pipes.pipe_names :
      "${module.database_layers.database_name}.${module.database_layers.raw_schema_names["01"]}.${name}"
    ],
    [for k, name in module.indigo_insurance_pipes.pipe_names :
      "${module.database_layers.database_name}.${module.database_layers.raw_schema_names["02"]}.${name}"
    ],
    [for k, name in module.horizon_assurance_pipes.pipe_names :
      "${module.database_layers.database_name}.${module.database_layers.raw_schema_names["03"]}.${name}"
    ],
  )

  depends_on = [module.rbac, module.warehouses]
}

# ---- AIRBYTE_SVC service user ----
# Self-hosted Airbyte writes replicated operational tables into RAW_OPS.
# Key-pair auth, separate key from LSILINDA and CI_SVC per ADR-0009 / ADR-0013.
resource "snowflake_user" "airbyte_svc" {
  name         = "AIRBYTE_SVC"
  login_name   = "AIRBYTE_SVC"
  display_name = "Airbyte service account (self-hosted)"
  comment      = "Runs Airbyte syncs from the mock operational DB into RAW_OPS. See ADR-0013."
  disabled     = "false"

  default_role      = "FR_AIRBYTE"
  default_warehouse = module.warehouses.warehouse_names["LOAD_WH"]

  rsa_public_key = file(var.airbyte_svc_public_key_path)
}

resource "snowflake_grant_account_role" "airbyte_svc_fr_airbyte" {
  role_name = module.rbac.functional_role_names["FR_AIRBYTE"]
  user_name = snowflake_user.airbyte_svc.name
}

# Airbyte's Snowflake destination connector also needs USAGE on the
# warehouse it runs against. FR_AIRBYTE inherits USAGE on the database
# via raw_ops_rw, but warehouse access is granted at the warehouses module.
resource "snowflake_grant_privileges_to_account_role" "fr_airbyte_load_wh_usage" {
  account_role_name = module.rbac.functional_role_names["FR_AIRBYTE"]
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = module.warehouses.warehouse_names["LOAD_WH"]
  }
}

# PBI_SVC removed 2026-04-22 — Power BI publish step scoped out per
# ADR-0017 addendum. No Power BI service identity needed; build phase
# uses LSILINDA OAuth only.

# ---- Quarantine alert (Snowflake-native email on new pipe errors) ----
# Closes ADR-0012 known-limitation "no alerting on pipe errors."
# Email integration is Snowflake-side only; delivery requires the recipient
# email to match the EMAIL property on a user in this account — see below.
module "quarantine_alert" {
  source = "../../modules/snowflake_quarantine_alert"

  database_name                         = module.database_layers.database_name
  schema_name                           = snowflake_schema.raw_quarantine.name
  warehouse_name                        = module.warehouses.warehouse_names["LOAD_WH"]
  quarantine_table_fully_qualified_name = module.quarantine.table_fully_qualified_name
  email_integration_name                = upper("ni_email_ops_${var.environment}")
  recipient_emails                      = ["eric.silinda@gmail.com"]
  # Hourly cadence — quarantine triage is not time-critical, and a 60-min
  # window keeps the alert's polling SQL out of query history every 5 min.
  # Lookback matches schedule so each window is evaluated exactly once.
  schedule_minutes = 60
  lookback_minutes = 60
  environment      = var.environment

  depends_on = [module.quarantine, snowflake_execute.lsilinda_email]
}

# LSILINDA pre-dates the IaC discipline (created interactively at account
# bootstrap). Snowflake's SYSTEM$SEND_EMAIL only delivers to addresses that
# match the EMAIL property on a user in this account — so we set it here
# via a one-shot ALTER USER. Captured as snowflake_execute to preserve
# state on revert. Not importing LSILINDA into full Terraform management
# keeps this PR scoped to the govern work; a full import can come later.
resource "snowflake_execute" "lsilinda_email" {
  execute = "ALTER USER LSILINDA SET EMAIL = 'eric.silinda@gmail.com'"
  revert  = "ALTER USER LSILINDA UNSET EMAIL"
  query   = "SHOW USERS LIKE 'LSILINDA'"
}
